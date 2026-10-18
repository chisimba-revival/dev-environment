<?php
if (PHP_SAPI !== 'cli') exit(64);
chdir('/var/www/html/ch');
$_SERVER['REQUEST_METHOD']='CLI'; $_SERVER['HTTP_HOST']='chisimba.test:8445'; $_SERVER['SCRIPT_NAME']='/ch/index.php'; $_SERVER['QUERY_STRING']='';
$GLOBALS['kewl_entry_point_run']=true; require 'classes/core/engine_class_inc.php'; $e=new engine();
$f=json_decode(file_get_contents('/tmp/restapi-local-fixture.json'),true,512,JSON_THROW_ON_ERROR);
$u=$e->getObject('userservice','security'); $row=$u->findByUserId($f['userId']);
if (!$row || $row['id']!==$f['storageId'] || $row['username']!==$f['username'] || !str_starts_with($row['username'],'api_test_') || $row['isactive']) throw new RuntimeException('Refusing cleanup outside inactive fixture');
$db=$u; $files=$e->getObject('dbfile','filemanager');
foreach ($files->selectPrepared('SELECT id, filename FROM tbl_files WHERE userid=?',[$f['userId']]) as $file) {
 if ($file['filename']!=='restapi-test.png') throw new RuntimeException('Unexpected fixture file');
 if (!$files->deleteFile($file['id'])) throw new RuntimeException('Fixture file cleanup failed');
}
$folders=$e->getObject('dbfolder','filemanager');
$folders->executePrepared('DELETE FROM tbl_files_folders WHERE folderpath=?',['users/'.$f['userId']]);
$path=$e->getObject('altconfig','config')->getcontentPath().'users/'.$f['userId'];
if (is_dir($path) && !rmdir($path)) throw new RuntimeException('Nonempty fixture directory');
$pid=$e->getObject('identityservice','security')->permissionUserIdForUser($f['userId']);
$db->transactionWithSavepoint(function() use ($db,$f,$pid) {
 foreach (['tbl_rest_refresh_tokens','tbl_rest_api_keys','tbl_rest_identity_epoch'] as $table) $db->executePrepared('DELETE FROM '.$table.' WHERE user_id=?',[$f['userId']]);
 if (isset($f['groupId'])) {
  $db->executePrepared('DELETE FROM tbl_perms_groupusers WHERE group_id=? AND perm_user_id=?',[$f['groupId'],$pid]);
  $db->executePrepared('DELETE FROM tbl_perms_grouprights WHERE group_id=?',[$f['groupId']]);
  $db->executePrepared('DELETE FROM tbl_perms_groups WHERE group_id=? AND group_define_name=?',[$f['groupId'],$f['username']]);
 }
 $db->executePrepared('DELETE FROM tbl_perms_perm_users WHERE perm_user_id=? AND auth_user_id=?',[$pid,$f['userId']]);
 $db->executePrepared('DELETE FROM tbl_users WHERE userid=? AND id=?',[$f['userId'],$f['storageId']]);
});
unlink('/tmp/restapi-local-fixture.json');
echo "Temporary account, permission group, tokens and uploaded image removed.\n";
