import pathlib,sys,subprocess,json,hashlib,shutil,gzip,os,secrets,time,re
B=pathlib.Path(__file__).resolve().parent
key=sys.argv[1];cfg=json.loads((B/'sites.json').read_text())[key]
site=pathlib.Path(cfg['site']);current=pathlib.Path(cfg['current']);web=cfg['web'];db=web.replace('-web-','-db-');host=cfg['host'];root=cfg['root'];work=B/key
def out(a):return subprocess.check_output(a,text=True).strip()
def run(a,**kw):return subprocess.run(a,check=True,**kw)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest() if p.is_file() else None
def inspect(name):return json.loads(out(['docker','inspect',name]))[0]
def fingerprint(query,columns):
 statements=[];grouped={t:[] for t in columns}
 for table,fields in columns.items():
  assert re.fullmatch('[a-zA-Z0-9_]+',table) and all(re.fullmatch('[a-zA-Z0-9_]+',f) for f in fields)
  statements.append("SELECT '"+table+"',SHA2(CAST(JSON_ARRAY("+','.join('`'+f+'`' for f in fields)+") AS CHAR),256) AS rowhash FROM `"+table+"` ORDER BY rowhash;")
 for row in query('\n'.join(statements)).splitlines():
  table,digest=row.split('\t');grouped[table].append(digest+'\n')
 return {t:{'rows':len(rows),'sha256':hashlib.sha256(''.join(rows).encode()).hexdigest()} for t,rows in grouped.items()}
def prune(stage):
 for path in retired:
  p=stage/path
  assert p.resolve().is_relative_to(stage.resolve())
  if p.is_dir():shutil.rmtree(p)
  elif p.exists():p.unlink()

def navigation_fingerprints(query):
 """Editable site links are protected data even though other menu rows regenerate."""
 q="SELECT id,SHA2(CAST(JSON_ARRAY(id,category,module,adminonly,permissions,dependscontext,contextplugin) AS CHAR),256) FROM tbl_menu_category WHERE SUBSTR(category,1,5)='site_' ORDER BY id;"
 return query(q).splitlines()
