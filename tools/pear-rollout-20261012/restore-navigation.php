<?php
/** Restore the single backup-verified navigation row, without touching content. */
if(PHP_SAPI!=='cli'||getenv('PEAR_NAV_RESTORE')!=='20261012')exit(64);
chdir('/var/www/html/ch');$GLOBALS['kewl_entry_point_run']=true;
$_SERVER['REQUEST_METHOD']='CLI';$_SERVER['HTTP_HOST']='kengasolutions.com';$_SERVER['SCRIPT_NAME']='/index.php';$_SERVER['QUERY_STRING']='';
require 'classes/core/engine_class_inc.php';$engine=new engine();
if(!in_array(parse_url($engine->getObject('altconfig','config')->getSiteRoot(),PHP_URL_HOST),['kengasolutions.com','www.kengasolutions.com'],true))throw new RuntimeException('Wrong site');
$expected=['id'=>'kenga-preview-contact','category'=>'site_31||view|mail|mod_contactform_title|','module'=>'contactform','adminonly'=>0,'permissions'=>null,'dependscontext'=>0,'contextplugin'=>0];
$rows=json_decode(file_get_contents('/release/kengasolutions/navigation-missing.json'),true,512,JSON_THROW_ON_ERROR);
if($rows!==[$expected])throw new RuntimeException('Unexpected recovery payload');
$menu=$engine->getObject('dbmenu','toolbar');
$menu->transaction(function()use($menu,$expected){
    $found=$menu->selectPrepared('SELECT * FROM tbl_menu_category WHERE id=? FOR UPDATE',[$expected['id']]);
    if($found){if(count($found)!==1||array_intersect_key($found[0],$expected)!=$expected)throw new RuntimeException('Existing navigation conflict');return;}
    if(!$menu->saveLinks($expected))throw new RuntimeException('Restore failed');
    $saved=$menu->getLinkById($expected['id']);if(array_intersect_key($saved??[],$expected)!=$expected)throw new RuntimeException('Restore verification failed');
});
echo "PASS restored exact backup Contact navigation row; no other rows changed\n";
