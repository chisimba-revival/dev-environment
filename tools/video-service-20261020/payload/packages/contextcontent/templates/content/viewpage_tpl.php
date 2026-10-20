<?php
$this->appendArrayVar('headerParams', '<style type="text/css">.ingest-table{max-width:100%;margin:1.25rem 0;overflow-x:auto}.ingest-table table{width:100%;border-collapse:collapse}.ingest-table th,.ingest-table td{min-width:8rem;padding:.7rem .8rem;border:1px solid #b0bec5;vertical-align:top;text-align:left}.ingest-table th{background:#eef2f3;font-weight:700}.ingest-table p{margin:.25rem 0}.ingest-table figure{margin:.5rem 0}.ingest-table img{display:block;max-width:100%;height:auto}</style>');
$res ="";
$prvpage = "";
$nextpage = "";
$objFile = $this->getObject('dbfile', 'filemanager');
$objHead = $this->newObject('htmlheading', 'htmlelements');

$objModule = $this->getObject('modules', 'modulecatalogue');

//Add link back to the chapter list on the middle links
$middle = '';
if(empty($pagelft)) {
    $pagelft = Null;
} else {
    $prvpage = $this->objContentOrder->getPrevPageId($this->contextCode, $currentChapter, $pagelft);
    //Check if first page in the chapter
    $prevLeftValue = $pagelft-2;
    $nextpage = $this->objContentOrder->getNextPageId($this->contextCode, $currentChapter, $prevLeftValue);
}
$link = new link ($this->uri(array("action"=>"showcontextchapters","chapterid"=>$currentChapter, 'prevpageid'=>$nextpage), $module));
$link->link = '&#171; '.$this->objLanguage->languageText('mod_contextcontent_backchapter','contextcontent');
$middle .= $link->show();

$middle .= ' <br /> ';


//A link to adding a page
$addLink = new link($this->uri(array('action' => 'addcontent', 'id' => $page['id'], 'context' => $this->contextCode, 'chapter' => $page['chapterid'])));
$addLink->link = $this->objLanguage->languageText('mod_contextcontent_addpage', 'contextcontent');

$addPageFromFileLink = new link($this->uri(array('action' => 'addpagefromfile', 'id' => $page['id'], 'context' => $this->contextCode, 'chapterid' => $page['chapterid'])));
$addPageFromFileLink->link = $this->objLanguage->languageText('mod_contextcontent_createpagefromfile', 'contextcontent', 'Create page from file');

$scormInstalled = false;
$scormLink = NULL;

//A link to editing a page
$editLink = new link($this->uri(array('action' => 'editpage', 'id' => $page['id'], 'context' => $this->contextCode)));
$editLink->link = $this->objLanguage->languageText('mod_contextcontent_editcontextpages', 'contextcontent');

if (($page['rght'] - $page['lft'] - 1) == 0) {
    $deleteLink = new link($this->uri(array('action' => 'deletepage', 'id' => $page['id'], 'context' => $this->contextCode)));
} else {
    $deleteLink = new link("javascript:alert('" . $this->objLanguage->languageText('mod_contextcontent_pagecannotbedeleteduntil', 'contextcontent') . ".');");
}
$deleteLink->link = $this->objLanguage->languageText('mod_contextcontent_delcontextpages', 'contextcontent');

$list = array();

if ($this->isValid('addpage')) {
    $list[] = $addLink->show();
    //   $list[] = $addPageFromFileLink->show();
    if ($scormInstalled) {
        $list[] = $scormLink;
    }
}

if ($this->isValid('editpage')) {
    $list[] = $editLink->show();
}

if ($this->isValid('deletepage')) {
    $list[] = $deleteLink->show();
}

if ((is_countable($list) ? count($list) : 0) == 0) {
    $middle = '&nbsp;';
} else {
    $middle .= '';
    $divider = '';

    foreach ($list as $item) {
        $middle .= $divider . $item;
        $divider = ' / ';
    }
}

if ($this->isValid('movepageup')) {
    $middle .= '<br />';
    $reorderLink = new link($this->uri(array('action' => 'viewchapter', 'id' => $currentChapter)));
    $reorderLink->link = $this->objLanguage->languageText(
        'mod_contextcontent_reorderchapterpages',
        'contextcontent',
        'Reorder chapter pages'
    );
    $reorderLink->cssClass = 'contextcontent-reorder-link';
    $middle .= $reorderLink->show();
}


