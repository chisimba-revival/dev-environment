import pathlib,sys,subprocess,json
b=pathlib.Path(__file__).resolve().parent;key=sys.argv[1];web='chisimba-com-web-1' if key=='chisimba' else 'kengalearn-production-web-1';host='chisimba.com' if key=='chisimba' else 'kengalearn.com'
r=json.loads((b/key/'deployed.json').read_text());i=json.loads(subprocess.check_output(['docker','inspect',web]))[0]
assert i['State']['Running'] and i['Image']==r['newImageId'];assert i['State'].get('Health',{}).get('Status','healthy')=='healthy'
p=subprocess.run(['docker','exec','-i','-e','PDO_RELEASE=20261011',web,'php','/dev/stdin','verify',host],input=(b/'operator.php').read_bytes(),capture_output=True);assert p.returncode==0 and b'PASS verify PDO' in p.stdout;print(p.stdout.decode().strip())
for r in json.loads((b/'manifest.json').read_text()):
 import hashlib
 code=pathlib.Path(json.loads((b/key/'deployed.json').read_text())['release'])/r['path'];actual=hashlib.sha256(code.read_bytes()).hexdigest() if code.is_file() else None;assert actual==r['after'],r['path']
assert subprocess.check_output(['docker','ps','-aq','--filter','name=pdo-release-']).strip()==b''
assert subprocess.check_output(['docker','network','ls','-q','--filter','name=pdo-release-']).strip()==b''
print('PASS live container healthy, exact deployed hashes, disposable rehearsal containers/networks removed')
