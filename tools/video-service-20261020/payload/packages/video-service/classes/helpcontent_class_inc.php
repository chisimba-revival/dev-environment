<?php
/** Contextual Help for the complete video workflow. @author Derek Keats */
if(empty($GLOBALS['kewl_entry_point_run']))die('No direct access');
class helpcontent extends ChisimbaObject
{
    public function mayViewTopic($topic){return $topic==='library' && $this->getObject('user','security')->isLoggedIn();}
    public function getTopic($topic){if(!$this->mayViewTopic($topic))return null;$t=fn($k)=>$this->getObject('language','language')->code2Txt('mod_video_service_'.$k,'video-service');return ['title'=>$t('library'),'summary'=>$t('help_summary'),'steps'=>array_map($t,['help_upload','help_access','help_progress','help_captions','help_delete','help_recovery']),'sections'=>[]];}
}
