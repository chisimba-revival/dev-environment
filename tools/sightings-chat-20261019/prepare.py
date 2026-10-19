from common import *
work.mkdir(mode=0o700,exist_ok=True);stage=work/'stage';current=current.resolve();expected=json.loads((B/(key+'-hashes.json')).read_text())
i=json.loads(out(['docker','inspect',web]))[0];image=i['Image']
baseline={'code':str(current),'image':i['Config']['Image'],'imageId':i['Image'],'files':[]}
for r in manifest:
 assert sha(current/r['path'])==expected[r['path']],'Live drift '+r['path']
 baseline['files'].append({'path':r['path'],'before':expected[r['path']]})
(work/'baseline.json').write_text(json.dumps(baseline,indent=2))
if stage.exists():
 for r in manifest:assert sha(stage/r['path'])==r['after'],'Staged drift '+r['path']
else:
 run(['cp','-a','--reflink=auto',str(current),str(stage)],stdout=subprocess.DEVNULL)
 for r in manifest:
  p=stage/r['path'];assert not p.is_symlink() and p.resolve().is_relative_to(stage.resolve())
  if r['after'] is None:p.unlink(missing_ok=True);continue
  source=B/'payload'/r['path'];assert sha(source)==r['after'];p.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source,p);p.chmod(p.stat().st_mode|0o444)
  for d in p.parents:
   if d==stage:break
   d.chmod(d.stat().st_mode|0o555)
prune(stage)
(work/'effective-manifest.json').write_text(json.dumps(manifest))
print(key+' STAGED',flush=True)
# Compile using the exact candidate image and candidate filesystem in one invocation.
linter=work/'lint.php';linter.write_text('''<?php $bad=[];foreach(json_decode(file_get_contents('/release/__KEY__/effective-manifest.json'),true) as $r){if($r['after']===null||!preg_match('/\\.(php|inc)$/',$r['path']))continue;$extra=str_ends_with($r['path'],'ai/tests/transport_failure_test.php')?' -d disable_functions=curl_init,curl_setopt_array,curl_exec,curl_error,curl_errno,curl_getinfo':'';$cmd=escapeshellarg(PHP_BINARY).$extra.' -d error_reporting=-1 -d display_errors=1 -l '.escapeshellarg('__ROOT__/'. $r['path']);exec($cmd.' 2>&1',$o,$s);if($s||preg_grep('/Warning|Deprecated|Fatal|Parse error/',$o))$bad[$r['path']]=$o;$o=[];}echo json_encode($bad);exit(count($bad)?1:0);'''.replace('__ROOT__',root).replace('__KEY__',key))
if not (work/'lint.log').exists() or (work/'lint.log').read_text()!='[]':
 r=subprocess.run(['docker','run','--rm','--network','none','--entrypoint','php','-v',str(stage)+':'+root+':ro','-v',str(B)+':/release:ro',image,'/release/'+key+'/lint.php'],capture_output=True);(work/'lint.log').write_bytes(r.stdout+r.stderr);assert r.returncode==0,'Lint failed';print(key+' LINT_PASS',flush=True)
