<?php

/**
 * Announcements Table
 *
 * This class contains a list of all db functions for the announcements module
 *
 * PHP version unknow
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


  /* ----------- data class extends dbTable for tbl_blog------------ */
// security check - must be included in all scripts

/**
 * Description for $GLOBALS
 * @global integer $GLOBALS['kewl_entry_point_run']
 * @name   $kewl_entry_point_run
 */
if (!$GLOBALS['kewl_entry_point_run']) {
    die("You cannot view this page directly");
}

define('CHISIMBA_ANNOUNCEMENTS_ADD', 0);
define('CHISIMBA_ANNOUNCEMENTS_UPDATE', 1);

class dbAnnouncements extends dbTable {
    /** Dependencies and state initialised by this component. */
    public $dbSysConfig;
    public $emailBody1;
    public $emailBody2;
    public $emailBody3;
    public $emailTitle;
    public $isAdmin;
    public $objIndexData;
    public $objLanguage;
    public $objUser;
    public $userId;


    /**
     * Constructor method to define the table
     */
    public function init($tableName = null, $pearDb = null, $errorCallback = 'globalPearErrorHandler') {
        parent::init('tbl_announcements');
        $this->objUser = $this->getObject('user', 'security');
        $this->userId = $this->objUser->userId();
        $this->isAdmin = $this->objUser->isAdmin();
        $this->loadClass("link", "htmlelements");
        $this->objIndexData = $this->getObject('indexdata', 'search');
        $this->objLanguage = $this->getObject("language", "language");
        $this->dbSysConfig = $this->getObject('dbsysconfig', 'sysconfig');
        $this->emailTitle = $this->objLanguage->languageText('mod_announcements_emailtitle', 'announcements', 'Important announcement');
        $this->emailBody1 = $this->objLanguage->languageText('mod_announcements_emailbody1', 'announcements', 'has posted an important new announcement titled');
        $this->emailBody2 = $this->objLanguage->languageText('mod_announcements_emailbody2', 'announcements', 'has updated  announcement titled');
        $this->emailBody3 = $this->objLanguage->languageText('mod_announcements_emailbody3', 'announcements', 'To view the announcement, click on this link');
        //$objMailer = $this->getObject('email', 'mail');
    }

    /**
     * Method to add an announcment
     * @param string $title Title of the Announcement
     * @param string $message Message of the Announcement
     * @param string $type Type of the Announcement - either site or context
     * @param array $contexts Type of the Announcement - If type is context, list of contexts announcement is for
     * @param boolean $email Should Announcement be emailed to users
     * @return string Insert Id
     */
    public function addAnnouncement($title, $message, $type='site', $contexts=array(), $email=TRUE, array $metadata=array()) {
        // Insert
        $messageId = $this->insert(array(
                    'title' => $title,
                    'message' => $message,
                    //'title' => $title,
                    'createdon' => $this->now(),
                    'createdby' => $this->objUser->userId(),
                    'contextid' => $type,
                    'announcement_type' => $metadata['announcement_type'] ?? 'general',
                    'audience' => $metadata['audience'] ?? 'everyone',
                    'resource_url' => $metadata['resource_url'] ?? '',
                    'publish_at' => $metadata['publish_at'] ?? $this->now(),
                    'expires_at' => $metadata['expires_at'] ?? NULL,
                    'show_in_latest' => !empty($metadata['show_in_latest']) ? 1 : 0
                ));

        if ($type == 'site') {
            // Site
            if ($messageId != FALSE) {
                $emailList = $this->getSiteRecipients();

                // Add to Search
                $this->addAnnouncementToSearchIndex($messageId, $title, $message, 'root');
                // Optimize Search
                $this->objIndexData->optimize();

                if ($email) {
                    $this->buildEmail($messageId, CHISIMBA_ANNOUNCEMENTS_ADD, $title, $message, $emailList);
                }
            }

        } else {
            // Context(s)
            if ($messageId != FALSE) {
                $emailList = array();
                $contextcodeList = "";
                foreach ($contexts as $context) {
                    $this->addMessageToContext($messageId, $context);
                    $emailList = array_merge($emailList, $this->getContextRecipients($context));
                    $contextcodeList.=$context . " ";
                    $this->addAnnouncementToSearchIndex($messageId, $title, $message, $context);
                }

                // Optimize Search
                $this->objIndexData->optimize();

                if ($email) {
                    $this->buildEmail($messageId, CHISIMBA_ANNOUNCEMENTS_ADD, $title, $message, $emailList);
                }
            }
        }
        return $messageId;
    }

