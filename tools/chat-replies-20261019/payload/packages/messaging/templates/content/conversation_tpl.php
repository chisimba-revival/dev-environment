<?php
/** Native shared-skin conversation and one-way announcement views. @author Derek Keats */
$v=$this->getObject('conversationview');$t=fn($key)=>$v->text($key);$e=fn($value)=>htmlspecialchars((string)$value,ENT_QUOTES,'UTF-8');
extract($conversation,EXTR_OVERWRITE);$icon=$this->getObject('iconservice','ui');
$url=fn($params=[])=>$this->uri($params+['action'=>'view'],'messaging');
$hidden=function($name,$value)use($e){echo '<input type="hidden" name="'.$e($name).'" value="'.$e($value).'">';};
?>
<div class="chisimba-publishing-layout"><section class="chisimba-form-card chisimba-form-card--wide chisimba-chat-workspace">
<header class="chisimba-cluster"><h1><?php echo $e($t('title')); ?></h1><?php echo $this->getObject('contextualhelp','help')->show('messaging','conversations'); ?></header>

<?php if($contextTitle!==''): ?><p><?php echo $e($t('context')).': <strong>'.$e($contextTitle).'</strong>'; ?></p><?php endif; ?>
<?php if($error): ?><p role="alert"><?php echo $e($t(in_array($error,['csrf','method','conflict','invalid','failed','scope_changed'],true)?$error:'unavailable')); ?></p><?php endif; ?>
<?php if($error&&!$allowed&&$body!==''): ?><label for="unsent-message"><?php echo $e($t('recover')); ?></label><textarea id="unsent-message" readonly rows="5"><?php echo $e($body); ?></textarea><?php endif; ?>
<?php if($tab!=='site'&&!$allowed): ?><p><?php echo $e($t('unavailable')); ?></p>
<?php elseif($tab==='discussion'): ?>

<?php if(!$channel): ?><p><?php echo $e($t('not_started')); ?></p>
<?php if($this->getObject('conversationpolicy')->mayModerate($context)): ?>
<form method="post" action="<?php echo $e($url(['action'=>'create'])); ?>"><?php $hidden('csrf_token',$conversationToken);$hidden('conversation_context',$context); ?><button type="submit" class="button"><?php echo $icon->render('plus',['decorative'=>true]).'<span>'.$e($t('start')).'</span>'; ?></button></form>

<?php endif;else: ?>

<p data-chat-unread class="chisimba-visually-hidden"><?php echo $e($t('unread')).': '.(int)$data['unread']; ?></p>
<div class="chisimba-form-actions">
<a data-chat-refresh class="button" href="<?php echo $e($url()); ?>"><?php echo $icon->render('refresh-cw',['decorative'=>true]).'<span>'.$e($t('refresh')).'</span>'; ?></a>
<?php if($data['older']): ?><a class="button" href="<?php echo $e($url(['before'=>$data['older']])); ?>"><?php echo $icon->render('arrow-left',['decorative'=>true]).'<span>'.$e($t('older')).'</span>'; ?></a><?php endif; ?>
</div>
<button type="button" class="button" data-chat-new hidden><?php echo $e($t('new_messages')); ?></button>
<div class="chisimba-chat" tabindex="0" aria-label="<?php echo $e($t('discussion')); ?>">
<?php if(!$data['messages']): ?><p><?php echo $e($t('empty')); ?></p><?php endif; ?>
<?php foreach($data['messages']as$post): ?><article data-message-id="<?php echo $e($post['id']); ?>" class="chisimba-chat__message<?php if((string)$post['sender_id']===$this->getObject('conversationpolicy')->actor())echo ' chisimba-chat__message--own'; ?>"><header class="chisimba-chat__meta"><strong><?php echo $e($this->getObject('user','security')->fullName($post['sender_id'])); ?></strong><time datetime="<?php echo $e(str_replace(' ','T',$post['created_at']).'Z'); ?>"><?php echo $e($post['created_at']).' UTC'; ?></time></header><?php if(!empty($post['reply'])): ?><blockquote class="chisimba-chat__quote"><strong><?php echo $e($post['reply']['sender_name']); ?></strong><p><?php echo $e($post['reply']['body']); ?></p></blockquote><?php endif; ?><p data-message-body><?php echo nl2br($e($post['body']),false); ?></p><?php if(isset($post['receipt'])): $receipt=$post['receipt']; ?><span class="chisimba-chat__receipt chisimba-chat__receipt--<?php echo $e($receipt); ?>" role="img" aria-label="<?php echo $e($t('receipt_'.$receipt)); ?>" title="<?php echo $e($t('receipt_'.$receipt)); ?>"><?php echo $icon->render($receipt==='sent'?'check':'check-check',['decorative'=>true]); ?></span><?php endif; ?><a class="button chisimba-chat__reply" data-chat-reply="<?php echo $e($post['id']); ?>" data-reply-author="<?php echo $e($this->getObject('user','security')->fullName($post['sender_id'])); ?>" data-reply-body="<?php echo $e(mb_substr($post['body'],0,300).(mb_strlen($post['body'])>300?'…':'')); ?>" href="<?php echo $e($url(['reply_to'=>$post['id']])).'#conversation-body'; ?>"><?php echo $icon->render('reply',['decorative'=>true]).'<span>'.$e($t('reply')).'</span>'; ?></a></article><?php endforeach; ?>
</div>
<?php $last=$data['messages']?end($data['messages']):['sequence_no'=>0]; ?>
<form data-chat-read data-delivered-url="<?php echo $e($url(['action'=>'delivered'])); ?>" method="post" action="<?php echo $e($url(['action'=>'read'])); ?>"><?php $hidden('csrf_token',$conversationToken);$hidden('conversation_context',$context);$hidden('channel',$channel['id']);$hidden('sequence',$last['sequence_no']); ?><button class="button" type="submit"><?php echo $icon->render('check',['decorative'=>true]).'<span>'.$e($t('read')).'</span>'; ?></button></form>

