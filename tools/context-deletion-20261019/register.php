<?php
if(PHP_SAPI!=='cli')exit(64);
$root=$argv[1]??'';$host=$argv[2]??'';
if(!in_array([$root,$host],[['/var/www/html/ch','chisimba.test:8445'],['/var/www/html','www.chisimba.com']],true))exit(64);
chdir($root);$_SERVER['REQUEST_METHOD']='CLI';$_SERVER['HTTP_HOST']=$host;$_SERVER['SCRIPT_NAME']=($root==='/var/www/html/ch'?'/ch':'').'/index.php';$_SERVER['QUERY_STRING']='';
$GLOBALS['kewl_entry_point_run']=true;require 'classes/core/engine_class_inc.php';$e=new engine();
$mf=$e->getObject('modulefile','modulecatalogue');
foreach(['context','contextadmin','contextgroups','groupadmin','announcements','messaging']as$name){
 $data=$mf->readRegisterFile($mf->findRegisterFile($name));
 if(!$e->getObject('modulesadmin','modulecatalogue')->installModule($data,$e->getObject('modules','modulecatalogue')->checkIfRegistered($name)))throw new RuntimeException($name.' update failed: '.$e->getObject('modulesadmin','modulecatalogue')->getLastErrorCode().' '.strip_tags($e->getObject('modulesadmin','modulecatalogue')->output));
}
echo "PASS course cleanup module registration\n";

$db=$e->getObject('contextdeletion','context');
$tables=['tbl_context','tbl_contextmodules','tbl_context_blocks','tbl_perms_groups','tbl_perms_groupusers','tbl_perms_grouprights','tbl_perms_group_subgroups'];
foreach(['messaging'=>'conversationstore','announcements'=>'dbannouncements'] as $module=>$service) $tables=array_merge($tables,$e->getObject($service,$module)->contextDeletionTables());
foreach($tables as $table){$rows=$db->selectPrepared('SELECT ENGINE AS engine FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME=?',[$table]);if(strtolower($rows[0]['engine']??'')!=='innodb')throw new RuntimeException('Deletion requires InnoDB: '.$table);}
echo "PASS transactional storage preflight\n";
