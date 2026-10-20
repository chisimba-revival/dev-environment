<?php
/** Offline behavioural tests: no provider calls or credentials. @author Derek Keats */
$GLOBALS['kewl_entry_point_run']=true;
class ChisimbaObject {}
require dirname(__DIR__).'/classes/muxvideoprovider_class_inc.php';
require dirname(__DIR__).'/classes/videoprogress_class_inc.php';
function check($condition,$message){if(!$condition)throw new RuntimeException($message);echo "PASS $message\n";}
function rejects(callable $call,$message){try{$call();}catch(Throwable $e){check(true,$message);return;}throw new RuntimeException($message);}
class FixtureMux extends muxvideoprovider {
 public array $calls=[];public array $responses=[];
 protected function request(string $method,string $path,?array $data=null):array{$this->calls[]=[$method,$path,$data];return array_shift($this->responses) ?? [];}
}
$mux=new FixtureMux();$mux->configure(['webhook_secret'=>'fixture-secret']);
$raw=json_encode(['id'=>'evt1','type'=>'video.asset.ready','data'=>['id'=>'asset1']]);$now=1700000000;$signature='t='.$now.',v1='.hash_hmac('sha256',$now.'.'.$raw,'fixture-secret');
check($mux->verifyWebhook($raw,$signature,$now)['id']==='evt1','valid raw-body webhook signature');
rejects(fn()=>$mux->verifyWebhook($raw.' ',$signature,$now),'modified body rejected');
rejects(fn()=>$mux->verifyWebhook($raw,$signature,$now+301),'stale signature rejected');
rejects(fn()=>$mux->verifyWebhook($raw,'t='.$now.',v1=forged',$now),'forged signature rejected');
$mux->responses=[['id'=>'up1','url'=>'https://upload.invalid/fixture']];$mux->createUpload('chisimba1','https://site.invalid');
check($mux->calls[0][2]['new_asset_settings']['playback_policies']===['signed'],'uploads request signed-only playback');
check($mux->calls[0][2]['new_asset_settings']['passthrough']==='chisimba1','stable Chisimba correlation ID');
check($mux->calls[0][2]['cors_origin']==='https://site.invalid','upload CORS uses configured origin');
$mux->responses=[['asset_id'=>'asset1'],['status'=>'ready','duration'=>100,'playback_ids'=>[['id'=>'public1','policy'=>'public'],['id'=>'signed1','policy'=>'signed']]]];
$status=$mux->processingStatus(['upload_id'=>'up1']);check($status['playback_id']==='signed1'&&$status['state']==='ready','upload reconciles to signed ready asset');
$mux->responses=[['asset_id'=>'asset1'],[]];$mux->deleteHostedVideo(['upload_id'=>'up1']);check(end($mux->calls)[0]==='DELETE','deletion reconciles uploaded asset before deleting');
$key=openssl_pkey_new(['private_key_bits'=>2048,'private_key_type'=>OPENSSL_KEYTYPE_RSA]);openssl_pkey_export($key,$pem);$mux->configure(['signing_private_key'=>$pem,'signing_key_id'=>'fixture-key']);
$grant=$mux->authorisePlayback('signed1',$now+900);$parts=explode('.',$grant['token']);$decode=fn($s)=>base64_decode(strtr($s,'-_','+/'));
$claims=json_decode($decode($parts[1]),true);check($claims['sub']==='signed1'&&$claims['aud']==='v'&&$claims['exp']===$now+900,'playback JWT is scoped and expires');
check(openssl_verify($parts[0].'.'.$parts[1],$decode($parts[2]),openssl_pkey_get_details($key)['key'],OPENSSL_ALGO_SHA256)===1,'playback JWT verifies using public key');
$p=videoprogress::advance([],0,100,1000,false);$p['intervals']=json_encode($p['intervals']);
$p=videoprogress::advance($p,10,100,1010,true);check(videoprogress::percentage($p,100)===10.0,'ten seconds watched earns ten percent');
$p['intervals']=json_encode($p['intervals']);$seek=videoprogress::advance($p,100,100,1011,true);check(videoprogress::percentage($seek,100)===10.0,'seeking to end earns no extra credit');
$p['last_position']=0;$p['last_at']=1011;$replay=videoprogress::advance($p,10,100,1021,true);check(videoprogress::percentage($replay,100)===10.0,'replayed intervals are not counted twice');
$gap=videoprogress::advance($p,20,100,1100,true);check(videoprogress::percentage($gap,100)===10.0,'long unattended gap earns no credit');
rejects(fn()=>videoprogress::advance($p,NAN,100,1020,true),'nonfinite position rejected');
rejects(fn()=>videoprogress::advance($p,1010,100,1020,true),'out-of-range position rejected');
