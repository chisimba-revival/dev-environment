<?php
/** One photo and caption, shared by web and mobile, with retry-safe receipts.
 * A channel lock serialises inserts even on legacy catalogues without unique indexes.
 * @author Derek Keats
 */
if (empty($GLOBALS['kewl_entry_point_run'])) die('No direct access');
class sightingservice extends ChisimbaObject
{
    private $store; private $policy; private $images;
    public function init() {
        $this->store=$this->getObject('conversationstore');$this->policy=$this->getObject('conversationpolicy');
        $this->images=$this->getObject('privateimageasset','filemanager');
    }
    private function channel($context) {
        $channel=$this->getObject('conversationservice')->forContext($context);
        if(!$channel)throw new DomainException('unavailable');return $channel;
    }
    public function history($context) {
        $channel=$this->channel($context);
        $rows=$this->store->selectPrepared('SELECT id,sender_id,submission_id,body,width,height,created_at FROM tbl_messaging_sightings_v2 WHERE channel_id=? ORDER BY created_at DESC,id DESC LIMIT 20',[$channel['id']]);
        foreach($rows as &$row){$row['sender_name']=$this->getObject('user','security')->fullName($row['sender_id']);if($row['sender_id']!==$this->policy->actor())unset($row['submission_id']);}
        return array_reverse($rows);
    }
    public function send($context,$key,$body,$encoded) {
        $channel=$this->channel($context);
        if(!empty($this->store->selectPrepared('SELECT @@in_transaction AS active')[0]['active']))throw new RuntimeException('Sighting upload requires its own transaction');
        if(!is_string($key)||!preg_match('/^[a-f0-9-]{32,36}$/D',$key)||!is_string($body)||trim($body)===''||strlen($body)>4000||!mb_check_encoding($body,'UTF-8')||preg_match('/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/',$body))throw new DomainException('invalid');
        $image=$this->images->prepare($encoded);$created=null;
        try{return $this->store->locked($channel['id'],function($locked)use($context,$key,$body,$image,&$created){
            $this->channel($context);$actor=$this->policy->actor();
            $old=$this->store->selectPrepared('SELECT id,submission_id,body,image_digest FROM tbl_messaging_sightings_v2 WHERE channel_id=? AND sender_id=? AND submission_id=?',[$locked['id'],$actor,$key])[0]??null;
            if($old){if(!hash_equals($old['body'],$body)||!hash_equals($old['image_digest'],$image['digest']))throw new DomainException('conflict');return ['id'=>$old['id'],'submission_id'=>$old['submission_id']];}
            $id=bin2hex(random_bytes(16));$this->images->put('messaging',hash('sha256',$context),$id,$image['bytes']);$created=$id;
            $this->store->executePrepared('INSERT INTO tbl_messaging_sightings_v2 (id,channel_id,sender_id,submission_id,body,image_digest,width,height,created_at) VALUES (?,?,?,?,?,?,?,?,?)',[$id,$locked['id'],$actor,$key,$body,$image['digest'],$image['width'],$image['height'],gmdate('Y-m-d H:i:s')]);
            return ['id'=>$id,'submission_id'=>$key];
        });}catch(Throwable $error){if($created!==null&&!$this->store->selectPrepared('SELECT id FROM tbl_messaging_sightings_v2 WHERE id=?',[$created]))$this->images->remove('messaging',hash('sha256',$context),$created);throw $error;}
    }
    /** Private bytes never have a static/public URL, including in a public course. */
    public function image($context,$id) {
        $channel=$this->channel($context);
        if(!is_string($id)||!preg_match('/^[a-f0-9]{32}$/D',$id))throw new DomainException('unavailable');
        if(!$this->store->selectPrepared('SELECT id FROM tbl_messaging_sightings_v2 WHERE channel_id=? AND id=?',[$channel['id'],$id]))throw new DomainException('unavailable');
        return $this->images->read('messaging',hash('sha256',$context),$id);
    }
}
