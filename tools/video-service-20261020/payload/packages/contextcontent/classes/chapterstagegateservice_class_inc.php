<?php
/**
 * Contextcontent-owned chapter-end assessment placement and progression service.
 * MCQ Tests remains the owner of test delivery, attempts and marking.
 */
if (!$GLOBALS['kewl_entry_point_run']) {
    die('You cannot view this page directly');
}

class chapterstagegateservice extends controller
{
    /** Dependencies and state initialised by this component. */
    public $objContextChapters;
    public $objResults;
    public $objTests;

    public function init()
    {
        $this->objContext = $this->getObject('dbcontext', 'context');
        $this->objContextChapters = $this->getObject('db_contextcontent_contextchapter', 'contextcontent');
        $this->objResults = $this->getObject('dbresults', 'mcqtests');
        $this->objTests = $this->getObject('dbtestadmin', 'mcqtests');
        $this->objUser = $this->getObject('user', 'security');
    }

    public function isGatedProgression($contextCode)
    {
        return strtolower((string) $this->objContext->getField('navigation_mode', $contextCode)) === 'gated';
    }

    public function isCourseManager($contextCode)
    {
        return $this->objUser->isAdmin()
            || $this->objUser->isContextLecturer($this->objUser->userId(), $contextCode);
    }

    public function chapterGate($contextCode, $chapterId)
    {
        $chapter = $this->objContextChapters->getChapter($chapterId, $contextCode);
        $video = $this->getObject('videoconsumer', 'contextcontent')->chapterRequirement($contextCode, $chapterId);
        if ($chapter === FALSE || $chapter['contextcode'] !== $contextCode
            || empty($chapter['stage_gate_enabled']) || empty($chapter['stage_gate_testid'])) {
            if ($chapter && $chapter['contextcode'] === $contextCode && $video['required']) {
                return ['chapterid'=>$chapterId, 'chaptertitle'=>$chapter['chaptertitle'], 'contextcode'=>$contextCode,
                    'testid'=>'', 'testname'=>'', 'testtype'=>'', 'teststatus'=>'', 'inprogress'=>false, 'totalmark'=>0, 'passmark'=>100, 'entryavailable'=>false, 'video'=>$video];
            }
            return FALSE;
        }
        $test = $this->testInContext($contextCode, $chapter['stage_gate_testid']);
        if ($test === FALSE) {
            // A missing configured assessment must not silently bypass required viewing.
            return ['chapterid'=>$chapterId, 'chaptertitle'=>$chapter['chaptertitle'], 'contextcode'=>$contextCode,
                'testid'=>$chapter['stage_gate_testid'], 'testname'=>$chapter['chaptertitle'], 'testtype'=>'',
                'teststatus'=>'unavailable', 'inprogress'=>false, 'totalmark'=>0, 'passmark'=>100,
                'entryavailable'=>false, 'video'=>$video];
        }
        $inProgressAttempt = $this->incompleteAttempt($test['id']);
        $inProgress = $inProgressAttempt !== FALSE;
        $isOpen = isset($test['status']) && $test['status'] === 'open';

        return array(
            'chapterid' => $chapter['chapterid'],
            'contextcode' => $contextCode,
            'video' => $video,
            'chaptertitle' => $chapter['chaptertitle'],
            'testid' => $test['id'],
            'testname' => $test['name'],
            'passmark' => max(1, min(100, (int) $chapter['stage_gate_passmark'])),
            'totalmark' => (float) $test['totalmark'],
            'testtype' => isset($test['testtype']) ? $test['testtype'] : '',
            'teststatus' => isset($test['status']) ? $test['status'] : 'inactive',
            'inprogress' => $inProgress,
            'inprogressresultid' => $inProgress ? $inProgressAttempt['id'] : NULL,
            'entryavailable' => $isOpen || $inProgress
        );
    }

