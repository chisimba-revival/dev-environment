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
post={'title':'Mobile text test','content':'First line\n<img src=x onerror=alert(1)>'}
check('Anonymous post denied',req(anon,'simpleblog/posts','POST',post),401)
e=check('Login evidence',req(session,'auth/login'),200)
time.sleep(max(1,e['minimum_seconds'])+1)
payload=dict(username=fixture['username'],password=fixture['password'],csrf_token=e['csrf_token'],abuse_issued_at=e['issued_at'],abuse_nonce=e['nonce'],abuse_signature=e['signature'],device_id='local-blog-test')
login=check('Login',req(session,'auth/login','POST',payload),201)
access=login['tokens']['access_token']
check('Unprivileged publisher denied',req(anon,'simpleblog/posts','POST',post,access),403)
subprocess.run(['docker','exec','-u','www-data','chisimba-php85-web','php','/tmp/restapi-permissions.php','bloggrant'],check=True)
check('Wrong method refused',req(anon,'simpleblog/posts',token=access),405)
check('Unexpected route refused',req(anon,'simpleblog/other','POST',post,access),404)
for label,extra in [('Other owner',{'userid':'someone-else'}),('Image',{'featured_image':'https://example.invalid/image.png'}),('Blocks',{'blocks':[]}),('Invalid status',{'status':'scheduled'}),('Empty text',{'content':''})]:
 check(label+' rejected',req(anon,'simpleblog/posts','POST',dict(post,**extra),access),422)
check('Scalar JSON rejected',req(anon,'simpleblog/posts','POST',42,access),422)
draft=check('Text draft created',req(anon,'simpleblog/posts','POST',post,access),201)
assert draft['status']=='draft'
published=check('Text post published',req(anon,'simpleblog/posts','POST',dict(post,status='posted'),access),201)
assert published['status']=='posted'
# Inspect only this fixture's posts through the installed dbTable service.
subprocess.run(['docker','exec','-u','www-data','chisimba-php85-web','php','/tmp/restapi-blog-inspect.php'],check=True)
for item,expected in [(draft,404),(published,200)]:
 url='https://chisimba.test:8445/ch/index.php?module=simpleblog&action=view&id='+item['id']
 try: response=anon.open(url)
 except urllib.error.HTTPError as error: response=error
 html=response.read().decode()
 if response.status!=expected: raise RuntimeError('Anonymous post visibility: '+str(response.status))
 if expected==200 and ('&lt;img' not in html or '<img src=x onerror' in html): raise RuntimeError('Plain text rendering failed')
 print('PASS anonymous visibility',expected)
subprocess.run(['docker','exec','-u','www-data','chisimba-php85-web','php','/tmp/restapi-permissions.php','revoke'],check=True)
check('Revoked publisher denied',req(anon,'simpleblog/posts','POST',post,access),403)
print('SimpleBlog text-only HTTP checks passed.')
