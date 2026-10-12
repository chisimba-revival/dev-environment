<?php
// CLI-only, explicitly authorised KengaLearn Kanban catalogue update.
if(PHP_SAPI!=='cli'||getenv('KANBAN_RELEASE')!=='0.146')exit(64);
chdir('/var/www/html');$GLOBALS['kewl_entry_point_run']=true;
$_SERVER['REQUEST_METHOD']='CLI';$_SERVER['HTTP_HOST']='kengalearn.com';
$_SERVER['SCRIPT_NAME']='/index.php';$_SERVER['QUERY_STRING']='';
require 'classes/core/engine_class_inc.php';
$engine=new engine();
if(!$engine->getDbObj() instanceof ChisimbaDatabaseConnection)throw new RuntimeException('PDO required');
$store=$engine->getObject('dbkanbantasks','kanban');
$fingerprint=function()use($store){$result=[];foreach(['tbl_kanban_boards','tbl_kanban_tasks','tbl_kanban_subtasks','tbl_kanban_access'] as $table)$result[$table]=hash('sha256',json_encode($store->selectExactPrepared('SELECT * FROM '.$table.' ORDER BY id')));// Catalogue-owned menu IDs regenerate; protect their complete semantics and exact editable site rows.
$result['menu_semantics']=hash('sha256',json_encode($store->selectExactPrepared('SELECT category,module,adminonly,permissions,dependscontext,contextplugin FROM tbl_menu_category ORDER BY category,module,adminonly,permissions,dependscontext,contextplugin')));
$result['site_navigation']=hash('sha256',json_encode($store->selectExactPrepared("SELECT * FROM tbl_menu_category WHERE SUBSTR(category,1,5)='site_' ORDER BY id")));
return $result;};
$before=$fingerprint();$patch=$engine->getObject('patch','modulecatalogue');
$result=$patch->applyUpdates('kanban');
if(!is_array($result)||(string)$patch->getVersion('kanban')!=='0.146')throw new RuntimeException('Kanban upgrade failed');
$language=$engine->getObject('language','language');
if(html_entity_decode($language->languageText('mod_kanban_order_saved','kanban'),ENT_QUOTES|ENT_HTML5,'UTF-8')!=='Task position saved.')throw new RuntimeException('Language registration failed');
$after=$fingerprint();if($before!==$after)throw new RuntimeException('Registration changed tables: '.implode(',',array_keys(array_diff_assoc($before,$after))));
echo "KANBAN_CATALOGUE_0.146_PASS\n";
