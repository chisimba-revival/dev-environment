<?php
if (PHP_SAPI !== 'cli' || getenv('RESTAPI_SITE_SETUP') !== 'chisimba.com') exit(64);
chdir('/var/www/html');
$_SERVER['REQUEST_METHOD']='CLI'; $_SERVER['HTTP_HOST']='chisimba.com'; $_SERVER['SCRIPT_NAME']='/index.php'; $_SERVER['QUERY_STRING']='';
$GLOBALS['kewl_entry_point_run']=true;
require 'classes/core/engine_class_inc.php';
$e=new engine();
$mf=$e->getObject('modulefile','modulecatalogue');
$data=$mf->readRegisterFile($mf->findRegisterFile('restapi'));
$modules=$e->getObject('modules','modulecatalogue');
if (!$modules->checkIfRegistered('simpleblog')) throw new RuntimeException('SimpleBlog must already be installed');
$admin=$e->getObject('modulesadmin','modulecatalogue');
if (!$admin->installModule($data,$modules->checkIfRegistered('restapi'))) throw new RuntimeException('REST registration failed');
$e->getObject('restschema','restapi')->upgrade();
echo "PASS REST registration and schema\n";
