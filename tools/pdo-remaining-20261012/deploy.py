"""Switch one rehearsed site's image/backend; preserve its current code and database."""
from common import *
import fcntl,datetime
baseline=json.loads((work/'baseline.json').read_text());prepared=json.loads((work/'prepared.json').read_text())
assert not (work/'deployed.json').exists()
assert sha(work/'baseline.json')==prepared['baselineHash'] and sha(B/'operator.php')==prepared['operatorHash']
assert json.loads((work/'protected-before.json').read_text())==json.loads((work/'protected-after.json').read_text())
assert (work/'contracts-pass.json').exists(),'Database contracts must pass on this staged code/image'
assert json.loads((work/'contracts-pass.json').read_text())['imageId']==prepared['imageId']
assert json.loads((work/'contracts-pass.json').read_text())['baselineHash']==prepared['baselineHash']
i=inspect(web);image=prepared['image'];assert i['State']['Running'] and i['Image']==baseline['imageId'];assert inspect(image)['Id']==prepared['imageId']
assert str(current.resolve())==baseline['code'];base=current.resolve();config=pathlib.Path(baseline['config']);compose=pathlib.Path(baseline['compose'])
def check_source():
 for path,digest in baseline['files'].items():assert sha(base/path)==digest,'Source drift '+path
check_source()
for name,digest in baseline['configHashes'].items():assert sha(config/name)==digest,'Configuration drift'
assert sha(compose)==baseline['composeHash']
original=compose.read_text();lines=original.splitlines(keepends=True);inside=False;count=0
for n,line in enumerate(lines):
 if re.match(r'^  web:\s*$',line):inside=True;continue
 if inside and re.match(r'^  \S',line):inside=False
 if inside and re.match(r'^    image:',line):lines[n]='    image: '+image+'\n';count+=1
assert count==1;candidate=''.join(lines)
xml=config/'config.xml';newxml,n=re.subn(r'(<DATABASE_ABSTRACTION>)\s*MDB2\s*(</DATABASE_ABSTRACTION>)',r'\g<1>PDO\g<2>',xml.read_text());assert n==1
stamp=datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%d-%H%M%S');backup=site/'backups'/('pdo-'+stamp);backup.mkdir(mode=0o700)
shutil.copy2(compose,backup/'compose.yml');shutil.copy2(xml,backup/'config-before.xml');(backup/'config-before.xml').chmod(0o600)
record={'site':key,'code':str(base),'backup':str(backup),'oldImageId':i['Image'],'newImageId':prepared['imageId'],'newImage':image,'status':'prepared','startedUTC':stamp}
logs={}
for m in i['Mounts']:
 if m['Destination'] in [root+'/error_log',root+'/error_logs']:
  for p in pathlib.Path(m['Source']).rglob('*'):
   if p.is_file() and not p.is_symlink():logs[str(p)]=p.stat().st_size
(backup/'logs-before.json').write_text(json.dumps(logs))
network=set(i['NetworkSettings']['Networks'])&set(inspect(db)['NetworkSettings']['Networks']);assert len(network)==1;network=network.pop()
labels=i['Config']['Labels'];cmd=['docker','compose','-p',labels['com.docker.compose.project']]
if labels.get('com.docker.compose.project.environment_file'):cmd+=['--env-file',labels['com.docker.compose.project.environment_file']]
cmd+=['-f',str(compose)];env=os.environ.copy()
for entry in inspect(db)['Config']['Env']:
 name,_,value=entry.partition('=')
 if name.startswith('MARIADB_'):env[name]=value
