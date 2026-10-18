<?php
/** Narrow disposable category fixture; persistence uses the shared dbTable store. */
if (PHP_SAPI!=='cli') exit(64);
$remote=getenv('CATEGORY_TEST_TARGET')==='chisimba.com';
chdir($remote?'/var/www/html':'/var/www/html/ch');
$_SERVER['REQUEST_METHOD']='CLI';$_SERVER['HTTP_HOST']=$remote?'www.chisimba.com':'chisimba.test:8445';$_SERVER['SCRIPT_NAME']=$remote?'/index.php':'/ch/index.php';$_SERVER['QUERY_STRING']='';
$GLOBALS['kewl_entry_point_run']=true;require 'classes/core/engine_class_inc.php';$e=new engine();
$f=json_decode(file_get_contents('/tmp/restapi-local-fixture.json'),true,512,JSON_THROW_ON_ERROR);
$users=$e->getObject('userservice','security');$u=$users->findByUserId($f['userId']);
if(!$u||$u['username']!==$f['username']||!str_starts_with($u['username'],'api_test_'))throw new RuntimeException('Fixture mismatch');
$stack=$e->getObject('nativeauthwebcomposition','security')->build();
if(!$stack['sessions']->establish($f['userId'],['username'=>$f['username'],'provider'=>'test']))throw new RuntimeException('Fixture session failed');
$service=$e->getObject('publishingservice','simpleblog');$c=$service->classification();$db=$e->getObject('classificationstore','classification');
$op=$argv[1]??'';
if($op==='seed'){
 $own=$c->saveTerm('personal',$f['userId'],'category','Mobile category test');
 $tag=$c->saveTerm('personal',$f['userId'],'tag','Wrong kind test');
 $v=$c::vocabulary('personal','test-other-'.$f['userId'],'category');
 $foreign=['id'=>bin2hex(random_bytes(16)),'vocabulary_id'=>$v['id'],'name'=>'Other account category','slug'=>'other-test','parent_id'=>''];
 $db->locked($v,static function()use($db,$foreign){$db->saveTerm($foreign);});
 $f['categoryTest']=['own'=>$own['id'],'tag'=>$tag['id'],'foreign'=>$foreign['id']];file_put_contents('/tmp/restapi-local-fixture.json',json_encode($f));
 echo json_encode($f['categoryTest']);
}elseif($op==='inspect'){
 $rows=$e->getObject('publishingstore','simpleblog')->selectPrepared('SELECT * FROM tbl_simpleblog_posts WHERE userid=?',[$f['userId']]);
 if(count($rows)!==1)throw new RuntimeException('Rejected writes were not rolled back');
 $terms=$c->forItem('simpleblog',$rows[0]['id'],'category',true);
 if(array_column($terms,'id')!==[$f['categoryTest']['own']])throw new RuntimeException('Category was not persisted');
 echo "PASS atomic category assignment; rejected requests left no posts\n";
}elseif($op==='cleanup'){
 foreach($e->getObject('publishingstore','simpleblog')->selectPrepared('SELECT id FROM tbl_simpleblog_posts WHERE userid=?',[$f['userId']])as$row)$service->delete($row['id']);
 foreach([['personal',$f['userId'],'category'],['personal',$f['userId'],'tag'],['personal','test-other-'.$f['userId'],'category']]as$args){
  $v=$c::vocabulary(...$args);
  foreach($db->terms($v['id'])as$t)$db->removeTerm($t['id']);
  $db->executePrepared('DELETE FROM tbl_classification_vocabularies WHERE id=?',[$v['id']]);
 }
 echo "PASS disposable categories and posts removed\n";
}else throw new RuntimeException('Unknown fixture operation');
