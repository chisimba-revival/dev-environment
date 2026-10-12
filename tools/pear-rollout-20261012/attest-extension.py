"""Attest additional manifest entries already byte-identical before rehearsal/deployment."""
from common import *
assert key in ['chisimba','kengalearn','learnthebirds']
additions=json.loads((B/'supporting-additions.json').read_text());initial=sha(B/'manifest-initial.json')
for r in additions:
 assert audit[r['path']]==r['after']==sha(current.resolve()/r['path'])==sha(work/'stage'/r['path']),r['path']
prepared=json.loads((work/'prepared.json').read_text());assert prepared['manifest'] in [initial,sha(B/'manifest.json')]
prepared['initialManifest']=initial;prepared['manifest']=sha(B/'manifest.json');(work/'prepared.json').write_text(json.dumps(prepared,indent=2))
baseline=json.loads((work/'baseline.json').read_text());existing={x['path'] for x in baseline['files']}
for r in additions:
 if r['path'] not in existing:baseline['files'].append({'path':r['path'],'before':audit[r['path']]})
(work/'baseline.json').write_text(json.dumps(baseline,indent=2));print('PASS unchanged supporting-file attestation',key)
