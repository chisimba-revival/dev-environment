<?php
if(PHP_SAPI!=='cli')exit(64);
chdir('/var/www/html');$_SERVER['REQUEST_METHOD']='CLI';$_SERVER['HTTP_HOST']='www.chisimba.com';$_SERVER['SCRIPT_NAME']='/index.php';$_SERVER['QUERY_STRING']='';$GLOBALS['kewl_entry_point_run']=true;require 'classes/core/engine_class_inc.php';$e=new engine();
$u=$e->getObject('userservice','security')->findByUsername('derek');$c=$e->getObject('dbcontext','context')->getContextDetails('gettingstarted');
if(!$u||!$c||$c['title']!=='Getting started with Chisimba'||$c['access']!=='Private')throw new RuntimeException('Unexpected course/owner');
$stack=$e->getObject('nativeauthwebcomposition','security')->build();if(!$stack['sessions']->establish($u['userid'],['username'=>$u['username'],'provider'=>'course-chat-setup']))throw new RuntimeException('Session failed');
$e->getObject('conversationservice','messaging')->create('gettingstarted');
$m=$e->getObject('dbcontextmodules','context');if(!$m->isContextPlugin('gettingstarted','messaging'))$m->addModule('gettingstarted','messaging');$m->setVisible('messaging','gettingstarted');
echo "PASS introductory course conversation ready\n";
