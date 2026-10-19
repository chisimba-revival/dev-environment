/** Progressive chat updates; the canonical controller still owns permissions and receipts. */
(() => {
  const form = document.querySelector('[data-conversation-compose]');
  if (!form) {
    // Read-only photo channels still update without a full-page refresh.
    const feed=document.querySelector('[data-conversation-feed]');
    if(!feed)return;
    const scope=feed.dataset.scope;let fetching=false;
    setInterval(async()=>{
      if(document.hidden||fetching)return;fetching=true;
      try{
        const url=new URL(feed.dataset.historyUrl,location.href);
        const response=await fetch(url.pathname+url.search,{credentials:'same-origin',cache:'no-store'});
        const page=new DOMParser().parseFromString(await response.text(),'text/html');
        const next=page.querySelector('[data-conversation-feed]');
        if(!response.ok||!next||next.dataset.scope!==scope){feed.replaceChildren();return;}
        const bottom=feed.scrollHeight-feed.scrollTop-feed.clientHeight<40,position=feed.scrollTop;
        if(feed.innerHTML!==next.innerHTML)feed.replaceChildren(...next.childNodes);
        feed.scrollTop=bottom?feed.scrollHeight:position;
      }catch{/* Keep already displayed photographs during a temporary outage. */}
      finally{fetching=false;}
    },15000);
    return;
  }
  const input = form.querySelector('textarea');
  const button = form.querySelector('button[type="submit"]');
  const status = document.querySelector('[data-chat-status]');
  const channel = form.elements.channel.value;
  const scope = form.elements.conversation_context.value;
  let sending = false, revision = 0, polling = false, acknowledging = false;
  let delivered = 0, read = 0;
  const readForm = document.querySelector('[data-chat-read]');
  const newer = document.querySelector('[data-chat-new]');
  const manualRefresh = document.querySelector('[data-chat-refresh]');
  const olderPage = new URL(location.href).searchParams.has('before');
  if (readForm) readForm.hidden = !olderPage;
  if (manualRefresh) manualRefresh.hidden = !olderPage;
  const atBottom = () => history().scrollHeight-history().scrollTop-history().clientHeight<40;
  // Sites may render a canonical host alias. Keep Ajax on the authenticated origin.
  const sameOrigin = target => {const url=new URL(target,location.href);return url.pathname+url.search;};
  const history = () => document.querySelector('.chisimba-chat');
  if (history()) history().scrollTop = history().scrollHeight;
  const say = key => { status.textContent = key === 'connected' ? '' : status.dataset[key] || '';  };
  function parse(html) {
    const page = new DOMParser().parseFromString(html, 'text/html');
    const next = page.querySelector('[data-conversation-compose]');
    if (!next || next.elements.channel.value !== channel || next.elements.conversation_context.value !== scope) throw Error('scope');
    return { page, next };
  }
  function refresh({page, next}, forceBottom = false) {
    const old = history(), fresh = page.querySelector('.chisimba-chat');
    if (!old || !fresh) throw Error('history');
    const nearBottom = old.scrollHeight - old.scrollTop - old.clientHeight < 40;
    const position = old.scrollTop;
    const previous = old.lastElementChild?.dataset.messageId;
    const changed = previous !== fresh.lastElementChild?.dataset.messageId;
    // Leave unchanged message actions and text selections mounted between polls.
    if(typeof old.innerHTML!=='string'||old.innerHTML!==fresh.innerHTML)old.replaceChildren(...fresh.childNodes);
    old.scrollTop = forceBottom || nearBottom ? old.scrollHeight : position;
    if(newer && changed && !nearBottom && !forceBottom)newer.hidden=false;
    if(newer && (nearBottom || forceBottom))newer.hidden=true;
    // Renew the form token without replacing the user's unsent text or receipt key.
    document.querySelectorAll('input[name="csrf_token"]').forEach(el => { el.value = next.elements.csrf_token.value; });
    const read = document.querySelector('input[name="sequence"]');
    const nextRead = page.querySelector('input[name="sequence"]');
    if (read && nextRead) read.value = nextRead.value;
    const unread = document.querySelector('[data-chat-unread]');
    if (unread) unread.textContent = page.querySelector('[data-chat-unread]').textContent;
  }
  async function poll() {
    if (sending || polling || acknowledging || document.hidden || new URL(location.href).searchParams.has('before')) return;
    polling = true;
    const ticket = revision;
    try {
      const response = await fetch(sameOrigin(form.dataset?.historyUrl || location.href), {credentials:'same-origin',cache:'no-store'});
      if (!response.ok) throw Error('read');
      const parsed = parse(await response.text());
      if (ticket !== revision || sending) return;
      refresh(parsed); say('connected');
    } catch { if (ticket === revision && !sending) say('offline'); }
    finally { polling = false; }
    void acknowledge();
  }
  form.addEventListener('submit', async event => {
    event.preventDefault();
    if (sending || acknowledging) return;
    sending = true; revision++; button.disabled = true; input.readOnly = true; say('sending');
    try {
      const response = await fetch(sameOrigin(form.action), {method:'POST',credentials:'same-origin',body:new URLSearchParams(new FormData(form)),cache:'no-store'});
      const html = await response.text();
      const parsed = parse(html);
      refresh(parsed, response.ok);
      if (!response.ok) {
        status.textContent = parsed.page.querySelector('[role="alert"]')?.textContent || status.dataset.offline;
        return;
      }
      input.value = '';
      chooseReply('','','');
      form.elements.submission_id.value = parsed.next.elements.submission_id.value;
      say('sent'); input.focus();
    } catch { say('retry'); }
    finally { sending = false; button.disabled = false; input.readOnly = false; }
    void acknowledge();
  });
  const replyPreview=document.querySelector('[data-reply-preview]');
  function chooseReply(id,author,excerpt) {
    if(!form.elements.reply_to || !replyPreview)return;
    form.elements.reply_to.value=id;replyPreview.hidden=!id;
    replyPreview.querySelector('[data-reply-author]').textContent=author;
    replyPreview.querySelector('[data-reply-excerpt]').textContent=excerpt;
  }
  history()?.addEventListener?.('click',event=>{
    const link=event.target.closest('[data-chat-reply]');if(!link)return;
    event.preventDefault();if(sending)return;
    chooseReply(link.dataset.chatReply,link.dataset.replyAuthor,link.dataset.replyBody);input.focus();
  });
  document.querySelector('[data-cancel-reply]')?.addEventListener('click',event=>{
    event.preventDefault();if(sending)return;chooseReply('','','');input.focus();
  });
  // Acknowledgements are explicit POSTs, serialised with sends and token renewal.
  async function acknowledge() {
    if(olderPage || !readForm || document.hidden || sending || polling || acknowledging)return;
    const sequence=Number(readForm.elements.sequence.value);
    const bounds=history().lastElementChild?.getBoundingClientRect();
    const inView=bounds && bounds.bottom>0 && bounds.bottom<=window.innerHeight;
    const markRead=atBottom() && inView && sequence>read;
    if(!sequence || (!markRead && sequence<=delivered))return;
    acknowledging=true;button.disabled=true;
    const body=new URLSearchParams(new FormData(readForm));
    const target=markRead?readForm.action:readForm.dataset.deliveredUrl;
    try {
      const response=await fetch(sameOrigin(target),{method:'POST',credentials:'same-origin',body,cache:'no-store'});
      if(!response.ok)throw Error('receipt');
      refresh(parse(await response.text()));
      delivered=Math.max(delivered,sequence);if(markRead)read=Math.max(read,sequence);
    } catch { /* Keep receipt unconfirmed and retry on the next successful poll. */ }
    finally { acknowledging=false;button.disabled=false; }
  }
  history()?.addEventListener?.('scroll',()=>{if(atBottom()){if(newer)newer.hidden=true;void acknowledge();}});
  newer?.addEventListener('click',()=>{history().scrollTop=history().scrollHeight;newer.hidden=true;void acknowledge();});
  window.addEventListener('beforeunload' , event => {
    if (input.value.trim()) { event.preventDefault(); event.returnValue = ''; }
  });
  window.addEventListener('scroll',acknowledge,{passive:true});
  window.addEventListener('online', poll);
  document.addEventListener('visibilitychange', poll);
  window.setInterval(poll, 3000);
  void acknowledge();
})();
