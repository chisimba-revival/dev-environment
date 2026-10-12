<?php
/** Small toolbar-only follow-up, using the ordinary catalogue and preserving site links. */
if(PHP_SAPI!=='cli'||getenv('PEAR_NAV_UPGRADE')!=='20261012')exit(64);
[$script,$root,$host]=$argv;
if(!in_array($root,['/var/www/html','/var/www/html/ch'],true)||!in_array($host,['chisimba.com','kengalearn.com','learnthebirds.com','kengapub.com','kengasolutions.com','heritagetreazures.com'],true))exit(64);
chdir($root);$GLOBALS['kewl_entry_point_run']=true;
$_SERVER['REQUEST_METHOD']='CLI';$_SERVER['HTTP_HOST']=$host;$_SERVER['SCRIPT_NAME']='/index.php';$_SERVER['QUERY_STRING']='';
error_reporting(E_ALL);set_error_handler(static function($s,$m,$f,$l){throw new ErrorException($m,0,$s,$f,$l);});
require 'classes/core/engine_class_inc.php';$engine=new engine();
if(!in_array(parse_url($engine->getObject('altconfig','config')->getSiteRoot(),PHP_URL_HOST),[$host,'www.'.$host],true))throw new RuntimeException('Wrong site');
$menu=$engine->getObject('dbmenu','toolbar');
$read=fn()=>$menu->selectPrepared("SELECT * FROM tbl_menu_category WHERE SUBSTR(category,1,5)=? ORDER BY id",['site_']);
$before=$read();$patch=$engine->getObject('patch','modulecatalogue');
$result=$patch->applyUpdates('toolbar');
if(!is_array($result)||($result['current']??'')!=='1.813')throw new RuntimeException('Toolbar update failed');
if($read()!==$before)throw new RuntimeException('Site navigation changed');
echo 'PASS toolbar 1.813; all '.count($before).' site navigation rows unchanged'."\n";
