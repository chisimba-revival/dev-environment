<?php
if (PHP_SAPI !== 'cli') exit(64);
chdir('/var/www/html/ch');
$_SERVER['REQUEST_METHOD']='CLI'; $_SERVER['HTTP_HOST']='chisimba.test:8445'; $_SERVER['SCRIPT_NAME']='/ch/index.php'; $_SERVER['QUERY_STRING']='';
$GLOBALS['kewl_entry_point_run']=true; require 'classes/core/engine_class_inc.php'; $e=new engine();
$f=json_decode(file_get_contents('/tmp/restapi-local-fixture.json'),true,512,JSON_THROW_ON_ERROR);
$users=$e->getObject('userservice','security');
$u=$users->findByUserId($f['userId']);
if (!$u || $u['username']!==$f['username'] || !str_starts_with($u['username'],'api_test_')) throw new RuntimeException('Fixture identity mismatch');
$g=$e->getObject('groupservice','groupadmin'); $p=$e->getObject('permissionservice','security');
$i=$e->getObject('identityservice','security'); $pid=$i->permissionUserIdForUser($f['userId']);
$op=$argv[1]??'grant';
if ($op==='grant') {
 $result=$g->ensureGroups([['name'=>$f['username'],'description'=>'Temporary REST HTTP test']]);
 if (empty($result['ok'])) throw new RuntimeException('Fixture group failed');
 $gid=$result['groups'][$f['username']]; $f['groupId']=$gid;
 file_put_contents('/tmp/restapi-local-fixture.json',json_encode($f));
 foreach (['files.view','files.upload'] as $right) {
  $rid=$p->rightIdForArea($p->areaIdForName('chisimba','restapi'),$right);
  if (!$p->ensureGroupGrant($gid,$rid)) throw new RuntimeException('Fixture grant failed');
 }
 if (!$g->ensureMembership($gid,$pid)) throw new RuntimeException('Fixture membership failed');
 $e->getObject('userfoldercheck','filemanager')->checkUserFolder($f['userId']);
} elseif ($op==='revoke') {
 if (!$g->removeMembership($f['groupId'],$pid)) throw new RuntimeException('Fixture revoke failed');
} elseif ($op==='deactivate') {
 $e->getObject('tokenauthservice','security')->revokeAllUserTokens($f['userId']);
 $users->setActive($f['userId'],false);
}
echo "Fixture $op complete.\n";
