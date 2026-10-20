<?php

/**
 * Context Content controller
 *
 * Controller class for the Context Content Module in Chisimba
 *
 * PHP version 5
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the
 * Free Software Foundation, Inc.,
 * 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
 *
 * @category  Chisimba
 * @package   contextcontent
 * @author    Tohir Solomons <tsolomons@uwc.ac.za>
 * @copyright 2008 Tohir Solomons
 * @license   http://www.gnu.org/licenses/gpl-2.0.txt The GNU General Public License
 * @version   $Id$
 * @link      http://avoir.uwc.ac.za
 */
// security check - must be included in all scripts
if (!
        /**
         * Description for $GLOBALS
         * @global entry point $GLOBALS['kewl_entry_point_run']
         * @name   $kewl_entry_point_run
         */
        $GLOBALS['kewl_entry_point_run']) {
    die("You cannot view this page directly");
}
// end security check

/**
 * Context Content controller
 *
 * Controller class for the Context Content Module in Chisimba
 *
 * @category  Chisimba
 * @package   contextcontent
 * @author    Tohir Solomons <tsolomons@uwc.ac.za>
 * @extension scorm functionality by Paul Mungai <pwando@uonbi.ac.ke>
 * @copyright 2008 Tohir Solomons
 * @license   http://www.gnu.org/licenses/gpl-2.0.txt The GNU General Public License
 * @version   Release: @package_version@
 * @link      http://avoir.uwc.ac.za
 */
class contextcontent extends controller {
    /** Dependencies and state initialised by this component. */
    public $csrf;
    public $eventsEnabled;
    public $moduleUri;
    public $objAlertUtils;
    public $objAltConfig;
    public $objAssessmentPalette;
    public $objAuthoring;
    public $objBookmarks;
    public $objChapterStageGates;
    public $objChapters;
    public $objContentInvolvement;
    public $objContentOrder;
    public $objContentPages;
    public $objContentTitles;
    public $objContentTypes;
    public $objContextActivityStreamer;
    public $objContextChapters;
    public $objContextComments;
    public $objContextGroups;
    public $objFilePreview;
    public $objFiles;
    public $objFolders;
    public $objIngest;
    public $objIngestStaging;
    public $objLanguage;
    public $objMcqTests;
    public $objMenuTools;
    public $objModuleCatalogue;
    public $objSectionProgression;
    public $objSections;
    public $objSysConfig;
    public $objTikTokVideo;
    public $siteRoot;
    public $userId;


    const CSRF_CONTEXT = 'contextcontent_authoring';

    /**
     * @var string $contextCode Context Code of Current Context
     */
    protected $contextCode;

    /**
     * Constructor
     */
    public function init() {
        try {
            // Load Chapter Classes
            $this->objChapters = $this->getObject('db_contextcontent_chapters');
            $this->objContextChapters = $this->getObject('db_contextcontent_contextchapter');
            $this->objContentOrder = $this->getObject('db_contextcontent_order');
            $this->objMcqTests = $this->getObject('dbtestadmin', 'mcqtests');
            $this->objChapterStageGates = $this->getObject('chapterstagegateservice', 'contextcontent');
            $this->objSections = $this->getObject('db_contextcontent_sections', 'contextcontent');
            $this->objSectionProgression = $this->getObject('sectionprogressionservice', 'contextcontent');
            // $this->objContentTitles = $this->getObject('db_contextcontent_titles');
            $this->objFiles = $this->getObject('dbfile', 'filemanager');
            $this->objFolders = $this->getObject('dbfolder', 'filemanager');

            // Load Content Classes
            $this->objContentPages = $this->getObject('db_contextcontent_pages');
            $this->objContentTitles = $this->getObject('db_contextcontent_titles');
            $this->objContentInvolvement = $this->getObject('db_contextcontent_involvement');
            $this->objContextActivityStreamer = $this->getObject('db_contextcontent_activitystreamer');
            //Load Module Catalogue Class
            $this->objModuleCatalogue = $this->getObject('modules', 'modulecatalogue');

            // Load Context Object
            $this->objContext = $this->getObject('dbcontext', 'context');
            $this->objAuthoring = $this->getObject('contentauthoringservice', 'contextcontent');
            $this->objContentTypes = $this->getObject('contenttyperegistry', 'contextcontent');
            $this->objAssessmentPalette = $this->getObject('assessmentpaletteservice', 'contextcontent');
            $this->objTikTokVideo = $this->getObject('tiktokvideoservice', 'contextcontent');
            $this->objBookmarks = $this->getObject('db_contextcontent_bookmarks', 'contextcontent');
            $this->objIngest = $this->getObject('ingestservice', 'ingestservice');
            $this->objIngestStaging = $this->getObject('ingeststagingservice', 'ingestservice');
            $stack = $this->getObject('nativeauthwebcomposition', 'security')->build();
            $this->csrf = $stack['csrf'];

            // Store Context Code
            $this->contextCode = $this->objContext->getContextCode();



            $this->objLanguage = $this->getObject('language', 'language');
            $this->objUser = $this->getObject('user', 'security');
            $this->userId = $this->objUser->userId();
            $this->objContextGroups = $this->getObject('managegroups', 'contextgroups');
            //Load Activity Streamer

            if ($this->objModuleCatalogue->checkIfRegistered('activitystreamer') && $this->objUser->isLoggedIn()) {
                $this->objActivityStreamer = $this->getObject('activityops', 'activitystreamer');
                $this->eventDispatcher->addObserver ( array ($this->objActivityStreamer, 'postmade' ) );
                $this->eventsEnabled = TRUE;
            } else {
                $this->eventsEnabled = FALSE;
            }
            $objSysConfig = $this->getObject('dbsysconfig', 'sysconfig');
            $enableActivityStreamer = $objSysConfig->getValue('ENABLE_ACTIVITYSTREAMER', 'contextcontent');
            if (strtoupper($enableActivityStreamer) == 'FALSE') {
                $this->eventsEnabled = FALSE;
            }

            $this->objMenuTools = $this->getObject('tools', 'toolbar');
            $this->objConfig = $this->getObject('altconfig', 'config');
            $this->objSysConfig = $this->getObject('dbsysconfig', 'sysconfig');
            $this->objContextComments = $this->getObject('db_contextcontent_comment', 'contextcontent');
            $this->objAlertUtils = $this->getObject('alertutils');
            $this->objFilePreview = $this->getObject('filepreview', 'filemanager');
            $this->objAltConfig = $this->getObject('altconfig', 'config');
            $this->objAltConfig = $this->getObject('altconfig', 'config');
            $this->siteRoot = $this->objAltConfig->getsiteRoot();
            $this->moduleUri = $this->objAltConfig->getModuleURI();


            $this->setVar('pageSuppressXML', TRUE);
        } catch (customException $e) {
            //oops, something not there - bail out
            echo customException::cleanUp();
            //we don't want to even attempt anything else right now.
            die();
        }
    }

    /**
     * Method to override login requirement for certain actions
     * @param string $action Action user is taking
     * @return boolean
     */
    function requiresLogin($action) {
        $actions = array('viewchapter', 'viewpage', 'rss', 'rsscall', 'notincontext', ''); //
        if (in_array($action, $actions)) {
            return FALSE;
            //var_dump($action);
        } else {
            return TRUE;
        }
    }

    /**
     * Dispatch Method to run required action
     * @param string $action
     */
    public function dispatch($action) {

        $this->contextCode = ($this->getParam('rss_contextcode') != "") ? $this->getParam('rss_contextcode') : $this->contextCode;
        if ($this->contextCode == '' && $action != 'notincontext') {
            $action = 'notincontext';
        }
        $this->validateRequestIdentifiers();

        $this->setLayoutTemplate('layout_chapter_tpl.php');
        if ($this->isMutation($action)) {
            try {
                if (in_array($action, array('changebookmark', 'addcomment'), true)) {
                    $this->requireAuthenticatedMutation($action);
                } else {
                    $this->requireAuthorisedMutation($action);
                }
            } catch (RuntimeException $exception) {
                if ($exception->getMessage() === 'The form has expired. Please reload and try again.' &&
                        in_array($action, array('savepage', 'updatepage'), true)) {
                    return $this->recoverExpiredPageForm($action);
                }
                throw $exception;
            }
        }
        if (in_array($action, array('addcontent', 'addpage', 'editpage', 'deletepage',
            'addchapter', 'editchapter', 'deletechapter', 'exportcontent',
            'useractivity', 'showuseractivity', 'viewlogs', 'viewlogdetails',
            'viewcontextcontentusage', 'viewcontextcontentusagedetails', 'addpagefromfile',
            'importdocument', 'managesections'), true)) {
            $this->requireCourseManager();
        }
        if (in_array($action, array('addscorm', 'addscormpage', 'editscorm', 'savescormpage',
            'savescormchapter', 'updatescormchapter', 'addpagefromfile', 'uploadfile',
            'createpagefromfile'), true)) {
            throw new RuntimeException('This legacy authoring path has been retired from contextcontent');
        }

        switch ($action) {

            case 'notincontext':
                return 'notincontext_tpl.php';
            case 'exportcontent':
                $this->ex1=$this->getObject('contextexport');
                $this->ex1->pagecrawl($this->contextCode);
                die;
            case 'switchcontext':
                die('Switch Context'); // Fix Up
            case 'addpage':
                return $this->addPage($this->getParam('chapter'), $this->getParam('id', ''), $this->getParam('context', ''));
            case 'addcontent':
                return $this->addContent($this->getParam('chapter'), $this->getParam('id', ''));
            case 'savepage':
                return $this->savePage();
            case 'savepageorder':
                return $this->savePageOrder();
            case 'useractivity':
                return $this->userActivity();

            case 'showuseractivity':
                return $this->showUserActivity();
// case 'autosavepage':
            //     return $this->autoSavePage();
            case 'addscorm':
                return $this->addScormChapter();
            case 'addscormpage':
                return $this->addScormPage($this->getParam('chapter'), $this->getParam('id', ''), $this->getParam('context', ''));
            case 'editscorm':
                return $this->editScormChapter($this->getParam('id'));
            case 'editpage':
                return $this->editPage($this->getParam('id'), $this->getParam('context'));
            case 'updatepage':
                return $this->updatePage();
            case 'viewpage':
                $trackPage = array();
                $itemid = $this->getParam('id');
                if ($itemid == "") {
                    $itemid = $this->getParam('prevchapterid');
                }
                if ($itemid == "") {
                    $itemid == "x";
                }
                $trackPage['contextItemId'] = $itemid;
                $trackPage['prevpageid'] = $this->getParam('prevpageid');
                $trackPage['prevchapterid'] = $this->getParam('prevchapterid');
                $trackPage['contextCode'] = $this->contextCode;
                $trackPage['module'] = $this->getParam('module');
                $trackPage['datecreated'] = date('Y-m-d H:i:s');
                $trackPage['pageorchapter'] = 'page';
                $trackPage['description'] = $this->objLanguage->languageText('mod_contextcontent_viewpage', 'contextcontent');
                return $this->viewPage($this->getParam('id'), $trackPage);

            //     return $this->viewPage($this->getParam('id'));
            case 'deletepage':
                return $this->deletePage($this->getParam('id'), $this->getParam('context'));
            case 'deletepageconfirm':
                return $this->deletePageConfirm();
            case 'fixleftright':
                return $this->fixLeftRightValues();
            case 'movepageup':
                return $this->movePageUp($this->getParam('id'));
            case 'movepagedown':
                return $this->movePageDown($this->getParam('id'));
            case 'savechapter':
                return $this->saveChapter();
            case 'managesections':
                return $this->manageSections();
            case 'viewsection':
                return $this->viewSection();
            case 'savesection':
                return $this->saveSection();
            case 'deletesection':
                return $this->deleteSection();
            case 'assignsection':
                return $this->assignSection();
            case 'savescormpage':
                return $this->saveScormPage();
            case 'savescormchapter':
                return $this->saveScormChapter();
            case 'addchapter':
                return $this->addChapter();
            case 'editchapter':
                return $this->editChapter($this->getParam('id'));
            case 'updatechapter':
                return $this->updateChapter();
            case 'updatescormchapter':
                return $this->updateScormChapter();
            case 'deletechapter':
                return $this->deleteChapter($this->getParam('id'));
            case 'deletechapterconfirm':
                return $this->deleteChapterConfirm();
            case 'movechapterup':
                return $this->moveChapterUp($this->getParam('id'));
            case 'movechapterdown':
                return $this->moveChapterDown($this->getParam('id'));
            case 'viewchapter':
                return $this->viewChapter($this->getParam('id'));
            case 'startstagegatequiz':
                return $this->startStageGateQuiz($this->getParam('id'));
            case 'coursecompletion':
                return $this->courseCompletion();
            case 'viewprintchapter':
                return $this->viewPrintChapter($this->getParam('id'));
            case 'changenavigation':
                return $this->changeNavigation($this->getParam('type'), $this->getParam('id'));
            case 'movetochapter':
                return $this->moveToChapter($this->getParam('id'), $this->getParam('chapter'));
            case 'changebookmark':
                return $this->changeBookMark();
            case 'search':
                return $this->search($this->getParam('contentsearch'));
            case 'showcontexttools':
                return $this->showcontexttools();
            case 'chapterlistastree':
                return $this->getChapterListAsTree();
            case 'showcontextchapters':
                return $this->showContextChapters();
            case 'rss':
                return $this->viewRss();
            case 'addcomment':
                return $this->addComment();
            case 'rsscall':
                return $this->rssCall();
            case 'addpagefromfile':
                $chapterid = $this->getParam('chapterid');
                return $this->addPageFromFile($chapterid);
            case 'uploadfile':
                return $this->uploadFile();
            case 'createpagefromfile':
                return $this->createpagefromfile();
            case 'importdocument':
                return $this->importDocument();
            case 'previewdocumentimport':
                return $this->previewDocumentImport();
            case 'confirmdocumentimport':
                return $this->confirmDocumentImport();
            case 'viewlogs':
            case 'viewlogdetails':
                return $this->activityReport(false);
            case 'viewcontextcontentusage':
            case 'viewcontextcontentusagedetails':
                return $this->activityReport(true);
            default:
                //return $this->home_debug();
                return $this->showContextChapters();
        }
    }

