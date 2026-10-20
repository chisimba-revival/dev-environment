"""Apply the committed one-line PHP 8.5 cleanup fix without changing data/schema."""
import pathlib,subprocess,json,hashlib,os,fcntl,datetime
site=pathlib.Path('/srv/chisimba-com');link=site/'app/current';old=link.resolve()
relative='packages/video-service/classes/muxvideoprovider_class_inc.php'
candidate=pathlib.Path('/tmp/muxvideoprovider-php85.php');new=candidate.read_bytes()
assert b'unset($curl);' in new and b'curl_close(' not in new
assert (old/relative).read_bytes()==new.replace(b'unset($curl);',b'curl_close($curl);')
def run(args,**kw):return subprocess.run(args,check=True,**kw)
def inspect(name):return json.loads(subprocess.check_output(['docker','inspect',name]))[0]
web='chisimba-com-web-1';info=inspect(web);assert info['State']['Running']
run(['docker','cp',str(candidate),web+':/tmp/muxvideoprovider-php85.php'])
run(['docker','exec',web,'php','-l','/tmp/muxvideoprovider-php85.php'])
stamp=datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%d-%H%M%S')
release=site/'releases'/('release-video-php85-'+stamp)/'ch';backup=site/'backups'/('video-php85-'+stamp)
with open(site/'shared-release.lock','a') as lock:
 fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
 assert link.resolve()==old and (old/relative).read_bytes()==new.replace(b'unset($curl);',b'curl_close($curl);')
 backup.mkdir(mode=0o700);release.parent.mkdir(parents=True)
 run(['cp','-a','--reflink=auto',str(old),str(release)])
 (backup/'muxvideoprovider.before.php').write_bytes((old/relative).read_bytes())
 (release/relative).write_bytes(new)
 labels=info['Config']['Labels'];cmd=['docker','compose','-p',labels['com.docker.compose.project']]
 if labels.get('com.docker.compose.project.environment_file'):cmd+=['--env-file',labels['com.docker.compose.project.environment_file']]
 cmd+=['-f',labels['com.docker.compose.project.config_files'],'up','-d','--no-deps','--no-build','--force-recreate','web']
 env=os.environ.copy()
 for entry in inspect('chisimba-com-db-1')['Config']['Env']:
  name,_,value=entry.partition('=')
  if name.startswith('MARIADB_'):env[name]=value
 def switch(path):
  tmp=link.parent/('.video-php85-'+stamp);tmp.symlink_to(path);os.replace(tmp,link)
 switch(release)
 try:
  run(cmd,env=env)
  run(['curl','--fail','--silent','--show-error','--retry','5','--retry-delay','2','--max-time','15','-o','/dev/null','https://www.chisimba.com/index.php?module=security&action=showlogin'])
 except BaseException:
  switch(old);run(cmd,env=env);raise
 receipt={'previous':str(old),'release':str(release),'backup':str(backup),'modulesCommit':'7c2935718','path':relative,'sha256':hashlib.sha256(new).hexdigest(),'schemaChanges':False,'health':'passed'}
 (backup/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n');print(json.dumps(receipt,indent=2))