$table = $this->newObject('htmltable', 'htmlelements');
//$table->border='1';
$table->startRow();
$table->cssClass = "pagenavigation";
$table->addCell($prevPage, '33%', 'top');
$table->addCell($middle, '33%', 'top', 'center');
$table->addCell($nextPage, '33%', 'top', 'right');
$table->endRow();

$table2 = $this->newObject('htmltable', 'htmlelements');
//$table->border='1';
$table2->startRow();
$table2->cssClass = "pagenavigation2";
$table2->addCell($prevPage, '33%', 'top');
$table2->addCell('&nbsp;', '33%', 'top', 'center');
$table2->addCell($nextPage, '33%', 'top', 'right');
$table2->endRow();

$topTable = $this->newObject('htmltable', 'htmlelements');
//$topTable->border='1';
$topTable->startRow();
$topTable->cssClass = "toppagenavigation";
$topTable->addCell($prevPage, '50%', 'top');
$topTable->addCell($nextPage, '50%', 'top', 'right');
$topTable->endRow();

$this->loadClass('link', 'htmlelements');

$this->setVar('pageTitle', htmlentities($this->objContext->getTitle() . ' - ' . $page['menutitle']));

$objWashout = $this->getObject('washout', 'utilities');

$content = "";
$pageintroheader = new htmlheading();
$pageintroheader->type = 1;
$pageintroheader->cssClass = "pagetitle";
$pageintroheader->str = $page['menutitle'];
$contentTypeClasses = array(
    'short_text' => ' contextcontent-short-text',
    'image_audio' => ' contextcontent-image-audio',
    'video' => ' contextcontent-video',
    'tiktok_video' => ' contextcontent-tiktok',
    'pdf' => ' contextcontent-resource',
    'zip_bundle' => ' contextcontent-resource',
    'external_reading' => ' contextcontent-resource',
    'assessment_activity' => ' contextcontent-assessment',
    'live_session' => ' contextcontent-live-session',
);
$typeClass = isset($contentTypeClasses[$page['contenttype']])
    ? $contentTypeClasses[$page['contenttype']]
    : ' contextcontent-rich-text';
$shortTextOpen = $page['contenttype'] === 'short_text' ? '<div class="contextcontent-phone-reading"><div class="contextcontent-phone-reading-speaker" aria-hidden="true"></div><div class="contextcontent-phone-reading-screen">' : '';
$shortTextClose = $page['contenttype'] === 'short_text' ? '</div><div class="contextcontent-phone-reading-gesture" aria-hidden="true"></div></div>' : '';
if ($page['contenttype'] === 'live_session') {
    $renderedPageContent = $this->getObject('liveclasscontentrenderer', 'liveclass')->render(
        $page,
        $this->contextCode,
        $this->isValid('editpage')
    );
} elseif ($page['contenttype'] === 'assessment_activity') {
    $renderedPageContent = $this->getObject('assessmentpaletteservice', 'contextcontent')->render(
        $page,
        $this->contextCode,
        $this->isValid('editpage')
    );
} elseif ($page['contenttype'] === 'zip_bundle' && preg_match('/\\[FILEPREVIEW\\s+id="([A-Za-z0-9_-]+)"\\s+comment="([^"\\r\\n]+\\.zip)"\\s*\\/\\]/i', $page['pagecontent'], $zipToken)) {
    $objFilePreview = $this->getObject('filepreview', 'filemanager');
    $zipPreview = $objFilePreview->previewFile($zipToken[1]);
    $zipDownload = '';
    if (isset($objFilePreview->file['fullurl']) && $objFilePreview->file['fullurl'] !== '') {
        $zipUrl = htmlspecialchars($objFilePreview->file['fullurl'], ENT_QUOTES, 'UTF-8');
        $zipName = isset($objFilePreview->file['filename'])
            ? htmlspecialchars($objFilePreview->file['filename'], ENT_QUOTES, 'UTF-8')
            : htmlspecialchars($zipToken[2], ENT_QUOTES, 'UTF-8');
        $zipLabel = htmlspecialchars($this->objLanguage->languageText('mod_contextcontent_download_files', 'contextcontent', 'Download files'), ENT_QUOTES, 'UTF-8');
        $zipDownload = '<p class="contextcontent-resource-action"><a class="contextcontent-resource-link contextcontent-resource-download" href="' . $zipUrl . '" download>' . $zipLabel . ' <span class="contextcontent-resource-filename">(' . $zipName . ')</span></a></p>';
    }
    $renderedZip = '<div class="contextcontent-resource-archive-preview">' . $zipPreview . '</div>' . $zipDownload;
    $renderedPageContent = str_replace($zipToken[0], $renderedZip, $page['pagecontent']);
} elseif ($page['contenttype'] === 'zip_bundle') {
    $renderedPageContent = $objWashout->parseText($page['pagecontent']);
} else {
    $renderedPageContent = in_array($page['contenttype'], array('image_audio', 'video', 'tiktok_video', 'pdf', 'external_reading'), true)
        ? $page['pagecontent']
        : $objWashout->parseText($page['pagecontent']);
}
if ($page['contenttype'] === 'pdf') {
    $pdfActionIcon = '<svg class="contextcontent-resource-type-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M6 2.5h8l4 4V21H6z"/><path d="M14 2.5v4h4"/><path d="M8.5 16.5h7M8.5 13h7M8.5 9.5h2.5"/></svg>';
    $renderedPageContent = preg_replace('/(<p class="contextcontent-resource-action"><a\b[^>]*>)/', '$1' . $pdfActionIcon, $renderedPageContent, 1);
}
$content .= '<article class="contextcontent-native-page' . $typeClass . '">' . $shortTextOpen . $pageintroheader->show() . $renderedPageContent . $shortTextClose . '</article>';

