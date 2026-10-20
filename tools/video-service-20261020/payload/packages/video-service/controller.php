<?php
/** Video library, authenticated API and provider callback routes. @author Derek Keats */
class video_service extends controller
{
    private $service; private $csrf;
    public function init(){ $this->service=$this->getObject('videoservice','video-service');$this->csrf=$this->getObject('nativeauthwebcomposition','security')->build()['csrf']; }
    public function requiresLogin($action){return !in_array($action,['webhook','caption'],true);}
    public function t(string $key): string {return $this->getObject('language','language')->code2Txt('mod_video_service_'.$key,'video-service');}
    private function json(array $data,int $status=200){http_response_code($status);header('Content-Type: application/json');header('Cache-Control: no-store');echo json_encode($data,JSON_HEX_TAG|JSON_HEX_AMP|JSON_HEX_APOS|JSON_HEX_QUOT);exit;}
    public function dispatch($action)
    {
        if($action==='webhook'){
            try {if(($_SERVER['REQUEST_METHOD'] ?? '')!=='POST')throw new RuntimeException('invalid_webhook');$this->service->webhook((string)$this->getParam('configuration',''),file_get_contents('php://input',false,null,0,1048577),(string)($_SERVER['HTTP_MUX_SIGNATURE'] ?? ''));$this->json(['ok'=>true]);}
            catch(Throwable $e){$this->json(['ok'=>false],$e->getMessage()==='invalid_webhook'?401:503);}
        }
        if($action==='caption'){
            try {$caption=$this->service->caption((string)$this->getParam('ticket',''),(string)$this->getParam('token',''));header('Content-Type: '.($caption['format']==='vtt'?'text/vtt':'application/x-subrip').'; charset=utf-8');header('Cache-Control: no-store');header('X-Content-Type-Options: nosniff');echo $caption['content'];exit;}catch(Throwable $e){http_response_code(404);exit;}
        }
        $scope=(string)$this->getParam('scope','site');$id=(string)$this->getParam('id','');
        try {
            if($action==='playback')$this->json(['ok'=>true,'playback'=>$this->service->playback($id,(string)$this->getParam('consumer',''),(string)$this->getParam('reference',''))]);
            if($action==='inspect'){$this->service->refresh($this->service->managed($id));return $this->nextAction(null,['scope'=>$scope]);}
            if($action==='status'){$video=$this->service->managed($id);$video=$this->service->refresh($video);$this->json(['ok'=>true,'state'=>$video['state']]);}
            if(in_array($action,['upload','metadata','delete','attach','detach','progress','reconcile','addcaption'],true)){
                if(($_SERVER['REQUEST_METHOD'] ?? '')!=='POST'||!$this->csrf->consume('video-service',(string)$this->getParam('csrf_token','')))throw new RuntimeException('form_expired');
                switch($action){
                    case 'upload':$result=$this->service->createUpload($scope,(string)$this->getParam('title',''),(string)$this->getParam('description',''),(string)$this->getParam('request_id',''));$this->json(['ok'=>true,'upload'=>$result,'csrf'=>$this->csrf->issue('video-service')]);break;
                    case 'addcaption':$file=$_FILES['caption_file'] ?? [];if(($file['error'] ?? UPLOAD_ERR_NO_FILE)!==UPLOAD_ERR_OK||!is_uploaded_file($file['tmp_name'])||$file['size']>1048576)throw new RuntimeException('invalid_caption');$this->service->addCaption($id,file_get_contents($file['tmp_name']),strtolower(pathinfo($file['name'],PATHINFO_EXTENSION)),(string)$this->getParam('language',''),(string)$this->getParam('caption_name',''));break;
                    case 'metadata':$this->service->managed($id);$title=trim((string)$this->getParam('title',''));$description=(string)$this->getParam('description','');if($title===''||mb_strlen($title)>255||mb_strlen($description)>10000)throw new RuntimeException('invalid_metadata');$this->service->db->withDatabaseLock('video-service',function()use($id,$title,$description){$current=$this->service->managed($id);if(!hash_equals(hash('sha256',$current['title']."\0".$current['description']),(string)$this->getParam('revision','')))throw new RuntimeException('stale_metadata');$this->service->db->save($id,['title'=>$title,'description'=>$description]);});break;
                    case 'delete':if($this->getParam('confirm')!=='delete')throw new RuntimeException('confirmation_required');$this->service->requestDeletion($id);break;
                    case 'attach':$context=(string)$this->getParam('context','');$this->service->consumer('contextcontent')->attach($context,(string)$this->getParam('placement',''),$id,(int)$this->getParam('percent',0));break;
                    case 'detach':$this->service->consumer('contextcontent')->detach((string)$this->getParam('reference',''));break;
                    case 'progress':$result=$this->service->progress($id,(string)$this->getParam('consumer',''),(string)$this->getParam('reference',''),(float)$this->getParam('position',-1),$this->getParam('playing')==='1');$this->json(['ok'=>true,'progress'=>$result,'csrf'=>$this->csrf->issue('video-service')]);break;
                    case 'reconcile':$this->service->requireManager('site');$this->service->reconcile();break;
                }
                if($this->getParam('ajax')==='1')$this->json(['ok'=>true]);
                return $this->nextAction(null,['scope'=>$scope]);
            }
            $this->service->requireManager($scope);
            $this->setVar('videoConfigured',$this->service->available());$this->setVar('videoScope',$scope);$this->setVar('videoToken',$this->csrf->issue('video-service'));
            $this->setVar('videoRows',$this->service->db->listing($scope,substr((string)$this->getParam('search',''),0,255),max(0,(int)$this->getParam('offset',0))));
            $this->setVar('videoService',$this->service);return 'library_tpl.php';
        }catch(Throwable $error){
            $known=['access_denied','not_found','video_unavailable','form_expired','invalid_metadata','configuration_missing','upload_creation_uncertain','video_in_use','confirmation_required','provider_busy','provider_uncertain','provider_rejected','invalid_progress','invalid_caption','stale_metadata','attachment_exists','upload_already_exists'];
            $code=in_array($error->getMessage(),$known,true)?$error->getMessage():'operation_failed';
            if($this->getParam('ajax')==='1'||in_array($action,['upload','playback','status','progress'],true))$this->json(['ok'=>false,'error'=>$code,'message'=>$this->t($code)],$code==='access_denied'?403:400);
            $this->setVar('videoError',$this->t($code));return 'error_tpl.php';
        }
    }
}
class_alias(video_service::class,'video-service');
