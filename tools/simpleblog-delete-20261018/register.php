<?php
if(PHP_SAPI!=='cli')exit(64);
$root=$argv[1]??'';$host=$argv[2]??'';
if(!in_array([$root,$host],[['/var/www/html/ch','chisimba.test:8445'],['/var/www/html','www.chisimba.com']],true))exit(64);
chdir($root);$_SERVER['REQUEST_METHOD']='CLI';$_SERVER['HTTP_HOST']=$host;$_SERVER['SCRIPT_NAME']=($root==='/var/www/html/ch'?'/ch':'').'/index.php';$_SERVER['QUERY_STRING']='';
$GLOBALS['kewl_entry_point_run']=true;require 'classes/core/engine_class_inc.php';$e=new engine();
$mf=$e->getObject('modulefile','modulecatalogue');$data=$mf->readRegisterFile($mf->findRegisterFile('simpleblog'));
if(!$e->getObject('modulesadmin','modulecatalogue')->installModule($data,true))throw new RuntimeException('SimpleBlog update failed');
echo "PASS SimpleBlog registration and language update\n";