    public function updateAnnouncement($id, $title, $message, $type='site', $contexts=array(), $email=FALSE) {
        if ($type == 'context') {
            $this->removeContextAnnouncement($id);
        }
        $result = $this->update('id', $id, array(
                    'title' => $title,
                    'message' => $message,
                    'title' => $title,
                    'createdon' => $this->now(),
                    'createdby' => $this->objUser->userId(),
                    'contextid' => $type,
                ));
        if ($type == 'site') {
            // Site
            if ($result != FALSE) {
                $emailList = $this->getSiteRecipients();

                // Add to Search
                $this->addAnnouncementToSearchIndex($id, $title, $message, 'root');
                // Optimize Search
                $this->objIndexData->optimize();

                if ($email) {
                    $this->buildEmail($id, CHISIMBA_ANNOUNCEMENTS_UPDATE, $title, $message, $emailList);
                }
            }
        } else {
            // Context(s)
            if ($result != FALSE) {
                $emailList = array();
                foreach ($contexts as $context) {
                    $this->addMessageToContext($id, $context);
                    $emailList = array_merge($emailList, $this->getContextRecipients($context));
                    $this->addAnnouncementToSearchIndex($id, $title, $message, $context);
                }

                // Optimize Search
                $this->objIndexData->optimize();

                if ($email) {
                    $this->buildEmail($id, CHISIMBA_ANNOUNCEMENTS_UPDATE, $title, $message, $emailList);
                }
            }
        }
    }

    /** Course removal preserves announcements also assigned to other courses. */
    public function contextDeletionTables() {
        return ['tbl_announcements','tbl_announcements_context','tbl_announcements_chat_receipts'];
    }
    public function deleteForContext($code) {
        $documents=[];
        $rows=$this->selectPrepared('SELECT a.id, a.contextid FROM tbl_announcements a JOIN tbl_announcements_context c ON c.announcementid=a.id WHERE c.contextid=? FOR UPDATE',[$code]);
        $this->executePrepared('DELETE FROM tbl_announcements_context WHERE contextid=?',[$code]);
        foreach ($rows as $row) {
            $documents[]='announcement_entry_'.$code.'_'.$row['id'];
            if ($row['contextid']!=='context' || $this->selectPrepared('SELECT id FROM tbl_announcements_context WHERE announcementid=?',[$row['id']])) continue;
            $this->executePrepared('DELETE FROM tbl_announcements_chat_receipts WHERE announcement_id=?',[$row['id']]);
            $this->executePrepared('DELETE FROM tbl_announcements WHERE id=?',[$row['id']]);
            $documents[]='announcement_entry_'.$row['id'];
        }
        return $documents;
    }

    public function deleteAnnouncement($id) {
        $announcement = $this->getMessage($id);
        if ($announcement == FALSE) {
            return FALSE;
        } else {
            if ($announcement['contextid'] == 'context') {
                $this->removeContextAnnouncement($id);
            }
            $this->delete('id', $id);
            $this->objIndexData->removeIndex('announcement_entry_' . $id);
            return TRUE;
        }
    }

    /**
     * Method to remove a context announcement
     * This function removes the search entry as well as link to db record
     *
     * @param string $id Record Id of Announcement
     *
     */
    private function removeContextAnnouncement($id)
    {
        parent::init('tbl_announcements_context');
        $result = $this->getAll(" WHERE announcementid = '{$id}' ");
        if ((is_countable($result) ? count($result) : 0) > 0) {
            foreach ($result as $context) {
                $this->objIndexData->removeIndex('announcement_entry_' . $context['contextid'] . '_' . $id);
                $this->delete('id', $context['id']);
            }
        }
        parent::init('tbl_announcements');
    }

