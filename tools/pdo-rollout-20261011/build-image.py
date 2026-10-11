import json,pathlib,subprocess,sys
key=sys.argv[1];web='chisimba-com-web-1' if key=='chisimba' else 'kengalearn-production-web-1'
i=json.loads(subprocess.check_output(['docker','inspect',web]))[0]
base=pathlib.Path('/tmp/chisimba-pdo-build-20261011');base.mkdir(exist_ok=True)
base_tag=key+'/pdo-base:20261011'
subprocess.run(['docker','tag',i['Image'],base_tag],check=True)
(base/'Dockerfile').write_text('FROM '+base_tag+'\nRUN docker-php-ext-install -j2 pdo_mysql\n')
tag=key+'/pdo:20261011'
subprocess.run(['docker','build','-t',tag,str(base)],check=True,stdout=sys.stderr)
subprocess.run(['docker','run','--rm','--network','none','--entrypoint','php',tag,'-r','if(!in_array("mysql",PDO::getAvailableDrivers(),true))exit(1); echo PHP_VERSION," PDO_MYSQL_READY\\n";'],check=True)
