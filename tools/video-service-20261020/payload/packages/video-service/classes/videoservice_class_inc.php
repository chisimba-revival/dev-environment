<?php
/** Reusable video orchestration; consumers retain their access and learning rules. @author Derek Keats */
if (empty($GLOBALS['kewl_entry_point_run'])) die('No direct access');
require_once __DIR__.'/videoproviderinterface.php';
class videoservice extends ChisimbaObject
{
    public $db; public $user; private array $configuration=[];
    public function init()
    {
        $this->db=$this->getObject('dbvideos','video-service');$this->user=$this->getObject('user','security');
        $config=$this->getObject('dbsysconfig','sysconfig');
        $value=fn($key)=>trim((string)$config->getValue($key,'video-service'));
        // Account profiles preserve old environments when an administrator adds another.
        $profiles=json_decode($value('VIDEO_MUX_ADDITIONAL_PROFILES') ?: '{}',true);
        if(!is_array($profiles))$profiles=[];
        $profiles['mux-default']=['provider'=>'mux','token_id'=>$value('VIDEO_MUX_TOKEN_ID'),
            'token_secret'=>$value('VIDEO_MUX_TOKEN_SECRET'),'signing_key_id'=>$value('VIDEO_MUX_SIGNING_KEY_ID'),
            'signing_private_key'=>$value('VIDEO_MUX_SIGNING_PRIVATE_KEY'),'webhook_secret'=>$value('VIDEO_MUX_WEBHOOK_SECRET')];
        $public=$value('VIDEO_PUBLIC_URL');
        $parts=parse_url($public);$origin=isset($parts['scheme'],$parts['host'])?$parts['scheme'].'://'.$parts['host'].(isset($parts['port'])?':'.$parts['port']:''):'';
        $this->configuration=['default'=>$value('VIDEO_DEFAULT_CONFIGURATION') ?: 'mux-default','providers'=>$profiles,'origin'=>$origin,'public_url'=>$public];
    }
    public function provider(string $configuration): VideoProviderInterface
    {
        $settings=$this->configuration['providers'][$configuration] ?? null;
        if(!is_array($settings)||($settings['provider'] ?? '')!=='mux')throw new RuntimeException('configuration_missing');
        $provider=$this->newObject('muxvideoprovider','video-service');$provider->configure($settings);return $provider;
    }
    public function available(): bool { try{return $this->provider($this->configuration['default'])->configured() && str_starts_with($this->configuration['public_url'],'https://');}catch(Throwable $error){return false;} }
    public function consumer(string $name)
    {
        // Trusted registry, never instantiate a class supplied in a request.
        $registry=['contextcontent'=>['videoconsumer','contextcontent']];
        if(!isset($registry[$name])||!$this->getObject('modules','modulecatalogue')->checkIfRegistered($registry[$name][1]))throw new RuntimeException('access_denied');
        return $this->getObject(...$registry[$name]);
    }
    public function requireManager(string $scope): void
    {
        if(!$this->user->isLoggedIn())throw new RuntimeException('access_denied');
        if($scope==='site' && $this->user->isAdmin())return;
        $parts=explode(':',$scope,2);
        if(count($parts)===2 && !preg_match('/^[A-Za-z0-9._-]{1,255}$/D',$parts[1]))throw new RuntimeException('access_denied');
        if(count($parts)!==2||!$this->consumer($parts[0])->mayManage($parts[1]))throw new RuntimeException('access_denied');
    }
    public function managed(string $id): array
    {
        $video=$this->db->one($id);if(!$video)throw new RuntimeException('not_found');$this->requireManager($video['scope']);return $video;
    }
    public function createUpload(string $scope,string $title,string $description,string $requestId): array
    {
        $this->requireManager($scope);$title=trim($title);
        if($title===''||mb_strlen($title)>255||mb_strlen($description)>10000)throw new RuntimeException('invalid_metadata');
        $configuration=$this->configuration['default'] ?? ''; $provider=$this->provider($configuration);
        $origin=$this->configuration['origin'] ?? '';
        if(!$provider->configured())throw new RuntimeException('configuration_missing');
        if(!preg_match('#^https://[^/]+$#D',$origin))throw new RuntimeException('configuration_missing');
        $id=$requestId;if(!preg_match('/^[a-f0-9]{32}$/D',$id))throw new RuntimeException('invalid_metadata');$now=gmdate('Y-m-d H:i:s');
        $this->db->withDatabaseLock('video-service',function()use($id,$scope,$title,$description,$configuration,$now){
        if($this->db->one($id))throw new RuntimeException('upload_already_exists');
        $this->db->create(['id'=>$id,'scope'=>$scope,'owner_id'=>$this->user->userId(),'title'=>$title,'description'=>$description,'provider'=>'mux','configuration'=>$configuration,'state'=>'uncertain','created_at'=>$now,'updated_at'=>$now]);
        });
        try { $upload=$provider->createUpload($id,$origin); }
        catch(Throwable $error){$this->db->save($id,['error_code'=>'upload_creation_uncertain']);throw new RuntimeException('upload_creation_uncertain');}
        $this->db->withDatabaseLock('video-service',function()use($id,$upload){$current=$this->db->one($id);$values=['upload_id'=>$upload['upload_id']];if($current['state']==='uncertain')$values['state']='uploading';$this->db->save($id,$values);});
        return ['id'=>$id,'url'=>$upload['url']];
    }
    public function refresh(array $video): array
    {
        return $this->db->withDatabaseLock('video-service',function()use($video){
            $video=$this->db->one($video['id']);
            if(in_array($video['state'],['deleted','pending_delete'],true))return $video;
            $values=$this->provider($video['configuration'])->processingStatus($video);$values['updated_at']=gmdate('Y-m-d H:i:s');
            $this->db->save($video['id'],$values);return $this->db->one($video['id']);
        });
    }
    public function playback(string $id,string $consumer='',string $reference=''): array
    {
        $video=$this->db->one($id);if(!$video||$video['state']!=='ready')throw new RuntimeException('video_unavailable');
        if($consumer==='')$this->requireManager($video['scope']);
        elseif(!$this->consumer($consumer)->mayPlay($reference,$id))throw new RuntimeException('access_denied');
        $grant=$this->provider($video['configuration'])->authorisePlayback($video['playback_id'],time()+900);
        $progress=$this->db->progress((string)$this->user->userId(),$consumer.':'.$reference,$id);
        return $grant+['position'=>(float)$progress['position'],'duration'=>(float)(json_decode($video['metadata'] ?: '{}',true)['duration'] ?? 0)];
    }
    public function progress(string $id,string $consumer,string $reference,float $position,bool $playing): array
    {
        if(!$this->user->isLoggedIn()||!$this->consumer($consumer)->mayPlay($reference,$id))throw new RuntimeException('access_denied');
        return $this->db->withDatabaseLock('video-service',function()use($id,$consumer,$reference,$position,$playing){
            $video=$this->db->one($id);if(!$video||$video['state']!=='ready')throw new RuntimeException('video_unavailable');
            $duration=(float)(json_decode($video['metadata'] ?: '{}',true)['duration'] ?? 0);$key=$consumer.':'.$reference;$user=(string)$this->user->userId();
            $this->getObject('videoprogress','video-service');$value=videoprogress::advance($this->db->progress($user,$key,$id),$position,$duration,time(),$playing);
            $this->db->saveProgress($user,$key,$id,$value);return ['position'=>$value['position'],'percent'=>videoprogress::percentage($value,$duration)];
        });
    }
    public function requestDeletion(string $id): void
    {
        $this->managed($id);
        $this->db->withDatabaseLock('video-service',function()use($id){
            if($this->getObject('modules','modulecatalogue')->checkIfRegistered('contextcontent') && $this->consumer('contextcontent')->references($id))throw new RuntimeException('video_in_use');
            $video=$this->db->one($id);
            if($video['state']==='deleted')return;
            if($video['state']==='uncertain' && empty($video['upload_id']) && empty($video['asset_id']))throw new RuntimeException('upload_creation_uncertain');
            $this->db->save($id,['state'=>'pending_delete']);
        });
        $this->finishDeletion($id);
    }
    private function finishDeletion(string $id): void
    {
        $this->db->withDatabaseLock('video-service',function()use($id){$video=$this->db->one($id);if($video['state']!=='pending_delete')return;
            $this->provider($video['configuration'])->deleteHostedVideo($video);$this->db->save($id,['state'=>'deleted','updated_at'=>gmdate('Y-m-d H:i:s')]);});
    }
    public function webhook(string $configuration,string $raw,string $signature): void
    {
        $event=$this->provider($configuration)->verifyWebhook($raw,$signature,time());
        $this->db->withDatabaseLock('video-service',function()use($configuration,$event){
            if($this->db->eventSeen($configuration,$event['id']))return;
            $data=$event['data'];$type=$event['type'];$video=null;
            if(str_starts_with($type,'video.upload.'))$video=$this->db->forProvider($configuration,'upload_id',(string)($data['id'] ?? ''));
            if(!$video && !empty($data['passthrough']))$video=$this->db->one($data['passthrough']);
            if(!$video)$video=$this->db->forProvider($configuration,'asset_id',(string)($data['asset_id'] ?? $data['id'] ?? ''));
            // Unknown events can precede the response that persists an upload ID. Ask Mux to retry.
            if(!$video && str_starts_with($type,'video.upload.'))throw new RuntimeException('webhook_retry');
            $this->db->transaction(function()use($video,$configuration,$event,$data,$type){
                if($video && $video['configuration']===$configuration){
                    $asset=str_starts_with($type,'video.asset.') && !str_contains($type,'.track.') ? ($data['id'] ?? '') : ($data['asset_id'] ?? '');
                    if($asset && empty($video['asset_id'])){$video['asset_id']=$asset;$this->db->save($video['id'],['asset_id'=>$asset]);}
                    if(in_array($video['state'],['deleted','pending_delete'],true)){
                        if($asset && $type!=='video.asset.deleted')$this->db->save($video['id'],['state'=>'pending_delete']);
                    } elseif($type==='video.asset.deleted')$this->db->save($video['id'],['state'=>'deleted']);
                    elseif(!empty($video['asset_id']))$this->db->save($video['id'],$this->provider($configuration)->metadata($video['asset_id']));
                    elseif(in_array($type,['video.upload.cancelled','video.upload.errored','video.upload.timed_out'],true))$this->db->save($video['id'],['state'=>'failed']);
                }
                $this->db->rememberEvent($configuration,$event['id']);
            });
        });
    }
    /** Stage only caption text for a time-limited provider fetch. */
    public function addCaption(string $id,string $content,string $format,string $language,string $name): void
    {
        $video=$this->managed($id);
        if($video['state']!=='ready'||strlen($content)>1048576||!mb_check_encoding($content,'UTF-8')
            ||!in_array($format,['vtt','srt'],true)||!preg_match('/^[a-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$/D',$language)
            ||trim($name)===''||mb_strlen($name)>100||!str_contains($content,'-->'))throw new RuntimeException('invalid_caption');
        $base=$this->configuration['public_url'] ?? '';
        if(!str_starts_with($base,($this->configuration['origin'] ?? '').'/')||!str_starts_with($base,'https://')||str_contains($base,'?'))throw new RuntimeException('configuration_missing');
        $ticket=bin2hex(random_bytes(16));$token=bin2hex(random_bytes(32));
        $this->db->executePrepared('INSERT INTO tbl_video_captions (id,token_hash,content,format,expires_at) VALUES (?,?,?,?,?)',[$ticket,hash('sha256',$token),$content,$format,time()+86400]);
        $url=$base.'?'.http_build_query(['module'=>'video-service','action'=>'caption','ticket'=>$ticket,'token'=>$token]);
        $this->provider($video['configuration'])->addCaption($video['asset_id'],$url,$language,$name);
    }
    public function caption(string $id,string $token): array
    {
        $row=$this->db->selectPrepared('SELECT * FROM tbl_video_captions WHERE id=?',[$id])[0] ?? null;
        if(!$row||(int)$row['expires_at']<time()||!hash_equals($row['token_hash'],hash('sha256',$token)))throw new RuntimeException('not_found');
        return $row;
    }
    public function reconcile(): array
    {
        $this->db->executePrepared('DELETE FROM tbl_video_captions WHERE expires_at<?',[time()]);
        $result=['checked'=>0,'failed'=>0];foreach($this->db->pending() as $video){try {if($video['state']==='pending_delete')$this->finishDeletion($video['id']);else $this->refresh($video);$result['checked']++;}catch(Throwable $error){$result['failed']++;$this->db->save($video['id'],['updated_at'=>gmdate('Y-m-d H:i:s')]);}}return $result;
    }
}
