"""Read navigation from the verified pre-release dump in a disposable isolated DB."""
from common import *
record=json.loads((work/'deployed.json').read_text());dump=pathlib.Path(record['backup'])/'database.sql.gz'
name='pear-navigation-'+key;password=secrets.token_hex(24);parts=[];capture=False
with gzip.open(dump,'rb') as f:
 for line in f:
  if line.startswith(b'-- Table structure for table '):
   if capture:break
   capture=b'`tbl_menu_category`' in line
  if capture:parts.append(line)
assert any(b'CREATE TABLE' in s for s in parts)
run(['docker','network','create','--internal',name],stdout=subprocess.DEVNULL)
try:
 run(['docker','run','-d','--rm','--name',name,'--network',name,'--tmpfs','/var/lib/mysql','-e','MARIADB_ROOT_PASSWORD='+password,'-e','MARIADB_DATABASE=nav_audit','mariadb:10.11.18'],stdout=subprocess.DEVNULL)
 for n in range(45):
  if subprocess.run(['docker','exec',name,'mariadb','-uroot','-p'+password,'nav_audit','-e','SELECT 1'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode==0:break
  time.sleep(1)
 run(['docker','exec','-i',name,'mariadb','-uroot','-p'+password,'nav_audit'],input=b''.join(parts),stdout=subprocess.DEVNULL)
 query="SELECT JSON_OBJECT('id',id,'category',category,'module',module,'adminonly',adminonly,'permissions',permissions,'dependscontext',dependscontext,'contextplugin',contextplugin) FROM tbl_menu_category WHERE SUBSTR(category,1,5)='site_' ORDER BY category,id;"
 old=subprocess.check_output(['docker','exec',name,'mariadb','-N','-B','--raw','-uroot','-p'+password,'nav_audit','-e',query],text=True)
 now=subprocess.check_output(['docker','exec','-i',db,'sh','-c','exec mariadb -N -B --raw -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" "$MARIADB_DATABASE"'],input=query.encode()).decode()
 before=[json.loads(x) for x in old.splitlines()];after=[json.loads(x) for x in now.splitlines()]
 missing=[r for r in before if not any({k:v for k,v in r.items() if k!='id'}=={k:v for k,v in a.items() if k!='id'} for a in after)]
 for label,value in [('before',before),('current',after),('missing',missing)]:(work/('navigation-'+label+'.json')).write_text(json.dumps(value,indent=2))
 print(key,'navigation before',len(before),'current',len(after),'missing or changed',len(missing),flush=True)
finally:
 subprocess.run(['docker','rm','-f',name],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL);subprocess.run(['docker','network','rm',name],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