if (in_array($page['contenttype'], array('pdf', 'zip_bundle', 'external_reading'), true)) {
    $this->appendArrayVar('headerParams', '<style type="text/css">.contextcontent-resource{max-width:820px;margin:1.5rem auto}.contextcontent-resource-body{margin-top:1rem;padding:1.4rem;border:1px solid #cfd8dc;border-left:5px solid #1976d2;border-radius:10px;background:#f7fafb}.contextcontent-resource-description{font-size:1.08rem;line-height:1.6}.contextcontent-resource-source{color:#546e7a;font-weight:700}.contextcontent-resource-action a{display:inline-flex;gap:.55rem;align-items:center;padding:.7rem 1rem;border-radius:6px;background:#1565c0;color:#fff;text-decoration:none;font-weight:700}.contextcontent-resource-type-icon{width:1.25rem;height:1.25rem;fill:none;stroke:currentColor;stroke-width:1.9;stroke-linecap:round;stroke-linejoin:round}.contextcontent-resource-action a:hover,.contextcontent-resource-action a:focus{background:#0d47a1;color:#fff}.contextcontent-external-notice{font-size:.9rem;color:#546e7a}</style>');
}
if ($page['contenttype'] === 'tiktok_video') {
    $this->appendArrayVar('headerParams', '<style type="text/css">.contextcontent-tiktok{width:430px;max-width:100%;margin:1.5rem auto}.contextcontent-tiktok-body figure{margin:0 auto}.contextcontent-tiktok-embed{position:relative;width:100%;aspect-ratio:9/16;overflow:hidden;border-radius:12px;background:#101416}.contextcontent-tiktok-embed iframe{position:absolute;inset:0;width:100%;height:100%;border:0}.contextcontent-tiktok-body figcaption{padding:.65rem 0;color:#455a64}.contextcontent-tiktok-transcript{margin:1rem 0 0;padding:1rem;border:1px solid #cfd8dc;border-radius:8px}@media(max-width:560px){.contextcontent-tiktok{margin:1rem auto}.contextcontent-tiktok-embed{border-radius:8px}}</style>');
}
if ($page['contenttype'] === 'video') {
    $this->appendArrayVar('headerParams', '<style type="text/css">.contextcontent-video{max-width:1000px;margin:1rem auto}.contextcontent-video-body figure{margin:0 auto}.contextcontent-video-body video{display:block;width:100%;height:auto;max-height:78vh;margin:0 auto;border-radius:12px;background:#101416}.contextcontent-video-embed{position:relative;width:100%;padding-top:56.25%;overflow:hidden;border-radius:12px;background:#101416}.contextcontent-video-portrait .contextcontent-video-embed{padding-top:177.78%}.contextcontent-video-embed iframe{position:absolute;inset:0;width:100%;height:100%;border:0}.contextcontent-video-portrait figure{max-width:430px}.contextcontent-video-landscape figure{max-width:960px}.contextcontent-video-landscape video{aspect-ratio:16/9;height:auto;min-height:0;object-fit:contain}.contextcontent-video-body figcaption{padding:.65rem 0;color:#455a64}.contextcontent-video-transcript{margin:1rem auto 0;max-width:960px;padding:1rem;border:1px solid #cfd8dc;border-radius:8px}@media(max-width:560px){.contextcontent-video-body video{max-height:72vh;border-radius:8px}}</style>');
}
if ($page['contenttype'] === 'image_audio') {
    $this->appendArrayVar('headerParams', '<style type="text/css">.contextcontent-image-audio{max-width:900px;margin:1rem auto}.contextcontent-image-audio-body figure{margin:0}.contextcontent-image-audio-body img{display:block;width:100%;height:auto;max-height:70vh;object-fit:contain;border-radius:12px;background:#eef2f3}.contextcontent-image-audio-body figcaption{padding:.65rem 0;color:#455a64}.contextcontent-image-audio-body audio{display:block;width:100%;margin:1rem 0}.contextcontent-audio-transcript{margin-top:1rem;padding:1rem;border:1px solid #cfd8dc;border-radius:8px}</style>');
}
if ($page['contenttype'] === 'short_text') {
    $this->appendArrayVar('headerParams', '<style type="text/css">'
        . '.contextcontent-short-text{width:360px;max-width:100%;margin:1.5rem auto} '
        . '.contextcontent-phone-reading{box-sizing:border-box;padding:12px 10px 10px;border:5px solid #263238;border-radius:38px;background:#263238;box-shadow:0 14px 34px rgba(0,0,0,.22)}'
        . '.contextcontent-phone-reading-speaker{width:54px;height:5px;margin:0 auto 10px;border-radius:4px;background:#78909c}'
        . '.contextcontent-phone-reading-screen{min-height:500px;padding:1.25rem;border-radius:25px;background:#fff;font-size:1.08rem;line-height:1.62}'
        . '.contextcontent-phone-reading-gesture{width:92px;height:4px;margin:9px auto 2px;border-radius:4px;background:#b0bec5}'
        . '.contextcontent-phone-reading-screen .pagetitle{font-size:1.65rem;line-height:1.2;margin-top:0}'
        . '.contextcontent-phone-reading-screen img,.contextcontent-phone-reading-screen video{max-width:100%;height:auto}'
        . '@media(max-width:560px){.contextcontent-short-text{max-width:100%;margin:1rem 0}.contextcontent-phone-reading{border-width:2px;border-radius:20px}.contextcontent-phone-reading-screen{min-height:0;padding:1.1rem}}'
        . '</style>');
}

