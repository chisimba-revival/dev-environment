<?php
/** Short-lived caption transfer, never original video storage. @author Derek Keats */
$tablename='tbl_video_captions';
$options=['collate'=>'utf8_general_ci','character_set'=>'utf8'];
$fields=['id'=>['type'=>'text','length'=>32,'notnull'=>true],'token_hash'=>['type'=>'text','length'=>64],'content'=>['type'=>'clob'],'format'=>['type'=>'text','length'=>8],'expires_at'=>['type'=>'integer']];
$tableIndexes=['primary'=>['primary'=>true,'fields'=>['id'=>[]]]];
