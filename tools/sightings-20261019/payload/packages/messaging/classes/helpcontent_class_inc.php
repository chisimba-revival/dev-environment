<?php
/** Shared contextual Help provider. @author Derek Keats */
if (empty($GLOBALS['kewl_entry_point_run'])) die('No direct access');
class helpcontent extends ChisimbaObject
{
    public function init() {}
    public function mayViewTopic($topic) {return $topic==='conversations'&&$this->getObject('user','security')->isLoggedIn();}
    public function getTopic($topic) {
        if(!$this->mayViewTopic($topic))return null;$v=$this->getObject('conversationview');
        return ['title'=>$v->text('title'),'summary'=>$v->text('intro'),'steps'=>[$v->text('help_access'),$v->text('help_send'),$v->text('help_reply'),$v->text('help_announcements'),$v->text('sighting_help')],
            'sections'=>[['heading'=>$v->text('read'),'body'=>$v->text('help_read').' '.$v->text('receipts_help')]]];
    }
}