    private function addAnnouncementToSearchIndex($id, $title, $message, $context)
    {
        // Prep Data
        if ($context == 'root') {
            $docId = 'announcement_entry_' . $id;
        } else {
            $docId = 'announcement_entry_' . $context . '_' . $id;
        }
        $docDate = $this->now();
        $url = $this->uri(array('action' => 'view', 'id' => $id), 'announcements');
        $title = $title;
        $contents = $title . ': ' . $message;
        $teaser = $message;
        $module = 'announcements';
        $userId = $this->objUser->userId();
        // Add to Index
        $this->objIndexData->luceneIndex($docId, $docDate, $url, $title, $contents, $teaser, $module, $userId, NULL, NULL, $context, 'noworkgroup', NULL, NULL, NULL, NULL, FALSE); // Turn off optimizing
    }

    /**
     * Method to link an announcement to a context
     *
     * @param string $messageId Record Id of the message
     * @param string $context Context Code
     *
     * @return insert id
     */
    private function addMessageToContext($messageId, $context) {
        parent::init('tbl_announcements_context');
        $result = $this->insert(array('announcementid' => $messageId, 'contextid' => $context));
        parent::init('tbl_announcements');
        return $result;
    }

    private function buildEmail($messageId, $emailType, $title, $message, $emailList)
    {
        switch ($emailType) {
            case CHISIMBA_ANNOUNCEMENTS_ADD:
                $emailBody = $this->emailBody1;
                break;
            case CHISIMBA_ANNOUNCEMENTS_UPDATE:
                $emailBody = $this->emailBody2;
                break;
            default:
                $emailBody = '';
        } // switch
        $link = new link($this->uri(array("action" => "view", "id" => $messageId)));
        $title_ = $this->emailTitle . ": '$title'";
        $message_ = $this->objUser->fullname() . " " . $emailBody . " '$title' ";
        if($this->dbSysConfig->getValue('SEND_ANN_BODY', 'announcements') == "TRUE"){
            $message_ .= ": " . $message . " ";
        }
        $message_ .= $this->emailBody3 . ": " . $link->href;
        $this->sendEmail($title_, $message_, $emailList);
    }
    /**
     * Method to email an announcement to users
     *
     * @param string $title Title of the announcement
     * @param string $message Message of the announceme nt
     * @param array $recipients List of Recipients (array of email addresses);
     */
    private function sendEmail($title, $message, $recipients) {
        //$recipients = array_unique($recipients);
        $objMailer = $this->getObject('email', 'mail');
        //$objMailer = $this->getObject('mailer', 'mail');
        //$message = trim($message, "\x00..\x1F");
        $message = preg_replace('/[\x00-\x1F]/', '', $message);
        $message = html_entity_decode($message);
        $message = strip_tags($message);
        $list = array();

        foreach ($recipients as $recipient) {
            $list[] = $recipient['emailaddress'];
        }
        //$objMailer->setValue('to', $list);
        $objMailer->setValue('to', $this->objUser->email());
        $objMailer->setValue('bcc', $list);
        $objMailer->setValue('from', $this->objUser->email());
        $objMailer->setValue('fromName', $this->objUser->fullname());
        $objMailer->setValue('subject', $title);
        $objMailer->setValue('body', $message);
        $objMailer->setValue('AltBody', $message);
        $objMailer->send();
    }

    /**
     * Method to get the list of email addresses of all users for site announcements
     * @return array Email Addresses of all Users
     */
    private function getSiteRecipients() {
        $users = $this->objUser->getAll();
        return $users;
    }

    /**
     * Method to get the list of email addresses for users belong to a context
     * @param string $contextCode Context Code
     * @return array Email Addresses of Context Users
     */
    private function getContextRecipients($contextCode) {
        $objGroups = $this->getObject('managegroups', 'contextgroups');
        $lecturers = $objGroups->contextUsers('Lecturers', $contextCode, array('emailAddress'));
        $students = $objGroups->contextUsers('Students', $contextCode, array('emailAddress'));
        $guests = $objGroups->contextUsers('Guests', $contextCode, array('emailAddress'));
        return array_merge($lecturers, $students, $guests);
    }

    /**
     * Method to get an Announcement Message
     * @param string $id Record Id of Announcement
     * @return array Record Details
     */
    public function getMessage($id) {
        return $this->getRow('id', $id);
    }