columns=json.loads((work/'columns.json').read_text())
def query(q):return subprocess.check_output(['docker','exec','-i',db,'sh','-c','exec mariadb -N -B -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" "$MARIADB_DATABASE"'],input=q.encode()).decode()
locks=[];timers=[];stopped=False
try:
 for timer in cfg['timers']:
  assert out(['systemctl','is-active',timer])=='active';run(['systemctl','stop',timer]);timers.append(timer)
  for attempt in range(120):
   if subprocess.run(['systemctl','is-active','--quiet',timer.replace('.timer','.service')]).returncode!=0:break
   time.sleep(1)
  else:raise RuntimeError('Worker still running')
 for path in [site/'pdo-release.lock']+[pathlib.Path(x) for x in cfg['locks']]:
  f=open(path,'r' if path.exists() else 'a');fcntl.flock(f,fcntl.LOCK_EX|fcntl.LOCK_NB);locks.append(f)
 check_source();assert sha(compose)==baseline['composeHash']
 for name,digest in baseline['configHashes'].items():assert sha(config/name)==digest
 run(['docker','stop',web],stdout=subprocess.DEVNULL);stopped=True;print(key+' WRITERS_STOPPED',flush=True)
 proc=subprocess.Popen(['docker','exec',db,'sh','-c','exec mariadb-dump -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" --single-transaction --quick --routines --triggers "$MARIADB_DATABASE"'],stdout=subprocess.PIPE)
 with gzip.open(backup/'database.sql.gz','wb') as f:shutil.copyfileobj(proc.stdout,f)
 assert proc.wait()==0;(backup/'database.sql.gz').chmod(0o600)
 with gzip.open(backup/'database.sql.gz','rb') as f:
  while f.read(1048576):pass
 archive='tar -czpf /backup/persistent-files.tar.gz -C / '+root[1:]+'/config '+root[1:]+'/usrfiles '+root[1:]+'/user_images var/data/filemanager var/lib/php/sessions && chmod 600 /backup/persistent-files.tar.gz'
 run(['docker','run','--rm','--user','0','--network','none','--volumes-from',web+':ro','-v',str(backup)+':/backup','--entrypoint','sh',i['Image'],'-c',archive],stdout=subprocess.DEVNULL)
 run(['tar','-tzf',str(backup/'persistent-files.tar.gz')],stdout=subprocess.DEVNULL)
 before=fingerprint(query,columns);(backup/'protected-before.json').write_text(json.dumps(before));print(key+' BACKUPS_VERIFIED',flush=True)
 xml.write_text(newxml);compose.write_text(candidate)
 r=subprocess.run(['docker','run','--rm','--volumes-from',web,'--network',network,'--entrypoint','php','-e','PEAR_RELEASE=20261012','-v',str(B)+':/release:ro',image,'/release/operator.php','verify',host,root],capture_output=True)
 (backup/'verify.log').write_bytes(r.stdout+r.stderr);assert r.returncode==0 and b'PASS verify PDO' in r.stdout,'Strict PDO verification failed';print(r.stdout.decode().strip(),flush=True)
 after=fingerprint(query,columns);(backup/'protected-after.json').write_text(json.dumps(after));assert before==after,'Database changed during backend switch'
 check_source()
 run(cmd+['up','-d','--no-deps','--no-build','--force-recreate','web'],env=env,stdout=subprocess.DEVNULL);stopped=False
 assert inspect(web)['Image']==prepared['imageId']
 for attempt in range(30):
  r=subprocess.run(['curl','-sS','-L','--max-time','5','-o','/dev/null','-w','%{http_code}','https://'+host+'/'],capture_output=True)
  if r.returncode==0 and r.stdout==b'200':break
  time.sleep(1)
 else:raise RuntimeError('Homepage did not reopen')
 for route in ['index.php?module=security&action=showlogin','index.php?module=registration-service&action=forgotpassword','index.php?module=contactform']:
  r=subprocess.run(['curl','-f','-sS','-L','--max-time','20','https://'+host+'/'+route],capture_output=True)
  assert r.returncode==0 and r.stdout and not re.search(rb'Fatal error|Uncaught .*Exception|SQLSTATE\[|<b>Warning</b>|<b>Deprecated</b>',r.stdout),'HTTP smoke failed'
  print(key+' HTTP_PASS '+route,flush=True)
 record.update(status='online-pdo-verified',tablesUnchanged=len(before),databaseHash=sha(backup/'database.sql.gz'),persistentHash=sha(backup/'persistent-files.tar.gz'))
 (backup/'release.json').write_text(json.dumps(record,indent=2));(work/'deployed.json').write_text(json.dumps(record,indent=2));print(key+' DEPLOYED '+str(backup),flush=True)
except BaseException:
 record.update(status='stopped-for-diagnosis',webStopped=stopped);(backup/'release.json').write_text(json.dumps(record,indent=2));raise
finally:
 for f in locks:f.close()
 if not stopped:
  for timer in timers:run(['systemctl','start',timer])
