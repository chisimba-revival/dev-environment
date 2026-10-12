"""Release Kanban ordering tested through full PDO and MDB2 suites."""
from common import *
import fcntl,datetime
rows=json.loads((B/'manifest.json').read_text());base=current.resolve();i=inspect(web);image=i['Image']
for r in rows:assert sha(base/r['path'])==r['before'],'Unexpected source drift '+r['path'];assert sha(B/'payload'/r['path'])==r['after']
stamp=datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%d-%H%M%S');backup=site/'backups'/('kanban-order-'+stamp);release=site/'releases'/('release-kanban-order-'+stamp)/'ch';backup.mkdir(mode=0o700);release.parent.mkdir(parents=True)
run(['cp','-a','--reflink=auto',str(base),str(release)],stdout=subprocess.DEVNULL)
for r in rows:shutil.copy2(B/'payload'/r['path'],release/r['path']);(release/r['path']).chmod(0o644)
for r in rows:
 if r['path'].endswith('.php'):
  result=subprocess.run(['docker','run','--rm','--network','none','--entrypoint','php','-v',str(release)+':'+root+':ro',image,'-d','error_reporting=-1','-l',root+'/'+r['path']],capture_output=True)
  assert result.returncode==0 and not re.search(b'Warning|Deprecated|Fatal',result.stdout+result.stderr),'Lint failure'
net=set(i['NetworkSettings']['Networks'])&set(inspect(db)['NetworkSettings']['Networks']);assert len(net)==1;network=net.pop()
labels=i['Config']['Labels'];compose=pathlib.Path(labels['com.docker.compose.project.config_files']);shutil.copy2(compose,backup/'compose.yml');cmd=['docker','compose','-p',labels['com.docker.compose.project']]
if labels.get('com.docker.compose.project.environment_file'):cmd+=['--env-file',labels['com.docker.compose.project.environment_file']]
cmd+=['-f',str(compose)];env=os.environ.copy()
for entry in inspect(db)['Config']['Env']:
 name,_,value=entry.partition('=')
 if name.startswith('MARIADB_'):env[name]=value
record={'site':key,'previous':str(base),'release':str(release),'backup':str(backup),'imageId':image,'framework':'f5ddd8fb4','modules':'b1d15c6b5','kanban':'0.146','manifest':sha(B/'manifest.json')}
prepared=json.loads((work/'prepared.json').read_text());assert prepared['manifest']==sha(B/'manifest.json') and prepared['imageId']==image
offsets={}
for m in i['Mounts']:
 if m['Destination'] in [root+'/error_log',root+'/error_logs']:
  for p in pathlib.Path(m['Source']).rglob('*'):
   if p.is_file() and not p.is_symlink():offsets[str(p)]=p.stat().st_size
(backup/'logs-before.json').write_text(json.dumps(offsets))
locks=[];timers=[];stopped=False
try:
 for timer in cfg['timers']:
  assert out(['systemctl','is-active',timer])=='active'
  if key=='kengalearn':continue
  run(['systemctl','stop',timer]);timers.append(timer)
  for n in range(120):
   if subprocess.run(['systemctl','is-active','--quiet',timer.replace('.timer','.service')]).returncode!=0:break
   time.sleep(1)
  else:raise RuntimeError('Active worker')
 paths=[site/'pear-release.lock']+[pathlib.Path(x) for x in cfg['locks']]
 if key=='kengalearn':paths.append(pathlib.Path('/run/chisimba-communications-worker.lock'))
 for p in paths:
  f=open(p,'r' if p.exists() else 'a');fcntl.flock(f,fcntl.LOCK_EX|fcntl.LOCK_NB);locks.append(f)
 assert current.resolve()==base and inspect(web)['Image']==image
 run(['docker','stop',web],stdout=subprocess.DEVNULL);stopped=True
 proc=subprocess.Popen(['docker','exec',db,'sh','-c','exec mariadb-dump -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" --single-transaction --quick --routines --triggers "$MARIADB_DATABASE"'],stdout=subprocess.PIPE)
 with gzip.open(backup/'database.sql.gz','wb') as f:shutil.copyfileobj(proc.stdout,f)
 assert proc.wait()==0;(backup/'database.sql.gz').chmod(0o600)
 with gzip.open(backup/'database.sql.gz','rb') as f:
  while f.read(1048576):pass
 for r in rows:assert sha(base/r['path'])==r['before']
 link=current.parent/('.navigation-link-'+stamp);assert current.is_symlink();link.symlink_to(release);os.replace(link,current)
 args=['docker','run','--rm','--volumes-from',web,'--network',network,'--entrypoint','php','-v',str(release)+':'+root+':ro','-v',str(B)+':/release:ro','-e','KANBAN_RELEASE=0.146',image,'/release/upgrade.php',root,host]
 result=subprocess.run(args,capture_output=True);(backup/'upgrade.log').write_bytes(result.stdout+result.stderr);assert result.returncode==0 and b'KANBAN_CATALOGUE_0.146_PASS' in result.stdout,'Catalogue follow-up failed';print(result.stdout.decode().strip(),flush=True)
 for r in rows:assert sha(release/r['path'])==r['after']
 run(cmd+['up','-d','--no-deps','--no-build','--force-recreate','web'],env=env,stdout=subprocess.DEVNULL);stopped=False
 for n in range(30):
  result=subprocess.run(['curl','-sS','-L','--max-time','5','-o','/dev/null','-w','%{http_code}','https://'+host+'/'],capture_output=True)
  if result.returncode==0 and result.stdout==b'200':break
  time.sleep(1)
 else:raise RuntimeError('HTTP readiness failed')
 record['status']='online-verified';(backup/'release.json').write_text(json.dumps(record,indent=2));(work/'deployed.json').write_text(json.dumps(record,indent=2));print('KANBAN_DEPLOYED '+key+' '+str(backup),flush=True)
except BaseException:
 record['status']='stopped-for-diagnosis';record['stopped']=stopped;(backup/'release.json').write_text(json.dumps(record,indent=2));raise
finally:
 for f in locks:f.close()
 if not stopped:
  for timer in timers:run(['systemctl','start',timer])
