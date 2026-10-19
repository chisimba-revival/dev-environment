"""Apply the tested mobile chat delta on Chisimba.com only."""
import pathlib,json,hashlib,subprocess,shutil,datetime,os,fcntl,gzip
site=pathlib.Path('/srv/chisimba-com');b=site/'staging/chat-width-20261019';cur=site/'app/current';previous=cur.resolve()
lock=open(site/'shared-release.lock','a');fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
assert not (b/'deployed.json').exists()
m=json.loads((b/'manifest.json').read_text())
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest() if p.exists() else None
def run(a,**kw):return subprocess.run(a,check=True,**kw)
for r in m:assert sha(previous/r['path'])==r['before'],'Live drift '+r['path'];assert sha(b/'payload'/r['path'])==r['after']
stamp=datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%d-%H%M%S');backup=site/'backups'/('chat-width-'+stamp);backup.mkdir(mode=0o700)
release=site/'releases'/('release-chat-width-'+stamp)/'ch';release.parent.mkdir();run(['cp','-a','--reflink=auto',str(previous),str(release)])
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
record=dict(previous=str(previous),release=str(release),backup=str(backup),modules='2e790e9053c4618db5f7ce55ee7287a9adc23cba',framework='e41841b18d2745f816798d9ea132c021ff6c12fb',status='prepared')
(backup/'release.json').write_text(json.dumps(record,indent=2));switched=False
try:
 network=next(iter(i['NetworkSettings']['Networks']))

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
