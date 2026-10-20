<?php
/** Bounded CLI reconciliation; schedule through the installation's worker runner. @author Derek Keats */
if(PHP_SAPI!=='cli')exit(64);
$root=$argv[1] ?? '';
if(!$root||!is_file($root.'/classes/core/engine_class_inc.php'))exit("Usage: php reconcile.php /absolute/chisimba/root\n");
chdir($root);$_SERVER['REQUEST_METHOD']='CLI';$_SERVER['HTTP_HOST']='localhost';$_SERVER['SCRIPT_NAME']='/index.php';$_SERVER['QUERY_STRING']='';
$GLOBALS['kewl_entry_point_run']=true;require 'classes/core/engine_class_inc.php';$engine=new engine();
try{$result=$engine->getObject('videoservice','video-service')->reconcile();echo json_encode($result)."\n";exit($result['failed']?1:0);}catch(Throwable $error){fwrite(STDERR,"Video reconciliation failed; check configuration and database availability.\n");exit(1);}
