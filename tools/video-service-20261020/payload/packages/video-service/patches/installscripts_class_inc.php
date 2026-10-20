<?php
/** Enforce identity and idempotency using shared schema constraints. @author Derek Keats */
if(empty($GLOBALS['kewl_entry_point_run']))die('No direct access');
class video_service_installscripts extends dbTable
{
    public function postinstall($version=null)
    {
        $admin=$this->getObject('modulesadmin','modulecatalogue');
        foreach(['tbl_video_captions'=>'content','tbl_video_progress'=>'intervals'] as $table=>$column){
            $row=$this->selectPrepared('SELECT DATA_TYPE AS datatype FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME=? AND COLUMN_NAME=?',[$table,$column])[0] ?? null;
            if(!$row)throw new RuntimeException('Video schema is incomplete');
            if($row['datatype']!=='longtext' && $admin->executeSchemaStatement('ALTER TABLE '.$table.' MODIFY '.$column.' LONGTEXT')===false)throw new RuntimeException('Video text schema upgrade failed');
        }
        $definitions=[
            'tbl_video_assets'=>['video_identity'=>['id'=>[]]],
            'tbl_video_events'=>['video_event_identity'=>['id'=>[]],'video_event_dedupe'=>['configuration'=>[],'event_id'=>[]]],
            'tbl_video_progress'=>['video_progress_identity'=>['id'=>[]],'video_progress_reference'=>['user_id'=>[],'reference'=>[],'video_id'=>[]]],
            'tbl_video_captions'=>['video_caption_identity'=>['id'=>[]]]
        ];
        foreach($definitions as $table=>$indexes){
            $constraints=$admin->listTableConstraints($table);
            if(!is_array($constraints))throw new RuntimeException('Video constraint inspection failed');
            foreach($indexes as $name=>$fields)if(!in_array($name,$constraints,true)){
                if($admin->createConstraint($table,$name,['unique'=>true,'fields'=>$fields])===false)throw new RuntimeException('Video constraint installation failed');
            }
        }
    }
}
class_alias(video_service_installscripts::class,'video-service_installscripts');
