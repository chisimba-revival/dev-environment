<?php
/** Mux transport and verification; no course or completion rules. @author Derek Keats */
if (empty($GLOBALS['kewl_entry_point_run'])) die('No direct access');
require_once __DIR__.'/videoproviderinterface.php';
class muxvideoprovider extends ChisimbaObject implements VideoProviderInterface
{
    private array $settings = [];
    public function configure(array $settings): void { $this->settings = $settings; }
    public function configured(): bool { foreach(['token_id','token_secret','signing_key_id','signing_private_key','webhook_secret'] as $key)if(empty($this->settings[$key]))return false;return true; }
    public function capabilities(): array { return ['direct_upload'=>true,'captions'=>true,'signed_playback'=>true]; }
    /** Only trusted deployment configuration supplies credentials and origins. */
    protected function request(string $method, string $path, ?array $data = null): array
    {
        if (empty($this->settings['token_id']) || empty($this->settings['token_secret'])) throw new RuntimeException('configuration_missing');
        $curl = curl_init('https://api.mux.com/video/v1/'.$path);
        curl_setopt_array($curl, [CURLOPT_RETURNTRANSFER=>true, CURLOPT_CUSTOMREQUEST=>$method,
            CURLOPT_USERPWD=>$this->settings['token_id'].':'.$this->settings['token_secret'],
            CURLOPT_HTTPHEADER=>['Content-Type: application/json'], CURLOPT_CONNECTTIMEOUT=>10,
            CURLOPT_TIMEOUT=>30, CURLOPT_FOLLOWLOCATION=>false, CURLOPT_PROTOCOLS=>CURLPROTO_HTTPS]);
        if ($data !== null) curl_setopt($curl, CURLOPT_POSTFIELDS, json_encode($data, JSON_THROW_ON_ERROR));
        $raw = curl_exec($curl); $status = curl_getinfo($curl, CURLINFO_HTTP_CODE); curl_close($curl);
        if ($method === 'DELETE' && $status === 404) return [];
        if ($status === 404) throw new RuntimeException('provider_not_found');
        if ($raw === false || $status === 0 || $status >= 500) throw new RuntimeException('provider_uncertain');
        if ($status === 429) throw new RuntimeException('provider_busy');
        if ($status < 200 || $status >= 300) throw new RuntimeException('provider_rejected');
        return $raw === '' ? [] : (json_decode($raw, true, 64, JSON_THROW_ON_ERROR)['data'] ?? []);
    }
    public function createUpload(string $videoId, string $origin): array
    {
        $data = $this->request('POST','uploads',['cors_origin'=>$origin,'timeout'=>3600,
            'new_asset_settings'=>['playback_policies'=>['signed'],'video_quality'=>'basic','passthrough'=>$videoId]]);
        return ['upload_id'=>$data['id'],'url'=>$data['url']];
    }
    public function processingStatus(array $video): array
    {
        $asset = $video['asset_id'] ?? '';
        if (!$asset && !empty($video['upload_id'])) {
            $upload = $this->request('GET','uploads/'.rawurlencode($video['upload_id']));
            $asset = $upload['asset_id'] ?? '';
            if (!$asset) return ['state'=>in_array($upload['status'] ?? '',['errored','timed_out','cancelled'],true)?'failed':'uploading'];
        }
        if (!$asset) return ['state'=>'uncertain'];
        return $this->metadata($asset);
    }
    public function metadata(string $assetId): array
    {
        try {$asset = $this->request('GET','assets/'.rawurlencode($assetId));}
        catch(RuntimeException $error){if($error->getMessage()==='provider_not_found')return ['state'=>'deleted','asset_id'=>$assetId];throw $error;}
        $playback = '';
        foreach ($asset['playback_ids'] ?? [] as $id) if ($id['policy'] === 'signed') { $playback=$id['id']; break; }
        return ['asset_id'=>$assetId,'playback_id'=>$playback,
            'state'=>($asset['status'] ?? '')==='ready' ? ($playback!==''?'ready':'failed') : (($asset['status'] ?? '')==='errored' ? 'failed' : 'processing'),
            'metadata'=>json_encode(['duration'=>$asset['duration'] ?? 0,'aspect_ratio'=>$asset['aspect_ratio'] ?? '',
                'tracks'=>array_map(static fn($t)=>array_intersect_key($t,array_flip(['id','type','status','language_code','name','text_type','max_width','max_height'])), $asset['tracks'] ?? [])])];
    }
    public function authorisePlayback(string $playbackId, int $expires): array
    {
        $key = $this->settings['signing_private_key'] ?? '';
        if (!str_contains($key,'BEGIN')) $key = base64_decode($key,true) ?: '';
        $encode = static fn($s)=>rtrim(strtr(base64_encode($s),'+/','-_'),'=');
        $privateKey=$key!==''?openssl_pkey_get_private($key):false;
        if($privateKey===false || empty($this->settings['signing_key_id']))throw new RuntimeException('configuration_missing');
        $header=$encode(json_encode(['alg'=>'RS256','typ'=>'JWT','kid'=>$this->settings['signing_key_id'] ?? '']));
        $payload=$encode(json_encode(['sub'=>$playbackId,'aud'=>'v','exp'=>$expires]));
        if (!openssl_sign($header.'.'.$payload,$signature,$privateKey,OPENSSL_ALGO_SHA256)) throw new RuntimeException('configuration_missing');
        $grant=['playback_id'=>$playbackId,'token'=>$header.'.'.$payload.'.'.$encode($signature),'expires'=>$expires];
        foreach(['thumbnail'=>'t','storyboard'=>'s'] as $name=>$audience){
            $claims=$encode(json_encode(['sub'=>$playbackId,'aud'=>$audience,'exp'=>$expires]));
            if(!openssl_sign($header.'.'.$claims,$signed,$privateKey,OPENSSL_ALGO_SHA256))throw new RuntimeException('configuration_missing');
            $grant[$name.'_token']=$header.'.'.$claims.'.'.$encode($signed);
        }
        return $grant;
    }
    public function deleteHostedVideo(array $video): void
    {
        if (!empty($video['upload_id']) && empty($video['asset_id'])) {
            try {$upload=$this->request('GET','uploads/'.rawurlencode($video['upload_id']));}
            catch(RuntimeException $error){if($error->getMessage()==='provider_not_found')return;throw $error;}
            if (!empty($upload['asset_id'])) $video['asset_id']=$upload['asset_id'];
            elseif (($upload['status'] ?? '')==='waiting') $this->request('PUT','uploads/'.rawurlencode($video['upload_id']).'/cancel');
        }
        if (!empty($video['asset_id'])) $this->request('DELETE','assets/'.rawurlencode($video['asset_id']));
    }
    public function addCaption(string $asset, string $url, string $language, string $name): array
    {
        return $this->request('POST','assets/'.rawurlencode($asset).'/tracks', ['url'=>$url,'type'=>'text','text_type'=>'subtitles','language_code'=>$language,'name'=>$name,'closed_captions'=>false]);
    }
    public function verifyWebhook(string $raw, string $signature, int $now): array
    {
        if (strlen($raw)>1048576 || empty($this->settings['webhook_secret'])) throw new RuntimeException('invalid_webhook');
        $parts=[]; foreach(explode(',',$signature) as $part) { $pair=explode('=',trim($part),2); if(count($pair)===2)$parts[$pair[0]][]=$pair[1]; }
        $stamp=$parts['t'][0] ?? '';
        if(!ctype_digit($stamp) || abs($now-(int)$stamp)>300) throw new RuntimeException('invalid_webhook');
        $expected=hash_hmac('sha256',$stamp.'.'.$raw,$this->settings['webhook_secret']); $valid=false;
        foreach($parts['v1'] ?? [] as $candidate) $valid=hash_equals($expected,$candidate)||$valid;
        if(!$valid) throw new RuntimeException('invalid_webhook');
        $event=json_decode($raw,true,64,JSON_THROW_ON_ERROR);
        if(!is_array($event)||empty($event['id'])||empty($event['type'])||!is_array($event['data'] ?? null)) throw new RuntimeException('invalid_webhook');
        return $event;
    }
}
