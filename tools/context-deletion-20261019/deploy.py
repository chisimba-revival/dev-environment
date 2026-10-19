"""Apply the tested atomic course deletion delta on Chisimba.com only."""
import pathlib,json,hashlib,subprocess,shutil,datetime,os,fcntl,gzip
site=pathlib.Path('/srv/chisimba-com');b=site/'staging/context-deletion-20261019';cur=site/'app/current';previous=cur.resolve()
lock=open(site/'shared-release.lock','a');fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
assert not (b/'deployed.json').exists()
m=json.loads((b/'manifest.json').read_text())
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest() if p.exists() else None
def run(a,**kw):return subprocess.run(a,check=True,**kw)
for r in m:assert sha(previous/r['path'])==r['before'],'Live drift '+r['path'];assert sha(b/'payload'/r['path'])==r['after']
stamp=datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%d-%H%M%S');backup=site/'backups'/('context-deletion-'+stamp);backup.mkdir(mode=0o700)
release=site/'releases'/('release-context-deletion-'+stamp)/'ch';release.parent.mkdir();run(['cp','-a','--reflink=auto',str(previous),str(release)])
assert not (release/'packages').is_symlink(), 'Inspect shared modules mount before writing'
for r in m:
 p=release/r['path'];assert p.parent.resolve().is_relative_to(release.resolve()), 'Unsafe source parent';p.parent.mkdir(parents=True,exist_ok=True)
 if r['after'] is None:p.unlink()
 else:shutil.copy2(b/'payload'/r['path'],p)
web='chisimba-com-web-1';i=json.loads(subprocess.check_output(['docker','inspect',web]))[0]
for r in m:
 if r['after'] is not None and r['path'].endswith('.php'):run(['docker','run','--rm','--network','none','-v',str(release)+':/source:ro','--entrypoint','php',i['Image'],'-l','/source/'+r['path']],stdout=subprocess.DEVNULL)
cmd=['docker','compose','-p','chisimba-com','--env-file',str(site/'shared/secrets/production.env'),'-f',str(site/'app/deploy/compose.yml')]
shutil.copy2(site/'app/deploy/compose.yml',backup/'compose.yml');os.chmod(backup/'compose.yml',0o600)
proc=subprocess.Popen(['docker','exec','chisimba-com-db-1','sh','-c','exec mariadb-dump -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" --single-transaction --quick "$MARIADB_DATABASE"'],stdout=subprocess.PIPE)
with gzip.open(backup/'database.sql.gz','wb') as f:shutil.copyfileobj(proc.stdout,f)
assert proc.wait()==0;os.chmod(backup/'database.sql.gz',0o600)
with gzip.open(backup/'database.sql.gz','rb') as f:
 while f.read(1048576):pass
record=dict(previous=str(previous),release=str(release),backup=str(backup),modules='9a89992d764337e490bb48466bb0cae96a660cdd',framework='d05a19ac2b198338b614acc5eae50e111ce36680',status='prepared')
(backup/'release.json').write_text(json.dumps(record,indent=2));switched=False
try:
 network=next(iter(i['NetworkSettings']['Networks']))
 run(['docker','run','--rm','--volumes-from',web,'--network',network,'--user','www-data','--env-file',str(site/'shared/secrets/restapi.env'),'-e','RESTAPI_SITE_SETUP=chisimba.com','-e','CHISIMBA_JWKS_KEY_PATH=/var/data/restapi/jwks_private.pem','-e','CHISIMBA_DENYLIST_REDIS=restapi-redis:6379','-v',str(release)+':/var/www/html:ro','-v',str(b)+':/setup:ro','--entrypoint','php',i['Image'],'/setup/register.php','/var/www/html','www.chisimba.com'])
 for r in m:assert sha(previous/r['path'])==r['before'],'Live drift before switch'
 link=cur.parent/('.branding-'+stamp);link.symlink_to(release);os.replace(link,cur);switched=True
 run(cmd+['up','-d','--no-deps','--no-build','--force-recreate','web'])
 for r in m:assert sha(cur/r['path'])==r['after']
 record['status']='switched-awaiting-validation';(b/'deployed.json').write_text(json.dumps(record,indent=2));print('DEPLOYED '+str(backup))
except BaseException:
 if switched:
  link=cur.parent/('.branding-restore-'+stamp);link.symlink_to(previous);os.replace(link,cur);run(cmd+['up','-d','--no-deps','--no-build','--force-recreate','web'])
 record['status']='previous-source-retained';raise
finally:(backup/'release.json').write_text(json.dumps(record,indent=2))
