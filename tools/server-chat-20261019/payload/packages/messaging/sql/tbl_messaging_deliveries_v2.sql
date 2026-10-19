<?php
/** Context messaging schema. @author Derek Keats */
$tablename='tbl_messaging_deliveries_v2';
$options=['comment'=>'Context messaging','collate'=>'utf8mb4_unicode_ci','charset'=>'utf8mb4','type'=>'InnoDB'];
$fields=[
 'id'=>['type'=>'text','notnull'=>true,'length'=>32],
 'channel_id'=>['type'=>'text','notnull'=>true,'length'=>32],
 'user_id'=>['type'=>'text','notnull'=>true,'length'=>64],
 'sequence_no'=>['type'=>'integer','notnull'=>true,'length'=>8],
];
$tableIndexes=[
 'msg_deliveries_pk'=>['primary'=>true,'fields'=>['id'=>[]]],
 'msg_deliveries_u0'=>['unique'=>true,'fields'=>['channel_id'=>[],'user_id'=>[]]],
];
