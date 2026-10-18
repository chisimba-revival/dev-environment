import json, subprocess, urllib.request, urllib.error, ssl, http.cookiejar, time
base='https://chisimba.test:8445/ch/api/v1/'
ctx=ssl._create_unverified_context() # Existing local development certificate only.
fixture=json.loads(subprocess.check_output(['docker','exec','-u','www-data','chisimba-php85-web','cat','/tmp/restapi-local-fixture.json']))
jar=http.cookiejar.CookieJar()
def client(cookies=False):
 handlers=[urllib.request.HTTPSHandler(context=ctx)]
 if cookies: handlers.append(urllib.request.HTTPCookieProcessor(jar))
 return urllib.request.build_opener(*handlers)
anon=client(); session=client(True)
def req(c,path,method='GET',data=None,token=None):
 headers={}
 if data is not None: headers['Content-Type']='application/json';data=json.dumps(data).encode()
 if token: headers['Authorization']='Bearer '+token
 r=urllib.request.Request(base+path,data=data,headers=headers,method=method)
 try: response=c.open(r)
 except urllib.error.HTTPError as e: response=e
 raw=response.read()
 try: body=json.loads(raw)
 except ValueError: raise RuntimeError('Non-JSON response: status '+str(response.status))
 return response.status,body

def check(name,result,expected):
 status,body=result
 if status!=expected: raise RuntimeError(name+': '+str(status)+' '+str(body.get('error',{})))
 print('PASS',name, status,flush=True)
 return body.get('data',body)
check('Anonymous identity denied',req(anon,'auth/me'),401)
e=check('Login evidence',req(session,'auth/login'),200)
assert len(list(jar))>0
payload=dict(username=fixture['username'],password=fixture['password'],csrf_token=e['csrf_token'],abuse_issued_at=e['issued_at'],abuse_nonce=e['nonce'],abuse_signature=e['signature'],device_id='local-http-test')
time.sleep(max(1,e['minimum_seconds'])+1)
check('Missing session rejected',req(anon,'auth/login','POST',payload),422)
login=check('Password login',req(session,'auth/login','POST',payload),201)
t=login['tokens']; access=t['access_token']
check('Bearer alone authenticates',req(anon,'auth/me',token=access),200)
check('Cookie alone denied by API',req(session,'auth/me'),401)
check('Unprivileged user listing denied',req(anon,'users',token=access),403)
check('Unprivileged upload denied',req(anon,'files','POST',{'policy':'image'},access),403)
t2=check('Refresh rotation',req(anon,'auth/refresh','POST',{'refresh_token':t['refresh_token'],'device_id':'local-http-test'}),200)
check('Rotated bearer authenticates',req(anon,'auth/me',token=t2['access_token']),200)
check('Replayed refresh denied',req(anon,'auth/refresh','POST',{'refresh_token':t['refresh_token'],'device_id':'local-http-test'}),401)
check('Replay revokes replacement refresh',req(anon,'auth/refresh','POST',{'refresh_token':t2['refresh_token'],'device_id':'local-http-test'}),401)
subprocess.run(['docker','exec','-u','www-data','chisimba-php85-web','php','/tmp/restapi-permissions.php','grant'],check=True)
check('Granted files list without cookies',req(anon,'files?policy=image',token=access),200)
# A one-pixel PNG exercises multipart upload without using any personal content.
import base64
png=base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=')
boundary='ChisimbaLocalApiTest'
body=('--'+boundary+'\r\nContent-Disposition: form-data; name="policy"\r\n\r\nimage\r\n--'+boundary+'\r\nContent-Disposition: form-data; name="file"; filename="restapi-test.png"\r\nContent-Type: image/png\r\n\r\n').encode()+png+('\r\n--'+boundary+'--\r\n').encode()
r=urllib.request.Request(base+'files',data=body,headers={'Authorization':'Bearer '+access,'Content-Type':'multipart/form-data; boundary='+boundary},method='POST')
try: response=anon.open(r)
except urllib.error.HTTPError as error: response=error
uploaded=check('Authorised image upload', (response.status,json.loads(response.read())),201)
print('Upload response fields:',list(uploaded))
subprocess.run(['docker','exec','-u','www-data','chisimba-php85-web','php','/tmp/restapi-permissions.php','revoke'],check=True)
check('Removed permission takes effect on existing token',req(anon,'files?policy=image',token=access),403)
subprocess.run(['docker','exec','-u','www-data','chisimba-php85-web','php','/tmp/restapi-permissions.php','deactivate'],check=True)
check('Deactivated account rejected',req(anon,'auth/me',token=access),401)
print('Local HTTP authentication and file checks passed.')
