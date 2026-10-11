import pathlib,sys,subprocess,json,datetime
b=pathlib.Path(__file__).resolve().parent;key=sys.argv[1];mode=sys.argv[2];web='chisimba-com-web-1' if key=='chisimba' else 'kengalearn-production-web-1'
a=['docker','exec','-i'];state=b/key/'logs-before.json'
if mode=='check':a+=['-e','LOG_CHECK=1','-e','LOG_BASELINE='+json.dumps(json.loads(state.read_text())['sizes'])]
r=subprocess.run(a+[web,'php','/dev/stdin'],input=(b/'log-window.php').read_bytes(),capture_output=True,check=True);data=json.loads(r.stdout)
if mode=='before':data['time']=datetime.datetime.now(datetime.timezone.utc).isoformat()
(b/key/('logs-'+mode+'.json')).write_text(json.dumps(data,indent=2));print(key,mode,'tracked logs',len(data['sizes']),'new warning/error lines',len(data['findings']))
