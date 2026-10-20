<?php
/** Shared video library. @author Derek Keats */
$e=static fn($s)=>htmlspecialchars((string)$s,ENT_QUOTES,'UTF-8');$t=fn($key)=>$this->t($key);
$url=fn($action,$extra=[])=>$this->uri(array_merge(['action'=>$action,'scope'=>$videoScope],$extra),'video-service');
$hidden=function($id='')use($e,$videoToken,$videoScope){return '<input type="hidden" name="csrf_token" value="'.$e($videoToken).'"><input type="hidden" name="scope" value="'.$e($videoScope).'"><input type="hidden" name="id" value="'.$e($id).'">';};
echo '<div class="chisimba-cluster"><h1>'.$e($t('library')).'</h1>'.$this->getObject('contextualhelp','help')->show('video-service','library',true).'</div>';
if(!$videoConfigured)echo '<p class="chisimba-notice" role="status">'.$e($t('configuration_missing')).'</p>';
echo '<form method="get" action="'.$e($this->uri([], 'video-service')).'" class="chisimba-form-actions"><input type="hidden" name="module" value="video-service"><input type="hidden" name="scope" value="'.$e($videoScope).'"><div class="chisimba-form-field"><label>'.$e($t('search')).' <input type="text" name="search" value="'.$e($this->getParam('search','')).'"></label></div><button>'.$e($t('search')).'</button></form>';
echo '<form method="post" action="'.$e($url('upload')).'" data-video-upload data-library="'.$e($url('')).'" data-authorising="'.$e($t('authorising')).'" data-uploading="'.$e($t('uploading')).'" data-processing="'.$e($t('processing')).'" data-interrupted="'.$e($t('interrupted')).'" data-error="'.$e($t('operation_failed')).'" class="chisimba-form-card">'.$hidden();
echo '<input type="hidden" name="request_id" value="'.bin2hex(random_bytes(16)).'"><h2>'.$e($t('upload')).'</h2><div class="chisimba-form-field"><label>'.$e($t('title')).'<input type="text" name="title" maxlength="255" required></label></div><div class="chisimba-form-field"><label>'.$e($t('description')).'<textarea name="description" maxlength="10000"></textarea></label></div><div class="chisimba-form-field"><label>'.$e($t('file')).'<input type="file" name="video_file" accept="video/*" required></label></div><progress hidden max="100" value="0" aria-label="'.$e($t('uploading')).'"></progress><p role="status" aria-live="polite"></p><div class="chisimba-form-actions chisimba-form-actions--equal"><button type="submit"'.(!$videoConfigured?' disabled':'').'>'.$e($t('upload')).'</button><button type="button" data-upload-pause hidden>'.$e($t('pause_upload')).'</button><button type="button" data-upload-resume hidden>'.$e($t('resume_upload')).'</button></div></form>';
$context=str_starts_with($videoScope,'contextcontent:')?substr($videoScope,15):'';
$pages=$context!==''?$this->getObject('db_contextcontent_order','contextcontent')->getContextPages($context):[];
$pageTitles=array_column($pages ?: [],'menutitle','id');
foreach($videoRows as $video){
 echo '<article class="chisimba-form-card"><h2>'.$e($video['title']).'</h2><p>'.$e($t('state_'.$video['state'])).'</p>';
 echo '<form method="post" action="'.$e($url('metadata')).'">'.$hidden($video['id']).'<input type="hidden" name="revision" value="'.$e(hash('sha256',$video['title']."\0".$video['description'])).'"><div class="chisimba-form-field"><label>'.$e($t('title')).'<input type="text" name="title" maxlength="255" required value="'.$e($video['title']).'"></label></div><div class="chisimba-form-field"><label>'.$e($t('description')).'<textarea name="description" maxlength="10000">'.$e($video['description']).'</textarea></label></div><button>'.$e($t('save')).'</button></form>';
 if($video['state']==='ready')echo $this->getObject('videoplayer','video-service')->render($video['id']);
 if($video['state']==='ready'){
  echo '<form method="post" enctype="multipart/form-data" action="'.$e($url('addcaption')).'">'.$hidden($video['id']).'<div class="chisimba-form-field"><label>'.$e($t('captions')).'<input type="file" name="caption_file" accept=".vtt,.srt" required></label></div><div class="chisimba-form-field"><label>'.$e($t('language')).'<input type="text" name="language" value="en" required></label></div><div class="chisimba-form-field"><label>'.$e($t('caption_name')).'<input type="text" name="caption_name" maxlength="100" required></label></div><button>'.$e($t('add_caption')).'</button></form>';
  $metadata=json_decode($video['metadata'] ?: '{}',true);
  foreach($metadata['tracks'] ?? [] as $track)if(($track['type'] ?? '')==='text')echo '<p>'.$e($track['name'] ?? $track['language_code'] ?? '').' — '.$e($t('track_'.($track['status'] ?? 'preparing'))).'</p>';
 }

 echo '<p><a href="'.$e($url('inspect',['id'=>$video['id']])).'">'.$e($t('refresh')).'</a></p>';
 if($context!=='' && !in_array($video['state'],['deleted','pending_delete'],true)){
  echo '<form method="post" action="'.$e($url('attach')).'">'.$hidden($video['id']).'<input type="hidden" name="context" value="'.$e($context).'"><div class="chisimba-form-field"><label>'.$e($t('lesson')).'<select name="placement" required><option value=""></option>';
  foreach($pages ?: [] as $page)echo '<option value="'.$e($page['id']).'">'.$e($page['menutitle'] ?? $page['id']).'</option>';
  echo '</select></label></div><div class="chisimba-form-field"><label>'.$e($t('required_percent')).'<input name="percent" type="number" min="0" max="100" value="0" required></label></div><p>'.$e($t('percent_help')).'</p><button>'.$e($t('attach')).'</button></form>';
 }
 $links=$context!==''?$videoService->consumer('contextcontent')->references($video['id']):[];
 foreach($links as $link){echo '<form method="post" action="'.$e($url('detach')).'">'.$hidden($video['id']).'<input type="hidden" name="reference" value="'.$e($link['id']).'"><p>'.$e($t('attached')).' '.$e($pageTitles[$link['placement_id']] ?? $t('removed_lesson')).'</p><button>'.$e($t('detach')).'</button></form>';}
 echo '<details><summary>'.$e($t('delete')).'</summary><form method="post" action="'.$e($url('delete')).'">'.$hidden($video['id']).'<p>'.$e($t('delete_help')).'</p><div class="chisimba-form-field"><label><input type="checkbox" name="confirm" value="delete" required> '.$e($t('confirm_delete')).'</label></div><button>'.$e($t('delete')).'</button></form></details></article>';
}
$offset=max(0,(int)$this->getParam('offset',0));
echo '<nav class="chisimba-form-actions">';if($offset>0)echo '<a href="'.$e($url('',['offset'=>max(0,$offset-30),'search'=>$this->getParam('search','')])).'">'.$e($t('previous')).'</a>';if(count($videoRows)===30)echo '<a href="'.$e($url('',['offset'=>$offset+30,'search'=>$this->getParam('search','')])).'">'.$e($t('next')).'</a>';echo '</nav>';
echo '<script defer src="'.$e($this->getResourceUri('vendor/upchunk.js','video-service')).'"></script><script defer src="'.$e($this->getResourceUri('library.js','video-service')).'"></script>';