<p data-chat-status role="status" aria-live="polite" <?php foreach(['connected','offline','sending','sent','retry']as$status): ?>data-<?php echo $status; ?>="<?php echo $e($t('chat_'.$status)); ?>" <?php endforeach; ?>></p>
<form data-conversation-compose data-history-url="<?php echo $e($url($this->getParam('before')?['before'=>(int)$this->getParam('before')]:[])); ?>" method="post" action="<?php echo $e($url(['action'=>'send'])); ?>">
<?php $hidden('csrf_token',$conversationToken);$hidden('conversation_context',$context);$hidden('channel',$channel['id']);$hidden('submission_id',$key);$hidden('reply_to',$replyTo); ?>
<div data-reply-preview class="chisimba-chat__quote" <?php if($replyTo==='')echo 'hidden'; ?>><span><?php echo $e($t('replying')); ?></span> <strong data-reply-author><?php echo $e($replyQuote['sender_name']??''); ?></strong><p data-reply-excerpt><?php echo $e($replyQuote['body']??''); ?></p><a class="button" data-cancel-reply href="<?php echo $e($url()).'#conversation-body'; ?>"><?php echo $icon->render('x',['decorative'=>true]).'<span>'.$e($t('cancel_reply')).'</span>'; ?></a></div>
<div class="chisimba-form-field chisimba-form-field--brief"><label for="conversation-body"><?php echo $e($t('message')); ?></label><textarea id="conversation-body" name="body" rows="2" maxlength="20000" required aria-describedby="conversation-send-help"><?php echo $e($body); ?></textarea></div>
<p id="conversation-send-help" class="chisimba-visually-hidden"><?php echo $e($t('send_help')); ?></p>
<button class="button" type="submit"><?php echo $icon->render('send',['decorative'=>true]).'<span>'.$e($t('send')).'</span>'; ?></button>
</form>
<?php endif;else: ?>
<h2><?php echo $e($t($tab)); ?></h2><p><?php echo $e($t('oneway')); ?></p>
<?php if(!$announcements): ?><p><?php echo $e($t('no_announcements')); ?></p><?php endif; ?>
<?php foreach($announcements as $item): ?><article class="chisimba-flow"><h3><?php echo $e($item['title']); ?></h3><p><?php echo nl2br($e(html_entity_decode(strip_tags($item['message']),ENT_QUOTES,'UTF-8')),false); ?></p></article><?php endforeach; ?>
<a class="button" href="<?php echo $e($this->uri([],'announcements')); ?>"><?php echo $icon->render('megaphone',['decorative'=>true]).'<span>'.$e($t('manage_announcements')).'</span>'; ?></a>
<?php endif; ?>
</section>

<aside class="chisimba-publishing-sidebar"><section class="chisimba-form-card"><h2><?php echo $e($t('context')); ?></h2>
<?php if($allowed): ?><p><?php echo $e($contextTitle); ?></p><a class="button" href="<?php echo $e($this->uri([],'context')); ?>"><?php echo $icon->render('home',['decorative'=>true]).'<span>'.$e($t('context_home')).'</span>'; ?></a><?php endif; ?>
<nav class="chisimba-form-actions chisimba-form-actions--equal" aria-label="<?php echo $e($t('channels')); ?>">
<?php foreach(['discussion'=>'message-circle','announcements'=>'megaphone','site'=>'bell']as$name=>$symbol): ?>
<a class="button" <?php if($tab===$name)echo 'aria-current="page"'; ?> href="<?php echo $e($url(['tab'=>$name])); ?>"><?php echo $icon->render($symbol,['decorative'=>true]).'<span>'.$e($t($name)).'</span>'; ?></a>
<?php endforeach; ?>
</nav></section></aside></div>