    public function entryDecision($contextCode, $targetChapterId)
    {
        if (!$this->isGatedProgression($contextCode) || $this->isCourseManager($contextCode)) {
            return array('allowed' => TRUE);
        }
        $chapters = $this->objContextChapters->getContextChapters($contextCode);
        if (!is_array($chapters)) {
            return array('allowed' => TRUE);
        }
        foreach ($chapters as $chapter) {
            if ($chapter['chapterid'] === $targetChapterId) {
                break;
            }
            $gate = $this->chapterGate($contextCode, $chapter['chapterid']);
            if ($gate !== FALSE && !$this->hasPassed($gate)) {
                $gate['returnchapterid'] = $targetChapterId;
                return array('allowed' => FALSE, 'gate' => $gate);
            }
        }
        return array('allowed' => TRUE);
    }

    public function hasPassed($gate)
    {
        return (empty($gate['testid']) || $this->bestPercentage($gate['testid'], $gate['totalmark']) >= $gate['passmark'])
            && (!isset($gate['video']) || $gate['video']['complete']);
    }

    public function bestPercentage($testId, $totalMark)
    {
        if ($totalMark <= 0 || !$this->objUser->isLoggedIn()) {
            return NULL;
        }
        $attempts = $this->objResults->getResult($this->objUser->userId(), $testId);
        if (!is_array($attempts)) {
            return NULL;
        }
        $best = NULL;
        foreach ($attempts as $attempt) {
            if ($attempt['endtime'] === NULL || $attempt['endtime'] === '' || (float) $attempt['mark'] < 0) {
                continue;
            }
            $percentage = ((float) $attempt['mark'] / $totalMark) * 100;
            $best = $best === NULL ? $percentage : max($best, $percentage);
        }
        return $best;
    }

    /**
     * Summarise chapter stage-gate progress for the current learner.  This is
     * deliberately limited to Contextcontent-owned chapter progression; formal
     * assessment completion belongs to the Gradebook assessment plan.
     */
    public function courseCompletionSummary($contextCode)
    {
        if (!$this->isGatedProgression($contextCode)) {
            return array('complete' => FALSE, 'chapters' => array());
        }
        $chapters = $this->objContextChapters->getContextChapters($contextCode);
        if (!is_array($chapters) || empty($chapters)) {
            return array('complete' => FALSE, 'chapters' => array());
        }
        $summary = array();
        $complete = TRUE;
        $hasGate = FALSE;
        foreach ($chapters as $chapter) {
            $gate = $this->chapterGate($contextCode, $chapter['chapterid']);
            if ($gate === FALSE) {
                $summary[] = array(
                    'chaptertitle' => $chapter['chaptertitle'],
                    'gate' => FALSE,
                    'bestpercentage' => NULL
                );
                continue;
            }
            $hasGate = TRUE;
            $best = empty($gate['testid']) ? $gate['video']['percent'] : $this->bestPercentage($gate['testid'], $gate['totalmark']);
            if (!$this->hasPassed($gate)) {
                $complete = FALSE;
            }
            $summary[] = array(
                'chaptertitle' => $chapter['chaptertitle'],
                'gate' => TRUE,
                'bestpercentage' => $best === NULL ? 0 : $best
            );
        }
        return array('complete' => $complete && $hasGate, 'chapters' => $summary);
    }

    /** Return the chapter immediately following the supplied chapter, if any. */
    public function nextChapterId($contextCode, $chapterId)
    {
        $chapters = $this->objContextChapters->getContextChapters($contextCode);
        if (!is_array($chapters)) {
            return NULL;
        }
        $currentFound = FALSE;
        foreach ($chapters as $chapter) {
            if ($currentFound) {
                return $chapter['chapterid'];
            }
            if ($chapter['chapterid'] === $chapterId) {
                $currentFound = TRUE;
            }
        }
        return NULL;
    }

    private function incompleteAttempt($testId)
    {
        if (!$this->objUser->isLoggedIn()) {
            return FALSE;
        }
        $latest = $this->objResults->getLatestAttempt($this->objUser->userId(), $testId);
        if ($latest === FALSE || (int) $latest['mark'] !== -1) {
            return FALSE;
        }
        return $latest;
    }

    private function testInContext($contextCode, $testId)
    {
        $tests = $this->objTests->getTests($contextCode, 'id,name,totalmark,context,testtype,status', $testId);
        if (!is_array($tests) || empty($tests[0]) || $tests[0]['context'] !== $contextCode) {
            return FALSE;
        }
        return $tests[0];
    }
}
?>