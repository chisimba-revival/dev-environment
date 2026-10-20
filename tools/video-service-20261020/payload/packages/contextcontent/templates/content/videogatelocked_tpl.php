<?php
/** Video stage requirements use the existing chapter return flow. @author Derek Keats */
$e=static fn($s)=>htmlspecialchars((string)$s,ENT_QUOTES,'UTF-8');
echo '<section class="chisimba-form-card"><p>'.$e($this->objLanguage->code2Txt('mod_contextcontent_video_gate','contextcontent')).'</p><a href="'.$e($this->uri(['action'=>'viewchapter','id'=>$stageGateLocked['chapterid']])).'">'.$e($this->objLanguage->code2Txt('mod_contextcontent_stage_gate_return_course','contextcontent')).'</a></section>';
