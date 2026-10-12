from common import *
r=json.loads((work/'deployed.json').read_text());assert r['status']=='online-verified';assert str(current.resolve())==r['release'];assert inspect(web)['Image']==r['imageId']
for row in json.loads((B/'manifest.json').read_text()):assert sha(current/row['path'])==row['after'],'Manifest drift'
for timer in cfg['timers']:assert out(['systemctl','is-active',timer])=='active'
offsets=json.loads((pathlib.Path(r['backup'])/'logs-before.json').read_text());bad=[]
for m in inspect(web)['Mounts']:
 if m['Destination'] in [root+'/error_log',root+'/error_logs']:
  for p in pathlib.Path(m['Source']).rglob('*'):
   if not p.is_file() or p.is_symlink():continue
   start=offsets.get(str(p),0)
   with p.open('rb') as f:f.seek(start if p.stat().st_size>=start else 0);delta=f.read()
   if re.search(rb'(PHP (?:Warning|Deprecated|Fatal)|Uncaught|Fatal error|Warning:|Deprecated:)',delta):bad.append(str(p))
assert not bad,'New PHP diagnostics in '+','.join(bad)
print('KANBAN_FINAL_PASS: manifest, exact image, current release, worker timers, PHP diagnostic delta')
print(json.dumps(r))
