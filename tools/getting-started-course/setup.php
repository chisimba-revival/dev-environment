<?php
/** One explicitly commissioned private course and test student; no emails or content publishing. */
if (PHP_SAPI !== 'cli') exit(64);
$local=($argv[1]??'')==='local-check';
if(!$local&&($argv[1]??'')!=='chisimba-com')exit(64);
chdir($local?'/var/www/html/ch':'/var/www/html');
$_SERVER['REQUEST_METHOD']='CLI';$_SERVER['HTTP_HOST']=$local?'chisimba.test:8445':'www.chisimba.com';$_SERVER['SCRIPT_NAME']=$local?'/ch/index.php':'/index.php';$_SERVER['QUERY_STRING']='';
$GLOBALS['kewl_entry_point_run']=true;require 'classes/core/engine_class_inc.php';$e=new engine();
$users=$e->getObject('userservice','security');$contexts=$e->getObject('dbcontext','context');
$owner=$users->findByUsername($local?'admin':'derek');
if(!$owner)throw new RuntimeException('Course owner missing');
$stack=$e->getObject('nativeauthwebcomposition','security')->build();
if(!$stack['sessions']->establish($owner['userid'],['username'=>$owner['username'],'provider'=>'course-setup']))throw new RuntimeException('Owner session failed');
$code=$local?'gettingstartedcheck':'gettingstarted';$username=$local?'course_student_check':'chisimba_test_student';
if($contexts->getContextDetails($code)||$users->findByUsername($username))throw new RuntimeException('Already exists; inspect before changing');
$password=bin2hex(random_bytes(16)).'!aA2';$record=null;
try {
 $users->transactionWithSavepoint(function()use($e,$users,$contexts,$code,$username,$password,$local,&$record){
  $record=$e->getObject('userprovisioningservice','security')->createLocalUser(['userId'=>$users->generateUserId(),'username'=>$username,'firstName'=>'Chisimba','surname'=>'Test Student','emailAddress'=>$username.'@example.invalid','howCreated'=>'useradmin','isActive'=>true],$password);
  if(empty($record['ok']))throw new RuntimeException('Student provisioning failed');
  if(!$contexts->createContext($code,'Getting started with Chisimba','Published','Private','<p>A simple space to try Chisimba. Practise finding your way around, writing and joining course conversations as these capabilities become available.</p>',false,1,'','','standard',null,false))throw new RuntimeException('Course creation failed');
  $model=$e->getObject('groupadminmodel','groupadmin');$groups=$e->getObject('groupservice','groupadmin');$pid=$e->getObject('identityservice','security')->permissionUserIdForUser($record['userId']);
  if(!$groups->ensureMembership($model->getLeafId([$code,'Students']),$pid))throw new RuntimeException('Student enrolment failed');
  $uc=$e->getObject('usercontext','context');
  if(!$uc->isContextMember($record['userId'],$code)||$e->getObject('user','security')->isContextLecturer($record['userId'],$code))throw new RuntimeException('Student role verification failed');
  if(!$e->getObject('user','security')->isContextLecturer($e->getObject('user','security')->userId(),$code))throw new RuntimeException('Teacher role verification failed');
  if($local)throw new RuntimeException('LOCAL_ROLLBACK');
 });
}catch(RuntimeException $x){
 if(!$local||$x->getMessage()!=='LOCAL_ROLLBACK')throw $x;
 if($contexts->getContextDetails($code)||$users->findByUsername($username))throw new RuntimeException('Local rollback failed');
 echo "PASS local provisioning, teacher/student roles and rollback\n";exit;
}
umask(0077);
$record['username']=$username;$record['password']=$password;$record['course']=$code;
file_put_contents('/tmp/chisimba-course-account.json',json_encode($record,JSON_PRETTY_PRINT));chmod('/tmp/chisimba-course-account.json',0600);
echo "Created private gettingstarted course, teacher Derek and enrolled test student. Credentials stored privately.\n";
