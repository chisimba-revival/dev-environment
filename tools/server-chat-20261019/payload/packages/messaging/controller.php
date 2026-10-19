<?php
/** Context conversations. Legacy chat handlers are deliberately not routed. @author Derek Keats */
if (empty($GLOBALS['kewl_entry_point_run'])) die('No direct access');
class messaging extends controller
{
    private $service; private $policy; private $csrf; private const TOKEN='messaging_conversation_v2';
    public function init() {
        $this->service=$this->getObject('conversationservice');$this->policy=$this->getObject('conversationpolicy');
        $this->appendArrayVar('headerParams','<script defer src="'.$this->getResourceUri('conversation.js').'?v=2.003'.'"></script>');
        $this->csrf=$this->getObject('nativeauthwebcomposition','security')->build()['csrf'];
    }
    public function requiresLogin($action) {return true;}
    public function dispatch($action) {
        $action=(string)$action;$context=$this->getObject('dbcontext','context')->getContextCode();
        $context=is_string($context)?$context:'';$tab=$this->getParam('tab','discussion');
        $error='';$body=$this->getParam('body','');$key=$this->getParam('submission_id',bin2hex(random_bytes(16)));
        $body=is_string($body)?$body:'';$key=is_string($key)?$key:'';
        try {
            if(!in_array($action,['','view','roomlist','im','create','send','read','delivered'],true)||!in_array($tab,['discussion','announcements','site'],true))throw new DomainException('unavailable');
            if(in_array($action,['create','send','read','delivered'],true)) {
                if(($_SERVER['REQUEST_METHOD']??'GET')!=='POST'){http_response_code(405);throw new DomainException('method');}
                if(!$this->csrf->consume(self::TOKEN,(is_string($this->getParam('csrf_token',''))?$this->getParam('csrf_token',''):''))){http_response_code(403);throw new DomainException('csrf');}
                if($this->getParam('conversation_context')!==$context)throw new DomainException('scope_changed');
                if($action==='create')$this->service->create($context);
                else {
                    $channel=$this->service->forContext($context);
                    if(!$channel||$this->getParam('channel')!==$channel['id'])throw new DomainException('unavailable');
                    if($action==='send')$this->service->send($channel['id'],$key,$body);
                    elseif($action==='delivered')$this->service->markDelivered($channel['id'],filter_var($this->getParam('sequence'),FILTER_VALIDATE_INT)===false?-1:(int)$this->getParam('sequence'));
                    else $this->service->markRead($channel['id'],filter_var($this->getParam('sequence'),FILTER_VALIDATE_INT)===false?-1:(int)$this->getParam('sequence'));
                }
                return $this->nextAction('view',['tab'=>'discussion']);
            }
        }catch(DomainException $e){$error=$e->getMessage();if($error==='unavailable')http_response_code(404);elseif(!in_array($error,['method','csrf'],true))http_response_code(400);}
        catch(Throwable $e){$error='failed';http_response_code(503);error_log('Messaging operation failed; submitted text was retained.');}
        $data=null;$channel=null;$announcements=[];$allowed=$error!=='scope_changed'&&$this->policy->mayRead($context);
        $contextTitle=$allowed?(string)($this->getObject('dbcontext','context')->getContextDetails($context)['title']??''):'';
        try {
            if($tab==='site')$announcements=$this->getObject('conversationview')->announcements($context,true);
            elseif($allowed) {
                if($tab==='announcements')$announcements=$this->getObject('conversationview')->announcements($context);
                else {$channel=$this->service->forContext($context);if($channel)$data=$this->service->history($channel['id'],max(0,(int)$this->getParam('before',0)));}
            }
        }catch(DomainException $e){$error=$e->getMessage();$allowed=false;http_response_code(404);}
        catch(Throwable $e){$error='failed';$allowed=false;http_response_code(503);error_log('Messaging view failed.');}
        $this->setVar('conversation',compact('context','tab','error','body','key','data','channel','announcements','allowed','contextTitle'));
        $this->setVar('conversationToken',$this->csrf->issue(self::TOKEN));
        return 'conversation_tpl.php';
    }
}
