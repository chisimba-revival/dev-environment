<?php
/** Explicit operator maintenance; dry-run by default. Never accessible over HTTP.
 * Usage from runtime root: CHISIMBA_IMAGE_MAINTENANCE=1 php packages/messaging/tools/cleanup-images.php [--apply]
 * @author Derek Keats
 */
if(PHP_SAPI!=='cli'||getenv('CHISIMBA_IMAGE_MAINTENANCE')!=='1')exit(64);
if(!is_file('classes/core/engine_class_inc.php'))throw new RuntimeException('Run from the configured runtime root');
$GLOBALS['kewl_entry_point_run']=true;$_SERVER['REQUEST_METHOD']='CLI';$_SERVER['SCRIPT_NAME']='/index.php';$_SERVER['QUERY_STRING']='';
require 'classes/core/engine_class_inc.php';$engine=new engine();$store=$engine->getObject('conversationstore','messaging');
$apply=($argv[1]??'')==='--apply';
if($apply)$store->afterContextDeletion();
$count=$store->withDatabaseLock('msg:images:orphans',fn()=>$engine->getObject('privateimageasset','filemanager')->pruneUnreferenced('messaging',fn($id)=>(bool)$store->selectPrepared('SELECT id FROM tbl_messaging_sightings_v2 WHERE id=?',[$id]),$apply));
echo ($apply?'Removed':'Eligible').': '.$count." unreferenced private images older than 24 hours (limit 100).\n";
