<?php
/** Managed video schema. @author Derek Keats */
$tablename = 'tbl_video_assets';
$options = ['collate'=>'utf8_general_ci', 'character_set'=>'utf8'];
$fields = [
    'id' => ['type'=>'text','length'=>32,'notnull'=>true],
    'scope' => ['type'=>'text','length'=>255],
    'owner_id' => ['type'=>'text','length'=>64],
    'title' => ['type'=>'text','length'=>255],
    'description' => ['type'=>'text'],
    'provider' => ['type'=>'text','length'=>32],
    'configuration' => ['type'=>'text','length'=>64],
    'state' => ['type'=>'text','length'=>32],
    'upload_id' => ['type'=>'text','length'=>191],
    'asset_id' => ['type'=>'text','length'=>191],
    'playback_id' => ['type'=>'text','length'=>191],
    'metadata' => ['type'=>'text'],
    'error_code' => ['type'=>'text','length'=>64],
    'created_at' => ['type'=>'timestamp'],
    'updated_at' => ['type'=>'timestamp'],
];
$tableIndexes = ['primary'=>['primary'=>true,'fields'=>['id'=>[]]]];
