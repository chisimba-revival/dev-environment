"""Keep capability query strings and referrers out of this site's access logs."""
import pathlib,hashlib,json,subprocess,shutil
FORMAT='%h %l %u %t \\"%m %U %H\\" %>s %O \\"%{User-Agent}i\\"'
HOST=pathlib.Path('/etc/apache2/sites-available/chisimba.com.conf')
APP=pathlib.Path('/srv/chisimba-com/app/deploy/chisimba-restapi.conf')
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def prepare(work,image):
 target=work/'logging';target.mkdir(mode=0o700,exist_ok=True);records=[]
 for p in [HOST,APP]:
  old=p.read_text()
  if p==HOST:
   assert old.count('CustomLog ${APACHE_LOG_DIR}/chisimba.com-access.log combined')==2
   new=old.replace('CustomLog ${APACHE_LOG_DIR}/chisimba.com-access.log combined','CustomLog ${APACHE_LOG_DIR}/chisimba.com-access.log "'+FORMAT+'"')
  else:
   assert 'Video-service access log policy' not in old
   new=old+'\n# Video-service access log policy: paths only, no query strings or referrers.\nLogFormat "'+FORMAT+'" combined\n'
  candidate=target/p.name;candidate.write_text(new);candidate.chmod(0o600)
  records.append({'path':str(p),'before':digest(p),'candidate':str(candidate),'after':digest(candidate)})
 # Parse the application policy with the exact existing Apache image.
 subprocess.run(['docker','run','--rm','--network','none','--entrypoint','apache2ctl','-v',str(target/APP.name)+':/etc/apache2/conf-enabled/chisimba-restapi.conf:ro',image,'-t'],check=True)
 (target/'manifest.json').write_text(json.dumps(records,indent=2))
 print('LOG_POLICY_PREPARED',flush=True)
def apply(work,backup):
 records=json.loads((work/'logging/manifest.json').read_text())
 for r in records:
  p=pathlib.Path(r['path']);candidate=pathlib.Path(r['candidate'])
  assert digest(p)==r['before'] and digest(candidate)==r['after'],'Logging configuration drift'
 for r in records:
  p=pathlib.Path(r['path']);shutil.copy2(p,backup/(p.name+'.before'));p.write_bytes(pathlib.Path(r['candidate']).read_bytes())
 try:subprocess.run(['apache2ctl','configtest'],check=True)
 except BaseException:
  for r in records:
   p=pathlib.Path(r['path']);shutil.copy2(backup/(p.name+'.before'),p)
  raise
 subprocess.run(['systemctl','reload','apache2'],check=True)
 (backup/'logging-manifest.json').write_text(json.dumps(records,indent=2))
 print('LOG_POLICY_APPLIED',flush=True)
