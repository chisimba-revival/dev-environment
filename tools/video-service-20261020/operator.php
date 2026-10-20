<?php
/** Bounded Video Service release operator; no live media or user impersonation. */
if(PHP_SAPI!=='cli'||getenv('PATCH_RELEASE')!=='20261020')exit(64);
$mode=$argv[1]??'';$host=$argv[2]??'';$root=$argv[3]??'';
if($host!=='www.chisimba.com'||$root!=='/var/www/html')exit(64);
chdir($root);
if(getenv('REHEARSAL')==='1'&&!str_contains(file_get_contents('config/dbdetails_inc.php'),'@release-db/chisimba_rehearsal'))throw new RuntimeException('Isolated clone required');
if($mode==='fixture'){
 if(getenv('REHEARSAL')!=='1')exit(64);
 putenv('CHISIMBA_VIDEO_TEST=1');putenv('CHISIMBA_TEST_ROOT='.$root);
 require $root.'/packages/video-service/tests/pdo_integration_test.php';echo "PASS fixture\n";exit;
}
$_SERVER['REQUEST_METHOD']='CLI';$_SERVER['HTTP_HOST']=$host;$_SERVER['SCRIPT_NAME']='/index.php';$_SERVER['QUERY_STRING']='';
$GLOBALS['kewl_entry_point_run']=true;require 'classes/core/engine_class_inc.php';$e=new engine();
if(!in_array(parse_url($e->getObject('altconfig','config')->getSiteRoot(),PHP_URL_HOST),['chisimba.com','www.chisimba.com'],true))throw new RuntimeException('Wrong site');
$p=$e->getObject('patch','modulecatalogue');$sys=$e->getObject('dbsysconfig','sysconfig');
if($mode==='state'){$state=(string)$sys->getValue('MAINTENANCE_ENABLED','systemmanagement','');echo 'STATE '.($state===''?'unset':$state)."\n";exit;}
$versions=['video-service'=>'0.001','contextcontent'=>'2.106'];
if($mode==='upgrade'){
 $mf=$e->getObject('modulefile','modulecatalogue');$admin=$e->getObject('modulesadmin','modulecatalogue');$registered=$e->getObject('modules','modulecatalogue');
 foreach($versions as $name=>$version){
  $data=$mf->readRegisterFile($mf->findRegisterFile($name));
  foreach($data['DEPENDS']??[] as $dep)if(!$registered->checkIfRegistered($dep))throw new RuntimeException('Missing dependency '.$dep);
  if(!$admin->installModule($data,$registered->checkIfRegistered($name)))throw new RuntimeException('Registration failed '.$name);
  $hook=$e->getPatchObject($name);if(!$hook||!method_exists($hook,'postinstall'))throw new RuntimeException('Missing hook '.$name);$hook->postinstall();
  echo 'UPDATED '.$name."\n";
 }
 if(trim((string)$sys->getValue('VIDEO_PUBLIC_URL','video-service',''))==='')$sys->changeParam('VIDEO_PUBLIC_URL','video-service','https://www.chisimba.com/index.php');
}elseif($mode!=='verify')exit(64);
foreach($versions as $module=>$version)if($p->getVersion($module)!==$version)throw new RuntimeException('Version mismatch '.$module);
foreach(['curl','openssl','mbstring'] as $extension)if(!extension_loaded($extension))throw new RuntimeException('Missing '.$extension);
foreach(['tbl_video_assets','tbl_video_events','tbl_video_progress','tbl_video_captions','tbl_contextcontent_videos'] as $table){
 $row=$p->selectPrepared('SELECT ENGINE AS engine FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME=?',[$table])[0]??null;
 if(strtolower($row['engine']??'')!=='innodb')throw new RuntimeException('Transactional table missing '.$table);
}
if($sys->getValue('VIDEO_PUBLIC_URL','video-service','')!=='https://www.chisimba.com/index.php')throw new RuntimeException('Public URL mismatch');
echo 'PASS '.$mode."\n";
