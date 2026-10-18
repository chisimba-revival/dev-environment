"""Delete only the disposable API fixture's newly created private post."""
import urllib.request,urllib.error,urllib.parse,ssl,http.cookiejar,json,subprocess,time,re,html,os
remote=os.environ.get('BLOG_DELETE_TARGET')=='chisimba.com'
web='chisimba-com-web-1' if remote else 'chisimba-php85-web'
base='https://www.chisimba.com' if remote else 'https://chisimba.test:8445/ch'
ctx=ssl.create_default_context() if remote else ssl.create_default_context(cafile='private-storage/php85/mobile-tls/localhost.crt')
# The desktop's normal chisimba.test certificate uses the existing dev CA.
if not remote:ctx=ssl._create_unverified_context()  # Local-only test host; never used for the public target.
def cli(script,*args):return subprocess.check_output(['docker','exec','-u','www-data',web,'php','/tmp/restapi-'+script+'.php',*args])
f=json.loads(subprocess.check_output(['docker','exec','-u','www-data',web,'cat','/tmp/restapi-local-fixture.json']))
assert f['username'].startswith('api_test_')
jar=http.cookiejar.CookieJar();client=urllib.request.build_opener(urllib.request.HTTPSHandler(context=ctx),urllib.request.HTTPCookieProcessor(jar));anon=urllib.request.build_opener(urllib.request.HTTPSHandler(context=ctx))
def request(path,data=None,json_body=False,token=None,c=client):
 headers={}
 if data is not None:
  headers['Content-Type']='application/json' if json_body else 'application/x-www-form-urlencoded';data=(json.dumps(data) if json_body else urllib.parse.urlencode(data)).encode()
 if token:headers['Authorization']='Bearer '+token
 try:r=c.open(urllib.request.Request(base+path,data=data,headers=headers),timeout=30)
 except urllib.error.HTTPError as e:r=e
 return r.status,r.read().decode()
def api(path,data=None,token=None):
 code,raw=request('/api/v1/'+path,data,True,token);assert code in [200,201],f'API {path} status {code}';return json.loads(raw)['data']
def route(action,post):return '/index.php?'+urllib.parse.urlencode(dict(module='simpleblog',action=action,id=post))
def csrf(raw):return html.unescape(re.search(r'name="csrf_token" value="([^"]+)"',raw).group(1))
try:
 e=api('auth/login');time.sleep(max(1,e['minimum_seconds'])+1)
 result=api('auth/login',dict(username=f['username'],password=f['password'],csrf_token=e['csrf_token'],abuse_issued_at=e['issued_at'],abuse_nonce=e['nonce'],abuse_signature=e['signature'],device_id='delete-visibility-test'))
 p=api('simpleblog/posts',dict(title='Temporary deletion confirmation check',content='Only this synthetic draft is deleted.',status='draft'),result['tokens']['access_token'])['id']
 manage='/index.php?'+urllib.parse.urlencode(dict(module='simpleblog',action='manage',scope='personal',blogid=f['userId']))
 for path in [manage,route('preview',p),route('edit',p)]:
  code,raw=request(path);assert code==200 and 'action=confirmdelete' in html.unescape(raw),'Missing visible delete';print('PASS visible delete',flush=True)
 code,raw=request(route('confirmdelete',p));assert code==200 and 'Temporary deletion confirmation check' in raw and 'Confirm deletion' in raw and '>Cancel<' in raw;print('PASS named confirmation and cancel',flush=True)
 code,_=request(route('delete',p));assert code==403;print('PASS GET cannot delete',flush=True)
 code,_=request(route('delete',p),{'id':p,'csrf_token':'invalid'});assert code==403;print('PASS invalid CSRF cannot delete',flush=True)
 code,raw=request(route('confirmdelete',p));assert code==200;token=csrf(raw)
 cli('permissions','revoke')
 code,_=request(route('delete',p),{'id':p,'csrf_token':token});assert code in [400,403,404];print('PASS permission revoked after confirmation prevents deletion',flush=True)
 cli('permissions','bloggrant')
 code,raw=request(route('confirmdelete',p));assert code==200;token=csrf(raw)
 code,public=request(route('confirmdelete',p),c=anon);assert 'Temporary deletion confirmation check' not in public;print('PASS anonymous cannot see draft confirmation',flush=True)
 code,raw=request(route('delete',p),{'id':p,'csrf_token':token});assert code==200,'Deletion should redirect to management'
 code,_=request(route('preview',p));assert code==404;print('PASS authorised confirmed deletion',flush=True)
finally:
 print(cli('permissions','deactivate').decode().strip());print(cli('cleanup').decode().strip())