    /** Native reports and authorised, filtered CSV downloads. */
    private function activityReport($summary)
    {
        $this->requireCourseManager();
        $service = $this->getObject('contentactivityreport');
        $input = [];
        foreach (['startdate', 'enddate', 'studentsonly', 'q', 'page', 'sort'] as $name) {
            $value = $this->getParam($name, null);
            if ($value !== null) $input[$name] = $value;
        }
        try { $filters = $service->filters($input); }
        catch (InvalidArgumentException $error) {
            $filters = $service->filters([]);
            $this->setVar('reportError', true);
            $this->setVar('reportSummary', $summary);
            $this->setVar('reportFilters', $filters);
            $this->setVar('reportData', ['rows'=>[], 'total'=>0, 'page'=>1]);
            $this->setLayoutTemplate('layout_firstpage_tpl.php');
            return 'activityreport_tpl.php';
        }
        $report = $service->report((string) $this->contextCode, $filters, (bool) $summary);
        if ($this->getParam('format') === 'csv') {
            header('Content-Type: text/csv; charset=UTF-8');
            header('Content-Disposition: attachment; filename="content-activity.csv"');
            header('Cache-Control: private, no-store');
            $out = fopen('php://output', 'w');
            $columns = $summary ? ['username','fullname','accesses'] : ['username','fullname','title','pageorchapter','starttime','endtime'];
            fputcsv($out, $columns, ',', '"', '');
            for ($offset = 0; $offset < $report['total']; $offset += 500) {
                $filters['offset'] = $offset;
                $batch = $service->report((string) $this->contextCode, $filters, (bool) $summary, true);
                foreach ($batch['rows'] as $row) fputcsv($out, array_map(fn($key) => $service->csvCell($row[$key] ?? ''), $columns), ',', '"', '');
            }
            fclose($out);
            exit;
        }
        $this->setVar('reportSummary', $summary);
        $this->setVar('reportFilters', $filters);
        $this->setVar('reportData', $report);
        $this->setLayoutTemplate('layout_firstpage_tpl.php');
        return 'activityreport_tpl.php';
    }

    private function isPost()
    {
        return strtoupper((string) ($_SERVER['REQUEST_METHOD'] ?? '')) === 'POST';
    }

    private function validateRequestIdentifiers()
    {
        $contextCode = (string) $this->contextCode;
        if ($contextCode !== ''
            && !preg_match('/^[A-Za-z0-9._-]{1,255}$/', $contextCode)) {
            throw new InvalidArgumentException('Invalid course code');
        }
        foreach (array('id', 'chapter', 'chapterid', 'pageid', 'parentnode', 'insert_after', 'sectionid') as $name) {
            $value = (string) $this->getParam($name, '');
            if ($value !== '' && $value !== 'root'
                && !preg_match('/^[A-Za-z0-9_-]{1,64}$/', $value)) {
                throw new InvalidArgumentException('Invalid content identifier');
            }
        }
    }

    private function recoverExpiredPageForm($action)
    {
        // Authentication already passed before CSRF verification. Re-check the
        // course-manager boundary, then render the same form with a fresh token.
        $this->requireCourseManager();
        $this->setVar('preserveSubmittedPageForm', true);
        $this->setVar('pageFormError', $this->objLanguage->languageText(
            'mod_contextcontent_form_expired_preserved', 'contextcontent'));

        if ($action === 'updatepage') {
            return $this->editPage((string) $this->getParam('id', ''));
        }
        return $this->addPage(
            (string) $this->getParam('chapter', ''),
            (string) $this->getParam('insert_after', ''),
            (string) $this->getParam('context', '')
        );
    }

    private function isMutation($action)
    {
        return in_array($action, array(
            'savepage', 'updatepage', 'deletepageconfirm', 'fixleftright',
            'movepageup', 'movepagedown', 'savechapter', 'updatechapter',
            'deletechapterconfirm', 'movechapterup', 'movechapterdown',
            'movetochapter', 'changebookmark', 'addcomment', 'uploadfile',
            'createpagefromfile', 'previewdocumentimport', 'confirmdocumentimport',
            'savepageorder', 'savesection', 'deletesection', 'assignsection'
        ), true);
    }

    private function requireAuthorisedMutation($action)
    {
        $this->requireAuthenticatedMutation($action);
        if (!($this->objUser->isAdmin() || $this->objContextGroups->isContextLecturer())) {
            throw new RuntimeException('You may not manage content in this course');
        }
    }

    private function requireAuthenticatedMutation($action)
    {
        if (!$this->isPost()) {
            throw new RuntimeException('POST is required for ' . $action);
        }
        if (!$this->objUser->isLoggedIn()) {
            throw new RuntimeException('Sign in is required');
        }
        $token = (string) $this->getParam('csrf_token', '');
        if (!$this->csrf->consume(self::CSRF_CONTEXT, $token)) {
            throw new RuntimeException('The form has expired. Please reload and try again.');
        }
    }

    private function requireCourseManager()
    {
        if (!$this->objUser->isLoggedIn()
            || !($this->objUser->isAdmin() || $this->objContextGroups->isContextLecturer())) {
            throw new RuntimeException('You may not manage content in this course');
        }
    }

    private function prepareMutationForm()
    {
        $this->setVar('contextContentCsrf', $this->csrf->issue(self::CSRF_CONTEXT));
    }

    private function importDocument()
    {
        $this->prepareMutationForm();
        $this->setVar('documentImportState', 'upload');
        $this->setVar('documentImportMaximumBytes', 52428800);
        return 'importdocument_tpl.php';
    }

    private function previewDocumentImport()
    {
        $this->requireCourseManager();
        $this->setVar('documentImportState', 'error');
        try {
            $staged = $this->objIngestStaging->stageUpload($_FILES['source_document'] ?? array(), $this->userId);
            $document = $this->objIngest->preview($staged['path'] ?? $this->objIngestStaging->resolve($staged['token'], $this->userId)['path']);
            $preview = $this->objIngest->applyCapability($document, 'contextcontent', 'contextcontentingestprofile');
            $this->setVar('documentImportState', 'preview');
            $this->setVar('documentImportStage', $staged);
            $this->setVar('documentImportPreview', $preview);
        } catch (Throwable $error) {
            $this->setVar('documentImportErrorCode', $error->getMessage());
        }
        $this->prepareMutationForm();
        return 'importdocument_tpl.php';
    }

    private function confirmDocumentImport()
    {
        $this->requireCourseManager();
        $token = (string) $this->getParam('stage_token', '');
        try {
            $staged = $this->objIngestStaging->resolve($token, $this->userId);
            $document = $this->objIngest->parse($staged['path']);
            $result = $this->objIngest->deliver($document, 'contextcontent', 'contextcontentingestconsumer', array(
                'target' => $this->contextCode,
                'contextcode' => $this->contextCode,
                'language' => 'en',
                'force' => (string) $this->getParam('force_import', '') === '1'
            ));
            if (($result['status'] ?? '') === 'completed' || ($result['status'] ?? '') === 'unchanged') {
                $this->objIngestStaging->discard($token, $this->userId);
            }
            $this->setVar('documentImportState', 'result');
            $this->setVar('documentImportResult', $result);
        } catch (Throwable $error) {
            $this->setVar('documentImportState', 'error');
            $this->setVar('documentImportErrorCode', $error->getMessage());
        }
        $this->prepareMutationForm();
        return 'importdocument_tpl.php';
    }

    /**
     * Method to override isValid to enable administrators to perform certain action
     *
     * @param $action Action to be taken
     * @return boolean
     */
    public function isValid($action, $default = true) {
        $courseDetails = $this->objContext->getField('access', $this->contextCode);
        if ($this->objUser->isAdmin() || $this->objContextGroups->isContextLecturer()) {
            return TRUE;
        } else {
            return FALSE; //parent::isValid ( $action );
        }
    }

    /**
     * Method that is used by the rss feeds and bookmark to go direct to contextcontent and/or chapter
     *
     * */
    public function rssCall() {
        $contextcode = $this->getParam('rss_contextcode');
        $chapterid = $this->getParam('id');
        $status = $this->objContext->joinContext($contextcode);
        if ($chapterid && $status) {
            return $this->nextAction('viewchapter', array('id' => $chapterid));
        } else if ($status) {
            return $this->showContextChapters();
        }
        return $this->nextAction('notincontext');
    }

    /**
     * Method to display the list of chapters in a context
     *
     * This is also the home page of the module
     */
    protected function showContextChapters() {

        if ($this->objSectionProgression->enabled($this->contextCode)) {
            $this->setVar('sections', $this->objSectionProgression->sections($this->contextCode));
            $this->setVar('canManageSections', $this->objSectionProgression->isManager($this->contextCode));
            if ($this->objUser->isLoggedIn()) { $this->prepareMutationForm(); }
            $this->setLayoutTemplate('layout_firstpage_tpl.php');
            return 'listsections_tpl.php';
        }

        $numContextChapters = $this->objContextChapters->getNumContextChapters($this->contextCode);

        $this->setVarByRef('numContextChapters', $numContextChapters);
        $this->setVar('userId', $this->userId);

        if ($numContextChapters == 0) {

            $this->setLayoutTemplate(NULL);

            // If user can create chapter, show create chapter form
            if ($this->isValid('savechapter')) {
                $this->prepareMutationForm();
                return 'nochapters_tpl.php';
            } else { // Else notify user there is no content
                return 'nocontent_tpl.php';
            }
        } else {
            $chapters = $this->objContextChapters->getContextChapters($this->contextCode);
            $this->setVarByRef('chapters', $chapters);
            if ($this->isValid('movechapterup') || $this->isValid('movechapterdown')) {
                $this->prepareMutationForm();
            }

            $this->setVar('showScrollLinks', TRUE);

            $this->setLayoutTemplate('layout_firstpage_tpl.php');
            return 'listchapters_tpl.php';
        }
    }

    /**
     * Method to add a new chapter
     */
    protected function addChapter() {
        $this->prepareMutationForm();
        $this->setVar('mode', 'add');
        $sectionsEnabled = $this->objSectionProgression->enabled($this->contextCode);
        $this->setVar('sectionsEnabled', $sectionsEnabled);
        $this->setVar('availableSections', $sectionsEnabled ? $this->objSections->forContext($this->contextCode, TRUE) : array());

        $this->setLayoutTemplate('layout_authoring_tpl.php');

        return 'addeditchapter_tpl.php';
    }

    /**
     * Method to add a new scorm chapter
     */
    protected function addScormChapter() {
        $this->setVar('mode', 'add');
        $this->setVar('contextCodeMessage',"");

        $this->setLayoutTemplate('layout_firstpage_tpl.php');

        return 'addeditscormchapter_tpl.php';
    }

