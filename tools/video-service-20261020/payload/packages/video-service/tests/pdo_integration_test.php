<?php
/** Installed local PDO integration; synthetic rows cleaned in finally. @author Derek Keats */
if(PHP_SAPI!=='cli'||getenv('CHISIMBA_VIDEO_TEST')!=='1')exit("Set CHISIMBA_VIDEO_TEST=1 on a disposable/local installation.\n");
$root=getenv('CHISIMBA_TEST_ROOT') ?: '/var/www/html/ch';chdir($root);
$_SERVER['REQUEST_METHOD']='CLI';$_SERVER['HTTP_HOST']='chisimba.test:8445';$_SERVER['SCRIPT_NAME']='/ch/index.php';$_SERVER['QUERY_STRING']='';
$GLOBALS['kewl_entry_point_run']=true;require 'classes/core/engine_class_inc.php';$engine=new engine();
ini_set('display_errors','1');
$db=$engine->getObject('dbvideos','video-service');$engine->getObject('videoservice','video-service');$engine->getObject('muxvideoprovider','video-service');
function checkVideo($value,$message){if(!$value)throw new RuntimeException($message);echo "PASS $message\n";}
class VideoFixtureProvider extends muxvideoprovider {
 public int $deletions=0;public int $uploads=0;public function configured():bool{return true;}public function createUpload(string $id,string $origin):array{$this->uploads++;return ['upload_id'=>'fixture-upload','url'=>'https://fixture.invalid/upload'];}public function metadata(string $id):array{return ['asset_id'=>$id,'playback_id'=>'fixture-playback','state'=>'ready','metadata'=>json_encode(['duration'=>100])];}
 public function authorisePlayback(string $id,int $expires):array{return ['playback_id'=>$id,'expires'=>$expires,'token'=>'fixture'];}
 public function deleteHostedVideo(array $video):void{$this->deletions++;}
}
class VideoFixtureService extends videoservice {
 public $fixtureProvider;public $fixtureConsumer;
 public function provider(string $configuration):muxvideoprovider{return $this->fixtureProvider;}
 public function consumer(string $name){return $this->fixtureConsumer;}
}
$id=bin2hex(random_bytes(16));$eventId='video-test-'.bin2hex(random_bytes(8));$configuration='fixture-'.bin2hex(random_bytes(8));$now=gmdate('Y-m-d H:i:s');
$service=new VideoFixtureService();$service->objEngine=$engine;$service->db=$db;
$service->user=new class {public function isLoggedIn(){return true;} public function isAdmin(){return true;} public function userId(){return 'video-test-user';}};
$service->fixtureConsumer=new class {public bool $allowed=true;public bool $used=true;public function mayPlay($r,$v){return $this->allowed;}public function references($v){return $this->used?[['id'=>'fixture']]:[];}};
$provider=new VideoFixtureProvider();$provider->configure(['webhook_secret'=>'fixture']);$service->fixtureProvider=$provider;
$settings=new ReflectionProperty(videoservice::class,'configuration');$settings->setValue($service,['default'=>$configuration,'origin'=>'https://fixture.invalid']);
try {
 $service->createUpload('site','Synthetic video test','',$id);
 try{$service->createUpload('site','Synthetic video test','',$id);throw new LogicException('replayed upload');}catch(RuntimeException $e){checkVideo($e->getMessage()==='upload_already_exists'&&$provider->uploads===1,'repeated upload authorisation creates only one provider upload');}
 try{$db->transaction(function()use($db,$id){$db->save($id,['title'=>'must roll back']);throw new RuntimeException('rollback fixture');});}catch(RuntimeException $e){if($e->getMessage()!=='rollback fixture')throw $e;}
 checkVideo($db->one($id)['title']==='Synthetic video test','dbTable transaction rolls back failed metadata change');
 $raw=json_encode(['id'=>$eventId,'type'=>'video.asset.ready','data'=>['id'=>'fixture-asset','passthrough'=>$id]]);$stamp=time();$signature='t='.$stamp.',v1='.hash_hmac('sha256',$stamp.'.'.$raw,'fixture');
 $service->webhook($configuration,$raw,$signature);$service->webhook($configuration,$raw,$signature);
 checkVideo($db->one($id)['state']==='ready','verified webhook makes asset ready');
 checkVideo(count($db->selectPrepared('SELECT id FROM tbl_video_events WHERE configuration=?',[$configuration]))===1,'duplicate webhook commits once');
 checkVideo($service->playback($id,'contextcontent','fixture')['playback_id']==='fixture-playback','authorised consumer receives playback grant');
 $service->fixtureConsumer->allowed=false;
 try{$service->playback($id,'contextcontent','fixture');throw new LogicException('access unexpectedly granted');}catch(RuntimeException $e){checkVideo($e->getMessage()==='access_denied','revoked membership blocks new playback');}
 $service->fixtureConsumer->allowed=true;
 $service->progress($id,'contextcontent','fixture',0,false);
 $db->executePrepared('UPDATE tbl_video_progress SET last_at=? WHERE video_id=?',[time()-10,$id]);
 $result=$service->progress($id,'contextcontent','fixture',10,true);
 checkVideo(abs($result['percent']-10)<0.01,'PDO progress stores watched intervals');
 try{$service->requestDeletion($id);throw new LogicException('deletion unexpectedly allowed');}catch(RuntimeException $e){checkVideo($e->getMessage()==='video_in_use','attached video deletion blocked');}
 $service->fixtureConsumer->used=false;$service->requestDeletion($id);
 checkVideo($db->one($id)['state']==='deleted'&&$provider->deletions===1,'hosted deletion leaves local tombstone');
 $late=json_encode(['id'=>$eventId.'late','type'=>'video.asset.ready','data'=>['id'=>'fixture-asset','passthrough'=>$id]]);
 $service->webhook($configuration,$late,'t='.$stamp.',v1='.hash_hmac('sha256',$stamp.'.'.$late,'fixture'));
 checkVideo($db->one($id)['state']==='pending_delete','late ready callback cannot resurrect deleted video');
 checkVideo((float)$db->progress('video-test-user','contextcontent:fixture',$id)['position']===10.0,'deletion preserves independent learning record');
}finally{
 $db->executePrepared('DELETE FROM tbl_video_progress WHERE video_id=?',[$id]);
 $db->executePrepared('DELETE FROM tbl_video_events WHERE configuration=?',[$configuration]);
 $db->executePrepared('DELETE FROM tbl_video_assets WHERE id=?',[$id]);
}
