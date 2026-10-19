<?php
/** Sightings metadata. Image bytes are owned by File Manager private storage. @author Derek Keats */
$tablename='tbl_messaging_sightings_v2';
$options=['comment'=>'Private context sightings','collate'=>'utf8mb4_unicode_ci','charset'=>'utf8mb4','type'=>'InnoDB'];
$fields=['id'=>['type'=>'text','notnull'=>true,'length'=>32],
 'channel_id'=>['type'=>'text','notnull'=>true,'length'=>32],
 'sender_id'=>['type'=>'text','notnull'=>true,'length'=>32],
 'submission_id'=>['type'=>'text','notnull'=>true,'length'=>36],
 'body'=>['type'=>'clob','notnull'=>true],
 'image_digest'=>['type'=>'text','notnull'=>true,'length'=>64],
 'width'=>['type'=>'integer','notnull'=>true],
 'height'=>['type'=>'integer','notnull'=>true],
 'created_at'=>['type'=>'timestamp','notnull'=>true]];
$tableIndexes=['msg_sightings_channel'=>['fields'=>['channel_id'=>[]]],'msg_sightings_receipt'=>['fields'=>['channel_id'=>[],'sender_id'=>[],'submission_id'=>[]]]];
