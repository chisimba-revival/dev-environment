<?php
/** Shared semantic player shell. Provider-specific playback is kept in its adapter. @author Derek Keats */
if (empty($GLOBALS['kewl_entry_point_run'])) die('No direct access');
class videoplayer extends ChisimbaObject
{
    public function render(string $video,string $consumer='',string $reference=''): string
    {
        $service=$this->getObject('videoservice','video-service');
        if($consumer==='')$service->managed($video);elseif(!$service->consumer($consumer)->mayPlay($reference,$video))return '';
        $e=static fn($s)=>htmlspecialchars((string)$s,ENT_QUOTES,'UTF-8');
        $token=$this->getObject('nativeauthwebcomposition','security')->build()['csrf']->issue('video-service');
        $t=fn($key)=>$this->getObject('language','language')->code2Txt('mod_video_service_'.$key,'video-service');
        $url=$this->uri(['action'=>'playback','id'=>$video,'consumer'=>$consumer,'reference'=>$reference],'video-service');
        $progress=$this->uri(['action'=>'progress'],'video-service');
        return '<section data-chisimba-video data-error="'.$e($t('operation_failed')).'" data-playback="'.$e($url).'" data-progress="'.$e($progress).'" data-id="'.$e($video).'" data-consumer="'.$e($consumer).'" data-reference="'.$e($reference).'" data-csrf="'.$e($token).'">'
            .'<mux-player stream-type="on-demand" preload="none" aria-label="'.$e($t('player')).'"></mux-player><p role="status" aria-live="polite">'.$e($t('loading')).'</p>'
            .'<button type="button" data-video-retry>'.$e($t('retry')).'</button></section>'
            .'<script defer src="'.$e($this->getResourceUri('vendor/mux-player.js','video-service')).'"></script>'
            .'<script defer src="'.$e($this->getResourceUri('player.js','video-service')).'"></script>';
    }
}
