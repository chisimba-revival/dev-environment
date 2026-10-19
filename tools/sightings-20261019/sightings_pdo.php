<?php
/** Disposable PDO and private-storage tests. No sessions, user grants or production records. */
if(PHP_SAPI!=='cli'||getenv('SIGHTINGS_LOCAL_TEST')!=='1')exit(64);
chdir('/var/www/html');$_SERVER['REQUEST_METHOD']='CLI';$_SERVER['HTTP_HOST']='chisimba.test:8445';$_SERVER['SCRIPT_NAME']='/ch/index.php';$_SERVER['QUERY_STRING']='';$GLOBALS['kewl_entry_point_run']=true;require 'classes/core/engine_class_inc.php';$e=new engine();
if(getenv('REHEARSAL')!=='1'||!str_contains(file_get_contents('config/dbdetails_inc.php'),'@release-db/chisimba_rehearsal'))throw new RuntimeException('Isolated clone only');
$store=$e->getObject('conversationstore','messaging');$images=$e->getObject('privateimageasset','filemanager');$e->getObject('sightingservice','messaging');
class SightingFixtureService extends sightingservice {public $dependencies;public function getObject($name,$moduleName=''){return $this->dependencies[$name];}}
function check($ok,$label){if(!$ok)throw new RuntimeException($label);echo "PASS $label\n";}
function denied($call,$reason){try{$call();throw new RuntimeException('Expected rejection');}catch(DomainException $error){check($error->getMessage()===$reason,'reject '.$reason);}}
$context='sightingtest'.bin2hex(random_bytes(5));$channel=bin2hex(random_bytes(16));$created=[];
$policy=new class {public function actor(){return 'sightingfixture';}};
$access=new class($context,$channel){public $allowed=true;public function __construct(public $context,public $channel){} public function forContext($context){if(!$this->allowed||$context!==$this->context)throw new DomainException('unavailable');return ['id'=>$this->channel,'context_code'=>$context];}};
$service=new SightingFixtureService();$service->dependencies=['conversationstore'=>$store,'privateimageasset'=>$images,'conversationpolicy'=>$policy,'conversationservice'=>$access,'user'=>new class {public function fullName($id){return 'Fixture';}}];$service->init();
$gd=imagecreatetruecolor(80,60);imagefill($gd,0,0,imagecolorallocate($gd,20,120,60));ob_start();imagejpeg($gd,null,80);$original=ob_get_clean();$gd=null;
// Inject an EXIF-like marker; re-encoding must strip even metadata we do not understand.
$marker="Exif\0\0GPS-SYNTHETIC";$raw=substr($original,0,2)."\xff\xe1".pack('n',strlen($marker)+2).$marker.substr($original,2);$encoded=base64_encode($raw);
try{
 $store->executePrepared('INSERT INTO tbl_messaging_channels_v2 (id,context_code,last_sequence) VALUES (?,?,0)',[$channel,$context]);
 $key=bin2hex(random_bytes(16));$a=$service->send($context,$key,'Synthetic bird',$encoded);$created[]=$a['id'];
 $b=$service->send($context,$key,'Synthetic bird',$encoded);check($a===$b,'retry returns one sighting');
 $bytes=$service->image($context,$a['id']);check(!str_contains($bytes,'GPS-SYNTHETIC'),'embedded metadata stripped');check(getimagesizefromstring($bytes)[0]===80,'small image not enlarged');
 denied(fn()=>$service->send($context,$key,'Changed',$encoded),'conflict');
 denied(fn()=>$service->send($context,bin2hex(random_bytes(16)),'Bad','invalid'),'invalid');
 denied(fn()=>$service->image('other',$a['id']),'unavailable');
 $access->allowed=false;denied(fn()=>$service->history($context),'unavailable');denied(fn()=>$service->image($context,$a['id']),'unavailable');denied(fn()=>$service->send($context,$key,'Synthetic bird',$encoded),'unavailable');$access->allowed=true;
 try{$store->transactionWithSavepoint(function()use($store,$context){$store->deleteForContext($context);throw new LogicException('rollback');});}catch(LogicException $error){if($error->getMessage()!=='rollback')throw $error;}
 check($service->image($context,$a['id'])===$bytes,'failed course deletion preserves image');
 check(!$store->selectPrepared('SELECT id FROM tbl_messaging_image_cleanup WHERE id=?',[$a['id']]),'failed deletion rolls back cleanup outbox');
 $store->transactionWithSavepoint(fn()=>$store->deleteForContext($context));
 check((bool)$store->selectPrepared('SELECT id FROM tbl_messaging_image_cleanup WHERE id=?',[$a['id']]),'committed deletion queues cleanup');
 $store->afterContextDeletion();check(!$store->selectPrepared('SELECT id FROM tbl_messaging_image_cleanup WHERE id=?',[$a['id']]),'cleanup receipt removed after file deletion');
 denied(fn()=>$images->read('messaging',hash('sha256',$context),$a['id']),'unavailable');
 foreach(['not an image',str_repeat('a',750001)] as $bad)denied(fn()=>$images->prepare(base64_encode($bad)),'invalid');
 $large=imagecreatetruecolor(2049,1);ob_start();imagejpeg($large);$oversized=ob_get_clean();$large=null;denied(fn()=>$images->prepare(base64_encode($oversized)),'invalid');

 $failedIds=[];
 $recordingImages=new class($images){public $created=[];public function __construct(public $real){}public function prepare($v){return $this->real->prepare($v);}public function put($owner,$scope,$id,$bytes){$this->created[]=$id;return $this->real->put($owner,$scope,$id,$bytes);}public function remove($owner,$scope,$id){return $this->real->remove($owner,$scope,$id);}};
 // The first channel was deleted above; create another disposable one for injected failure.
 $store->executePrepared('INSERT INTO tbl_messaging_channels_v2 (id,context_code,last_sequence) VALUES (?,?,0)',[$channel,$context]);
 $failingStore=new class($store){public function __construct(public $real){}public function locked($id,$callback){return $this->real->locked($id,$callback);}public function selectPrepared($sql,$values=[]){return $this->real->selectPrepared($sql,$values);}public function executePrepared($sql,$values){throw new RuntimeException('injected receipt failure');}};
 $service->dependencies['conversationstore']=$failingStore;$service->dependencies['privateimageasset']=$recordingImages;$service->init();
 try{$service->send($context,bin2hex(random_bytes(16)),'Failed receipt',$encoded);throw new LogicException('Failure accepted');}catch(RuntimeException $error){check($error->getMessage()==='injected receipt failure','database insert failure propagates');}
 check(count($recordingImages->created)===1,'failure reached private image write');$failedId=$recordingImages->created[0];$created[]=$failedId;
 denied(fn()=>$images->read('messaging',hash('sha256',$context),$failedId),'unavailable');
 check(!$store->selectPrepared('SELECT id FROM tbl_messaging_sightings_v2 WHERE id=?',[$failedId]),'failed upload leaves no sighting row');
 $service->dependencies['conversationstore']=$store;$service->dependencies['privateimageasset']=$images;$service->init();
 try{$store->transactionWithSavepoint(fn()=>$service->send($context,bin2hex(random_bytes(16)),'Nested write',$encoded));throw new LogicException('Nested accepted');}catch(RuntimeException $error){check($error->getMessage()==='Sighting upload requires its own transaction','outer transaction cannot leave dangling image after rollback');}
 $owner='fixture_'.bin2hex(random_bytes(5));$scope=hash('sha256',$context);$orphan=bin2hex(random_bytes(16));
 $images->put($owner,$scope,$orphan,$original);
 $root=rtrim($e->getObject('dbsysconfig','sysconfig')->getValue('SECUREFODLER','filemanager'),'/').'/owned-images/'.$owner;
 touch($root.'/'.$scope.'/'.$orphan.'.jpg',time()-90000);
 check($images->pruneUnreferenced($owner,fn($id)=>false,false)===1,'orphan dry run identifies old file');
 check($images->pruneUnreferenced($owner,fn($id)=>true,true)===0,'referenced image is never pruned');
 check($images->pruneUnreferenced($owner,fn($id)=>false,true)===1,'old unreferenced file cleaned');
 rmdir($root.'/'.$scope);rmdir($root);
 echo "PASS sightings PDO/private image fixture\n";
}finally{
 foreach($created as $id){$images->remove('messaging',hash('sha256',$context),$id);$store->executePrepared('DELETE FROM tbl_messaging_image_cleanup WHERE id=?',[$id]);}
 $store->executePrepared('DELETE FROM tbl_messaging_sightings_v2 WHERE channel_id=?',[$channel]);$store->executePrepared('DELETE FROM tbl_messaging_channels_v2 WHERE id=?',[$channel]);
}
