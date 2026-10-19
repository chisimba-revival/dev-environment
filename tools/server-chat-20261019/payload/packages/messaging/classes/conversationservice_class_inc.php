<?php
/** Shared web/mobile domain boundary: current access and repeat-safe submission. @author Derek Keats */
if (empty($GLOBALS['kewl_entry_point_run'])) die('No direct access');
class conversationservice extends ChisimbaObject
{
    private $store; private $policy;
    public function init() {$this->store=$this->getObject('conversationstore');$this->policy=$this->getObject('conversationpolicy');}
    public function forContext($context) {
        if(!$this->policy->mayRead($context))throw new DomainException('unavailable');
        $channel=$this->store->channel(substr(hash('sha256','context-discussion:'.$context),0,32));
        if($channel)$this->access($channel);
        return $channel;
    }
    public function create($context) {
        if(!$this->policy->mayModerate($context))throw new DomainException('unavailable');
        return $this->store->create($context);
    }
    private function access($channel) {
        if(!$channel || !$this->policy->mayRead($channel['context_code'])
            || $this->store->banned($channel['id'],$this->policy->actor()))throw new DomainException('unavailable');
    }
    public function history($id,$before=0) {
        $channel=$this->store->channel($id);$this->access($channel);
        if(!is_int($before)||$before<0)throw new DomainException('invalid');
        $rows=$this->store->history($id,$before?:((int)$channel['last_sequence']+1),51);
        // Only expose aggregate receipt state for the requesting sender's messages.
        $positions=$this->store->receiptPositions($id,$this->policy->actor());
        foreach($rows as &$row)if($row['sender_id']===$this->policy->actor())$row['receipt']=$positions['read']>=$row['sequence_no']?'read':($positions['delivered']>=$row['sequence_no']?'delivered':'sent');
        unset($row);
        $older=count($rows)>50;if($older)array_shift($rows);
        return ['channel'=>$channel,'messages'=>$rows,'older'=>$older&&$rows?(int)$rows[0]['sequence_no']:null,
            'unread'=>max(0,(int)$channel['last_sequence']-$this->store->readPosition($id,$this->policy->actor()))];
    }
    public function send($id,$key,$body) {
        if(!is_string($key)||!preg_match('/^[a-f0-9-]{32,36}$/D',$key)||!is_string($body)
            ||!mb_check_encoding($body,'UTF-8')||trim($body)===''||strlen($body)>20000
            ||preg_match('/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/',$body))throw new DomainException('invalid');
        $this->access($this->store->channel($id));
        return $this->store->locked($id,function($channel)use($id,$key,$body){
            $this->access($channel);$actor=$this->policy->actor();
            $old=$this->store->receipt($id,$actor,$key);
            if($old){if(!hash_equals($old['body'],$body))throw new DomainException('conflict');return $old;}
            return $this->store->append($id,$actor,$key,$body,(int)$channel['last_sequence']+1);
        });
    }
    public function markRead($id,$sequence) {
        return $this->store->locked($id,function($channel)use($id,$sequence){
            $this->access($channel);
            if(!is_int($sequence)||$sequence<0||$sequence>(int)$channel['last_sequence'])throw new DomainException('invalid');
            $this->store->markRead($id,$this->policy->actor(),$sequence);
        });
    }
    public function markDelivered($id,$sequence) {
        return $this->store->locked($id,function($channel)use($id,$sequence){
            $this->access($channel);
            if(!is_int($sequence)||$sequence<0||$sequence>(int)$channel['last_sequence'])throw new DomainException('invalid');
            $this->store->markDelivered($id,$this->policy->actor(),$sequence);
        });
    }
}