    /**
     * Method to save a newly create chapter
     */
    protected function saveChapter() {
        $title = trim((string) $this->getParam('chaptertitle'));
        if ($title === '' || mb_strlen($title) > 255) {
            throw new InvalidArgumentException('A chapter title of at most 255 characters is required');
        }
        $intro = (string) $this->getParam('intro');
        $visibility = (string) $this->getParam('visibility');
        if (!in_array($visibility, array('Y', 'N', 'I'), true)) {
            throw new InvalidArgumentException('Invalid chapter visibility');
        }
        $startDate = $this->getParam('startdate');
        $endDate = $this->getParam('enddate');
        $sectionId = (string)$this->getParam('sectionid', '');
        if ($sectionId !== '' && $this->objSections->inContext($sectionId, $this->contextCode) === FALSE) {
            throw new InvalidArgumentException('Invalid section');
        }
        $this->objChapters->beginTransaction();
        try {
            $chapterId = $this->objChapters->addChapter('', $title, $intro);
            $result = $this->objContextChapters->addChapterToContext($chapterId, $this->contextCode, $visibility);
            if (!$result) { throw new RuntimeException('Could not create chapter'); }
            if ($sectionId !== '') { $this->objContextChapters->assignSection($result, $this->contextCode, $sectionId); }
            $this->objContextChapters->updateChapterReleaseDate($result, $startDate);
            $this->objContextChapters->updateChapterEndDate($result, $endDate);
            $this->objChapters->commitTransaction();
        } catch (Throwable $error) {
            $this->objChapters->rollbackTransaction();
            throw $error;
        }

        if ($result == FALSE) {
            return $this->nextAction(NULL, array('error' => 'couldnotcreatechapter'));
        } else {
            //add to activity log
            $contextinfo = $this->objContext->getContext($this->contextCode);
            if ($this->eventsEnabled) {
                $message = $this->objUser->fullname() . " " . $this->objLanguage->languageText('mod_contextcontent_addednewchapter', 'contextcontent') . " " . $this->objContext->getTitle($this->contextCode);
                $this->eventDispatcher->post($this->objActivityStreamer, "contextcontent", array('title' => $message,
                    'link' => $this->uri(array('action' => 'showcontextchapters', 'chapterid' => $chapterId), 'contextcontent'),
                    'contextcode' => $this->contextCode,
                    'author' => $this->objUser->fullname(),
                    'description' => $message));
            }
            //send alerts [ JC OK
            $alerts = explode("|", $contextinfo['alerts']);
            //--$index;
            foreach ($alerts as $alert) {
                if ($alert == '1') {
                    $this->objAlertUtils->sendEmailAlert($this->contextCode, $this->objContext->getTitle($this->contextCode));
                }
            }
            return $this->nextAction('viewchapter', array('message' => 'chaptercreated', 'id' => $chapterId));
        }
    }

    /**
     * Method to save a newly created scorm chapter
     */
    protected function saveScormChapter() {
        $title = $this->getParam('chapter');
        $intro = $this->getParam('parentfolder');
        $visibility = $this->getParam('visibility');
        $scorm = $this->getParam('scorm');

        $chapterId = $this->objChapters->addChapter('', $title, $intro);

        $result = $this->objContextChapters->addChapterToContext($chapterId, $this->contextCode, $visibility, $scorm);

        if ($result == FALSE) {
            return $this->nextAction(NULL, array('error' => 'couldnotcreatechapter'));
        } else {
            //add to activity log
            $contextinfo = $this->objContext->getContext($this->contextCode);
            if ($this->eventsEnabled) {
                $message = $this->objUser->fullname() . " " . $this->objLanguage->languageText('mod_contextcontent_addednewchapter', 'contextcontent') . " " . $this->objContext->getTitle($this->contextCode);
                $this->eventDispatcher->post($this->objActivityStreamer, "contextcontent", array('title' => $message,
                    'link' => $this->uri(array()),
                    'contextcode' => $this->contextCode,
                    'author' => $this->objUser->fullname(),
                    'description' => $message));
            }
            return $this->nextAction(NULL, array('message' => 'chaptercreated', 'id' => $result));
        }
    }

    /**
     * Method to edit a chapter
     *
     * @param string $id Record Id of the Chapter
     */
    protected function editChapter($id) {
        $this->prepareMutationForm();
        $chapter = $this->objContextChapters->getChapter($id, $this->contextCode);

        if ($chapter == FALSE) {
            return $this->nextAction(NULL, array('error' => 'editchapterdoesnotexist'));
        } else {
            $this->setVar('mode', 'edit');

            $this->setVarByRef('chapter', $chapter);
            $this->setVarByRef('id', $id);
            $this->setVarByRef('currentChapter', $id);
            $allStageGateTests = $this->objMcqTests->getTests($this->contextCode);
            $stageGateTests = array();
            $selectedStageGateIsInvalid = FALSE;
            if (is_array($allStageGateTests)) {
                foreach ($allStageGateTests as $stageGateTest) {
                    if (isset($stageGateTest['testtype']) && $stageGateTest['testtype'] === 'Formative') {
                        $stageGateTests[] = $stageGateTest;
                    } elseif (!empty($chapter['stage_gate_testid'])
                        && isset($stageGateTest['id'])
                        && $stageGateTest['id'] === $chapter['stage_gate_testid']) {
                        $selectedStageGateIsInvalid = TRUE;
                    }
                }
            }
            $this->setVar('stageGateTests', $stageGateTests);
            $this->setVar('selectedStageGateIsInvalid', $selectedStageGateIsInvalid);
            $sectionsEnabled = $this->objSectionProgression->enabled($this->contextCode);
            $this->setVar('sectionsEnabled', $sectionsEnabled);
            $this->setVar('availableSections', $sectionsEnabled ? $this->objSections->forContext($this->contextCode, TRUE) : array());

            $this->setVar('hideNavSwitch', TRUE);
            $this->setVar('currentPage', NULL);

            $this->setLayoutTemplate('layout_authoring_tpl.php');
            return 'addeditchapter_tpl.php';
        }
    }

    /**
     * Method to edit a scorm chapter
     *
     * @param string $id Record Id of the Chapter
     */
    protected function editScormChapter($id) {
        $chapter = $this->objContextChapters->getChapter($id);
        if ($this->eventsEnabled) {
            $ischapterlogged = $this->objContextActivityStreamer->deleteRecord($id);
        }
        if ($chapter == FALSE) {
            return $this->nextAction(NULL, array('error' => 'editchapterdoesnotexist'));
        } else {
            $this->setVar('mode', 'edit');

            $this->setVarByRef('chapter', $chapter);
            $this->setVarByRef('id', $id);

            $this->setLayoutTemplate('layout_firstpage_tpl.php');

            return 'addeditscormchapter_tpl.php';
        }
    }

    /**
     * Method to update a chapter
     */
    protected function updateChapter() {

        $id = $this->getParam('id');
        $chaptercontentid = $this->getParam('chaptercontentid');
        $contextchapterid = $this->getParam('contextchapterid');
        $title = trim((string) $this->getParam('chaptertitle'));
        if ($title === '' || mb_strlen($title) > 255) {
            throw new InvalidArgumentException('A chapter title of at most 255 characters is required');
        }
        $intro = $this->getParam('intro');
        $visibility = $this->getParam('visibility');

        $startdate = $this->getParam('startdate');
        $enddate = $this->getParam('enddate');
        $sectionId = (string)$this->getParam('sectionid', '');
        if ($sectionId !== '' && $this->objSections->inContext($sectionId, $this->contextCode) === FALSE) {
            throw new InvalidArgumentException('Invalid section');
        }
        $stageGateTestId = trim((string) $this->getParam('stage_gate_testid', ''));
        $stageGatePassMarkValue = trim((string) $this->getParam('stage_gate_passmark', ''));
        $stageGatePassMark = $stageGatePassMarkValue === '' ? 70 : (int) $stageGatePassMarkValue;

        // The selected quiz is the durable authoring intent.  Do not discard it
        // because a legacy radio helper omitted or reformatted its companion value.
        $stageGateEnabled = $stageGateTestId === '' ? 0 : 1;
        if ($stageGateEnabled && ($stageGatePassMark < 1 || $stageGatePassMark > 100)) {
            throw new InvalidArgumentException($this->objLanguage->languageText('mod_contextcontent_stage_gate_invalid', 'contextcontent'));
        }
        if ($stageGateEnabled) {
            $stageGateTest = $this->objMcqTests->getTests($this->contextCode, 'id,testtype', $stageGateTestId);
            if (!is_array($stageGateTest) || empty($stageGateTest[0])
                || !isset($stageGateTest[0]['testtype'])
                || $stageGateTest[0]['testtype'] !== 'Formative') {
                throw new InvalidArgumentException(
                    $this->objLanguage->languageText('mod_contextcontent_stage_gate_formative_required', 'contextcontent')
                );
            }
        }
        if (!$stageGateEnabled) { $stageGatePassMark = 0; }
        if ($id == '' || $chaptercontentid == '' || $contextchapterid == '') {
            return $this->nextAction(NULL, array('error' => 'noidprovided'));
        } else {
            //Remove previous records on activity streamer
            if ($this->eventsEnabled) {
                $ischapterlogged = $this->objContextActivityStreamer->deleteRecord($id);
            }
            $objChapterContent = $this->getObject('db_contextcontent_chaptercontent');

            $chapter = $objChapterContent->getRow('id', $chaptercontentid);

            if ($chapter == FALSE) {
                return $this->nextAction(NULL, array('error' => 'invalididprovided'));
            } else if ($chapter['chapterid'] != $id) {
                return $this->nextAction(NULL, array('error' => 'invalididprovided'));
            } else {
                $objChapterContent->updateChapter($chaptercontentid, $title, $intro);
                $this->objContextChapters->updateChapterVisibility($contextchapterid, $visibility);
                $this->objContextChapters->updateChapterReleaseDate($contextchapterid, $startdate);
                $this->objContextChapters->updateChapterEndDate($contextchapterid, $enddate);
                $existingPlacement = $this->objContextChapters->getRow('id', $contextchapterid);
                if ($this->objSectionProgression->enabled($this->contextCode)
                    && is_array($existingPlacement)
                    && (string)($existingPlacement['sectionid'] ?? '') !== $sectionId) {
                    $this->objContextChapters->assignSection($contextchapterid, $this->contextCode, $sectionId);
                }
                $stageGateSaved = $this->objContextChapters->updateChapterStageGate($contextchapterid, $stageGateTestId, $stageGatePassMark, $stageGateEnabled);
                if ($stageGateSaved === FALSE) {
                    throw new RuntimeException('The chapter stage gate could not be saved');
                }
                $savedChapter = $this->objContextChapters->getChapter($id, $this->contextCode);
                $savedCorrectly = $savedChapter !== FALSE
                    && (string) $savedChapter['stage_gate_testid'] === (string) $stageGateTestId
                    && (int) $savedChapter['stage_gate_passmark'] === (int) $stageGatePassMark
                    && (int) $savedChapter['stage_gate_enabled'] === (int) $stageGateEnabled;
                if (!$savedCorrectly) {
                    throw new RuntimeException('The chapter stage gate was not persisted in the current course');
                }

                return $this->nextAction('editchapter', array('message' => 'chapterupdated', 'id' => $id, 'stage_gate_saved' => '1'));
            }
        }
    }

    /**
     * Method to update a scorm chapter
     */
    protected function updateScormChapter() {

        $id = $this->getParam('id');
        $chaptercontentid = $this->getParam('chaptercontentid');
        $contextchapterid = $this->getParam('contextchapterid');
        $title = $this->getParam('chapter');
        $intro = $this->getParam('parentfolder');
        $visibility = $this->getParam('visibility');
        $scorm = $this->getParam('scorm');
        if ($id == '' || $chaptercontentid == '' || $contextchapterid == '') {
            return $this->nextAction(NULL, array('error' => 'noidprovided'));
        } else {
            $objChapterContent = $this->getObject('db_contextcontent_chaptercontent');

            $chapter = $objChapterContent->getRow('id', $chaptercontentid);

            if ($chapter == FALSE) {
                return $this->nextAction(NULL, array('error' => 'invalididprovided'));
            } else if ($chapter['chapterid'] != $id) {
                return $this->nextAction(NULL, array('error' => 'invalididprovided'));
            } else {
                $objChapterContent->updateChapter($chaptercontentid, $title, $intro);
                $this->objContextChapters->updateChapterVisibility($contextchapterid, $visibility);

                return $this->nextAction(NULL, array('message' => 'chapterupdated', 'id' => $id));
            }
        }
    }

    /**
     * Method to delete a chapter
     *
     * This function generates a confirmation form
     *
     * @param string $id Record Id of the Chapter
     */
    protected function deleteChapter($id) {
        $this->prepareMutationForm();
        $chapter = $this->objContextChapters->getChapter($id);

        if ($chapter == FALSE) {
            return $this->nextAction(NULL, array('error' => 'editchapterdoesnotexist'));
        } else {

            if ($this->objContextChapters->isContextChapter($this->contextCode, $id)) {
                $this->setVar('mode', 'edit');

                $this->setVarByRef('chapter', $chapter);
                $this->setVarByRef('id', $id);

                $numPages = $this->objContentOrder->getContextPages($this->contextCode, $id);
                $this->setVar('numPages', count($numPages));

                $this->setLayoutTemplate('layout_firstpage_tpl.php');

                return 'deletechapter_tpl.php';
            } else {
                return $this->nextAction(NULL, array('error' => 'chapternotinthiscontext'));
            }
        }
    }

