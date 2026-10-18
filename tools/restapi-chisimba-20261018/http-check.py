"""Public HTTPS smoke check using only a disposable account and private draft."""
import json, subprocess, urllib.request, urllib.error, ssl, http.cookiejar, time
web='chisimba-com-web-1';base='https://www.chisimba.com/api/v1/'
def cli(name,*args):return subprocess.check_output(['docker','exec','-u','www-data',web,'php','/tmp/restapi-'+name+'.php',*args])
fixture=None
try:
 print(cli('prepare').decode().strip(),flush=True)
 fixture=json.loads(subprocess.check_output(['docker','exec','-u','www-data',web,'cat','/tmp/restapi-local-fixture.json']))
 jar=http.cookiejar.CookieJar();ctx=ssl.create_default_context()
 anon=urllib.request.build_opener(urllib.request.HTTPSHandler(context=ctx))
 session=urllib.request.build_opener(urllib.request.HTTPSHandler(context=ctx),urllib.request.HTTPCookieProcessor(jar))
 def request(c,path,method='GET',data=None,token=None,expect=200):
  headers={}
  if data is not None:headers['Content-Type']='application/json';data=json.dumps(data).encode()
  if token:headers['Authorization']='Bearer '+token
  try:r=c.open(urllib.request.Request(base+path,data=data,headers=headers,method=method),timeout=30)
  except urllib.error.HTTPError as e:r=e
  assert r.status==expect, 'Unexpected HTTP status '+str(r.status)+' at '+path
  payload=json.loads(r.read());return payload.get('data',payload)
 body={'title':'Temporary mobile API check','content':'Private deployment verification. Removed after the check.','status':'draft'}
 request(anon,'simpleblog/posts','POST',body,expect=401);print('PASS anonymous denied',flush=True)
 e=request(session,'auth/login');time.sleep(max(1,e['minimum_seconds'])+1)
 login=request(session,'auth/login','POST',dict(username=fixture['username'],password=fixture['password'],csrf_token=e['csrf_token'],abuse_issued_at=e['issued_at'],abuse_nonce=e['nonce'],abuse_signature=e['signature'],device_id='chisimba-com-deployment-check'),expect=201)
 access=login['tokens']['access_token'];print('PASS trusted HTTPS login',flush=True)
 request(anon,'simpleblog/posts','POST',body,access,403);print('PASS unprivileged denied',flush=True)
 cli('permissions','bloggrant')
 post=request(anon,'simpleblog/posts','POST',body,access,201);assert post['status']=='draft';print('PASS private draft created',flush=True)
 try:r=anon.open('https://www.chisimba.com/index.php?module=simpleblog&action=view&id='+post['id'])
 except urllib.error.HTTPError as e:r=e
 assert r.status==404;print('PASS private draft hidden from anonymous readers',flush=True)
 cli('permissions','revoke');request(anon,'simpleblog/posts','POST',body,access,403);print('PASS revoked permission denied',flush=True)
finally:
 if fixture:
  print(cli('permissions','deactivate').decode().strip(),flush=True)
  print(cli('cleanup').decode().strip(),flush=True)