    /**
     * Method to get a list of context announcements
     *
     * @param array $contexts List of contexts if required
     * @param int $limit Number of Results
     * @param int $page Page of Results
     *
     * @return array List of announcements
     */
    public function getAllAnnouncements($contexts, $limit=NULL, $page=NULL) {
        $where = '';
        $or = '';
        if (!empty($this->userId)) {
            if ((is_countable($contexts) ? count($contexts) : 0) > 0) {
                foreach ($contexts as $context) {
                    $where .= "{$or} tbl_announcements_context.contextid = '{$context}'";
                    $or = " OR ";
                }
            }
            if ($this->isAdmin) {
                $where .= "{$or} tbl_announcements.contextid = 'site'";
            }
        } else {
            $where .= "{$or} tbl_announcements.contextid != 'context'";
        }
        if ($where != '') {
            $where = 'WHERE ' . $where;
        }
        $sql = "SELECT DISTINCT tbl_announcements.id, title, createdon, tbl_announcements.contextid, message, createdby FROM tbl_announcements
        LEFT JOIN tbl_announcements_context ON ( tbl_announcements_context.announcementid = tbl_announcements.id )
                {$where}
        ORDER BY createdon DESC ";
        // AND createdby = '{$this->userId}'
        if ($limit != NULL && $page != NULL) {

            $page = $page * $limit;

            $sql .= " LIMIT {$page}, {$limit}";
        }
        return $this->getArray($sql);
    }

    /** Return active site and context announcements visible to this user. */
    public function getVisibleAnnouncements(array $contexts,array $audiences,$limit,$offset,$onlyScope=null) {
        if(!$audiences)return [];
        $scope=["a.contextid='site'"];foreach($contexts as $context)$scope[]='ac.contextid=?';
        if(!in_array($onlyScope,[null,'site','context'],true))throw new InvalidArgumentException('Invalid announcement scope');
        $scopeFilter=$onlyScope===null?'':($onlyScope==='site'?" AND a.contextid='site'":" AND a.contextid='context'");
        $params=array_merge(array_values($contexts),array_values($audiences),[$this->now(),$this->now()]);
        $limit=max(1,min(100,(int)$limit));$offset=max(0,(int)$offset);
        return $this->selectPrepared('SELECT DISTINCT a.* FROM tbl_announcements a LEFT JOIN tbl_announcements_context ac ON ac.announcementid=a.id WHERE ('.implode(' OR ',$scope).')'.$scopeFilter.' AND a.audience IN ('.implode(',',array_fill(0,count($audiences),'?')).') AND (a.publish_at IS NULL OR a.publish_at<=?) AND (a.expires_at IS NULL OR a.expires_at>?) ORDER BY COALESCE(a.publish_at,a.createdon) DESC LIMIT '.$offset.','.$limit,$params);
    }

    /**
     * Method to get a list of site announcements
     *
     * @param int $limit Number of Results
     * @param int $page Page of Results
     *
     * @return array List of announcements
     */
    public function getSiteAnnouncements($limit=NULL, $page=NULL) {

        $sql = "SELECT DISTINCT tbl_announcements.id, title, createdon, tbl_announcements.contextid, message, createdby FROM tbl_announcements
        WHERE (contextid = 'site')
        ORDER BY createdon DESC ";


        if (is_int($limit) && is_int($page)) {

            $sql .= " LIMIT {$page}, {$limit}";
        }

//echo $sql;

        return $this->getArray($sql);
    }

    /** Return active site announcements addressed to authors for the sidebar. */
    public function getLatestAuthorUpdates($limit=3) {
        $limit=max(1,min(10,(int)$limit));$now=$this->now();$cutoff=date('Y-m-d H:i:s',strtotime($now)-(7*86400));
        return $this->selectPrepared("SELECT * FROM tbl_announcements WHERE contextid='site' AND audience='authors' AND COALESCE(publish_at,createdon)>=? AND (publish_at IS NULL OR publish_at<=?) AND (expires_at IS NULL OR expires_at>?) ORDER BY COALESCE(publish_at,createdon) DESC LIMIT ".$limit,[$cutoff,$now,$now]);
    }