$bookmarkControl = '';
if ($this->objUser->isLoggedIn() && !$this->isValid('editpage')) {
    $bookmarkOnLabel = $this->objLanguage->languageText('mod_contextcontent_bookmark_page', 'contextcontent', 'Bookmark page');
    $bookmarkOffLabel = $this->objLanguage->languageText('mod_contextcontent_remove_bookmark', 'contextcontent', 'Remove bookmark');
    $bookmarkAddedMessage = $this->objLanguage->languageText('mod_contextcontent_bookmark_added', 'contextcontent', 'Page bookmarked');
    $bookmarkRemovedMessage = $this->objLanguage->languageText('mod_contextcontent_bookmark_removed', 'contextcontent', 'Bookmark removed');
    $bookmarkErrorMessage = $this->objLanguage->languageText('mod_contextcontent_bookmark_error', 'contextcontent', 'Bookmark could not be updated');
    $bookmarkLabel = $contextContentBookmarked ? $bookmarkOffLabel : $bookmarkOnLabel;
    $bookmarkType = $contextContentBookmarked ? 'off' : 'on';
    $bookmarkPressed = $contextContentBookmarked ? 'true' : 'false';
    $bookmarkIcon = '<svg class="contextcontent-bookmark-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M6 3.5h12v17l-6-4-6 4z"/></svg>';
    $bookmarkControl = '<div class="contextcontent-bookmark-control">'
        . '<button type="button" class="contextcontent-bookmark-toggle' . ($contextContentBookmarked ? ' is-bookmarked' : '') . '"'
        . ' aria-pressed="' . $bookmarkPressed . '"'
        . ' aria-label="' . htmlspecialchars($bookmarkLabel, ENT_QUOTES, 'UTF-8') . '"'
        . ' title="' . htmlspecialchars($bookmarkLabel, ENT_QUOTES, 'UTF-8') . '"'
        . ' data-bookmark-url="' . $this->uri(array('action' => 'changebookmark')) . '"'
        . ' data-page-id="' . htmlspecialchars($page['id'], ENT_QUOTES, 'UTF-8') . '"'
        . ' data-bookmark-type="' . $bookmarkType . '"'
        . ' data-csrf="' . htmlspecialchars($contextContentCsrf, ENT_QUOTES, 'UTF-8') . '"'
        . ' data-label-on="' . htmlspecialchars($bookmarkOnLabel, ENT_QUOTES, 'UTF-8') . '"'
        . ' data-label-off="' . htmlspecialchars($bookmarkOffLabel, ENT_QUOTES, 'UTF-8') . '"'
        . ' data-message-added="' . htmlspecialchars($bookmarkAddedMessage, ENT_QUOTES, 'UTF-8') . '"'
        . ' data-message-removed="' . htmlspecialchars($bookmarkRemovedMessage, ENT_QUOTES, 'UTF-8') . '"'
        . ' data-message-error="' . htmlspecialchars($bookmarkErrorMessage, ENT_QUOTES, 'UTF-8') . '">'
        . $bookmarkIcon . '<span class="contextcontent-bookmark-state-indicator" aria-hidden="true"></span>'
        . '</button><span class="contextcontent-bookmark-feedback" role="status" aria-live="polite"></span></div>';
}