dump=work/'database.sql.gz';proc=subprocess.Popen(['docker','exec',db,'sh','-c','exec mariadb-dump -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" --single-transaction --quick --routines --triggers "$MARIADB_DATABASE"'],stdout=subprocess.PIPE)
with gzip.open(dump,'wb') as f:shutil.copyfileobj(proc.stdout,f)
assert proc.wait()==0;dump.chmod(0o600)
network='sightings-chat-release-'+key;container=network+'-db';password=secrets.token_hex(24)
run(['docker','network','create','--internal',network],stdout=subprocess.DEVNULL)
try:
 run(['docker','run','-d','--rm','--name',container,'--network',network,'--network-alias','release-db','--tmpfs','/var/lib/mysql','-e','MARIADB_ROOT_PASSWORD='+password,'-e','MARIADB_DATABASE=chisimba_rehearsal','mariadb:10.11.18'],stdout=subprocess.DEVNULL)
 for attempt in range(45):
  if subprocess.run(['docker','exec',container,'mariadb','-uroot','-p'+password,'chisimba_rehearsal','-e','SELECT 1'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode==0:break
  time.sleep(1)
 else:raise RuntimeError('Clone not ready')
 with gzip.open(dump,'rb') as f:
  p=subprocess.Popen(['docker','exec','-i',container,'mariadb','-uroot','-p'+password,'chisimba_rehearsal'],stdin=subprocess.PIPE);shutil.copyfileobj(f,p.stdin);p.stdin.close();assert p.wait()==0
 def query(sql):return subprocess.check_output(['docker','exec','-i',container,'mariadb','-N','-B','-uroot','-p'+password,'chisimba_rehearsal'],input=sql.encode()).decode()
 excluded=('tbl_module_blocks','tbl_modules','tbl_en','tbl_languagetext','tbl_menu','tbl_perms','tbl_sysconfig','tbl_systext','tbl_permissions','tbl_groupadmin','tbl_frontpage','tbl_userparams')
 columns={}
 for row in query("SELECT TABLE_NAME,COLUMN_NAME FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() ORDER BY TABLE_NAME,ORDINAL_POSITION;").splitlines():
  table,field=row.split('\t');
  if table.startswith(excluded):continue
  assert re.fullmatch('[a-zA-Z0-9_]+',table) and re.fullmatch('[a-zA-Z0-9_]+',field)
  columns.setdefault(table,[]).append(field)
 def fingerprint():
  statements=[];grouped={t:[] for t in columns}
  for table,fields in columns.items():
   statements.append("SELECT '"+table+"',SHA2(CAST(JSON_ARRAY("+','.join('`'+f+'`' for f in fields)+") AS CHAR),256) AS rowhash FROM `"+table+"` ORDER BY rowhash;")
  for row in query('\n'.join(statements)).splitlines():
   table,digest=row.split('\t');grouped[table].append(digest+'\n')
  return {t:{'rows':len(rows),'sha256':hashlib.sha256(''.join(rows).encode()).hexdigest()} for t,rows in grouped.items()}
 navigation_before=navigation_fingerprints(query);(work/'navigation-protected-before.json').write_text(json.dumps(navigation_before))
 before=fingerprint();(work/'columns.json').write_text(json.dumps(columns));(work/'protected-before.json').write_text(json.dumps(before,indent=2))
 clone=work/'config';clone.mkdir(mode=0o700,exist_ok=True)
 run(['docker','run','--rm','--network','none','--entrypoint','sh','-v',next(m['Source'] for m in i['Mounts'] if m['Destination']==root+'/config')+':/source:ro','-v',str(clone)+':/dest',image,'-c','cp -a /source/. /dest/ && chown -R '+str(os.getuid())+':'+str(os.getgid())+' /dest'])
 (clone/'dbdetails_inc.php').unlink();(clone/'dbdetails_inc.php').write_text("<?php define('KEWL_DB_DSN','mysqli://root:"+password+"@release-db/chisimba_rehearsal');\n");(clone/'dbdetails_inc.php').chmod(0o600)
 # Preserve the site's selected database backend in the rehearsal.
 args=['docker','run','--rm','--network',network,'--entrypoint','php','-e','PATCH_RELEASE=20261019','-e','REHEARSAL=1','-v',str(stage)+':'+root+':ro','-v',str(clone)+':'+root+'/config','-v',str(B)+':/release:ro','--tmpfs',root+'/error_log','--tmpfs',root+'/error_logs','--tmpfs','/var/lib/php/sessions','--tmpfs',root+'/usrfiles','--tmpfs',root+'/user_images','--tmpfs','/var/data/filemanager']
 for m in i['Mounts']:
  if m['Destination'].startswith('/usr/local/etc/php/'):args+=['-v',m['Source']+':'+m['Destination']+':ro']
 for label,mode in [('upgrade','upgrade'),('repeat','upgrade'),('verify','verify'),('media','media')]:
  r=subprocess.run(args+[image,'/release/operator.php',mode,host,root],capture_output=True);(work/(label+'.log')).write_bytes(r.stdout+r.stderr)
  for line in r.stdout.decode(errors='replace').splitlines():
   if line.startswith(('PASS ','UPDATED ')):print(key+' '+line,flush=True)
  assert r.returncode==0 and ('PASS '+mode).encode() in r.stdout,'Rehearsal failed '+label
 navigation_after=navigation_fingerprints(query);(work/'navigation-protected-after.json').write_text(json.dumps(navigation_after));assert all(row in navigation_after for row in navigation_before),'Existing site navigation changed'
 after=fingerprint();(work/'protected-after.json').write_text(json.dumps(after,indent=2));assert before==after,'Business data changed '+','.join(t for t in before if before[t]!=after[t])
 (work/'prepared.json').write_text(json.dumps({'manifest':sha(B/'manifest.json'),'effectiveManifest':sha(work/'effective-manifest.json'),'imageId':json.loads(out(['docker','image','inspect',image]))[0]['Id'],'image':image,'tables':len(before)},indent=2));print(key+' PREPARED '+str(len(before))+' protected tables',flush=True)
finally:
 subprocess.run(['docker','stop',container],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL);subprocess.run(['docker','network','rm',network],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)

shutil.rmtree(clone)
dump.unlink()