    /**
     * Method to delete the chapter after confirmation
     *
     * If confirmation is not received, chapter is not deleted.
     */
    protected function deleteChapterConfirm() {


        $confirmation = $this->getParam('confirmation', 'N');
        $context = $this->getParam('context');
        $id = $this->getParam('id');

        // Check that confirmation has been received
        if ($confirmation == 'Y') {
            // Check that Context Matches
            if ($context != $this->contextCode) {
                return $this->nextAction(NULL, array('message' => 'attempttodeletechapteroutofcontext', 'id' => $id));
            }

            // Check That Chapter is In Context
            if ($this->objContextChapters->isContextChapter($this->contextCode, $id)) {

                // Check how many other chapters also have this context
                $numContextWithChapter = $this->objContextChapters->getNumContextWithChapter($id);

                $chapter = $this->objContextChapters->getContextChapterTitle($id);

                // If only one, do full delete
                if ($numContextWithChapter == 1) {
                    // Delete Chapter
                    $this->objContextChapters->removeChapterFromContext($id, $this->contextCode);
                    $this->objChapters->deleteChapter($id);

                    // Delete Pages in Chapter
                    $pages = $this->objContentOrder->getContextPages($this->contextCode, $id);

                    if (count($pages) > 0) {
                        foreach ($pages as $page) {
                            $this->objContentTitles->deleteTitle($page['titleid']);
                            //$this->objContentOrder->deletePage($page['id']);
                        }
                    }
                } else { // Else simply remove the chapter from this context.
                    $this->objContextChapters->removeChapterFromContext($id, $this->contextCode);
                }

                // Return Message
                return $this->nextAction(NULL, array('message' => 'chapterdeleted'));
            } else {
                return $this->nextAction(NULL, array('message' => 'chapternotincontext', 'id' => $id));
            }
        } else {
            return $this->nextAction(NULL, array('message' => 'deletechaptercancelled', 'id' => $id));
        }
    }

    /**
     * Method to add a page
     * @param string $chapter Record Id of Chapter under which page will be placed
     * @param string $parent Record Id of the Parent
     * @param string $contextCode Context Code
     */
    protected function addPage($chapter, $parent='', $contextCode='') {
        $this->prepareMutationForm();
        if ($contextCode != '' && $contextCode != $this->contextCode) {
            return $this->nextAction('switchcontext');
        }

        $this->setLayoutTemplate(NULL);

        $contentType = trim((string) $this->getParam('contenttype', ''));
        if ($contentType === '') {
            $course = $this->objContext->getContext($this->contextCode);
            $format = isset($course['delivery_format']) ? $course['delivery_format'] : 'standard';
            $this->setVar('contentTypes', $this->objContentTypes->forPalette('content', $format));
            $this->setVar('parent', '');
            $this->setVar('selectedContentType', '');
            $this->setVar('activePalette', $this->getParam('palette', 'content') === 'assessment' ? 'assessment' : 'content');
            $this->setVar('assessmentGroups', $this->objAssessmentPalette->all($this->contextCode));
            $this->setVarByRef('chapter', $chapter);
            return 'contenttypepicker_tpl.php';
        }
        $this->objContentTypes->get($contentType);
        if ($contentType === 'live_session') {
            return $this->nextAction('add', array(
                'flow_chapter' => $chapter,
                'flow_parent' => ''
            ), 'liveclass');
        }
        $this->setVar('contentType', $contentType);
        $this->setVar('mode', 'add');
        $this->setVar('formaction', 'savepage');
        $this->setVarByRef('chapter', $chapter);
        $this->setVarByRef('currentChapter', $chapter);

        $chapterTitle = $this->objContextChapters->getContextChapterTitle($chapter);
        $this->setVar('chapterTitle', $chapterTitle);

        $course = $this->objContext->getContext($this->contextCode);
        $format = isset($course['delivery_format']) ? $course['delivery_format'] : 'standard';
        $this->setVar('contentTypes', $this->objContentTypes->forPalette('content', $format));
        $this->setVar('parent', $parent);
        $this->setVar('selectedContentType', $contentType);
        $this->setVar('activePalette', $contentType === 'assessment_activity' ? 'assessment' : 'content');
        $this->setVar('assessmentGroups', $this->objAssessmentPalette->all($this->contextCode));
        if ($contentType === 'assessment_activity') {
            $selection = $this->objAssessmentPalette->selection(
                $this->getParam('providermodule', ''),
                $this->getParam('provideritemid', ''),
                $this->contextCode
            );
            if ($selection === false) {
                return $this->nextAction('addpage', array('chapter' => $chapter, 'palette' => 'assessment'));
            }
            $this->setVar('selectedAssessment', $selection);
        }

        return 'contenttypepicker_tpl.php';
    }

    /**
     * Method to add a scorm page
     * @param string $chapter Record Id of Chapter under which page will be placed
     * @param string $parent Record Id of the Parent
     * @param string $contextCode Context Code
     */
    protected function addScormPage($chapter, $parent='', $contextCode='') {
        if ($contextCode != '' && $contextCode != $this->contextCode) {
            return $this->nextAction('switchcontext');
        }

        $this->setLayoutTemplate(NULL);

        $this->setVar('mode', 'add');
        $this->setVar('formaction', 'savepage');
        $this->setVarByRef('chapter', $chapter);
        $this->setVarByRef('currentChapter', $chapter);

        $tree = $this->objContentOrder->getTree($this->contextCode, $chapter, 'dropdown');
        $this->setVarByRef('tree', $tree);
        $this->setVar('mode', 'add');

        $this->setLayoutTemplate('layout_firstpage_tpl.php');

        return 'addeditscormpage_tpl.php';
    }

    /**
     * Method to save a new page from file
     */
    function savePageFromFile(
    $menutitle, $headerscripts, $language, $pagecontent, $parent, $chapter) {

        $chapterTitle = $this->objContextChapters->getContextChapterTitle($chapter);
        $titleId = $this->objContentTitles->addTitle('', $menutitle, $pagecontent, $language, $headerscripts);


        $pageId = $this->objContentOrder->addPageToContext($titleId, $parent, $this->contextCode, $chapter);

        $this->setVar('mode', 'add');
        $this->setVar('formaction', 'savepage');
        //add to activity log
        $contextinfo = $this->objContext->getContext($this->contextCode);
        if ($this->eventsEnabled) {
            $message = $this->objUser->fullname() . " " . $this->objLanguage->languageText('mod_contextcontent_addednewpage', 'contextcontent') . " " . $this->objContext->getTitle($this->contextCode) . " " . $this->objLanguage->languageText('word_chapter', 'contextcontent') . ": " . $chapterTitle;
            $this->eventDispatcher->post($this->objActivityStreamer, "contextcontent", array('title' => $message,
                'link' => $this->uri(array()),
                'contextcode' => $this->contextCode,
                'author' => $this->objUser->fullname(),
                'description' => $message));
        }
        //send alerts [ JOC OK
        $alerts = explode("|", $contextinfo['alerts']);
        //--$index;
        foreach ($alerts as $alert) {
            if ($alert == '1') {
                $this->objAlertUtils->sendEmailAlert($this->contextCode, $this->objContext->getTitle($this->contextCode));
            }
        }
        return $this->nextAction('viewpage', array('id' => $pageId, 'message' => 'pagesaved'));
    }

    private function imageAudioBodyFromRequest()
    {
        $imageUrl = trim((string) $this->getParam('image_url'));
        $audioUrl = trim((string) $this->getParam('audio_url'));
        $alt = trim((string) $this->getParam('image_alt'));
        $caption = trim((string) $this->getParam('media_caption'));
        $transcript = trim((string) $this->getParam('audio_transcript'));
        if (!$this->isSafeMediaUrl($imageUrl) || ($audioUrl !== '' && !$this->isSafeMediaUrl($audioUrl))) {
            throw new InvalidArgumentException('Invalid media URL');
        }
        $e = function ($value) { return htmlspecialchars($value, ENT_QUOTES, 'UTF-8'); };
        $body = '<div class="contextcontent-image-audio-body"><figure>'
            . '<img src="' . $e($imageUrl) . '" alt="' . $e($alt) . '" loading="lazy" />';
        if ($caption !== '') { $body .= '<figcaption>' . $e($caption) . '</figcaption>'; }
        $body .= '</figure>';
        if ($audioUrl !== '') {
            $body .= '<audio controls preload="metadata" src="' . $e($audioUrl) . '"></audio>';
        }
        if ($transcript !== '') {
            $body .= '<details class="contextcontent-audio-transcript"><summary>'
                . $e($this->objLanguage->languageText('mod_contextcontent_audio_transcript', 'contextcontent'))
                . '</summary><p>' . nl2br($e($transcript)) . '</p></details>';
        }
        return $body . '</div>';
    }

    private function isSafeMediaUrl($url)
    {
        if ($url === '' || preg_match('/[\\x00-\\x1F\\x7F]/', $url)) { return false; }
        if (preg_match('/^(?:javascript|data|vbscript):/i', $url) || strpos($url, '//') === 0) { return false; }
        $scheme = parse_url($url, PHP_URL_SCHEME);
        return $scheme === null || $scheme === '' || in_array(strtolower($scheme), array('http', 'https'), true);
    }

    private function videoBodyFromRequest()
    {
        $videoUrl = trim((string) $this->getParam('video_url'));
        $caption = trim((string) $this->getParam('video_caption'));
        $transcript = trim((string) $this->getParam('video_transcript'));
        $orientation = (string) $this->getParam('video_orientation', 'portrait');
        if (!$this->isSafeMediaUrl($videoUrl)) {
            throw new InvalidArgumentException('Invalid media URL');
        }
        if (!in_array($orientation, array('portrait', 'landscape'), true)) { $orientation = 'portrait'; }
        $e = function ($value) { return htmlspecialchars($value, ENT_QUOTES, 'UTF-8'); };
        $embedUrl = $this->recognisedVideoEmbedUrl($videoUrl);
        $body = '<div class="contextcontent-video-body contextcontent-video-' . $orientation . '"><figure>';
        if ($embedUrl !== null) {
            $body .= '<div class="contextcontent-video-embed"><iframe src="' . $e($embedUrl)
                . '" title="' . $e($caption !== '' ? $caption : $this->objLanguage->languageText('mod_contextcontent_type_video', 'contextcontent'))
                . '" loading="lazy" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" allowfullscreen></iframe></div>';
        } else {
            $body .= '<video controls playsinline preload="metadata" src="' . $e($videoUrl) . '">'
                . $e($this->objLanguage->languageText('mod_contextcontent_video_not_supported', 'contextcontent'))
                . '</video>';
        }
        if ($caption !== '') { $body .= '<figcaption>' . $e($caption) . '</figcaption>'; }
        $body .= '</figure>';
        if ($transcript !== '') {
            $body .= '<details class="contextcontent-video-transcript"><summary>'
                . $e($this->objLanguage->languageText('mod_contextcontent_video_transcript', 'contextcontent'))
                . '</summary><p>' . nl2br($e($transcript)) . '</p></details>';
        }
        return $body . '</div>';
    }

    /**
     * Build a TikTok page body from the dedicated authoring controls.
     *
     * @return string Trusted provider markup.
     */
    private function tiktokBodyFromRequest()
    {
        return $this->objTikTokVideo->buildBody(
            trim((string) $this->getParam('tiktok_url')),
            trim((string) $this->getParam('tiktok_caption')),
            trim((string) $this->getParam('tiktok_transcript'))
        );
    }

    private function recognisedVideoEmbedUrl($url)
    {
        $parts = parse_url($url);
        $host = strtolower(isset($parts['host']) ? $parts['host'] : '');
        $host = preg_replace('/^www\\./', '', $host);
        $path = isset($parts['path']) ? trim($parts['path'], '/') : '';
        if ($host === 'youtu.be' && preg_match('/^[A-Za-z0-9_-]{6,20}$/', $path)) {
            return 'https://www.youtube-nocookie.com/embed/' . $path;
        }
        if (in_array($host, array('youtube.com', 'm.youtube.com', 'youtube-nocookie.com'), true)) {
            parse_str(isset($parts['query']) ? $parts['query'] : '', $query);
            $id = isset($query['v']) ? $query['v'] : (preg_match('#^(?:shorts|embed)/([A-Za-z0-9_-]{6,20})#', $path, $match) ? $match[1] : '');
            if (preg_match('/^[A-Za-z0-9_-]{6,20}$/', $id)) { return 'https://www.youtube-nocookie.com/embed/' . $id; }
        }
        if (in_array($host, array('vimeo.com', 'player.vimeo.com'), true)
            && preg_match('#(?:video/)?([0-9]{6,12})#', $path, $match)) {
            return 'https://player.vimeo.com/video/' . $match[1];
        }
        return null;
    }