// Attached managed video uses the placement ID, never a provider URL.
if ($objModule->checkIfRegistered('video-service')) {
    $videoLink = $this->getObject('videoconsumer', 'contextcontent')->placement($page['id']);
    if ($videoLink) $content .= $this->getObject('videoplayer', 'video-service')->render($videoLink['video_id'], 'contextcontent', $videoLink['id']);
    if ($videoLink) $content .= '<p><a href="'.htmlspecialchars($this->uri(['action'=>'viewpage','id'=>$page['id']]),ENT_QUOTES,'UTF-8').'">'.htmlspecialchars($this->objLanguage->languageText('mod_contextcontent_video_refresh','contextcontent'),ENT_QUOTES,'UTF-8').'</a></p>';
    if ($this->getObject('videoconsumer', 'contextcontent')->mayManage($this->contextCode)) {
        $content .= '<p><a href="'.htmlspecialchars($this->uri(['scope'=>'contextcontent:'.$this->contextCode], 'video-service'), ENT_QUOTES, 'UTF-8').'">'
            .htmlspecialchars($this->objLanguage->languageText('mod_contextcontent_video_library','contextcontent'), ENT_QUOTES, 'UTF-8').'</a></p>';
    }
}

if (!empty($isLastPageInChapter) && !empty($chapterStageGate) && empty($chapterStageGate['testid'])) {
    $content .= '<p>'.htmlspecialchars($this->objLanguage->code2Txt('mod_contextcontent_video_gate','contextcontent'),ENT_QUOTES,'UTF-8').'</p>';
}
if (!empty($isLastPageInChapter) && !empty($chapterStageGate) && !empty($chapterStageGate['testid'])) {
    $stageGatePassed = $this->objChapterStageGates->hasPassed($chapterStageGate);
    $stageGateUrl = $this->uri(array('action' => 'startstagegatequiz', 'id' => $chapterStageGate['chapterid']));
    $stageGateTitle = htmlspecialchars($chapterStageGate['testname'], ENT_QUOTES, 'UTF-8');
    $stageGatePassMark = (int) $chapterStageGate['passmark'];
    $stageGateStatus = $stageGatePassed
        ? $this->objLanguage->languageText('mod_contextcontent_stage_gate_passed', 'contextcontent')
        : ($chapterStageGateBestPercentage === NULL
            ? $this->objLanguage->languageText('mod_contextcontent_stage_gate_not_attempted', 'contextcontent')
            : $this->objLanguage->languageText('mod_contextcontent_stage_gate_not_yet_passed', 'contextcontent'));
    $stageGateBest = $chapterStageGateBestPercentage === NULL ? '' : ' ' . htmlspecialchars($this->objLanguage->languageText('mod_contextcontent_stage_gate_best_score', 'contextcontent') . ': ' . number_format($chapterStageGateBestPercentage, 1) . '%', ENT_QUOTES, 'UTF-8');
    $stageGateAction = '';
    if ($stageGatePassed && !empty($chapterStageGateNextSectionId)) {
        $nextSectionUrl = $this->uri(array('action' => 'viewsection', 'id' => $chapterStageGateNextSectionId));
        $stageGateAction = '<p><a class="contextcontent-stage-gate-action" href="' . $nextSectionUrl . '">' . htmlspecialchars($this->objLanguage->code2Txt('mod_contextcontent_continuenextsection', 'contextcontent', NULL, 'Continue to next [-section-]'), ENT_QUOTES, 'UTF-8') . '</a></p>';
    } elseif ($stageGatePassed && !empty($chapterStageGateNextChapterId)) {
        $nextChapterUrl = $this->uri(array('action' => 'viewchapter', 'id' => $chapterStageGateNextChapterId));
        $stageGateAction = '<p><a class="contextcontent-stage-gate-action" href="' . $nextChapterUrl . '">' . htmlspecialchars($this->objLanguage->languageText('mod_contextcontent_stage_gate_next_chapter', 'contextcontent'), ENT_QUOTES, 'UTF-8') . '</a></p>';
    } elseif ($stageGatePassed) {
        $stageGateAction = '<p class="contextcontent-stage-gate-complete">' . htmlspecialchars($this->objLanguage->code2Txt('mod_contextcontent_stage_gate_course_complete', 'contextcontent', NULL, '[-context-] content has been completed.'), ENT_QUOTES, 'UTF-8') . '</p>';
    } elseif (empty($chapterStageGate['entryavailable'])) {
        $stageGateAction = '<p class="contextcontent-stage-gate-unavailable">' . htmlspecialchars($this->objLanguage->languageText('mod_contextcontent_stage_gate_unavailable', 'contextcontent', 'This assessment is not currently open for entry.'), ENT_QUOTES, 'UTF-8') . '</p>';
    } else {
        $stageGateActionLabel = !empty($chapterStageGate['inprogress'])
            ? $this->objLanguage->languageText('mod_contextcontent_stage_gate_continue_quiz', 'contextcontent', 'Continue assessment')
            : $this->objLanguage->languageText('mod_contextcontent_stage_gate_open_quiz', 'contextcontent');
        $stageGateAction = '<p><a class="contextcontent-stage-gate-action" href="' . $stageGateUrl . '">' . htmlspecialchars($stageGateActionLabel, ENT_QUOTES, 'UTF-8') . '</a></p>';
    }
    $content .= '<section class="contextcontent-stage-gate ' . ($stageGatePassed ? 'contextcontent-stage-gate-passed' : 'contextcontent-stage-gate-pending') . '" aria-labelledby="contextcontent-stage-gate-title">'
        . '<h2 id="contextcontent-stage-gate-title">' . htmlspecialchars($this->objLanguage->languageText('mod_contextcontent_stage_gate_heading', 'contextcontent'), ENT_QUOTES, 'UTF-8') . '</h2>'
        . '<p><strong>' . $stageGateTitle . '</strong></p>'
        . '<p>' . htmlspecialchars($this->objLanguage->languageText('mod_contextcontent_stage_gate_requirement', 'contextcontent') . ': ' . $stageGatePassMark . '%', ENT_QUOTES, 'UTF-8') . $stageGateBest . '</p>'
        . '<p class="contextcontent-stage-gate-status">' . htmlspecialchars($stageGateStatus, ENT_QUOTES, 'UTF-8') . '</p>' . $stageGateAction . '</section>';
    $this->appendArrayVar('headerParams', '<style type="text/css">.contextcontent-stage-gate{margin:2rem 0 1rem;padding:1.25rem 1.4rem;border:1px solid #e0b45b;border-left:6px solid #b7791f;border-radius:10px;background:#fffaf0}.contextcontent-stage-gate-passed{border-color:#76b88a;border-left-color:#2f855a;background:#f0fff4}.contextcontent-stage-gate h2{margin:.05rem 0 .75rem;font-size:1.25rem}.contextcontent-stage-gate-status{font-weight:700}.contextcontent-stage-gate-action{display:inline-block;padding:.7rem 1rem;border-radius:6px;background:#1565c0;color:#fff!important;text-decoration:none;font-weight:700}.contextcontent-stage-gate-action:hover,.contextcontent-stage-gate-action:focus{background:#0d47a1}</style>');
}

