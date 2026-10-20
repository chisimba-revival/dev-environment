<?php
/** Managed video schema. @author Derek Keats */
$tablename = 'tbl_video_events';
$options = ['collate'=>'utf8_general_ci', 'character_set'=>'utf8'];
$fields = [
    'id' => ['type'=>'text','length'=>32,'notnull'=>true],
    'configuration' => ['type'=>'text','length'=>64],
    'event_id' => ['type'=>'text','length'=>191],
    'created_at' => ['type'=>'timestamp'],
];
$tableIndexes = ['primary'=>['primary'=>true,'fields'=>['id'=>[]]]];
$tableIndexes['video_event_unique']=['unique'=>true,'fields'=>['configuration'=>[],'event_id'=>[]]];
