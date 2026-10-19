<?php
/** Repeat-safe plain-text announcement sends. @author Derek Keats */
$tablename='tbl_announcements_chat_receipts';
$options=['comment'=>'Announcement message receipts','collate'=>'utf8mb4_unicode_ci','charset'=>'utf8mb4','type'=>'InnoDB'];
$fields=[
 'id'=>['type'=>'text','notnull'=>true,'length'=>64],
 'announcement_id'=>['type'=>'text','notnull'=>true,'length'=>32],
 'sender_id'=>['type'=>'text','notnull'=>true,'length'=>64],
 'submission_id'=>['type'=>'text','notnull'=>true,'length'=>36],
 'body_hash'=>['type'=>'text','notnull'=>true,'length'=>64],
];
$tableIndexes=['ann_chat_pk'=>['primary'=>true,'fields'=>['id'=>[]]],'ann_chat_post'=>['fields'=>['announcement_id'=>[]]]];
