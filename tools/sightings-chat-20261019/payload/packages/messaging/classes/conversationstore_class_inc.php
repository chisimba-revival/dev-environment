<?php
/** Transactional persistence for context conversations; legacy records are separate. @author Derek Keats */
if (empty($GLOBALS['kewl_entry_point_run'])) die('No direct access');
class conversationstore extends dbTable
{
    public function init($tableName=null,$pearDb=null,$errorCallback='globalPearErrorCallback') { parent::init('tbl_messaging_channels_v2',$pearDb,$errorCallback); }
    /** Tables owned by this participant in atomic course deletion. */
    public function contextDeletionTables() {
        return array_merge(array_map(fn($name)=>'tbl_messaging_'.$name.'_v2', ['channels','posts','replies','reads','deliveries','bans','sightings']),['tbl_messaging_image_cleanup']);
    }
    public function deleteForContext($code) {
        foreach ($this->selectPrepared('SELECT id FROM tbl_messaging_channels_v2 WHERE context_code=? FOR UPDATE',[$code]) as $channel) {
            foreach($this->selectPrepared('SELECT id FROM tbl_messaging_sightings_v2 WHERE channel_id=? AND width>0',[$channel['id']]) as $image)
                $this->executePrepared('INSERT INTO tbl_messaging_image_cleanup (id,scope_hash) VALUES (?,?)',[$image['id'],hash('sha256',$code)]);
            foreach (['replies','posts','reads','deliveries','bans','sightings'] as $name) {
                $this->executePrepared('DELETE FROM tbl_messaging_'.$name.'_v2 WHERE channel_id=?',[$channel['id']]);
            }
            $this->executePrepared('DELETE FROM tbl_messaging_channels_v2 WHERE id=?',[$channel['id']]);
        }
        return [];
    }
    /** Run only after the outermost deletion commits; errors retain the cleanup receipt. */
    public function afterContextDeletion() {
        if(!empty($this->selectPrepared('SELECT @@in_transaction AS active')[0]['active']))return;
        return $this->withDatabaseLock('msg:images:cleanup',function(){
        foreach($this->selectPrepared('SELECT id,scope_hash FROM tbl_messaging_image_cleanup LIMIT 100') as $row){
            $this->getObject('privateimageasset','filemanager')->remove('messaging',$row['scope_hash'],$row['id']);
            $this->executePrepared('DELETE FROM tbl_messaging_image_cleanup WHERE id=?',[$row['id']]);
        }
        });
    }
    public function channel($id) {return $this->selectPrepared('SELECT * FROM tbl_messaging_channels_v2 WHERE id=?',[$id])[0]??null;}
    public function create($context) {
        return $this->transactionWithSavepoint(function()use($context){
            if (!$this->selectPrepared('SELECT contextcode FROM tbl_context WHERE contextcode=? FOR UPDATE',[$context])) throw new DomainException('unavailable');
            $id=substr(hash('sha256','context-discussion:'.$context),0,32);
            $this->executePrepared('INSERT INTO tbl_messaging_channels_v2 (id,context_code,last_sequence) VALUES (?,?,0) ON DUPLICATE KEY UPDATE id=id',[$id,$context]);
            return $id;
        });
    }
    public function locked($id,callable $operation) {
        return $this->transactionWithSavepoint(function()use($id,$operation){
            $channel=$this->selectPrepared('SELECT * FROM tbl_messaging_channels_v2 WHERE id=? FOR UPDATE',[$id])[0]??null;
            if(!$channel)throw new DomainException('unavailable');
            return $operation($channel);
        });
    }
    public function banned($channel,$user) {return (bool)$this->selectPrepared('SELECT id FROM tbl_messaging_bans_v2 WHERE channel_id=? AND user_id=?',[$channel,$user]);}
    public function receipt($channel,$user,$key) {return $this->selectPrepared('SELECT * FROM tbl_messaging_posts_v2 WHERE channel_id=? AND sender_id=? AND submission_id=?',[$channel,$user,$key])[0]??null;}
    public function append($channel,$actor,$key,$body,$sequence,$replyTo='') {
        $row=['id'=>bin2hex(random_bytes(16)),'channel_id'=>$channel,'sender_id'=>$actor,'submission_id'=>$key,'body'=>$body,'sequence_no'=>$sequence,'created_at'=>gmdate('Y-m-d H:i:s')];
        $this->executePrepared('INSERT INTO tbl_messaging_posts_v2 (id,channel_id,sender_id,submission_id,body,sequence_no,created_at) VALUES (?,?,?,?,?,?,?)',array_values($row));
        $this->executePrepared('UPDATE tbl_messaging_channels_v2 SET last_sequence=? WHERE id=?',[$sequence,$channel]);
        if($replyTo!=='')$this->executePrepared('INSERT INTO tbl_messaging_replies_v2 (id,channel_id,reply_to) VALUES (?,?,?)',[$row['id'],$channel,$replyTo]);
        return $row;
    }
    public function history($channel,$before,$limit) {
        return array_reverse($this->selectPrepared('SELECT p.*, t.id AS quoted_id, t.sender_id AS quoted_sender_id, t.body AS quoted_body FROM tbl_messaging_posts_v2 p LEFT JOIN tbl_messaging_replies_v2 r ON r.id=p.id AND r.channel_id=p.channel_id LEFT JOIN tbl_messaging_posts_v2 t ON t.id=r.reply_to AND t.channel_id=p.channel_id WHERE p.channel_id=? AND p.sequence_no<? ORDER BY p.sequence_no DESC LIMIT '.(int)$limit,[$channel,$before]));
    }
    public function post($channel,$id) {return $this->selectPrepared('SELECT * FROM tbl_messaging_posts_v2 WHERE channel_id=? AND id=?',[$channel,$id])[0]??null;}
    public function replyTarget($channel,$id) {return (string)($this->selectPrepared('SELECT reply_to FROM tbl_messaging_replies_v2 WHERE channel_id=? AND id=?',[$channel,$id])[0]['reply_to']??'');}
    public function markRead($channel,$actor,$sequence) {
        $this->markPosition('tbl_messaging_reads_v2',$channel,$actor,$sequence);
    }
    public function readPosition($channel,$actor) {return (int)($this->selectPrepared('SELECT MAX(sequence_no) AS sequence_no FROM tbl_messaging_reads_v2 WHERE channel_id=? AND user_id=?',[$channel,$actor])[0]['sequence_no']??0);}
    /** Receipt positions are monotonic and never include the sender's own acknowledgement. */
    public function markDelivered($channel,$actor,$sequence) {
        $this->markPosition('tbl_messaging_deliveries_v2',$channel,$actor,$sequence);
    }
    public function receiptPositions($channel,$actor) {
        $positions=[];
        foreach(['delivered'=>'tbl_messaging_deliveries_v2','read'=>'tbl_messaging_reads_v2'] as $kind=>$table)
            $positions[$kind]=(int)($this->selectPrepared('SELECT MAX(sequence_no) AS position FROM '.$table.' WHERE channel_id=? AND user_id<>?',[$channel,$actor])[0]['position']??0);
        return $positions;
    }
    /** Called under the service's channel lock. Legacy catalogue indexes are not unique.
     * Update existing positions (including historical duplicates) without losing progress.
     */
    private function markPosition($table,$channel,$actor,$sequence) {
        $exists=$this->selectPrepared('SELECT id FROM '.$table.' WHERE channel_id=? AND user_id=?',[$channel,$actor]);
        if($exists)$this->executePrepared('UPDATE '.$table.' SET sequence_no=GREATEST(sequence_no,?) WHERE channel_id=? AND user_id=?',[$sequence,$channel,$actor]);
        else $this->executePrepared('INSERT INTO '.$table.' (id,channel_id,user_id,sequence_no) VALUES (?,?,?,?)',[substr(hash('sha256',$channel.':'.$actor),0,32),$channel,$actor,$sequence]);
    }
}
