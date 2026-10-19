"""Read-only post-release checks and non-secret receipt export for one site."""
from common import *

record = json.loads((work / 'deployed.json').read_text())
assert record['status'] == 'online-verified'
assert str(current.resolve()) == record['release']
assert inspect(web)['State']['Running']
for entry in manifest:
    assert sha(current / entry['path']) == entry['after']
for timer in cfg['timers']:
    assert out(['systemctl', 'is-active', timer]) == 'active'
backup = pathlib.Path(record['backup'])
assert json.loads((backup / 'protected-before.json').read_text()) == json.loads((backup / 'protected-after.json').read_text())
before_logs = json.loads((backup / 'logs-before.json').read_text())
new_logs = b''
for name, offset in before_logs.items():
    path = pathlib.Path(name)
    if path.is_file():
        with path.open('rb') as stream:
            stream.seek(offset if path.stat().st_size >= offset else 0)
            new_logs += stream.read()
record['postReleaseFatalErrors'] = len(re.findall(rb'Fatal error|Uncaught .*Exception|SQLSTATE\[', new_logs))
assert record['postReleaseFatalErrors'] == 0, 'Review new runtime errors'
record['postReleaseDeprecations'] = len(re.findall(rb'Deprecated', new_logs))
record['sourceVerified'] = True
record['webRunning'] = True
record['timersVerified'] = cfg['timers']
print(json.dumps(record, indent=2))
