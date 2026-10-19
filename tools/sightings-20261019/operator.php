<?php
/** Bounded release operator; registration only, no user impersonation or live test content. */
if(PHP_SAPI!=='cli'||getenv('PATCH_RELEASE')!=='20261019')exit(64);
$mode=$argv[1]??'';$host=$argv[2]??'';$root=$argv[3]??'';
if($host!=='chisimba.com'||$root!=='/var/www/html')exit(64);
chdir($root);
if(getenv('REHEARSAL')==='1'&&!str_contains(file_get_contents('config/dbdetails_inc.php'),'@release-db/chisimba_rehearsal'))throw new RuntimeException('Isolated clone required');
if($mode==='media'){
 if(getenv('REHEARSAL')!=='1')exit(64);
 putenv('SIGHTINGS_LOCAL_TEST=1');require '/release/sightings_pdo.php';echo "PASS media\n";exit;
}
$_SERVER['REQUEST_METHOD']='CLI';$_SERVER['HTTP_HOST']=$host;$_SERVER['SCRIPT_NAME']='/index.php';$_SERVER['QUERY_STRING']='';$GLOBALS['kewl_entry_point_run']=true;require 'classes/core/engine_class_inc.php';$e=new engine();
if(!in_array(parse_url($e->getObject('altconfig','config')->getSiteRoot(),PHP_URL_HOST),['chisimba.com','www.chisimba.com'],true))throw new RuntimeException('Wrong site');
$p=$e->getObject('patch','modulecatalogue');
if($mode==='state'){$state=(string)$e->getObject('dbsysconfig','sysconfig')->getValue('MAINTENANCE_ENABLED','systemmanagement','');echo 'STATE '.($state===''?'unset':$state)."\n";exit;}
$versions=['filemanager'=>'1.116','messaging'=>'2.008','restapi'=>'1.008','context'=>'2.067'];
if($mode==='upgrade')foreach($versions as $module=>$version){$result=$p->applyUpdates($module);if(!is_array($result)||($result['current']??'')!==$version)throw new RuntimeException('Registration failed: '.$module);}
elseif($mode!=='verify')exit(64);
foreach($versions as $module=>$version)if($p->getVersion($module)!==$version)throw new RuntimeException('Version mismatch: '.$module);
foreach(['tbl_messaging_sightings_v2','tbl_messaging_image_cleanup'] as $table){$row=$p->selectPrepared('SELECT ENGINE AS engine FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME=?',[$table])[0]??null;if(strtolower($row['engine']??'')!=='innodb')throw new RuntimeException('Transactional table missing');}
if(!extension_loaded('gd'))throw new RuntimeException('GD required');
echo 'PASS '.$mode."\n";
