<?php
/** Managed video schema. @author Derek Keats */
$tablename = 'tbl_contextcontent_videos';
$options = ['collate'=>'utf8_general_ci', 'character_set'=>'utf8'];
$fields = [
    'id' => ['type'=>'text','length'=>32,'notnull'=>true],
    'contextcode' => ['type'=>'text','length'=>255],
    'placement_id' => ['type'=>'text','length'=>32],
    'video_id' => ['type'=>'text','length'=>32],
    'required_percent' => ['type'=>'integer'],
];
$tableIndexes = ['primary'=>['primary'=>true,'fields'=>['id'=>[]]]];
$tableIndexes['context_video_placement']=['unique'=>true,'fields'=>['placement_id'=>[]]];