    private function resourceBodyFromRequest($contentType)
    {
        $supported = array('pdf', 'zip_bundle', 'external_reading');
        if (!in_array($contentType, $supported, true)) {
            throw new InvalidArgumentException('Unsupported resource content type');
        }
        $description = trim((string) $this->getParam('resource_description'));
        $source = trim((string) $this->getParam('resource_source'));
        $e = function ($value) { return htmlspecialchars($value, ENT_QUOTES, 'UTF-8'); };
        if ($contentType === 'zip_bundle') {
            $token = trim((string) $this->getParam('resource_filepreview'));
            if (!preg_match('/^\[FILEPREVIEW\s+id="([A-Za-z0-9_-]+)"\s+comment="([^"\r\n]+\.zip)"\s*\/\]$/i', $token)) {
                throw new InvalidArgumentException('Invalid File Manager ZIP token');
            }
            $body = '<div class="contextcontent-resource-body contextcontent-resource-zip_bundle">';
            if ($description !== '') {
                $body .= '<p class="contextcontent-resource-description">' . nl2br($e($description)) . '</p>';
            }
            if ($source !== '') {
                $body .= '<p class="contextcontent-resource-source">' . $e($source) . '</p>';
            }
            return $body . '<div class="contextcontent-resource-filepreview">' . $token . '</div></div>';
        }
        $url = trim((string) $this->getParam('resource_url'));
        if (!$this->isSafeMediaUrl($url)) {
            throw new InvalidArgumentException('Invalid resource URL');
        }
        $actionKey = $contentType === 'pdf' ? 'mod_contextcontent_download_pdf'
            : 'mod_contextcontent_open_external';
        $body = '<div class="contextcontent-resource-body contextcontent-resource-' . $e($contentType) . '">';
        if ($description !== '') {
            $body .= '<p class="contextcontent-resource-description">' . nl2br($e($description)) . '</p>';
        }
        if ($source !== '') {
            $body .= '<p class="contextcontent-resource-source">' . $e($source) . '</p>';
        }
        $external = $contentType === 'external_reading';
        $body .= '<p class="contextcontent-resource-action"><a href="' . $e($url) . '"'
            . ($external ? ' target="_blank" rel="noopener noreferrer"' : ' download') . '>'
            . $e($this->objLanguage->languageText($actionKey, 'contextcontent')) . '</a></p>';
        if ($external) {
            $body .= '<p class="contextcontent-external-notice">'
                . $e($this->objLanguage->languageText('mod_contextcontent_external_notice', 'contextcontent')) . '</p>';
        }
        return $body . '</div>';
    }

    protected function savePage() {

        $menutitle = trim((string) $this->getParam('menutitle'));
        $language = 'en';
        $pagecontent = (string) $this->getParam('pagecontent');
        $parent = (string) $this->getParam('parentnode');
        $insertAfter = (string) $this->getParam('insert_after');
        $chapter = (string) $this->getParam('chapter');
        $contentType = (string) $this->getParam('contenttype', 'rich_text');
        $providerModule = (string) $this->getParam('providermodule', '');
        $providerItemId = (string) $this->getParam('provideritemid', '');
        if ($contentType === 'assessment_activity'
            && $this->objAssessmentPalette->selection(
                $providerModule, $providerItemId, $this->contextCode
            ) === false) {
            return $this->nextAction('addpage', array('chapter' => $chapter, 'palette' => 'assessment'));
        }
        if ($contentType === 'image_audio') { $pagecontent = $this->imageAudioBodyFromRequest(); }
        if ($contentType === 'video') { $pagecontent = $this->videoBodyFromRequest(); }
        if ($contentType === 'tiktok_video') { $pagecontent = $this->tiktokBodyFromRequest(); }
        if (in_array($contentType, array('pdf', 'zip_bundle', 'external_reading'), true)) { $pagecontent = $this->resourceBodyFromRequest($contentType); }

        $chapterTitle = $this->objContextChapters->getContextChapterTitle($chapter);
        $pageId = $this->objAuthoring->createNativePage(array(
            'contextcode' => $this->contextCode,
            'chapterid' => $chapter,
            'parentid' => $parent,
            'insert_after' => $insertAfter,
            'contenttype' => $contentType,
            'title' => $menutitle,
            'body' => $pagecontent,
            'language' => $language,
            'providermodule' => $providerModule,
            'provideritemid' => $providerItemId
        ));

        $this->setVar('mode', 'add');
        $this->setVar('formaction', 'savepage');
        //add to activity log
        $contextinfo = $this->objContext->getContext($this->contextCode);
        if ($this->eventsEnabled) {
            $message = $this->objUser->fullname() . " " . $this->objLanguage->languageText('mod_contextcontent_addednewpage', 'contextcontent') . " " . $this->objContext->getTitle($this->contextCode) . " " . $this->objLanguage->languageText('word_chapter', 'contextcontent') . ": " . $chapterTitle;
            $this->eventDispatcher->post($this->objActivityStreamer, "contextcontent", array('title' => $message,
                'link' => $this->uri(array('action' => 'viewpage', 'id' => $pageId), 'contextcontent'),
                'contextcode' => $this->contextCode,
                'author' => $this->objUser->fullname(),
                'description' => $message));
        }
        //send alerts [ JOC OK
        $alerts = explode("|", $contextinfo['alerts']);
        //--$index;
        foreach ($alerts as $alert) {
            if ($alert == '1') {
                $this->objAlertUtils->sendEmailAlert($this->contextCode, $this->objContext->getTitle($this->contextCode));
            }
        }
        return $this->nextAction('viewpage', array('id' => $pageId, 'message' => 'pagesaved'));
    }

    /**
     * Method to save a newly added page
     */
    protected function autoSavePage() {

        $menutitle = (string) $this->getParam('menutitle');
        $language = 'en';
        $pagecontent = (string) $this->getParam('pagecontent');
        $parent = (string) $this->getParam('parentnode');
        $chapter = (string) $this->getParam('chapter');
        $contentType = (string) $this->getParam('contenttype', 'rich_text');
        $chapterTitle = $this->objContextChapters->getContextChapterTitle($chapter);
        $pageId = $this->objAuthoring->createNativePage(array(
            'contextcode' => $this->contextCode, 'chapterid' => $chapter,
            'parentid' => $parent, 'contenttype' => $contentType,
            'title' => $menutitle, 'body' => $pagecontent, 'language' => $language
        ));
        echo $pageId;
        die();
    }

    /**
     * Method to save a newly added scorm page
     */
    protected function saveScormPage() {

        $menutitle = stripslashes($this->getParam('menutitle'));
        // CHISIMBA_CONTEXTCONTENT_HEADER_SCRIPT_AUTHORING_RETIRED
        // Ignore submitted page-specific JavaScript/CSS at the save boundary.
        $headerscripts = '';
        $language = 'en';
        $pagecontent = $this->getParam('parentfolder');
        $parent = stripslashes($this->getParam('parentnode'));
        $chapter = stripslashes($this->getParam('chapter'));
        $chapterTitle = $this->objContextChapters->getContextChapterTitle($chapter);
        $scorm = $this->getParam('scorm');


        $titleId = $this->objContentTitles->addTitle('', $menutitle, $pagecontent, $language, $headerscripts, $scorm);

        $pageId = $this->objContentOrder->addPageToContext($titleId, $parent, $this->contextCode, $chapter);

        $this->setVar('mode', 'add');
        $this->setVar('formaction', 'savepage');
        //add to activity log
        $contextinfo = $this->objContext->getContext($this->contextCode);
        if ($this->eventsEnabled) {
            $message = $this->objUser->fullname() . " " . $this->objLanguage->languageText('mod_contextcontent_addednewpage', 'contextcontent') . " " . $this->objContext->getTitle($this->contextCode) . " " . $this->objLanguage->languageText('word_chapter', 'contextcontent') . ": " . $chapterTitle;
            $this->eventDispatcher->post($this->objActivityStreamer, "contextcontent", array('title' => $message,
                'link' => $this->uri(array()),
                'contextcode' => $this->contextCode,
                'author' => $this->objUser->fullname(),
                'description' => $message));
        }
        return $this->nextAction('viewpage', array('id' => $pageId, 'message' => 'pagesaved'));
    }

    /**
     * Method to view a page
     * @param string $pageId Record Id of the Page
     */
    protected function viewPage($pageId='') {
        if ($pageId == '') {
            return $this->nextAction(NULL);
        }

        $page = $this->objContentOrder->getPage($pageId, $this->contextCode);
        if ($page == FALSE) {
            return $this->nextAction(NULL, array('error' => 'pagedoesnotexist'));
        }
        $chapter = $this->objContextChapters->getChapter($page['chapterid'], $this->contextCode);
        if (!$this->objSectionProgression->isManager($this->contextCode) && is_array($chapter)) {
            if (($chapter['visibility'] ?? 'Y') === 'I') { return $this->showChapterIntroductionOnly($chapter); }
            if (($chapter['visibility'] ?? 'Y') === 'N') { return $this->showChapterUnavailable(); }
        }
        $entryDecision = $this->objChapterStageGates->entryDecision($this->contextCode, $page['chapterid']);
        if (!$entryDecision['allowed']) {
            return $this->showStageGateLocked($entryDecision['gate']);
        }
        // Persist the current learning-journey position for logged-in users.
        // This is deliberately independent of optional event broadcasting:
        // Context home needs a durable last-page position even when events are off.
        if (!empty($this->userId)) {
            $this->objContextActivityStreamer->addRecord(
                $this->userId,
                Null,
                $pageId,
                $this->contextCode,
                "contextcontent",
                Null,
                "page",
                $page['menutitle']
            );
        }


        $this->setVar('page', $page);
        if ($this->objUser->isLoggedIn()) {
            $this->prepareMutationForm();
            $bookmarkIds = $this->objBookmarks->idsForUser($this->contextCode, $this->userId);
            $this->setVar('contextContentBookmarked', in_array($pageId, $bookmarkIds, true));
        } else {
            $this->setVar('contextContentCsrf', '');
            $this->setVar('contextContentBookmarked', false);
        }
        $this->setVar('currentPage', $pageId);
        $this->setVar('currentChapter', $page['chapterid']);
        $this->setVar('pagelft', $page['lft']);
        $this->setVar('module', 'contextcontent');

        $nextPage = $this->objContentOrder->getNextPage($this->contextCode, $page['chapterid'], $page['lft']);
        $prevPage = $this->objContentOrder->getPreviousPage($this->contextCode, $page['chapterid'], $page['lft']);
        $isLastPageInChapter = $this->objContentOrder->getNextPageId($this->contextCode, $page['chapterid'], $page['lft']) === NULL;
        $isFirstPageInChapter = $this->objContentOrder->getPrevPageId($this->contextCode, $page['chapterid'], $page['lft']) === NULL;
        $sectionNextStop = $this->objSectionProgression->enabled($this->contextCode)
            ? $this->objSectionProgression->nextStop($this->contextCode, $page['chapterid'])
            : FALSE;
        if ($isLastPageInChapter) {
            $nextChapterId = $sectionNextStop!==FALSE
                ? ($sectionNextStop['type']==='chapter' ? $sectionNextStop['id'] : NULL)
                : $this->objChapterStageGates->nextChapterId($this->contextCode, $page['chapterid']);
            if ($sectionNextStop!==FALSE && $sectionNextStop['type']==='section') {
                $nextSection=$this->objSectionProgression->section($this->contextCode,$sectionNextStop['id']);
                if ($nextSection!==FALSE) {
                    $sectionLink=new link($this->uri(array('action'=>'viewsection','id'=>$nextSection['id'])));
                    $sectionLink->link=$this->objLanguage->code2Txt(
                        'mod_contextcontent_nextsection','contextcontent',NULL,'Next [-section-]'
                    ).': '.htmlentities($nextSection['title']).' &#187;';
                    $nextPage=$sectionLink->show();
                }
            } elseif (!empty($nextChapterId)) {
                $nextChapter = $this->objContextChapters->getChapter($nextChapterId);
                if ($nextChapter !== FALSE) {
                    $chapterLink = new link($this->uri(array('action' => 'viewchapter', 'id' => $nextChapterId)));
                    $chapterLink->link = $this->objLanguage->languageText('mod_contextcontent_nextchapter', 'contextcontent', 'Next chapter') . ': ' . htmlentities($nextChapter['chaptertitle']) . ' &#187;';
                    $nextPage = $chapterLink->show();
                }
            }
        }
        if ($isFirstPageInChapter) {
            $chapterOverviewLink = new link($this->uri(array('action' => 'viewchapter', 'id' => $page['chapterid'])));
            $chapterOverviewLink->link = '&#171; ' . $this->objLanguage->languageText('mod_contextcontent_chapteroverview', 'contextcontent', 'Chapter overview');
            $prevPage = $chapterOverviewLink->show();
        }
        $this->setVar('isFirstPageOnLevel', $this->objContentOrder->isFirstPageOnLevel($page['id']));
        $this->setVar('isLastPageOnLevel', $this->objContentOrder->isLastPageOnLevel($page['id']));
        $chapterStageGate = $this->objChapterStageGates->chapterGate($this->contextCode, $page['chapterid']);
        $chapterStageGateBest = $chapterStageGate === FALSE ? NULL
            : $this->objChapterStageGates->bestPercentage($chapterStageGate['testid'], $chapterStageGate['totalmark']);
        if ($isLastPageInChapter && $chapterStageGate!==FALSE
            && !$this->objChapterStageGates->hasPassed($chapterStageGate)) {
            $nextPage='';
        }
        $this->setVar('nextPage', $nextPage);
        $this->setVar('prevPage', $prevPage);
        $this->setVar('chapterStageGate', $chapterStageGate);
        $this->setVar('chapterStageGateBestPercentage', $chapterStageGateBest);
        $this->setVar('isLastPageInChapter', $isLastPageInChapter);
        $this->setVar('chapterStageGateNextChapterId', $chapterStageGate === FALSE
            ? NULL
            : ($sectionNextStop!==FALSE && $sectionNextStop['type']==='chapter'
                ? $sectionNextStop['id']
                : NULL));
        $this->setVar('chapterStageGateNextSectionId', $chapterStageGate === FALSE
            || $sectionNextStop===FALSE || $sectionNextStop['type']!=='section'
            ? NULL : $sectionNextStop['id']);


        $breadcrumbs = $this->objContentOrder->getBreadcrumbs($this->contextCode, $page['chapterid'], $page['lft'], $page['rght']);

        $chapterTitle = $this->objContextChapters->getContextChapterTitle($page['chapterid']);

        $this->setVar('currentChapterTitle', $chapterTitle);

        if ($chapterTitle != FALSE) {
            $chapterLink = new link($this->uri(array('action' => 'viewchapter', 'id' => $page['chapterid'])));
            $chapterLink->link = $this->objLanguage->languageText('word_chapter', 'word', 'Chapter') . ': ' . $chapterTitle;

            array_unshift($breadcrumbs, $chapterLink->show());
            //array_unshift($breadcrumbs, 'Chapter: '.$chapterTitle);
        }

        $this->objMenuTools->addToBreadCrumbs($breadcrumbs);

        $chapters = $this->objContextChapters->getContextChapters($this->contextCode);
        $this->setVar('chapters', $chapters);
        return 'viewpage_tpl.php';
    }

