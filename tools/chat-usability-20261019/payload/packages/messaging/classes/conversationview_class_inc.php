<?php
/** Language and announcement composition for the native conversation surface. @author Derek Keats */
if (empty($GLOBALS['kewl_entry_point_run'])) die('No direct access');
class conversationview extends ChisimbaObject
{
    public function init() {}
    public function text($key) {$text=$this->getObject('language','language')->code2Txt('mod_messaging_v2_'.$key,'messaging');$text=html_entity_decode($text,ENT_QUOTES,'UTF-8');return mb_strtoupper(mb_substr($text,0,1)).mb_substr($text,1);}
    /** Render UTC storage in the configured site timezone, independently of the device. */
    public function timestamp($stored) {
        $clock=$this->getObject('timeanddateservice','timeanddate-service');
        $local=$clock->inTimezone($stored);
        if($local===null)return '';
        $format=$this->getObject('language','language')->languageText('mod_messaging_v2_date_format','messaging');
        return $local->format($format).' ['.$clock->siteTimezone().']';
    }
    public function entryLink() {
        if(!$this->getObject('user','security')->isLoggedIn())return '';
        $context=$this->getObject('dbcontext','context')->getContextCode();
        $url=$this->uri(['action'=>'view'],'messaging');
        return '<a class="button" href="'.htmlspecialchars($url,ENT_QUOTES,'UTF-8').'">'.$this->getObject('iconservice','ui')->render('message-circle',['decorative'=>true]).'<span>'.htmlspecialchars($this->text('title'),ENT_QUOTES,'UTF-8').'</span></a>';
    }
    public function announcements($context,$site=false) {
        $user=$this->getObject('user','security');
        if(!$user->isLoggedIn())throw new DomainException('unavailable');
        if(!$site&&!$this->getObject('conversationpolicy')->mayRead($context))throw new DomainException('unavailable');
        $membership=$this->getObject('usercontext','context');$audiences=['everyone'];
        if($user->isAdmin())$audiences[]='admins';
        if($site?$membership->getContextWhereLecturer($user->userId()):in_array($context,(array)$membership->getContextWhereLecturer($user->userId()),true))$audiences[]='authors';
        if($site?$membership->getContextWhereStudent($user->userId()):in_array($context,(array)$membership->getContextWhereStudent($user->userId()),true))$audiences[]='readonlys';
        return $this->getObject('dbannouncements','announcements')->getVisibleAnnouncements($site?[]:[$context],$audiences,50,0,$site?'site':'context');
    }
}
