"""Deploy one rehearsed candidate. Never auto-restore a live database."""
import pathlib,sys,subprocess,json,hashlib,shutil,gzip,os,time,re,fcntl,datetime
B=pathlib.Path(__file__).resolve().parent;key='learnthebirds'
site=pathlib.Path('/srv/learnthebirds.com');web='learnthebirds-migrate-web-1';db='learnthebirds-migrate-db-1';host='learnthebirds.com'
def out(a):return subprocess.check_output(a,text=True).strip()
def run(a,**kw):return subprocess.run(a,check=True,**kw)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest() if p.is_file() else None
work=B/key;manifest=json.loads((B/'manifest.json').read_text());baseline=json.loads((work/'baseline.json').read_text());prepared=json.loads((work/'prepared.json').read_text());current=site/'app/current';previous=current.resolve()
assert str(previous)==baseline['code'];assert prepared['manifest']==sha(B/'manifest.json')
assert json.loads((work/'protected-before.json').read_text())==json.loads((work/'protected-after.json').read_text())
assert not (work/'deployed.json').exists()
i=json.loads(out(['docker','inspect',web]))[0];assert i['Image']==baseline['imageId'];image=prepared['image'];assert json.loads(out(['docker','image','inspect',image]))[0]['Id']==prepared['imageId']
for r in baseline['files']:assert sha(previous/r['path'])==r['before'],'Live drift '+r['path']
for r in manifest:assert sha(work/'stage'/r['path'])==r['after'],'Stage drift '+r['path']
networks=set(i['NetworkSettings']['Networks'])&set(json.loads(out(['docker','inspect',db]))[0]['NetworkSettings']['Networks']);assert len(networks)==1;network=networks.pop()
stamp=datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%d-%H%M%S');backup=site/'backups'/('pdo-'+stamp);release=site/'releases'/('release-pdo-'+stamp)/'ch';backup.mkdir(mode=0o700);release.parent.mkdir()
run(['cp','-a','--reflink=auto',str(work/'stage'),str(release)],stdout=subprocess.DEVNULL)
compose=site/'app/deploy/compose.yml';original=compose.read_text();lines=original.splitlines(keepends=True);inside=False;count=0
for n,line in enumerate(lines):
 if re.match(r'^  web:\s*$',line):inside=True;continue
 if inside and re.match(r'^  \S',line):inside=False
 if inside and re.match(r'^    image:',line):lines[n]='    image: '+image+'\n';count+=1
assert count==1;candidate=''.join(lines);(backup/'compose.yml').write_text(original)
# The old tag may have moved since the live container started. Record exact IDs.
record={'site':key,'host':host,'previous':str(previous),'release':str(release),'backup':str(backup),'oldImageId':i['Image'],'newImageId':prepared['imageId'],'commits':json.loads((B/'commits.json').read_text()),'manifest':sha(B/'manifest.json'),'startedUTC':stamp,'status':'prepared'}
(backup/'release.json').write_text(json.dumps(record,indent=2))
composecmd=['docker','compose','--env-file',i['Config']['Labels']['com.docker.compose.project.environment_file'],'-f',str(compose)]
def invoke(mode):
 args=['docker','run','--rm','--volumes-from',web,'--network',network,'--entrypoint','php','-e','PDO_RELEASE=20261011','-v',str(B)+':/release:ro']
 if switched and stopped:
  assert not json.loads(out(['docker','inspect',web]))[0]['State']['Running']
  args+=['-v',str(release)+':/var/www/html:ro','-e','PDO_SWITCH_STOPPED=1']
 args += [image,'/release/operator.php',mode,host]
 r=subprocess.run(args,capture_output=True)
 with open(backup/'operations.log','ab') as f:f.write(r.stdout+r.stderr)
 assert r.returncode==0,'Operator failed '+mode
 text=r.stdout.decode(errors='replace')
 for line in text.splitlines():
  if line.startswith(('PASS ','STATE ','UPDATED ','MAINTENANCE_MODULE ')):print(line,flush=True)
 assert ('STATE ' if mode=='state' else 'PASS '+mode) in text,'Missing acknowledgement '+mode
 return text
columns=json.loads((work/'columns.json').read_text())
def sql(q):return subprocess.check_output(['docker','exec','-i',db,'sh','-c','exec mariadb -N -B -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" "$MARIADB_DATABASE"'],input=q.encode()).decode()
def fingerprint():
 statements=[];grouped={t:[] for t in columns}
 for table,fields in columns.items():
  assert re.fullmatch('[a-zA-Z0-9_]+',table) and all(re.fullmatch('[a-zA-Z0-9_]+',f) for f in fields)
  statements.append("SELECT '"+table+"',SHA2(CAST(JSON_ARRAY("+','.join('`'+f+'`' for f in fields)+") AS CHAR),256) AS rowhash FROM `"+table+"` ORDER BY rowhash;")
 for row in sql('\n'.join(statements)).splitlines():
  table,digest=row.split('\t');grouped[table].append(digest+'\n')
 return {t:{'rows':len(rows),'sha256':hashlib.sha256(''.join(rows).encode()).hexdigest()} for t,rows in grouped.items()}
def switch(target):
 link=current.parent/('.pdo-link-'+stamp);assert not link.exists();link.symlink_to(target);os.replace(link,current)
def readiness():
 for attempt in range(30):
  r=subprocess.run(['curl','-sS','-L','-o','/dev/null','-w','%{http_code}','--max-time','5','https://'+host+'/index.php?module=security&action=showlogin'],capture_output=True)
  if r.returncode==0 and r.stdout==b'200':return
  time.sleep(1)
 raise RuntimeError('HTTP readiness failed')