    /**
     * Method to edit a page
     * @param string $pageId Record Id of the Page
     */
    protected function editPage($pageId) {
        $this->prepareMutationForm();
        if ($pageId == '') {
            return $this->nextAction(NULL);
        }
        $page = $this->objContentOrder->getPage($pageId, $this->contextCode);

        if ($page == FALSE) {
            return $this->nextAction(NULL, array('error' => 'pagedoesnotexist'));
        }

        $this->setLayoutTemplate(NULL);

        $this->setVarByRef('page', $page);
        $this->setVar('contentType', $page['contenttype']);
        $this->setVarByRef('currentChapter', $page['chapterid']);

        $chapterTitle = $this->objContextChapters->getContextChapterTitle($page['chapterid']);
        $this->setVar('chapterTitle', $chapterTitle);

        $this->setVar('mode', 'edit');
        $this->setVar('formaction', 'updatepage');

        return 'addeditpage_tpl.php';
    }

    /**
     * Method to Update a Page
     */
    protected function updatePage() {
        $pageId = $this->getParam('id');
        $contextCode = $this->getParam('context');
        $menutitle = stripslashes($this->getParam('menutitle'));
        // Ignore submitted header scripts; an edit preserves any legacy value.
        $pagecontent = stripslashes($this->getParam('pagecontent'));
        $parentnode = stripslashes($this->getParam('parentnode'));

        if ($contextCode != '' && $contextCode != $this->contextCode) {
            return $this->nextAction('switchcontext');
        } else {
            //Remove previous records on activity streamer
            if ($this->eventsEnabled) {
                $ischapterlogged = $this->objContextActivityStreamer->deleteRecord($pageId);
            }
            $page = $this->objContentOrder->getPage($pageId, $this->contextCode);
            $parentPage = $this->objContentOrder->getPage($parentnode, $this->contextCode);

            if ($page == FALSE) {
                return $this->nextAction(NULL, array('error' => 'pagedoesnotexist'));
            } else {
                if ($page['contenttype'] === 'image_audio') { $pagecontent = $this->imageAudioBodyFromRequest(); }
                if ($page['contenttype'] === 'video') { $pagecontent = $this->videoBodyFromRequest(); }
                if ($page['contenttype'] === 'tiktok_video') { $pagecontent = $this->tiktokBodyFromRequest(); }
                if (in_array($page['contenttype'], array('pdf', 'zip_bundle', 'external_reading'), true)) { $pagecontent = $this->resourceBodyFromRequest($page['contenttype']); }
                $this->objAuthoring->updateNativePage(array(
                    'contextcode' => $this->contextCode, 'chapterid' => $page['chapterid'],
                    'placementid' => $pageId, 'parentid' => $parentnode,
                    'contenttype' => $page['contenttype'], 'title' => $menutitle,
                    'body' => $pagecontent, 'language' => $page['language'],
                    'providermodule' => isset($page['providermodule']) ? $page['providermodule'] : '',
                    'provideritemid' => isset($page['provideritemid']) ? $page['provideritemid'] : ''
                ));

                return $this->nextAction('viewpage', array('id' => $pageId, 'message' => 'pageupdated'));
            }
        }
    }

    /**
     * Method to delete a page
     *
     * This method presents a confirmation form for users wanting to delete a page
     *
     * @param string $pageId Record Id of the Page
     */
    protected function deletePage($pageId) {
        $this->prepareMutationForm();
        if ($pageId == '') {
            return $this->nextAction(NULL);
        }

        $page = $this->objContentOrder->getPage($pageId, $this->contextCode);

        if ($page == FALSE) {
            return $this->nextAction(NULL, array('error' => 'pagedoesnotexist'));
        }

        $children = $page['rght'] - $page['lft'] - 1;

        if ($children != 0) {
            return $this->nextAction('viewpage', array('id' => $pageId, 'message' => 'pagehassubpages'));
        }

        $this->setVarByRef('page', $page);

        return 'deletepage_tpl.php';
    }

    /**
     * Method to delete a page once confirmation has been received.
     */
    protected function deletePageConfirm() {
        $confirmation = $this->getParam('confirmation', 'N');
        $pageId = $this->getParam('id');
        $context = $this->getParam('context');

        if ($pageId == '' || $context == '') {
            return $this->nextAction(NULL, array('error' => 'pagedoesnotexist', 'attemptedaction' => 'delete'));
        }

        $page = $this->objContentOrder->getPage($pageId, $this->contextCode);

        if ($page == FALSE) {
            return $this->nextAction(NULL, array('error' => 'pagedoesnotexist', 'attemptedaction' => 'delete'));
        } else {
            $children = $page['rght'] - $page['lft'] - 1;
            if ($children == 0) {
                if ($confirmation == 'Y') {

                    $nextPage = $this->objContentOrder->getNextPageSQL($this->contextCode, $page['chapterid'], $page['lft']);

                    $this->objContentTitles->deleteTitle($page['titleid']);

                    $this->objContentOrder->rebuildChapter($this->contextCode, $page['chapterid']);

                    if (is_array($nextPage)) {
                        return $this->nextAction('viewpage', array('id' => $nextPage['id'], 'message' => 'pagedeleted', 'title' => urlencode($page['menutitle'])));
                    } else {
                        return $this->nextAction('viewchapter', array('id' => $page['chapterid'], 'message' => 'pagedeleted', 'title' => urlencode($page['menutitle'])));
                    }
                } else {
                    return $this->nextAction('viewpage', array('id' => $pageId, 'message' => 'deletecancelled'));
                }
            } else {
                return $this->nextAction('viewpage', array('id' => $pageId, 'message' => 'pagehassubpages'));
            }
        }
    }

    /**
     * Method to move a page up
     * @param string $id Record Id of the Page
     */
    protected function movePageUp($id) {
        $result = $this->objContentOrder->movePageUp($id);

        return $this->nextAction('viewpage', array('id' => $id, 'message' => 'movepageup', 'result' => $result));
    }

    /**
     * Method to move a page down
     * @param string $id Record Id of the Page
     */
    protected function movePageDown($id) {
        //$result = $this->objContextChapters->moveChapterDown($id);
        $result = $this->objContentOrder->movePageDown($id);

        return $this->nextAction('viewpage', array('id' => $id, 'message' => 'movepageup', 'result' => $result));
    }

    protected function savePageOrder()
    {
        $chapterId = trim((string) $this->getParam('chapter'));
        $rawOrder = trim((string) $this->getParam('page_order'));
        if (!preg_match('/^[A-Za-z0-9_,-]+$/', $rawOrder)) {
            throw new InvalidArgumentException('Invalid page order');
        }
        $pageIds = array_values(array_filter(explode(',', $rawOrder), 'strlen'));
        $this->objContentOrder->reorderChapterPages($this->contextCode, $chapterId, $pageIds);
        return $this->nextAction('viewchapter', array('id' => $chapterId, 'message' => 'pageordersaved'));
    }

    /**
     * Method to move a chapter up
     * @param string $id Record Id of the Chapter
     */
    protected function moveChapterUp($id) {
        $result = $this->objContextChapters->moveChapterUp($id);

        return $this->nextAction(NULL, array('id' => $id, 'message' => 'movechapterup', 'result' => $result));
    }

    /**
     * Method to move a chapter down
     * @param string $id Record Id of the Chapter
     */
    protected function moveChapterDown($id) {
        $result = $this->objContextChapters->moveChapterDown($id);

        return $this->nextAction(NULL, array('id' => $id, 'message' => 'movechapterdown', 'result' => $result));
    }

    /**
     * Method to view a chapter
     *
     * This method redirects to the first page in a chapter
     *
     * @param string $id Record Id of the Chapter
     */
    /** Launch a configured chapter-end MCQ through its verified Contextcontent placement. */
    protected function courseCompletion()
    {
        $summary = $this->objChapterStageGates->courseCompletionSummary($this->contextCode);
        if (empty($summary['complete'])) {
            return $this->nextAction('showcontextchapters');
        }
        $this->setVar('courseCompletionChapters', $summary['chapters']);
        return 'coursecompletion_tpl.php';
    }

    protected function startStageGateQuiz($chapterId) {
        $gate = $this->objChapterStageGates->chapterGate($this->contextCode, $chapterId);
        if ($gate === FALSE || !$this->objChapterStageGates->isGatedProgression($this->contextCode)) {
            return $this->nextAction('viewchapter', array('id' => $chapterId));
        }
        if (empty($gate['entryavailable'])) {
            return $this->showStageGateLocked($gate);
        }
        $params = array(
            'id' => $gate['testid'],
            'stage_gate_passmark' => $gate['passmark'],
            'stage_gate_origin_chapter' => $chapterId
        );
        $nextStop=$this->objSectionProgression->enabled($this->contextCode)
            ? $this->objSectionProgression->nextStop($this->contextCode,$chapterId)
            : array('type'=>'chapter','id'=>$this->objChapterStageGates->nextChapterId($this->contextCode,$chapterId));
        if ($nextStop['type']==='section') {
            $params['stage_gate_return_section']=$nextStop['id'];
        } elseif ($nextStop['type']==='chapter' && !empty($nextStop['id'])) {
            $params['stage_gate_return_chapter']=$nextStop['id'];
        } else {
            $params['stage_gate_course_completion'] = '1';
        }
        $best = $this->objChapterStageGates->bestPercentage($gate['testid'], $gate['totalmark']);
        if (!empty($gate['inprogress']) && !empty($gate['inprogressresultid'])) {
            $params['resume'] = '1';
            $params['resume_result_id'] = $gate['inprogressresultid'];
        } elseif ($best !== NULL && $best < $gate['passmark']
            && strtolower((string) $gate['testtype']) === 'formative') {
            $params['retry'] = '1';
        }
        return $this->nextAction('answertest', $params, 'mcqtests');
    }

