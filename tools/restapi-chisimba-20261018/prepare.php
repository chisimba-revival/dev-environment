<?php
if (PHP_SAPI !== 'cli') exit(64);
if (is_file('/tmp/restapi-local-fixture.json')) throw new RuntimeException('Clean up the existing fixture before preparing another');
chdir('/var/www/html');
$_SERVER['REQUEST_METHOD']='CLI'; $_SERVER['HTTP_HOST']='chisimba.com'; $_SERVER['SCRIPT_NAME']='/index.php'; $_SERVER['QUERY_STRING']='';
$GLOBALS['kewl_entry_point_run']=true;
require 'classes/core/engine_class_inc.php';
$e=new engine();
$users=$e->getObject('userservice','security');
$password=bin2hex(random_bytes(24)).'!aA2';
$username='api_test_'.bin2hex(random_bytes(5));
$result=$e->getObject('userprovisioningservice','security')->createLocalUser(['userId'=>$users->generateUserId(),'username'=>$username,'firstName'=>'API','surname'=>'Local test','emailAddress'=>$username.'@example.invalid','howCreated'=>'useradmin','isActive'=>true],$password);
if (empty($result['ok'])) throw new RuntimeException('Fixture creation: '.$result['code']);
$result['username']=$username; $result['password']=$password;
file_put_contents('/tmp/restapi-local-fixture.json',json_encode($result)); chmod('/tmp/restapi-local-fixture.json',0600);
echo "Temporary test account created.\n";
