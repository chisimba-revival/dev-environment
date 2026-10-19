<?php
/** Plain-text, repeat-safe announcement messages shared by web and mobile. @author Derek Keats */
if (empty($GLOBALS['kewl_entry_point_run'])) die('No direct access');
class announcementchat extends dbTable
{
    public function init($tableName=null,$pearDb=null,$errorCallback='globalPearErrorCallback') {
        parent::init('tbl_announcements_chat_receipts',$pearDb,$errorCallback);
    }
    public function maySend($context,$site=false) {
        $user=$this->getObject('user','security');
        if(!$user->isLoggedIn())return false;
        if($site)return $user->isAdmin();
        return is_string($context)&&$context!==''&&strlen($context)<=32
            && (bool)$this->getObject('dbcontext','context')->getContextDetails($context)
            && ($user->isAdmin()||$user->isContextLecturer($user->userId(),$context)||$user->isCourseAdmin($context));
    }
    public function send($context,$site,$key,$body) {
        if(!$this->maySend($context,$site))throw new DomainException('unavailable');
        if(!is_string($key)||!preg_match('/^[a-f0-9-]{32,36}$/D',$key)||!is_string($body)
            ||!mb_check_encoding($body,'UTF-8')||trim($body)===''||strlen($body)>20000
            ||preg_match('/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/',$body))throw new DomainException('invalid');
        $actor=(string)$this->getObject('user','security')->userId();
        $receipt=hash('sha256',json_encode([$actor,$site?'site':'context:'.$context,$key]));
        return $this->withDatabaseLock('ann:'.substr($receipt,0,20),function()use($context,$site,$body,$actor,$receipt,$key){
            return $this->transactionWithSavepoint(function()use($context,$site,$body,$actor,$receipt,$key){
                if(!$this->maySend($context,$site))throw new DomainException('unavailable');
                $old=$this->selectPrepared('SELECT announcement_id,body_hash FROM tbl_announcements_chat_receipts WHERE id=?',[$receipt])[0]??null;
                if($old){if(!hash_equals($old['body_hash'],hash('sha256',$body)))throw new DomainException('conflict');return ['id'=>$old['announcement_id'],'submission_id'=>$key];}
                $id=bin2hex(random_bytes(16));$now=$this->getObject('timeanddateservice','timeanddate-service')->nowStorage();
                // Keep the existing announcement store canonical. No email or external delivery.
                $html=nl2br(htmlspecialchars($body,ENT_QUOTES,'UTF-8'),false);
                $title=mb_substr(trim(preg_replace('/\s+/u',' ',$body)),0,120);
                $this->executePrepared('INSERT INTO tbl_announcements (id,title,message,createdon,createdby,contextid,announcement_type,audience,publish_at,show_in_latest) VALUES (?,?,?,?,?,?,?,?,?,0)',[$id,$title,$html,$now,$actor,$site?'site':'context','general','everyone',$now]);
                if(!$site)$this->executePrepared('INSERT INTO tbl_announcements_context (id,announcementid,contextid) VALUES (?,?,?)',[bin2hex(random_bytes(16)),$id,$context]);
                $this->executePrepared('INSERT INTO tbl_announcements_chat_receipts (id,announcement_id,body_hash,sender_id,submission_id) VALUES (?,?,?,?,?)',[$receipt,$id,hash('sha256',$body),$actor,$key]);
                return ['id'=>$id,'submission_id'=>$key];
            });
        });
    }
    /** Canonical fields for both chat surfaces; preserve legacy announcement titles. */
    public function messages(array $rows) {
        $ids=array_column($rows,'id');$chat=[];$receipts=[];
        if($ids){$receipts=$this->selectPrepared('SELECT announcement_id,sender_id,submission_id FROM tbl_announcements_chat_receipts WHERE announcement_id IN ('.implode(',',array_fill(0,count($ids),'?')).')',$ids);$chat=array_column($receipts,'announcement_id');}
        $user=$this->getObject('user','security');$clock=$this->getObject('timeanddateservice','timeanddate-service');
        $messages=array_map(function($row)use($chat,$user,$clock,$receipts){
            $body=html_entity_decode(strip_tags(preg_replace('~</(?:p|div|li)>|<br\s*/?>\r?\n?~i',"\n",$row['message'])),ENT_QUOTES,'UTF-8');
            $created=$row['createdon'];
            if(!in_array($row['id'],$chat,true)){
                $body=$row['title']."\n".$body;
                // The legacy publisher used dbTable::now() (PHP local time). Chat sends store UTC.
                $created=$clock->toStorage($created,date_default_timezone_get())??$created;
            }
            $key=null;foreach($receipts as$r)if($r['announcement_id']===$row['id']&&(string)$r['sender_id']===(string)$user->userId())$key=$r['submission_id'];
            return ['submission_id'=>$key,'id'=>$row['id'],'sender_id'=>(string)$row['createdby'],'sender_name'=>$user->fullName($row['createdby']),'body'=>trim($body),'created_at'=>$created,'time_label'=>$clock->formatDateTime($created).' ['.$clock->siteTimezone().']'];
        },$rows);
        usort($messages,fn($a,$b)=>[$a['created_at'],$a['id']]<=>[$b['created_at'],$b['id']]);
        return $messages;
    }
}