$pageNotes = $objModule->checkIfRegistered("pagenotes");
if ($pageNotes) {
    $objContextModules =  $this->getObject('dbcontextmodules', 'context');
    $objContext = $this->getObject('dbcontext', 'context');
    if($objContextModules->isContextPlugin($objContext->getContextCode(), 'pagenotes')) {
        $objBlock = $this->getObject ( 'blocks', 'blocks' );
        $pageNotesInput= $objBlock->showBlock('widepagenotecontrol', 'pagenotes', NULL, 100, TRUE);
        $pageNotesRendered = $objBlock->showBlock('pagenoteswidebl', 'pagenotes', NULL, 100, TRUE);
        $content .= '<div class=\'pagenotes\'>' . $pageNotesInput . $pageNotesRendered . '</div>';
    }
}

$form = "";
if ((is_countable($chapters) ? count($chapters) : 0) > 1 && $this->isValid('movetochapter')) {
    $this->loadClass('form', 'htmlelements');
    $this->loadClass('dropdown', 'htmlelements');
    $this->loadClass('hiddeninput', 'htmlelements');
    $this->loadClass('button', 'htmlelements');
    $this->loadClass('label', 'htmlelements');
    $form = new form('movetochapter', $this->uri(array('action' => 'movetochapter')));
    $form->addToForm((new hiddeninput('csrf_token', $contextContentCsrf))->show());
    $hiddenInput = new hiddeninput('id', $page['id']);
    $dropdown = new dropdown('chapter');
    foreach ($chapters as $chapterItem) { $dropdown->addOption($chapterItem['chapterid'], $chapterItem['chaptertitle']); }
    $dropdown->setSelected($page['chapterid']);
    $label = new label($this->objLanguage->languageText('mod_contextcontent_movepagetoanotherchapter', 'contextcontent') . ': ', 'input_chapter');
    $button = new button('movepage', $this->objLanguage->languageText('mod_contextcontent_move', 'contextcontent'));
    $button->setToSubmit();
    $form->addToForm($hiddenInput->show() . $label->show() . $dropdown->show() . ' ' . $button->show());
    $form = $form->show();
}

