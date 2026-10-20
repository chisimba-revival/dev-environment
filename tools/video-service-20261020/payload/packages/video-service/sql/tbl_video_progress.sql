<?php
/** Managed video schema. @author Derek Keats */
$tablename = 'tbl_video_progress';
$options = ['collate'=>'utf8_general_ci', 'character_set'=>'utf8'];
$fields = [
    'id' => ['type'=>'text','length'=>32,'notnull'=>true],
    'user_id' => ['type'=>'text','length'=>64],
    'reference' => ['type'=>'text','length'=>191],
    'video_id' => ['type'=>'text','length'=>32],
    'position' => ['type'=>'float'],
    'intervals' => ['type'=>'clob'],
    'last_at' => ['type'=>'integer'],
    'last_position' => ['type'=>'float'],
];
$tableIndexes = ['primary'=>['primary'=>true,'fields'=>['id'=>[]]]];
$tableIndexes['video_progress_unique']=['unique'=>true,'fields'=>['user_id'=>[],'reference'=>[],'video_id'=>[]]];
