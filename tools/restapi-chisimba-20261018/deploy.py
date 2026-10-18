"""Guarded, site-specific deployment of tested shared API commit 4a02aad40.
Run on the authorised host after source manifest verification and local checks.
Preserves existing releases, configuration, uploads, database and secret material.
"""
import pathlib, subprocess, json, hashlib, shutil, datetime, os, secrets, gzip, fcntl
site=pathlib.Path('/srv/chisimba-com'); bundle=site/'staging/restapi-20261018'; current=site/'app/current'
web='chisimba-com-web-1'; db='chisimba-com-db-1'
def run(args,**kw):return subprocess.run(args,check=True,**kw)
def out(args):return subprocess.check_output(args).decode().strip()
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest() if p.exists() else None
lock=open(site/'shared-release.lock','a');fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
assert not (bundle/'deployed.json').exists(), 'Already deployed'
manifest=json.loads((bundle/'manifest.json').read_text()); previous=current.resolve()
for r in manifest:
 assert sha(previous/r['path']) in (r['before'],r['after']), 'Source drift: '+r['path']
 if r['after']:assert sha(bundle/'payload'/r['path'])==r['after']
i=json.loads(out(['docker','inspect',web]))[0]
assert i['State']['Running'];assert i['Config']['Image']=='chisimba/pdo:20261011'
compose=site/'app/deploy/compose.yml'; original=compose.read_text()
assert 'restapi' not in original and '    networks: [internal]' in original
stamp=datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%d-%H%M%S')
backup=site/'backups'/('restapi-'+stamp);backup.mkdir(mode=0o700)
release=site/'releases'/('release-restapi-'+stamp)/'ch';release.parent.mkdir()
run(['cp','-a','--reflink=auto',str(previous),str(release)])
for r in manifest:
 p=release/r['path']
 if r['after']:p.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(bundle/'payload'/r['path'],p)
 elif p.exists():p.unlink()
# Lint the actual assembled delta with the existing production PHP image.
phpfiles=[str(pathlib.Path('/source')/r['path']) for r in manifest if r['after'] and r['path'].endswith('.php')]
for p in phpfiles:
 run(['docker','run','--rm','--network','none','-v',str(release)+':/source:ro','--entrypoint','php',i['Image'],'-l',p],stdout=subprocess.DEVNULL)
print('PASS assembled PHP lint',flush=True)
shutil.copy2(compose,backup/'compose.yml');os.chmod(backup/'compose.yml',0o600)
run(['tar','-czpf',str(backup/'config.tar.gz'),'-C',str(site/'shared'),'config']);os.chmod(backup/'config.tar.gz',0o600)
proc=subprocess.Popen(['docker','exec',db,'sh','-c','exec mariadb-dump -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" --single-transaction --quick --routines --triggers "$MARIADB_DATABASE"'],stdout=subprocess.PIPE)
with gzip.open(backup/'database.sql.gz','wb') as f:shutil.copyfileobj(proc.stdout,f)
assert proc.wait()==0;os.chmod(backup/'database.sql.gz',0o600)
with gzip.open(backup/'database.sql.gz','rb') as f:
 while f.read(1048576):pass
print('PASS backups verified',flush=True)
keydir=site/'shared/restapi';assert not keydir.exists(),'Inspect existing keys before proceeding'
keydir.mkdir(mode=0o700);os.chown(keydir,33,33)
env=site/'shared/secrets/restapi.env';assert not env.exists()
fd=os.open(env,os.O_CREAT|os.O_EXCL|os.O_WRONLY,0o600)
with os.fdopen(fd,'w') as f:
 f.write('CHISIMBA_JWT_SECRET='+secrets.token_hex(48)+'\nCHISIMBA_SITE_KEY='+secrets.token_hex(48)+'\n')
shutil.copy2(bundle/'apache.conf',site/'app/deploy/chisimba-restapi.conf')
new=original.replace('    networks: [internal]', '''    env_file:
      - /srv/chisimba-com/shared/secrets/restapi.env
    environment:
      CHISIMBA_JWKS_KEY_PATH: /var/data/restapi/jwks_private.pem
      CHISIMBA_DENYLIST_REDIS: restapi-redis:6379
    networks: [internal]''',1)
new=new.replace('    depends_on:\n', '''      - /srv/chisimba-com/shared/restapi:/var/data/restapi
      - /srv/chisimba-com/app/deploy/chisimba-restapi.conf:/etc/apache2/conf-enabled/chisimba-restapi.conf:ro
    depends_on:
''',1)
new=new.replace('\nvolumes:\n', '''
  restapi-redis:
    image: redis:7.4-alpine
    restart: unless-stopped
    command: [redis-server, --appendonly, "yes"]
    volumes:
      - restapi_redis:/data
    networks: [internal]

volumes:
  restapi_redis:
''')
compose.write_text(new)
cmd=['docker','compose','-p','chisimba-com','--env-file',str(site/'shared/secrets/production.env'),'-f',str(compose)]
record=dict(previous=str(previous),release=str(release),backup=str(backup),framework='4a02aad40',status='prepared')
(backup/'release.json').write_text(json.dumps(record,indent=2))
switched=False
try:
 run(cmd+['config','--quiet'])
 run(cmd+['up','-d','--no-deps','restapi-redis'])
 network=next(iter(i['NetworkSettings']['Networks']))
 run(['docker','run','--rm','--volumes-from',web,'--network',network,'--user','www-data','--env-file',str(env),'-e','RESTAPI_SITE_SETUP=chisimba.com','-e','CHISIMBA_JWKS_KEY_PATH=/var/data/restapi/jwks_private.pem','-e','CHISIMBA_DENYLIST_REDIS=restapi-redis:6379','-v',str(release)+':/var/www/html:ro','-v',str(keydir)+':/var/data/restapi','-v',str(bundle)+':/setup:ro','--entrypoint','php',i['Image'],'/setup/register.php'])
 for r in manifest:assert sha(previous/r['path']) in (r['before'],r['after']), 'Live drift before switch'
 link=current.parent/('.restapi-'+stamp);link.symlink_to(release);os.replace(link,current);switched=True
 run(cmd+['up','-d','--no-deps','--no-build','--force-recreate','web'])
 record['status']='switched-awaiting-http-validation';(bundle/'deployed.json').write_text(json.dumps(record,indent=2))
 print('DEPLOYED '+str(backup),flush=True)
except BaseException:
 # Recover the website using the retained source and composition; additive schema remains.
 shutil.copy2(backup/'compose.yml',compose)
 if switched:
  link=current.parent/('.restore-'+stamp);link.symlink_to(previous);os.replace(link,current)
 run(cmd+['up','-d','--no-deps','--no-build','--force-recreate','web'])
 record['status']='previous-web-restored-inspect-additive-schema';raise
finally:(backup/'release.json').write_text(json.dumps(record,indent=2))