$res .= '<div id="tablenav">'.$topTable->show() . $content
    . '<div class="contextcontent-bottom-tools">' . $bookmarkControl . '</div>'
    . '<hr />' . $table->show() . $form.'</div>';

$this->appendArrayVar('headerParams', '<style type="text/css">'
    . '.contextcontent-bottom-tools{display:flex;justify-content:center;align-items:center;margin:0}'
    . '.contextcontent-bookmark-control{display:flex;align-items:center;gap:.55rem;min-height:2.4rem}'
    . '.contextcontent-bookmark-toggle{position:relative;display:inline-flex;align-items:center;justify-content:center;width:1.9rem;height:1.9rem;padding:0;border:1px solid #c4cdd2;border-radius:999px;background:#fff;color:#607d8b;cursor:pointer}'
    . '.contextcontent-bookmark-toggle:hover,.contextcontent-bookmark-toggle:focus{border-color:#295351;color:#295351;outline:2px solid transparent}'
    . '.contextcontent-bookmark-toggle.is-bookmarked{background:#eef7f3;border-color:#295351;color:#295351}'
    . '.contextcontent-bookmark-icon{width:1.25rem;height:1.25rem;fill:none;stroke:currentColor;stroke-width:1.9;stroke-linecap:round;stroke-linejoin:round}'
    . '.contextcontent-bookmark-toggle.is-bookmarked .contextcontent-bookmark-icon{fill:currentColor}'
    . '.contextcontent-bookmark-state-indicator{display:none;position:absolute;right:-2px;bottom:-2px;width:.55rem;height:.55rem;border-radius:50%;background:#295351;border:2px solid #fff}'
    . '.contextcontent-bookmark-toggle.is-bookmarked .contextcontent-bookmark-state-indicator{display:block}'
    . '.contextcontent-page-nav-with-bookmark{position:relative;min-height:2.7rem}.contextcontent-page-nav-with-bookmark>.contextcontent-bottom-tools{position:absolute;left:50%;top:50%;transform:translate(-50%,-50%);z-index:3}.contextcontent-page-nav-with-bookmark .contextcontent-bookmark-feedback{position:absolute;left:50%;top:100%;transform:translateX(-50%);white-space:nowrap;margin-top:.12rem;padding:0 .25rem;background:#fff}.contextcontent-bookmark-feedback{font-size:.88rem;color:#546e7a;min-width:0}'
    . '</style>');

