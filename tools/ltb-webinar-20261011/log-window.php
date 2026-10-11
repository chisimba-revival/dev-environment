<?php
$before=json_decode(getenv('LOG_BASELINE')?:'{}',true);$sizes=[];$findings=[];
foreach(['/var/www/html/error_log','/var/www/html/error_logs'] as $dir){
 if(!is_dir($dir))continue;
 foreach(new RecursiveIteratorIterator(new RecursiveDirectoryIterator($dir,FilesystemIterator::SKIP_DOTS)) as $f){
  if(!$f->isFile()||$f->isLink())continue;$p=$f->getPathname();$n=$f->getSize();$sizes[$p]=$n;
  if(getenv('LOG_CHECK')!=='1')continue;$offset=$before[$p]??0;if($offset>$n)$offset=0;
  if($n===$offset)continue;$text=file_get_contents($p,false,null,$offset);
  foreach(explode("\n",$text) as $line)if(preg_match('/warning|deprecated|fatal|uncaught|exception/i',$line))$findings[]=['file'=>$p,'line'=>$line];
 }
}
echo json_encode(['sizes'=>$sizes,'findings'=>$findings]);
