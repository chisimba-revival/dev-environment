#!/usr/bin/env python3
"""Synthetic webinar capacity checks on both database drivers in a disposable network."""
import pathlib,secrets,subprocess,time
base=pathlib.Path(__file__).resolve().parent
root=base/'learnthebirds/stage'
name='webinar-capacity-'+secrets.token_hex(5)
password=secrets.token_hex(24)
def run(args,**kw):
 result=subprocess.run(args,**kw)
 if result.returncode:raise RuntimeError('Disposable test failed; see diagnostics above')
 return result
run(['docker','network','create','--internal',name],stdout=subprocess.DEVNULL)
try:
 run(['docker','run','--rm','-d','--name',name,'--network',name,'--network-alias','baseline-db','--tmpfs','/var/lib/mysql','-e','MARIADB_ROOT_PASSWORD='+password,'-e','MARIADB_DATABASE=contract_fixture','mariadb:10.11.18'],stdout=subprocess.DEVNULL)
 for _ in range(60):
  if subprocess.run(['docker','exec',name,'mariadb','-uroot','-p'+password,'-e','SELECT 1'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode==0:break
  time.sleep(1)
 else:raise RuntimeError('Fixture database unavailable')
 for engine in ['PDO','MDB2']:
  for fixture in ['capacity_test.php','reminder_dashboard_test.php']:
   run(['docker','run','--rm','--network',name,'--entrypoint','php','-e','WEBINAR_CAPACITY_FIXTURE=1','-e','WEBINAR_TEST_ENGINE='+engine,'-e','CHISIMBA_DB_PASSWORD='+password,'-v',str(root)+':/framework/app:ro','-v',str(base/'tests')+':/framework/tests:ro','-v',str(root/'packages')+':/modules:ro','-v',str(base/'webinar-tests')+':/modules/webinar/tests:ro','-v',str(base/'audience-tests')+':/modules/audience/tests:ro','learnthebirds/pdo:20261011','-d','auto_prepend_file=','/modules/webinar/tests/'+fixture])
 run(['docker','exec',name,'mariadb','-uroot','-p'+password,'-e','CREATE DATABASE audience_test_webinar; CREATE DATABASE webinar_count_test;'],stdout=subprocess.DEVNULL)
 for fixture,variables in [('/modules/audience/tests/campaign_integration_test.php',{'AUDIENCE_TEST_DSN':'mysql:host=baseline-db;dbname=audience_test_webinar','AUDIENCE_TEST_USER':'root','AUDIENCE_TEST_PASSWORD':password,'AUDIENCE_TEST_FRAMEWORK':'/framework'}),('/modules/webinar/tests/registration_counts_test.php',{'WEBINAR_COUNT_TEST_DSN':'mysql:host=baseline-db;dbname=webinar_count_test','WEBINAR_COUNT_TEST_USER':'root','WEBINAR_COUNT_TEST_PASSWORD':password})]:
  args=['docker','run','--rm','--network',name,'--entrypoint','php']
  for key,value in variables.items():args+=['-e',key+'='+value]
  run(args+['-v',str(root)+':/framework/app:ro','-v',str(base/'tests')+':/framework/tests:ro','-v',str(root/'packages')+':/modules:ro','-v',str(base/'webinar-tests')+':/modules/webinar/tests:ro','-v',str(base/'audience-tests')+':/modules/audience/tests:ro','learnthebirds/pdo:20261011','-d','auto_prepend_file=/framework/tests/core/strict_warning_bootstrap.php',fixture])
finally:
 subprocess.run(['docker','rm','-f',name],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
 subprocess.run(['docker','network','rm',name],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
