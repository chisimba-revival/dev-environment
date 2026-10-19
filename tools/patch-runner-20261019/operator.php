<?php
if(PHP_SAPI!=='cli'||getenv('PATCH_RELEASE')!=='20261019')exit(64);
$mode=$argv[1]??'';$host=$argv[2]??'';$root=$argv[3]??'';
if(!in_array($host,['chisimba.com','kengalearn.com','learnthebirds.com','kengapub.com','kengasolutions.com','heritagetreazures.com'],true)||!in_array($root,['/var/www/html','/var/www/html/ch'],true))exit(64);
chdir($root);
if(getenv('REHEARSAL')==='1' && !str_contains(file_get_contents('config/dbdetails_inc.php'),'@release-db/chisimba_rehearsal'))throw new RuntimeException('Isolated database required');
if($mode==='pdo'){
 if(getenv('REHEARSAL')!=='1')exit(64);
 putenv('CHISIMBA_PATCH_TEST=1');$argv[1]=$host;require '/release/patch_runner_pdo_test.php';echo "PASS pdo\n";exit;
}
$_SERVER['REQUEST_METHOD']='CLI';$_SERVER['HTTP_HOST']=$host;$_SERVER['SCRIPT_NAME']=($root==='/var/www/html/ch'?'/ch':'').'/index.php';$_SERVER['QUERY_STRING']='';
$GLOBALS['kewl_entry_point_run']=true;require 'classes/core/engine_class_inc.php';$e=new engine();
$p=$e->getObject('patch','modulecatalogue');
if (!in_array(parse_url($e->getObject('altconfig','config')->getSiteRoot(),PHP_URL_HOST),[$host,'www.'.$host],true))throw new RuntimeException('Wrong site');
if($mode==='state'){$state=(string)$e->getObject('dbsysconfig','sysconfig')->getValue('MAINTENANCE_ENABLED','systemmanagement','');echo 'STATE '.($state===''?'unset':$state)."\n";exit;}
if($mode==='upgrade'){
 $result=$p->applyUpdates('modulecatalogue');
 if(!is_array($result)||($result['current']??'')!=='3.142')throw new RuntimeException('Catalogue update did not complete');
 echo "PASS upgrade\n";
}elseif($mode==='verify'){
 if($p->getVersion('modulecatalogue')!=='3.142')throw new RuntimeException('Catalogue version mismatch');
 echo "PASS verify\n";
}else exit(64);
