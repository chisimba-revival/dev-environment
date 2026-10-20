<?php
/** Course policy and combined MCQ/video stage behaviour without a database. @author Derek Keats */
$GLOBALS['kewl_entry_point_run']=true;
class ChisimbaObject {public array $objects=[];public function getObject($name,$module=''){return $this->objects[$name];}}
class controller extends ChisimbaObject {}
class dbTable extends ChisimbaObject {public array $rows=[];public function selectPrepared($sql,$params=[]){return $this->rows;}}
require dirname(__DIR__,2).'/contextcontent/classes/videoconsumer_class_inc.php';
require dirname(__DIR__,2).'/contextcontent/classes/chapterstagegateservice_class_inc.php';
function verifyVideo($ok,$message){if(!$ok)throw new RuntimeException($message);echo "PASS $message\n";}
class CourseVideoFixture extends videoconsumer {
 public bool $manager=false;public ?array $fixtureLink=['id'=>'ref','placement_id'=>'page','video_id'=>'video','contextcode'=>'course'];
 public function link(string $id):?array{return $id==='ref'?$this->fixtureLink:null;}
 public function mayManage(string $context):bool{return $this->manager;}
}
$consumer=new CourseVideoFixture();$consumer->rows=[['id'=>'page']];
$user=new class {public bool $logged=true;public function isLoggedIn(){return $this->logged;}public function userId(){return 'student';}};
$context=new class {public string $status='Published';public function getContext($id){return ['status'=>$this->status];}};
$membership=new class {public bool $member=true;public function isContextMember($u,$c){return $this->member;}};
$gates=new class {public bool $allowed=true;public function entryDecision($c,$ch){return ['allowed'=>$this->allowed];}};
$consumer->objects=['user'=>$user,'dbcontext'=>$context,'usercontext'=>$membership,'chapterstagegateservice'=>$gates,'db_contextcontent_order'=>new class {public function getPage($p,$c){return ['chapterid'=>'chapter'];}}];
verifyVideo($consumer->mayPlay('ref','video'),'enrolled member can play visible lesson');
verifyVideo(!$consumer->mayPlay('ref','other-video'),'lesson cannot authorise another video');
verifyVideo(!$consumer->mayPlay('unknown','video'),'unknown reference fails closed');
$membership->member=false;verifyVideo(!$consumer->mayPlay('ref','video'),'outsider and revoked enrolment denied');$membership->member=true;
$user->logged=false;verifyVideo(!$consumer->mayPlay('ref','video'),'anonymous playback denied');$user->logged=true;
$context->status='Draft';verifyVideo(!$consumer->mayPlay('ref','video'),'draft course denied');$context->status='Published';
$consumer->rows=[];verifyVideo(!$consumer->mayPlay('ref','video'),'hidden page or chapter denied');$consumer->rows=[['id'=>'page']];
$gates->allowed=false;verifyVideo(!$consumer->mayPlay('ref','video'),'locked stage denied');
$consumer->manager=true;verifyVideo($consumer->mayPlay('ref','video'),'course manager can preview locked lesson');
class GateVideoFixture extends chapterstagegateservice {
 public float $score=0;
 public function bestPercentage($testId,$totalMark){return $this->score;}
 public function isGatedProgression($contextCode){return true;}
 public function isCourseManager($contextCode){return false;}
}
$gateService=new GateVideoFixture();$gate=['testid'=>'quiz','totalmark'=>100,'passmark'=>60,'video'=>['required'=>true,'complete'=>false,'percent'=>0]];
$gateService->score=80;verifyVideo(!$gateService->hasPassed($gate),'MCQ success alone does not bypass required video');
$gate['video']['complete']=true;verifyVideo($gateService->hasPassed($gate),'MCQ and video together pass');
$gateService->score=40;verifyVideo(!$gateService->hasPassed($gate),'video success does not bypass MCQ');
$gate['testid']='';verifyVideo($gateService->hasPassed($gate),'video-only gate can pass without MCQ');
$gate['video']['complete']=false;verifyVideo(!$gateService->hasPassed($gate),'video-only gate stays locked while incomplete');
$videoRequirements=new class {public bool $complete=false;public function chapterRequirement($context,$chapter){return ['required'=>$chapter==='first','complete'=>$this->complete,'percent'=>$this->complete?100:0];}};
$gateService->objects['videoconsumer']=$videoRequirements;
$gateService->objContextChapters=new class {
 public function getChapter($id,$context=null){return ['chapterid'=>$id,'contextcode'=>'course','chaptertitle'=>$id,'stage_gate_enabled'=>0,'stage_gate_testid'=>''];}
 public function getContextChapters($context){return [['chapterid'=>'first','chaptertitle'=>'First'],['chapterid'=>'second','chaptertitle'=>'Second']];}
};
verifyVideo(!$gateService->entryDecision('course','second')['allowed'],'actual chapter decision blocks on video-only preceding gate');
$videoRequirements->complete=true;
verifyVideo($gateService->entryDecision('course','second')['allowed'],'actual chapter decision opens after required viewing');
verifyVideo($gateService->courseCompletionSummary('course')['complete'],'video-only stage participates in course completion summary');
