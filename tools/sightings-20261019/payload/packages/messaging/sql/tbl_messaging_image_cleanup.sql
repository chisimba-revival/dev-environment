<?php
/** Transactional deletion outbox; failed filesystem cleanup is safe to retry. @author Derek Keats */
$tablename='tbl_messaging_image_cleanup';
$options=['comment'=>'Private sighting image cleanup outbox','collate'=>'utf8mb4_unicode_ci','charset'=>'utf8mb4','type'=>'InnoDB'];
$fields=['id'=>['type'=>'text','notnull'=>true,'length'=>32],'scope_hash'=>['type'=>'text','notnull'=>true,'length'=>64]];
$tableIndexes=['msg_image_cleanup_id'=>['fields'=>['id'=>[]]]];
