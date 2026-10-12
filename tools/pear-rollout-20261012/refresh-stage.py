"""Refresh only a disposable stage after reviewed supporting-file additions."""
from common import *
assert key in ['kengapub','kengasolutions','heritagetreazures']
assert not (work/'deployed.json').exists()
stage=work/'stage'
assert stage.resolve()==B/key/'stage'
if stage.exists():shutil.rmtree(stage)
for name in ['prepared.json','lint.log']:(work/name).unlink(missing_ok=True)
print('Disposable stage reset',key)
