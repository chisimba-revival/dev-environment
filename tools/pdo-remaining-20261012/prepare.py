"""Rehearse an image/config-only PDO switch against an isolated database copy."""
from common import *
work.mkdir(mode=0o700,exist_ok=True)
i=inspect(web);image='chisimba/pdo-remaining:20261012';candidate=inspect(image)
assert i['State']['Running']
assert i['Image']=='sha256:fae7188e142b799d73a08768d9f1a9da95aec12106ec126d3e2921ca9c5b0386'
base=current.resolve();stage=work/'stage'
assert not stage.exists(),'Use a new rehearsal directory for a repeated preparation'
run(['cp','-a','--reflink=auto',str(base),str(stage)],stdout=subprocess.DEVNULL)
files={str(p.relative_to(base)):sha(p) for p in base.rglob('*') if p.is_file() and not p.is_symlink() and p.relative_to(base).parts[0] not in ['config','usrfiles','user_images','error_log','error_logs']}
config=pathlib.Path(next(m['Source'] for m in i['Mounts'] if m['Destination']==root+'/config'))
assert re.search(r'<DATABASE_ABSTRACTION>\s*MDB2\s*</DATABASE_ABSTRACTION>',(config/'config.xml').read_text())
compose=pathlib.Path(i['Config']['Labels']['com.docker.compose.project.config_files'])
baseline={'code':str(base),'imageId':i['Image'],'files':files,'config':str(config),'configHashes':{p.name:sha(p) for p in config.iterdir() if p.is_file()},'compose':str(compose),'composeHash':sha(compose)}
(work/'baseline.json').write_text(json.dumps(baseline,indent=2))
# Check that only the MySQL PDO driver was added to the exact parent image.
def extensions(img):return set(out(['docker','run','--rm','--network','none','--entrypoint','php',img,'-r','echo implode("\\n",get_loaded_extensions());']).splitlines())
assert extensions(i['Image']).issubset(extensions(image));assert 'pdo_mysql' in extensions(image)
proc=subprocess.Popen(['docker','exec',db,'sh','-c','exec mariadb-dump -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" --single-transaction --quick --routines --triggers "$MARIADB_DATABASE"'],stdout=subprocess.PIPE)
dump=work/'database.sql.gz'
with gzip.open(dump,'wb') as f:shutil.copyfileobj(proc.stdout,f)
assert proc.wait()==0;dump.chmod(0o600)
network='pdo-remaining-'+key;container=network+'-db';password=secrets.token_hex(24)
run(['docker','network','create','--internal',network],stdout=subprocess.DEVNULL)
try:
 run(['docker','run','-d','--rm','--name',container,'--network',network,'--network-alias','release-db','--tmpfs','/var/lib/mysql','-e','MARIADB_ROOT_PASSWORD='+password,'-e','MARIADB_DATABASE=chisimba_rehearsal','mariadb:10.11.18'],stdout=subprocess.DEVNULL)
 for attempt in range(60):
  if subprocess.run(['docker','exec',container,'mariadb','-uroot','-p'+password,'chisimba_rehearsal','-e','SELECT 1'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode==0:break
  time.sleep(1)
 else:raise RuntimeError('Clone not ready')
 with gzip.open(dump,'rb') as f:
  p=subprocess.Popen(['docker','exec','-i',container,'mariadb','-uroot','-p'+password,'chisimba_rehearsal'],stdin=subprocess.PIPE);shutil.copyfileobj(f,p.stdin);p.stdin.close();assert p.wait()==0
 def query(sql):return subprocess.check_output(['docker','exec','-i',container,'mariadb','-N','-B','-uroot','-p'+password,'chisimba_rehearsal'],input=sql.encode()).decode()
 columns={}
 for row in query('SELECT TABLE_NAME,COLUMN_NAME FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() ORDER BY TABLE_NAME,ORDINAL_POSITION;').splitlines():
  table,field=row.split('\t');columns.setdefault(table,[]).append(field)
 before=fingerprint(query,columns);(work/'columns.json').write_text(json.dumps(columns));(work/'protected-before.json').write_text(json.dumps(before,indent=2))
 clone=work/'config';shutil.copytree(config,clone);clone.chmod(0o700)
 (clone/'dbdetails_inc.php').write_text("<?php define('KEWL_DB_DSN','mysqli://root:"+password+"@release-db/chisimba_rehearsal');\n");(clone/'dbdetails_inc.php').chmod(0o600)
 xml=clone/'config.xml';s,n=re.subn(r'(<DATABASE_ABSTRACTION>).*?(</DATABASE_ABSTRACTION>)',r'\g<1>PDO\g<2>',xml.read_text(),flags=re.S);assert n==1;xml.write_text(s)
 args=['docker','run','--rm','--network',network,'--entrypoint','php','-e','PEAR_RELEASE=20261012','-e','REHEARSAL=1','-v',str(stage)+':'+root+':ro','-v',str(clone)+':'+root+'/config','-v',str(B)+':/release:ro','--tmpfs',root+'/error_log','--tmpfs',root+'/error_logs','--tmpfs','/var/lib/php/sessions','--tmpfs',root+'/usrfiles','--tmpfs',root+'/user_images','--tmpfs','/var/data/filemanager']
 for m in i['Mounts']:
  if m['Destination'].startswith('/usr/local/etc/php/'):args+=['-v',m['Source']+':'+m['Destination']+':ro']
 for label in ['verify','repeat']:
  r=subprocess.run(args+[image,'/release/operator.php','verify',host,root],capture_output=True);(work/(label+'.log')).write_bytes(r.stdout+r.stderr)
  assert r.returncode==0 and b'PASS verify PDO' in r.stdout,'Rehearsal failed '+label
  print(key+' '+r.stdout.decode().strip(),flush=True)
 after=fingerprint(query,columns);(work/'protected-after.json').write_text(json.dumps(after,indent=2));assert before==after,'Data changed '+','.join(t for t in before if before[t]!=after[t])
 (work/'prepared.json').write_text(json.dumps({'image':image,'imageId':candidate['Id'],'tables':len(before),'baselineHash':sha(work/'baseline.json'),'operatorHash':sha(B/'operator.php')},indent=2));print(key+' PREPARED '+str(len(before))+' tables unchanged',flush=True)
finally:
 subprocess.run(['docker','stop',container],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL);subprocess.run(['docker','network','rm',network],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