    protected function viewChapter($id) {

        $visibleChapter = $this->objContextChapters->getChapter($id, $this->contextCode);
        if (!$this->objSectionProgression->isManager($this->contextCode) && is_array($visibleChapter)) {
            if (($visibleChapter['visibility'] ?? 'Y') === 'I') { return $this->showChapterIntroductionOnly($visibleChapter); }
            if (($visibleChapter['visibility'] ?? 'Y') === 'N') { return $this->showChapterUnavailable(); }
        }

        $entryDecision = $this->objChapterStageGates->entryDecision($this->contextCode, $id);
        if (!$entryDecision['allowed']) {
            return $this->showStageGateLocked($entryDecision['gate']);
        }

        $firstPage = $this->objContentOrder->getFirstChapterPage($this->contextCode, $id);
        if ($this->eventsEnabled) {
            $ischapterlogged = $this->objContextActivityStreamer->getRecord($this->userId, $id);
            //if ($ischapterlogged == FALSE || $ischapterlogged == TRUE) {
            $ischapterlogged = $this->objContextActivityStreamer->addRecord($this->userId, Null, $id, $this->contextCode, "contextcontent", Null, "chapter");
            //}
        }
        if ($firstPage == FALSE) {

            $chapter = $this->objContextChapters->getChapter($id);

            if ($chapter == FALSE) {
                return $this->nextAction(NULL, array('error' => 'chapterdoesnotexist'));
            } else {
                $this->setVarByRef('chapter', $chapter);
                $this->setVar('errorTitle', $this->objLanguage->languageText('mod_contextcontent_chapternewcontent', 'contextcontent', 'New Content'));
                $this->setVar('errorMessage', $this->objLanguage->languageText('mod_contextcontent_chapternewcontentinstruction', 'contextcontent', 'Pages to be added here'));
                return 'chapternocontent_tpl.php';
            }
        } else {
            $chapter = $this->objContextChapters->getChapter($id);
            if ($chapter == FALSE) {
                return $this->nextAction(NULL, array('error' => 'chapterdoesnotexist'));
            }
            $chapterPages = $this->objContentOrder->getContextPages($this->contextCode, $id);
            $this->setVarByRef('chapter', $chapter);
            $this->setVar('chapterId', $id);
            $this->setVar('firstPage', $firstPage['id']);
            $this->setVar('chapterPageCount', is_array($chapterPages) ? count($chapterPages) : 0);
            $canManageCourse = $this->objUser->isLoggedIn()
                && ($this->objUser->isAdmin() || $this->objContextGroups->isContextLecturer());
            $this->setVar('canManageCourse', $canManageCourse);
            $this->setVar('chapterPages', $chapterPages);
            if ($canManageCourse) { $this->prepareMutationForm(); }
            $this->setVar('message', $this->getParam('message'));
            $this->setLayoutTemplate('layout_firstpage_tpl.php');
            return 'viewchapter_tpl.php';
        }
    }

    /** Render a translated learner-facing message when a configured gate is not passed. */
    protected function showStageGateLocked($gate) {
        $this->setLayoutTemplate('layout_firstpage_tpl.php');
        $this->setVar('stageGateLocked', $gate);
        if (!empty($gate['video']['required']) && !$gate['video']['complete']) { return 'videogatelocked_tpl.php'; }
        $this->setVar('stageGateLockedBestPercentage', $this->objChapterStageGates->bestPercentage($gate['testid'], $gate['totalmark']));
        return 'stagegatelocked_tpl.php';
    }

    protected function showChapterIntroductionOnly($chapter) {
        $this->setVar('introOnlyChapter', $chapter);
        $this->setLayoutTemplate('layout_firstpage_tpl.php');
        return 'chapterintroductiononly_tpl.php';
    }

    protected function showChapterUnavailable() {
        $this->setLayoutTemplate('layout_firstpage_tpl.php');
        return 'chapterunavailable_tpl.php';
    }

    private function manageSections() {
        if (!$this->objSectionProgression->enabled($this->contextCode)) { return $this->nextAction('showcontextchapters'); }
        $this->prepareMutationForm();
        $sections = $this->objSections->forContext($this->contextCode, TRUE);
        $editId = (string)$this->getParam('editsection', '');
        $editSection = $editId === '' ? FALSE : $this->objSections->inContext($editId, $this->contextCode);
        $this->setVar('sections', $sections);
        $this->setVar('editSection', $editSection);
        $this->setVar('chapters', $this->objContextChapters->getContextChapters($this->contextCode));
        $this->setLayoutTemplate('layout_authoring_tpl.php');
        return 'managesections_tpl.php';
    }

    private function saveSection() {
        $title=trim((string)$this->getParam('title','')); $visibility=(string)$this->getParam('visibility','Y');
        if ($title==='' || mb_strlen($title)>255 || !in_array($visibility,array('Y','N'),TRUE)) { throw new InvalidArgumentException('Invalid section'); }
        $this->objSections->saveSection($this->contextCode,(string)$this->getParam('sectionid',''),$title,(string)$this->getParam('introduction',''),$visibility);
        return $this->nextAction('managesections');
    }

    private function deleteSection() {
        $id=(string)$this->getParam('sectionid','');
        foreach ($this->objContextChapters->getContextChapters($this->contextCode) as $chapter) { if (($chapter['sectionid'] ?? '')===$id) { throw new RuntimeException('Move chapters out of this section first'); } }
        $this->objSections->removeFromContext($id,$this->contextCode); return $this->nextAction('managesections');
    }

    private function assignSection() {
        $sectionId=(string)$this->getParam('sectionid','');
        if ($sectionId==='__unassigned__') { $sectionId=''; }
        if ($sectionId!=='' && $this->objSections->inContext($sectionId,$this->contextCode)===FALSE) { throw new InvalidArgumentException('Invalid section'); }
        $this->objContextChapters->assignSection((string)$this->getParam('id',''),$this->contextCode,$sectionId);
        return $this->nextAction('managesections');
    }

    private function viewSection() {
        if (!$this->objSectionProgression->enabled($this->contextCode)) {
            return $this->nextAction('showcontextchapters');
        }
        $section=$this->objSectionProgression->section(
            $this->contextCode,
            (string)$this->getParam('id','')
        );
        if ($section===FALSE) { return $this->nextAction('showcontextchapters'); }
        $firstChapter=empty($section['chapters'])?FALSE:$section['chapters'][0];
        if ($firstChapter!==FALSE && !$this->objSectionProgression->isManager($this->contextCode)) {
            $entryDecision=$this->objChapterStageGates->entryDecision(
                $this->contextCode,
                $firstChapter['chapterid']
            );
            if (!$entryDecision['allowed']) { return $this->showStageGateLocked($entryDecision['gate']); }
        }
        $this->setVar('section',$section);
        $this->setVar('firstSectionChapter',$firstChapter);
        $this->setLayoutTemplate('layout_firstpage_tpl.php');
        return 'sectionpage_tpl.php';
    }

    /**
     * Method to Render a Chapter in PDF
     * @param string $id Record Id of Chapter
     * @return PDF File
     */
    private function viewPrintChapter($id) {
        // Load Class to clean up paths
        $objCleanUrl = $this->getObject('cleanurl', 'filemanager');

        // Get all the pages of the chapter
        $pages = $this->objContentOrder->getPages($id, $this->contextCode);

        //$contextCode = sha1($this->contextCode);
        $contextCode = ($this->contextCode);

        // Set the Path where the Files will be stored
        $path = $this->objConfig->getcontentBasePath() . '/contextcontent/' . $contextCode;

        // Get Site Root Path
        $siteRoot = $this->objConfig->getSitePath() . '/';

        // Clean up slashes
        $objCleanUrl->cleanUpUrl($siteRoot);

        // Load Class for Creating Directories
        $objMkdir = $this->newObject('mkdir', 'files');
        // Recursively create directories if it does not exist
        $objMkdir->mkdirs($path);

        // If Chapter has no pages
        if (count($pages) == 0) {
            // Send Error Message. Chapter has no Pages / Content
            $this->setVar('errorTitle', $this->objLanguage->languageText('mod_contextcontent_chapternewcontent', 'contextcontent', 'New Content'));
            $this->setVar('errorMessage', $this->objLanguage->languageText('mod_contextcontent_chapternewcontentinstruction', 'contextcontent', 'Pages to be added here'));

            return 'errormessage_tpl.php';
        } else {
            // Create Absolute Path to where PDF is stored
            $destination = $this->objConfig->getcontentBasePath() . '/contextcontent/' . $contextCode . '/chapter_' . $id . '.pdf';
            // Clean Up slashes
            $objCleanUrl->cleanUpUrl($destination);

            // If PDF file exists
            if (file_exists($destination)) {
                // Redirect to PDF
                // Create Local Path to PDF
                $redirect = $this->objConfig->getcontentPath() . '/contextcontent/' . $contextCode . '/chapter_' . $id . '.pdf';

                // Redirect
                header('location: ' . $redirect);
            } else {
                // Else, Create PDF file

                /* Creating the PDF Process:
                  Get All Pages
                  Export all Pages into HTML format
                  Use HTML Doc to convert HTML into PDF
                 */

                // Array consisting of list of paths to HTML files
                $pagePath = array();

                // Loop through Chapter Pages
                foreach ($pages as $page) {
                    // Get Page Content
                    $pageContent = $this->objContentOrder->getPage($page['id'], $this->contextCode);

                    // Create HTML filename
                    $filename = $path . '/' . $page['id'] . '.html';

                    // Add HTML Path to array
                    $pagePath[] = $filename;

                    // Load File Object
                    $objFile = $this->getObject('dbfile', 'filemanager');

                    /*
                      To get images to work properly, we need to use the absolute
                      path to the image.

                      This code basically uses regex to get all items that use
                      filemanager, and convert them to absolute paths.
                     */

                    // Page Content
                    $pageText = $pageContent['pagecontent'];

                    // Replace XHTML
                    $pageText = str_replace('&amp;', '&', $pageText);



                    // Get Image Source Links
                    $results = spliti('src="', $pageText);
                    // Loop through the matches
                    foreach ($results as $line) {
                        $r2 = split('"', $line);
                        $srcURL = $r2[0];
                        $r2 = split('module=filemanager&action=file&id=', $srcURL);
                        if (isset($r2[1])) {
                            $r3 = split('&', $r2[1]);
                            $fileId = $r3[0];
                            $filePath = $objFile->getFullFilePath($fileId);
                            $pageText = str_replace($srcURL, $filePath, $pageText);
                        }
                    }


                    // Create HTML Document
                    $content = '<html><head>';
                    $content .= '<title>' . $pageContent['menutitle'] . '</title>';
                    $content .= '</head><body>';

                    $content .= $pageText;

                    $content .= '</body></html>';

                    // Write HTML Document to File System
                    $handle = fopen($filename, 'w');
                    fwrite($handle, $content);
                    fclose($handle);
                }

                // Load HTML Doc Class
                $objHtmlDoc = $this->getObject('htmldoc', 'htmldoc');

                // Create Parameters for HTML Doc Source Inputs
                $htmlSources = '';

                foreach ($pagePath as $htmlPage) {
                    $htmlSources .= $htmlPage . ' ';
                }

                // Render to PDF
                $objHtmlDoc->render($htmlSources, TRUE, TRUE, $destination);

                // Check if PDF Exists - Prove that file was successfully created.
                if (file_exists($destination)) {
                    $redirect = $this->objConfig->getcontentPath() . '/contextcontent/' . $contextCode . '/chapter_' . $id . '.pdf';
                    header('location: ' . $redirect);
                } else {
                    // Else Show Error Message
                    $this->setVar('errorTitle', $this->objLanguage->languageText('mod_contextcontent_couldnotcreatepdf', 'contextcontent', 'Could not create PDF Document'));
                    $this->setVar('errorMessage', ' ');
                    return 'errormessage_tpl.php';
                }
            }
        }
    }

