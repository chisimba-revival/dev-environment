<?php
/** Reply references; message bodies remain in the canonical posts table. @author Derek Keats */
$tablename='tbl_messaging_replies_v2';
$options=['comment'=>'Conversation reply references','collate'=>'utf8mb4_unicode_ci','charset'=>'utf8mb4','type'=>'InnoDB'];
$fields=['id'=>['type'=>'text','notnull'=>true,'length'=>32],'channel_id'=>['type'=>'text','notnull'=>true,'length'=>32],'reply_to'=>['type'=>'text','notnull'=>true,'length'=>32]];
$tableIndexes=['msg_replies_post'=>['fields'=>['id'=>[]]],'msg_replies_channel'=>['fields'=>['channel_id'=>[]]]];
