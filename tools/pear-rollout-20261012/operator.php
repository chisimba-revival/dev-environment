<?php
if (PHP_SAPI !== 'cli' || getenv('PEAR_RELEASE') !== '20261012') exit(64);
ob_start();
[$script,$mode,$host,$root] = $argv;
if (!in_array($host,['chisimba.com','kengalearn.com','learnthebirds.com','kengapub.com','kengasolutions.com','heritagetreazures.com'],true)) exit(64);
if(!in_array($root,['/var/www/html','/var/www/html/ch'],true))exit(64);
chdir($root);
$rehearsal = str_contains(file_get_contents('config/dbdetails_inc.php'),'@release-db/chisimba_rehearsal');
if (getenv('REHEARSAL')==='1' && !$rehearsal) throw new RuntimeException('Clone required');
if ($rehearsal || in_array($mode,['upgrade','verify'],true)) { error_reporting(E_ALL); set_error_handler(static function($severity,$message,$file,$line){fwrite(STDERR,"STRICT ".$message." at ".$file.":".$line."\n");throw new ErrorException($message,0,$severity,$file,$line);}); }
$GLOBALS['kewl_entry_point_run']=true;
$_SERVER['REQUEST_METHOD']='CLI';$_SERVER['HTTP_HOST']=$host;$_SERVER['SCRIPT_NAME']='/index.php';$_SERVER['QUERY_STRING']='';
require 'classes/core/engine_class_inc.php';$engine=new engine();
if (!in_array(parse_url($engine->getObject('altconfig','config')->getSiteRoot(),PHP_URL_HOST),[$host,'www.'.$host],true)) throw new RuntimeException('Wrong site');
$settings=$engine->getObject('dbsysconfig','sysconfig');
$state=(string)$settings->getValue('MAINTENANCE_ENABLED','systemmanagement','');
if ($mode==='state') {echo 'STATE '.($state===''?'unset':$state)."\n";echo 'MAINTENANCE_MODULE '.($engine->getObject('modules','modulecatalogue')->checkIfRegistered('systemmanagement')?'1':'0')."\n";exit;}
if (in_array($mode,['offline','online'],true)) {
 $result=$settings->changeParam('MAINTENANCE_ENABLED','systemmanagement',$mode==='offline'?'1':'0');
 if($result===false || PEAR::isError($result))throw new RuntimeException('Maintenance write failed');
 echo 'PASS '.$mode."\n";exit;
}
$backend=$engine->getDbObj() instanceof ChisimbaDatabaseConnection?'PDO':'MDB2';
$files=$engine->getObject('modulefile','modulecatalogue');$catalogue=$engine->getObject('modules','modulecatalogue');$patch=$engine->getObject('patch','modulecatalogue');
if ($mode==='upgrade') {
 if(!$rehearsal && $state!=='1' && !(getenv('PEAR_SWITCH_STOPPED')==='1'))throw new RuntimeException('Maintenance or stopped web container required');
 $admin=$engine->getObject('modulesadmin','modulecatalogue');$affected=[];
 foreach(json_decode(file_get_contents('/release/manifest.json'),true,512,JSON_THROW_ON_ERROR) as $row){$p=explode('/',$row['path']);if(in_array($p[0],['core_modules','packages'],true)&&$row['after']!==null)$affected[$p[1]]=true;}
 $done=[];
 $upgrade=function($id)use(&$upgrade,&$done,$affected,$files,$catalogue,$patch,$engine,$admin){
  if(isset($done[$id])){if(!$done[$id])throw new RuntimeException('Dependency cycle '.$id);return;}
  if(!isset($affected[$id]))throw new RuntimeException('Dependency outside candidate '.$id);
  $done[$id]=false;
  $data=$files->readRegisterFile($files->findRegisterFile($id));
  if((string)$patch->getVersion($id)===(string)$data['MODULE_VERSION']){$done[$id]=true;return;}
  foreach($data['DEPENDS']??[] as $dep)if(!$catalogue->checkIfRegistered($dep))$upgrade($dep);
  $hook=$engine->getPatchObject($id);
  if($hook&&method_exists($hook,'preinstall'))$hook->preinstall($data['MODULE_VERSION']);
  if($catalogue->checkIfRegistered($id)){$result=$patch->applyUpdates($id);if(!is_array($result)||!isset($result['current']))throw new RuntimeException('Update failed '.$id);}elseif(!$admin->installModule($data,false))throw new RuntimeException('Dependency install failed '.$id);
  if($hook&&method_exists($hook,'postinstall'))$hook->postinstall($data['MODULE_VERSION']);
  if((string)$patch->getVersion($id)!==(string)$data['MODULE_VERSION'])throw new RuntimeException('Version mismatch '.$id);
  $expected=[];
  foreach(['BLOCK'=>'normal','WIDEBLOCK'=>'wide'] as $kind=>$width)foreach($data[$kind]??[] as $block){
   $parts=explode('|',$block);$audience=[];
   foreach(explode(',',strtolower($parts[2]??'general')) as $value){$value=trim($value);if(in_array($value,['general','readonly','author','admin','root'],true)&&!in_array($value,$audience,true))$audience[]=$value;}
   $expected[]=[$parts[0],$width,$parts[1]??'site',$audience?implode(',',$audience):'general'];
  }
  $actual=array_map('array_values',$catalogue->selectExactPrepared('SELECT blockname,blockwidth,blocktype,blockaudience FROM tbl_module_blocks WHERE moduleid=?',[$id]));
  sort($actual);sort($expected);if($actual!==$expected)throw new RuntimeException('Block registration mismatch '.$id);
  $done[$id]=true;echo 'UPDATED '.$id.' '.$data['MODULE_VERSION']."\n";
 };
 foreach(array_keys($affected) as $id)if($catalogue->checkIfRegistered($id)&&$files->findRegisterFile($id))$upgrade($id);
 echo "PASS upgrade\n";exit;
}
if($mode!=='verify')exit(64);
foreach(['blogimporter'] as $unmigrated)if($catalogue->checkIfRegistered($unmigrated))throw new RuntimeException('Registered legacy driver caller '.$unmigrated);
if(get_class($engine->eventDispatcher)!=='ChisimbaEventDispatcher')throw new RuntimeException('Native events missing');
$language=$engine->getObject('language','language');
if(!is_string($language->languageText('word_home','system','Home')) || get_class($language->lang)!=='ChisimbaTranslation' || class_exists('Translation2',false))throw new RuntimeException('Native language failed');
if(count($engine->getObject('languagecode','language')->countryListArr())<200)throw new RuntimeException('Locale resources missing');
if(class_exists('Config',false))throw new RuntimeException('PEAR Config loaded');
if(count($engine->getObject('catalogueconfig','modulecatalogue')->getModulelist('all'))<1)throw new RuntimeException('Empty catalogue');
$stack=$engine->getObject('nativeauthwebcomposition','security')->build();
if(!$stack['factors'] instanceof DbTableMfaRepository || $stack['factors']->findActiveTotpForUser('pdo-release-absent-'.bin2hex(random_bytes(16)))!==null)throw new RuntimeException('MFA boundary failed');
$engine->getObject('abuseprotectionprovider','abuseprotection');
foreach(json_decode(file_get_contents('/release/retired.json'),true) as $path)if(file_exists($path))throw new RuntimeException('Retired dependency remains '.$path);
echo 'PASS verify '.$backend.' '.PHP_VERSION.' native configuration/translation/authentication/MFA/catalogue'."\n";
