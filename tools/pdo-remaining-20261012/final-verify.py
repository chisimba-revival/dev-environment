"""Check live PDO selection, source/config integrity, worker state and log delta."""
from common import *
r=json.loads((work/'deployed.json').read_text());baseline=json.loads((work/'baseline.json').read_text());backup=pathlib.Path(r['backup']);i=inspect(web)
assert i['State']['Running'] and i['Image']==r['newImageId']
assert str(current.resolve())==r['code']
for path,digest in baseline['files'].items():assert sha(current/path)==digest,'Source drift '+path
config=pathlib.Path(baseline['config'])
for name,digest in baseline['configHashes'].items():
 if name!='config.xml':assert sha(config/name)==digest,'Unexpected config change'
old=(backup/'config-before.xml').read_text();new=(config/'config.xml').read_text();expected,n=re.subn(r'(<DATABASE_ABSTRACTION>)\s*MDB2\s*(</DATABASE_ABSTRACTION>)',r'\g<1>PDO\g<2>',old);assert n==1 and new==expected
network=set(i['NetworkSettings']['Networks'])&set(inspect(db)['NetworkSettings']['Networks']);assert len(network)==1
p=subprocess.run(['docker','run','--rm','--volumes-from',web,'--network',network.pop(),'--entrypoint','php','-e','PEAR_RELEASE=20261012','-v',str(B)+':/release:ro',r['newImageId'],'/release/operator.php','verify',host,root],capture_output=True)
assert p.returncode==0 and b'PASS verify PDO' in p.stdout;print(p.stdout.decode().strip())
offsets=json.loads((backup/'logs-before.json').read_text());findings=[]
for m in i['Mounts']:
 if m['Destination'] not in [root+'/error_log',root+'/error_logs']:continue
 for f in pathlib.Path(m['Source']).rglob('*'):
  if not f.is_file() or f.is_symlink():continue
  with f.open('rb') as stream:
   offset=offsets.get(str(f),0);stream.seek(offset if offset<=f.stat().st_size else 0);delta=stream.read().decode(errors='replace')
  for line in delta.splitlines():
   if re.search(r'warning|deprecated|fatal|uncaught|exception',line,re.I):findings.append({'file':str(f),'line':line})
(work/'log-findings.json').write_text(json.dumps(findings,indent=2));assert not findings,'Inspect private log-findings.json'
for timer in cfg['timers']:assert out(['systemctl','is-active',timer])=='active';print('TIMER_ACTIVE '+timer)
print(key+' PASS PDO source/config integrity; zero new PHP diagnostics')
(work/'final-verified.json').write_text(json.dumps({'imageId':i['Image'],'diagnostics':0,'sourceUnchanged':True,'backend':'PDO'}))