    /** Resolve active notification recipients for a site or selected contexts. */
    public function recipientUserIds($audience, array $contexts=array()) {
        $audience=(string)$audience;$join='';$params=[];$where='u.isactive=1';
        if($audience!=='everyone'||$contexts){$join=' JOIN tbl_perms_perm_users pu ON pu.auth_user_id=u.userid JOIN tbl_perms_groupusers gu ON gu.perm_user_id=pu.perm_user_id JOIN tbl_perms_groups g ON g.group_id=gu.group_id';}
        if($audience==='admins')$where.=" AND g.group_define_name='Site Admin'";
        elseif($audience==='authors')$where.=" AND (g.group_define_name='Lecturers' OR g.group_define_name LIKE '%^Lecturers')";
        elseif($audience==='readonlys')$where.=" AND (g.group_define_name='Students' OR g.group_define_name LIKE '%^Students')";
        elseif($audience!=='everyone')return array();
        if($contexts){$parts=array();foreach(array_unique($contexts) as $code){$parts[]='g.group_define_name LIKE ?';$params[]=(string)$code.'^%';}$where.=' AND ('.implode(' OR ',$parts).')';}
        $rows=$this->selectPrepared("SELECT DISTINCT u.userid FROM tbl_users u{$join} WHERE {$where} ORDER BY u.userid",$params);
        return array_values(array_filter(array_map(fn($row)=>(string)($row['userid']??''),$rows)));
    }

    /** Quote one scalar through the active framework database adapter. */


    /**
     * Method to get a list of announcements for a particular context
     *
     * @param string $context Context Code
     * @param int $limit Number of Results
     * @param int $page Page of Results
     *
     * @return array List of announcements
     */
    public function getContextAnnouncements($context, $limit=NULL, $page=NULL) {

        $sql = "SELECT DISTINCT tbl_announcements.id, title, createdon, tbl_announcements.contextid, message, createdby FROM tbl_announcements
        LEFT JOIN tbl_announcements_context ON ( tbl_announcements_context.announcementid = tbl_announcements.id )
        WHERE (tbl_announcements_context.contextid = '{$context}')
        ORDER BY createdon DESC ";

        if ($limit != NULL && $page != NULL) {

            $page = $page * $limit;

            $sql .= " LIMIT {$page}, {$limit}";
        }

//echo $sql;

        return $this->getArray($sql);
    }

    /**
     * Method to get the number of announcements in particular contexts
     *
     * @param array $contexts Context Codes
     * @return int Number of announcements
     */
    public function getNumAnnouncements($contexts) {
        $where = '';
        $or = '';
        if (!empty($this->userId)) {
            if ((is_countable($contexts) ? count($contexts) : 0) > 0) {
                foreach ($contexts as $context) {
                    $where .= "{$or} tbl_announcements_context.contextid = '{$context}'";
                    $or = " OR ";
                }
            }

            if ($this->isAdmin) {
                $where .= "{$or} tbl_announcements.contextid = 'site'";
            }
        } else {
            $where .= "{$or} tbl_announcements.contextid != 'context'";
        }
        if ($where != '') {
            $where = 'WHERE ' . $where;
        }

        $sql = "SELECT count( DISTINCT tbl_announcements.id ) AS recordcount FROM tbl_announcements
        LEFT JOIN tbl_announcements_context ON ( tbl_announcements_context.announcementid = tbl_announcements.id )
                {$where}
        ORDER BY createdon DESC ";
//AND tbl_announcements.createdby = '{$this->userId}'
        $result = $this->getArray($sql);

        return $result[0]['recordcount'];
    }

    /**
     * Method to get the number of announcements in a particular context
     *
     * @param string $context Context Code
     * @return int Number of announcements
     */
    public function getNumContextAnnouncements($context) {

        $sql = "SELECT count( DISTINCT tbl_announcements.id ) AS recordcount FROM tbl_announcements
        INNER JOIN tbl_announcements_context ON ( tbl_announcements_context.announcementid = tbl_announcements.id )
        WHERE (tbl_announcements_context.contextid = '{$context}')
        ORDER BY createdon DESC ";

        $result = $this->getArray($sql);

        return $result[0]['recordcount'];
    }

    /**
     * Method to get the contexts a message is linked to
     * @param string $messageId Message Id
     * @return array List of Contexts
     */
    public function getMessageContexts($messageId) {
        parent::init('tbl_announcements_context');

        $result = $this->getAll(" WHERE announcementid = '{$messageId}' ");

        parent::init('tbl_announcements');

        $return = array();

        if ((is_countable($result) ? count($result) : 0) > 0) {
            foreach ($result as $context) {
                $return[] = $context['contextid'];
            }
        }

        return $return;
    }

}

?>