    /**
     * Method to change the navigation approach for context
     * This method is a response to an ajax call
     * @param string $type Type of navigation to switch to
     * @param string $pageId Record Id of the Page
     */
    private function changeNavigation($type, $pageId='') {
        // CHISIMBA_CONTEXTCONTENT_NAVIGATION_LINKS

        $page = $this->objContentOrder->getPage($pageId, $this->contextCode);

        if ($page == FALSE) {
            echo ''; // Return Nothing - AJAX won't do anything
        } else {
            if ($type == 'twolevel') {
                $this->setSession('navigationType', 'twolevel');
                echo $this->objContentOrder->getTwoLevelNav($this->contextCode, $page['chapterid'], $pageId);
                echo '<p><a href="#contentnav" class="chisimba-content-nav-switch" data-contextcontent-navigation="tree" aria-controls="contentnav">' . $this->objLanguage->languageText('mod_contextcontent_viewastree', 'contextcontent', 'View as Tree') . '...</a>';
                echo '<br /><a href="#contentnav" class="chisimba-content-nav-switch" data-contextcontent-navigation="bookmarks" aria-controls="contentnav">' . $this->objLanguage->languageText('mod_contextcontent_viewbookmarkedpages', 'contextcontent', 'View Bookmarked Pages') . '</a></p>';
            } else if ($type == 'tree') {
                $this->setSession('navigationType', 'tree');
                echo $this->objContentOrder->getTree($this->contextCode, $page['chapterid'], 'htmllist', $pageId, 'contextcontent');
                echo '<p><a href="#contentnav" class="chisimba-content-nav-switch" data-contextcontent-navigation="twolevel" aria-controls="contentnav">' . $this->objLanguage->languageText('mod_contextcontent_viewtwolevels', 'contextcontent', 'View Two Levels at a time') . ' ...</a><br /><a href="#contentnav" class="chisimba-content-nav-switch" data-contextcontent-navigation="bookmarks" aria-controls="contentnav">' . $this->objLanguage->languageText('mod_contextcontent_viewbookmarkedpages', 'contextcontent', 'View Bookmarked Pages') . '</a></p>';
            } else if ($type == 'bookmarks') {
                $this->setSession('navigationType', 'bookmarks');

                echo $this->renderBookmarkedNavigation($page['chapterid']);

                echo '<p><a href="#contentnav" class="chisimba-content-nav-switch" data-contextcontent-navigation="twolevel" aria-controls="contentnav">' . $this->objLanguage->languageText('mod_contextcontent_viewtwolevels', 'contextcontent', 'View Two Levels at a time') . ' ...</a><br /><a href="#contentnav" class="chisimba-content-nav-switch" data-contextcontent-navigation="tree" aria-controls="contentnav">' . $this->objLanguage->languageText('mod_contextcontent_viewastree', 'contextcontent', 'View as Tree') . '...</a></p>';
            } else {
                echo ''; // Unknown Type - Return Nothing - AJAX won't do anything
            }
        }
    }

    /**
     * Method to move a page to another a chapter
     * @param string $pageId Record Id of the Page
     * @param string $chapter Record Id of the Chapter
     */
    private function moveToChapter($pageId, $chapter) {
        $result = $this->objContentOrder->movePageToChapter($pageId, $chapter, $this->contextCode);

        return $this->nextAction('viewpage', array('id' => $pageId, 'message' => $result));
    }

    /**
     * Method to toggle the status of a bookmarked page
     */
    protected function changeBookMark() {
        $id = $this->getParam('id');
        $type = $this->getParam('type', 'on');

        $page = $this->objContentOrder->getPage($id, $this->contextCode);
        if (!$page) { throw new InvalidArgumentException('Page does not exist in this course'); }
        $bookmarked = $type === 'on';
        $this->objBookmarks->setBookmark($this->contextCode, $id, $this->userId, $bookmarked);

        if ($this->getParam('ajax', '0') === '1') {
            while (ob_get_level() > 0) {
                ob_end_clean();
            }
            if (!headers_sent()) {
                http_response_code(200);
                header('Content-Type: application/json; charset=UTF-8');
                header('Cache-Control: no-store');
            }
            echo json_encode(array(
                'ok' => TRUE,
                'bookmarked' => $bookmarked,
                'pageid' => $id
            ));
            exit;
        }

        return $this->nextAction('viewpage', array('id' => $id));
    }

    private function renderBookmarkedNavigation($chapterId)
    {
        if (!$this->objUser->isLoggedIn()) { return '<p>Sign in to use bookmarks.</p>'; }
        $wanted = array_flip($this->objBookmarks->idsForUser($this->contextCode, $this->userId));
        $pages = $this->objContentOrder->getContextPages($this->contextCode, $chapterId);
        $html = '<ul class="bookmarkedpages">';
        foreach ($pages as $page) {
            if (!isset($wanted[$page['id']])) { continue; }
            $url = $this->uri(array('action' => 'viewpage', 'id' => $page['id']));
            $html .= '<li><a href="' . htmlspecialchars($url, ENT_QUOTES, 'UTF-8') . '">'
                . htmlspecialchars($page['menutitle'], ENT_QUOTES, 'UTF-8') . '</a></li>';
        }
        return $html . '</ul>';
    }

    protected function addContent($chapter, $parent = '')
    {
        if (!$this->objContextChapters->getChapter($chapter)) {
            throw new InvalidArgumentException('Chapter does not exist');
        }
        $course = $this->objContext->getContext($this->contextCode);
        $format = isset($course['delivery_format']) ? $course['delivery_format'] : 'standard';
        $this->setVar('contentTypes', $this->objContentTypes->all($format));
        $this->setVar('chapter', $chapter);
        $this->setVar('parent', $parent);
        $this->setLayoutTemplate(NULL);
        return 'contenttypepicker_tpl.php';
    }

    /**
     * Method to search for text within a context content
     * @param string $searchText Text to search for
     */
    protected function search($searchText) {
        $chapters = $this->objContextChapters->getContextChapters($this->contextCode);
        $this->setVarByRef('chapters', $chapters);

        $this->setLayoutTemplate('layout_firstpage_tpl.php');

        $objSearchResults = $this->getObject('searchresults', 'search');
        $searchResults = $objSearchResults->displaySearchResults($searchText, 'contextcontent', $this->contextCode);

        $this->setVarByRef('searchText', $searchText);
        $this->setVarByRef('searchResults', $searchResults);

        return 'searchresults_tpl.php';
    }

    /**
     * Method to get current session settings, as weill as list of chapters for a context
     * This is used for debugging purposes
     */
    public function home_debug() {
        echo '<pre>';
        //print_r($_SESSION);

        $numPages = $this->objContentOrder->getNumContextPages($this->contextCode);
        echo $numPages . '<br /><br />';

        $firstPage = $this->objContentOrder->getFirstPage($this->contextCode);
        print_r($firstPage);

        echo $this->contextCode;

        echo '<hr />';

        echo $this->objContextChapters->getContextChaptersSQL($this->contextCode);

        echo '<hr />';

        echo $this->objContextChapters->getNumContextChapters($this->contextCode);

        $results = $this->objContextChapters->getContextChapters($this->contextCode);

        print_r($results);
    }

    /**
     * Method to fix left right value - debugging purpose
     */
    protected function fixLeftRightValues() {
        $this->objContentOrder->rebuildContext($this->contextCode);
    }

    /**
     * Used to add the comment on the page
     *
     */
    public function addComment() {
        $comment = trim((string) $this->getParam('comment'));
        $userid = $this->objUser->userId();
        $pageid = (string) $this->getParam('pageid');
        if (!$this->objContentOrder->getPage($pageid, $this->contextCode)) {
            throw new InvalidArgumentException('Page does not exist in this course');
        }
        if (mb_strlen($comment) > 5000) {
            throw new InvalidArgumentException('Comment is too long');
        }
        if (!empty($comment) && !empty($userid) && !empty($pageid)) {
            $id = $this->objContextComments->addPageComment(
                $userid, $pageid, htmlspecialchars($comment, ENT_QUOTES, 'UTF-8')
            );
        }
        return $this->nextAction('viewpage', array('id' => $pageid));
    }

    /**
     * Used to display the latest presentations of a user RSS Feed
     *
     */
    public function viewRss() {
        $this->objFeedCreator = $this->getObject('feeder', 'feed');
        $format = 'RSS2.0'; // $this->getParam('feedselector');
        //grab the feed items
        $posts = $this->objContextChapters->getContextChapters($this->getParam('rss_contextcode'));
        error_log(var_export($posts, true));
        //set up the feed...
        $fullname = $this->getParam('title');
        //title of the feed
        $feedtitle = htmlentities($fullname);
        //description
        $feedDescription = "RSS2.0 Feed of the $fullname stream";

        //link back to the blog
        $feedLink = $this->objConfig->getSiteRoot() . "index.php?module=contextcontent&action=rsscall&rss_contextcode=" . $this->getParam('rss_contextcode');
        //sanitize the link
        $feedLink = htmlentities($feedLink);
        //set up the url
        $feedURL = $this->objConfig->getSiteRoot() . "index.php?module=contextcontent&action=rss";
        $feedURL = htmlentities($feedURL);
        //set up the feed
        $this->objFeedCreator->setupFeed(TRUE, $feedtitle, $feedDescription, $feedLink, $feedURL);
        //loop through the posts and create feed items from them
        foreach ($posts as $feeditems) {
            //use the post title as the feed item title
            $itemTitle = $fullname . ': ' . $feeditems['chaptertitle'];
            $itemLink = str_replace('&amp;', '&', $this->uri(array('action' => 'rsscall', 'id' => $feeditems['chapterid'], 'rss_contextcode' => $this->getParam('rss_contextcode'))));
            //description
            $itemDescription = substr(strip_tags($feeditems['introduction']), 0, 200) . '...';
            //where are we getting this from
            $itemSource = $this->objConfig->getSiteRoot() . "index.php?module=contextcontent&action=rsscall&rss_contextcode=" . $this->getParam('rss_contextcode');
            //feed author
            //$auth = $feeditem['from_user'];
            //$itemAuthor = htmlentities($auth."<$auth@capetown.peeps.co.za>");
            //add this item to the feed
            $this->objFeedCreator->addItem($itemTitle, $itemLink, $itemDescription, $itemSource, $itemAuthor);
        }
        //check which format was chosen and output according to that
        $feed = $this->objFeedCreator->output(); //defaults to RSS2.0
        echo htmlentities($feed);
        return;
    }

    /**
     * returns a template for uploading files used to create pages
     * @return <type>
     */
    function addPageFromFile($chapterid) {
        $this->setVarByRef('chapterid', $chapterid);
        return "uploadfile_tpl.php";
    }

    function createpagefromfile() {
        $id = $this->getParam("pagefile");
        $file = $this->objFiles->getFile($id);
        $chapterid = $this->getParam('chapterid');

        $filename = $file['name'];
        $filename = strtolower($filename);
        $exts = split("[/\\.]", $filename);
        $n = count($exts) - 1;
        $ext = $exts[$n];

        $path = $this->siteRoot . "/usrfiles/" . $file['path'];

        //   $content='[FILEPREVIEW id="'.$file['fileid'].'" comment="'.$filename.'" /]';
        $objFilePreview = $this->getObject('filepreview', 'filemanager');
        $content = $objFilePreview->previewFile($id);
        if ($ext == 'pdf') {
            $content = '[PDF]' . $path . '[/PDF]';
        }

        $menutitle = $this->getParam('menutitle');
        $headerscripts = '';
        $language = 'en';
        $pagecontent = $content;
        $parent = 'root';
        $chapter = stripslashes($chapterid);

        return $this->nextAction('savepage',
                array(
                    'menutitle' => $menutitle,
                    'headerscripts' => $headerscripts,
                    'language' => $language,
                    'pagecontent' => $pagecontent,
                    'parent' => $parent,
                    'chapter' => $chapter));
    }

    /**
     * handles the file upload
     */
    function uploadFile() {

        $pageid = $this->getParam('id');
        $context = $this->getParam('context');
        $chapterid = $this->getParam('chapterid');

        $objFileUpload = $this->getObject('uploadinput', 'filemanager');
        $objFileUpload->enableOverwriteIncrement = TRUE;
        $file = $objFileUpload->handleUpload('fileupload');
        $filename = $file['name'];
        $filename = strtolower($filename);
        $exts = split("[/\\.]", $filename);
        $n = count($exts) - 1;
        $ext = $exts[$n];

        $path = $this->siteRoot . "/usrfiles/" . $file['path'];

        // $content='[FILEPREVIEW id="'.$file['fileid'].'" comment="'.$filename.'" /]';
        $objFilePreview = $this->getObject('filepreview', 'filemanager');
        $content = $objFilePreview->previewFile($file['fileid']);
        if ($ext == 'pdf') {
            $content = '[PDF]' . $path . '[/PDF]';
        }

        $menutitle = $this->getParam('menutitle');
        $headerscripts = '';
        $language = 'en';
        $pagecontent = $content;
        $parent = 'root';
        $chapter = stripslashes($chapterid);

        return $this->nextAction('savepage',
                array(
                    'menutitle' => $menutitle,
                    'headerscripts' => $headerscripts,
                    'language' => $language,
                    'pagecontent' => $pagecontent,
                    'parent' => $parent,
                    'chapter' => $chapter));
    }

}

?>
