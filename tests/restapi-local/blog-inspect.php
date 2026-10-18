<?php
if (PHP_SAPI !== 'cli') exit(64);
chdir('/var/www/html/ch');
$_SERVER['REQUEST_METHOD']='CLI'; $_SERVER['HTTP_HOST']='chisimba.test:8445'; $_SERVER['SCRIPT_NAME']='/ch/index.php'; $_SERVER['QUERY_STRING']='';
$GLOBALS['kewl_entry_point_run']=true; require 'classes/core/engine_class_inc.php'; $e=new engine();
$f=json_decode(file_get_contents('/tmp/restapi-local-fixture.json'),true,512,JSON_THROW_ON_ERROR);
$rows=$e->getObject('publishingstore','simpleblog')->selectPrepared('SELECT * FROM tbl_simpleblog_posts WHERE userid=?',[$f['userId']]);
if (count($rows)!==2) throw new RuntimeException('Rejected requests wrote unexpected rows');
foreach ($rows as $row) {
 if ($row['post_type']!=='personal' || $row['blogid']!==$f['userId'] || strpos($row['post_content'],'<img')!==false || strpos($row['post_content'],'&lt;img')===false || !empty($row['featured_image'])) throw new RuntimeException('Text ownership/storage mismatch');
}
echo "PASS stored ownership, text escaping, no media and no invalid-request writes.\n";
