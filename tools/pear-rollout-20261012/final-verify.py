from common import *
record=json.loads((work/'deployed.json').read_text());backup=pathlib.Path(record['backup']);release=pathlib.Path(record['release']);i=inspect(web)
if (work/'navigation-deployed.json').exists():
 follow=json.loads((work/'navigation-deployed.json').read_text());release=pathlib.Path(follow['release'])
 merged={r['path']:r for r in manifest};merged.update({r['path']:r for r in json.loads((B/'navigation-manifest.json').read_text())});manifest=list(merged.values())
assert i['State']['Running'];assert current.resolve()==release;assert i['Image']==record['imageId']
for r in manifest:assert sha(release/r['path'])==r['after'],'Manifest mismatch '+r['path']
for p in retired:assert not (release/p).exists(),'Retired path '+p
before=json.loads((backup/'logs-before.json').read_text());findings=[]
for m in i['Mounts']:
 if m['Destination'] not in [root+'/error_log',root+'/error_logs']:continue
 for p in pathlib.Path(m['Source']).rglob('*'):
  if not p.is_file() or p.is_symlink():continue
  offset=before.get(str(p),0)
  with p.open('rb') as f:
   f.seek(offset if offset<=p.stat().st_size else 0);text=f.read().decode(errors='replace')
  for line in text.splitlines():
   if re.search('warning|deprecated|fatal|uncaught|exception',line,re.I):findings.append({'file':str(p),'line':line})
(work/'log-findings.json').write_text(json.dumps(findings,indent=2));print(key,'manifest',len(manifest),'retired paths absent','new diagnostic lines',len(findings))
for timer in cfg['timers']:assert out(['systemctl','is-active',timer])=='active';print('TIMER_ACTIVE',timer)
assert not findings,'Inspect private log-findings.json'
print('PASS final verification',key)
