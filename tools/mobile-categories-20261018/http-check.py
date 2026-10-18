"""Verify authorised categories and atomic assignment against a disposable fixture only."""
import json,subprocess,urllib.request,urllib.error,ssl,http.cookiejar,time,os
remote=os.environ.get('CATEGORY_TEST_TARGET')=='chisimba.com'
web='chisimba-com-web-1' if remote else 'chisimba-php85-web'
base=('https://www.chisimba.com' if remote else 'https://chisimba.test:8445/ch')+'/api/v1/'
ctx=ssl.create_default_context() if remote else ssl._create_unverified_context() # Local development certificate only.
f=json.loads(subprocess.check_output(['docker','exec','-u','www-data',web,'cat','/tmp/restapi-local-fixture.json']))
assert f['username'].startswith('api_test_')
def cli(script,*args):return subprocess.check_output(['docker','exec','-u','www-data','-e','CATEGORY_TEST_TARGET='+('chisimba.com' if remote else 'local'),web,'php','/tmp/restapi-'+script+'.php',*args])
jar=http.cookiejar.CookieJar();loginclient=urllib.request.build_opener(urllib.request.HTTPSHandler(context=ctx),urllib.request.HTTPCookieProcessor(jar));client=urllib.request.build_opener(urllib.request.HTTPSHandler(context=ctx))
def req(path,expected,token=None,data=None,c=client):
 headers={'Accept':'application/json'}
 if token:headers['Authorization']='Bearer '+token
 if data is not None:headers['Content-Type']='application/json'
 try:r=c.open(urllib.request.Request(base+path,data=None if data is None else json.dumps(data).encode(),headers=headers),timeout=30)
 except urllib.error.HTTPError as error:r=error
 body=json.loads(r.read());assert r.status==expected,f'{path}: expected {expected}, got {r.status}'
 print('PASS',path,expected,flush=True);return body.get('data')
try:
 req('simpleblog/categories',401)
 e=req('auth/login',200,c=loginclient);time.sleep(max(1,e['minimum_seconds'])+1)
 auth=req('auth/login',201,data=dict(username=f['username'],password=f['password'],csrf_token=e['csrf_token'],abuse_issued_at=e['issued_at'],abuse_nonce=e['nonce'],abuse_signature=e['signature'],device_id='category-test'),c=loginclient)
 token=auth['tokens']['access_token'];req('simpleblog/categories',403,token)
 cli('permissions','bloggrant');ids=json.loads(cli('category-fixture','seed'))
 choices=req('simpleblog/categories',200,token)['categories'];assert [t['id'] for t in choices]==[ids['own']]
 assert req('simpleblog/categories?owner=someone-else',200,token)['categories']==choices
 req('simpleblog/categories/other',404,token);req('simpleblog/categories',405,token,data={})
 post=dict(title='Category API test',content='Private disposable category test.',status='draft')
 for category in [[ids['foreign']],[ids['tag']],['missing'],None,'bad',[23]]:req('simpleblog/posts',422,token,dict(post,categories=category))
 req('simpleblog/posts',201,token,dict(post,categories=[ids['own']]))
 print(cli('category-fixture','inspect').decode().strip())
 cli('permissions','revoke');req('simpleblog/categories',403,token);req('simpleblog/posts',403,token,dict(post,categories=[ids['own']]))
finally:
 cli('permissions','bloggrant');print(cli('category-fixture','cleanup').decode().strip());cli('permissions','deactivate');print(cli('cleanup').decode().strip())