locks=[];offline=False;stopped=False;switched=False
try:
 paths=[site/'app/pdo-release.lock','/run/lock/learnthebirds-mail.lock']
 run(['systemctl','stop','learnthebirds-mail.timer'])
 if key=='kengalearn':paths += [site/'app/chisimba-ai-worker.lock',site/'worksheet-ai-worker.lock']
 for p in paths:
  f=open(p,'a');fcntl.flock(f,fcntl.LOCK_EX if str(p)=='/run/lock/learnthebirds-mail.lock' else fcntl.LOCK_EX|fcntl.LOCK_NB);locks.append(f)
 state=invoke('state');assert 'STATE 0\n' in state or 'STATE unset\n' in state,'Existing maintenance state must be preserved'
 maintenance='MAINTENANCE_MODULE 1' in state
 if maintenance:
  invoke('offline');offline=True;assert 'STATE 1' in invoke('state')
 run(['docker','stop',web],stdout=subprocess.DEVNULL);stopped=True;print('WRITERS_STOPPED',flush=True)
 proc=subprocess.Popen(['docker','exec',db,'sh','-c','exec mariadb-dump -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" --single-transaction --quick --routines --triggers "$MARIADB_DATABASE"'],stdout=subprocess.PIPE)
 with gzip.open(backup/'database.sql.gz','wb') as f:shutil.copyfileobj(proc.stdout,f)
 assert proc.wait()==0;(backup/'database.sql.gz').chmod(0o600)
 with gzip.open(backup/'database.sql.gz','rb') as f:
  while f.read(1048576):pass
 archive='tar -czpf /backup/persistent-files.tar.gz -C / var/www/html/config var/www/html/usrfiles var/www/html/user_images var/data/filemanager var/lib/php/sessions && cp -p /var/www/html/config/config.xml /backup/config-before.xml && chown '+str(os.getuid())+':'+str(os.getgid())+' /backup/persistent-files.tar.gz /backup/config-before.xml && chmod 600 /backup/persistent-files.tar.gz /backup/config-before.xml'
 run(['docker','run','--rm','--user','0','--network','none','--volumes-from',web+':ro','-v',str(backup)+':/backup','--entrypoint','sh',i['Image'],'-c',archive],stdout=subprocess.DEVNULL)
 run(['tar','-tzf',str(backup/'persistent-files.tar.gz')],stdout=subprocess.DEVNULL)
 before=fingerprint();(backup/'protected-before.json').write_text(json.dumps(before,indent=2));print('BACKUPS_VERIFIED',flush=True)
 for r in baseline['files']:assert sha(previous/r['path'])==r['before'],'Live drift before switch'
 # Preserve original configuration contents and file permissions; only select PDO.
 php='$p="/var/www/html/config/config.xml";$s=file_get_contents($p);$s=preg_replace("~(<DATABASE_ABSTRACTION>).*?(</DATABASE_ABSTRACTION>)~s","${1}PDO${2}",$s,-1,$n);if($n!==1)exit(1);if(file_put_contents($p,$s)===false)exit(1);'
 # Avoid PHP interpolation in the replacement by using a callback.
 php=php.replace('preg_replace("~(<DATABASE_ABSTRACTION>).*?(</DATABASE_ABSTRACTION>)~s","${1}PDO${2}",$s,-1,$n)','preg_replace_callback("~(<DATABASE_ABSTRACTION>).*?(</DATABASE_ABSTRACTION>)~s",fn($m)=>$m[1]."PDO".$m[2],$s,-1,$n)')
 run(['docker','run','--rm','--user','0','--network','none','--volumes-from',web,'--entrypoint','php',image,'-r',php],stdout=subprocess.DEVNULL)
 compose.write_text(candidate);switch(release);switched=True
 invoke('upgrade');invoke('verify')
 after=fingerprint();(backup/'protected-after.json').write_text(json.dumps(after,indent=2));assert before==after,'Protected data changed '+','.join(t for t in before if before[t]!=after[t])
 for r in manifest:assert sha(release/r['path'])==r['after'],'Deployed hash mismatch'
 if maintenance:
  assert 'STATE 1' in invoke('state');invoke('online');offline=False
 run(composecmd+['up','-d','--no-deps','--no-build','--force-recreate','web'],stdout=subprocess.DEVNULL);stopped=False
 readiness()
 for route in ['', 'index.php?module=security&action=showlogin','index.php?module=registration-service&action=forgotpassword']:
  r=subprocess.run(['curl','-sS','-L','--max-time','20','https://'+host+'/'+route],capture_output=True);assert r.returncode==0 and r.stdout and not re.search(rb'(Fatal error|Uncaught .*Exception|SQLSTATE\[)',r.stdout),'Public smoke failed';print('HTTP_PASS '+route,flush=True)
 run(['systemctl','start','learnthebirds-mail.timer'])
 record.update(status='online-pdo-verified',database=sha(backup/'database.sql.gz'),persistentFiles=sha(backup/'persistent-files.tar.gz'),protectedTables=len(before))
 (backup/'release.json').write_text(json.dumps(record,indent=2));(work/'deployed.json').write_text(json.dumps(record,indent=2));print('DEPLOYED '+str(backup),flush=True)
except BaseException:
 record.update(status='stopped-for-diagnosis',offline=offline,stopped=stopped,switched=switched);(backup/'release.json').write_text(json.dumps(record,indent=2))
 print('STOPPED. Backups and exact previous code/image/config retained at '+str(backup)+'. No database rollback attempted.',flush=True)
 raise
finally:
 for f in locks:f.close()