if ($bookmarkControl !== '') {
    $this->appendArrayVar('headerParams', '<script type="text/javascript">'
        . 'document.addEventListener("DOMContentLoaded",function(){var tools=document.querySelector("#tablenav .contextcontent-bottom-tools");if(!tools){return;}var hr=tools.nextElementSibling;while(hr&&hr.tagName!=="HR"){hr=hr.nextElementSibling;}var nav=hr?hr.nextElementSibling:null;if(!nav){return;}var wrap=document.createElement("div");wrap.className="contextcontent-page-nav-with-bookmark";nav.parentNode.insertBefore(wrap,nav);wrap.appendChild(nav);wrap.appendChild(tools);});'
        . 'document.addEventListener("click",function(e){var b=e.target.closest(".contextcontent-bookmark-toggle");if(!b){return;}e.preventDefault();if(b.disabled){return;}b.disabled=true;var body=new URLSearchParams();body.set("csrf_token",b.dataset.csrf);body.set("id",b.dataset.pageId);body.set("type",b.dataset.bookmarkType);body.set("ajax","1");var feedback=b.parentNode.querySelector(".contextcontent-bookmark-feedback");fetch(b.dataset.bookmarkUrl,{method:"POST",headers:{"Content-Type":"application/x-www-form-urlencoded; charset=UTF-8","X-Requested-With":"XMLHttpRequest","Accept":"application/json"},body:body.toString(),credentials:"same-origin"}).then(function(r){if(!r.ok){throw new Error("request");}return r.json();}).then(function(data){if(!data||data.ok!==true){throw new Error("state");}var on=data.bookmarked===true;b.classList.toggle("is-bookmarked",on);b.setAttribute("aria-pressed",on?"true":"false");b.dataset.bookmarkType=on?"off":"on";var label=on?b.dataset.labelOff:b.dataset.labelOn;b.setAttribute("aria-label",label);b.setAttribute("title",label);feedback.textContent=on?b.dataset.messageAdded:b.dataset.messageRemoved;window.setTimeout(function(){if(feedback){feedback.textContent="";}},2200);}).catch(function(){feedback.textContent=b.dataset.messageError;}).finally(function(){b.disabled=false;});});'
        . '</script>');
}

$showcomment = $this->objContext->getField('showcomment', $contextCode = NULL);
if ($showcomment == 1) {
    $head = $this->objLanguage->languageText('mod_contextcontent_word_comment', 'contextcontent');
    $objHead->type = 1;
    $objHead->str = $head;
    $res .=  '<br/>' . $objHead->show() . '<br/>';
    $commentpost = $this->objContextComments->getPageComments($currentPage);
    if ((is_countable($commentpost) ? count($commentpost) : 0) < 1) {
        $res .=  $this->objLanguage->languageText('mod_contextcontent_nocomment', 'contextcontent') . '<br/>';
    } else {
        $cnt = 0;
        $oddcolor = $this->objSysConfig->getValue('CONTEXTCONTENT_ODD', 'contextcontent');
        $evencolor = $this->objSysConfig->getValue('CONTEXTCONTENT_EVEN', 'contextcontent');
        foreach ($commentpost as $comment) {
            $objOutput = '<strong>' . $this->objUser->fullname($comment['userid']) . '</strong><br/>';
            $objOutput .= '<i>' . $comment['datecreated'] . '</i><br/>';
            $objOutput .= $comment['comment'];
            if ($cnt % 2 == 0) { $res .=  '<div class="colorbox ' . $evencolor . 'box">' . $objOutput . '</div>'; }
            else { $res .=  '<div class="colorbox ' . $oddcolor . 'box">' . $objOutput . '</div>'; }
            $cnt++;
        }
    }
    $this->loadClass('textarea', 'htmlelements');
    $cform = new form('contextcontent', $this->uri(array('action' => 'addcomment', 'pageid' => $currentPage)));
    $cform->addToForm((new hiddeninput('csrf_token', $contextContentCsrf))->show());
    $cfieldset = $this->getObject('fieldset', 'htmlelements');
    $ct = $this->newObject('htmltable', 'htmlelements');
    $ct->cellpadding = 5;
    $ct->startRow();
    $ctvlabel = new label($this->objLanguage->languageText('mod_contextcontent_writecomment', 'contextcontent') . ':', 'input_cvalue');
    $ct->addCell($ctvlabel->show());
    $ct->endRow();
    $ct->startRow();
    $ctv = new textarea('comment', '', 8, 70);
    $ct->addCell($ctv->show());
    $ct->endRow();
    $this->objconvButton = new button($this->objLanguage->languageText('mod_contextcontent_submitcomment', 'contextcontent'));
    $this->objconvButton->setValue($this->objLanguage->languageText('mod_contextcontent_submitcomment', 'contextcontent'));
    $this->objconvButton->setToSubmit();
    $cfieldset->addContent($ct->show());
    $cform->addToForm($cfieldset->show());
    $cform->addToForm($this->objconvButton->show());
    $res .=  '<br/>' . $cform->show();
}

echo '<div id="context_content">' . $res . "</div>";
?>
