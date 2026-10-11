import pathlib,json,hashlib
b=pathlib.Path(__file__).resolve().parent;r=pathlib.Path('/srv/learnthebirds.com/app/current').resolve();data={}
for row in json.loads((b/'manifest.json').read_text()):
 p=r/row['path'];data[row['path']]=hashlib.sha256(p.read_bytes()).hexdigest() if p.is_file() else None
(b/'learnthebirds-hashes.json').write_text(json.dumps(data,indent=2))
print('Captured',len(data),'overlay hashes')
