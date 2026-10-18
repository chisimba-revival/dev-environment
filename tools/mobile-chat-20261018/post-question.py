"""Post Derek's authorised test question using the student's normal web form."""
import pathlib,json,urllib.request,urllib.parse,http.cookiejar,time,re,html,hashlib
f=json.loads(pathlib.Path('private-storage/course-testing/account.json').read_text());base='https://www.chisimba.com'
assert f['username']=='chisimba_test_student' and f['course']=='gettingstarted'
c=urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))
e=json.load(c.open(base+'/api/v1/auth/login'))['data'];time.sleep(max(1,e['minimum_seconds'])+1)
p=dict(username=f['username'],password=f['password'],csrf_token=e['csrf_token'],abuse_issued_at=e['issued_at'],abuse_nonce=e['nonce'],abuse_signature=e['signature'],device_id='student-chat-question')
r=c.open(urllib.request.Request(base+'/api/v1/auth/login',data=json.dumps(p).encode(),headers={'Content-Type':'application/json'}));assert r.status==201;auth=json.load(r)['data'];token=auth['tokens']['access_token']
def api(path):return json.load(c.open(urllib.request.Request(base+'/api/v1/'+path,headers={'Authorization':'Bearer '+token})))['data']
assert any(x['id']=='gettingstarted' for x in api('messaging/contexts')['contexts'])
c.open(base+'/index.php?module=context&action=joincontext&contextcode=gettingstarted').read()
page=c.open(base+'/index.php?module=messaging').read().decode()
def field(name):return html.unescape(re.search('name="'+name+'" value="([^"]+)"',page).group(1))
key=hashlib.sha256(b'chisimba-student-first-chat-question-20261018').hexdigest()[:32]
body='Test question: Hi Derek, can I write a message while I am offline and send it when I reconnect?'
p=dict(csrf_token=field('csrf_token'),conversation_context=field('conversation_context'),channel=field('channel'),submission_id=key,body=body)
assert p['conversation_context']=='gettingstarted'
r=c.open(urllib.request.Request(base+'/index.php?module=messaging&action=send',data=urllib.parse.urlencode(p).encode()));assert r.status==200 and body in r.read().decode()
rows=api('messaging/history?context=gettingstarted')['messages'];matches=[m for m in rows if m['submission_id']==key];assert len(matches)==1 and matches[0]['sender_id']==f['userId']
print('PASS student question posted through web form and visible through mobile API; exactly one confirmed message')
