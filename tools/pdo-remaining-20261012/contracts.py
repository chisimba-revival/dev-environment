#!/usr/bin/env python3
"""Run native PDO/dbTable integration checks in disposable containers, never the installed database.

Usage: python3 contracts.py IMAGE SITE
The fixture uses an internal Docker network, no published ports and tmpfs data.
"""
import pathlib
import shutil
import secrets
import subprocess
import sys
import time

image = sys.argv[1] if len(sys.argv) > 1 else 'chisimba-php85-web'
name = 'chisimba-pdo-contract-' + secrets.token_hex(6)
password = secrets.token_hex(24)
base = pathlib.Path(__file__).resolve().parent
key = sys.argv[2]
root = base / key / 'stage'

def run(args, **options):
    result = subprocess.run(args, **options)
    if result.returncode:
        raise RuntimeError('Disposable database check failed; see PHP diagnostics above')
    return result

run(['docker', 'network', 'create', '--internal', name], stdout=subprocess.DEVNULL)
try:
    run(['docker', 'run', '--rm', '-d', '--name', name, '--network', name,
         '--network-alias', 'baseline-db', '--tmpfs', '/var/lib/mysql',
         '-e', 'MARIADB_ROOT_PASSWORD=' + password,
         '-e', 'MARIADB_DATABASE=contract_fixture', 'mariadb:10.11.18'],
        stdout=subprocess.DEVNULL)
    for attempt in range(60):
        result = subprocess.run(['docker', 'exec', name, 'mariadb', '-uroot',
                                 '-p' + password, '-e', 'SELECT 1'],
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if result.returncode == 0:
            break
        time.sleep(1)
    else:
        raise RuntimeError('Disposable MariaDB failed to become ready')
    test_modules=root/'packages'
    if not (test_modules/'shop').is_dir():
        test_modules=root.parent/'contract-modules'
        if not test_modules.exists():
            run(['cp','-a','--reflink=auto',str(root/'packages'),str(test_modules)])
        if not (test_modules/'shop').exists():
            shutil.copytree(base/'fixture-modules/shop',test_modules/'shop')
    for fixture in ('pdo_contract_test.php', 'pdo_engine_composition_test.php', 'installer_schema_checks.php'):
        run(['docker', 'run', '--rm', '--network', name, '--entrypoint', 'php',
             '-e', 'CHISIMBA_DB_BASELINE=1', '-e', 'CHISIMBA_DB_PASSWORD=' + password,
             '-v', str(root) + ':/framework/app:ro', '-v', str(base / 'tests') + ':/framework/tests:ro', '-v', str(test_modules) + ':/modules:ro', image,
             '-d', 'display_errors=1', '-d', 'auto_prepend_file=', '/framework/tests/database/' + fixture])
finally:
    subprocess.run(['docker', 'rm', '-f', name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(['docker', 'network', 'rm', name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

import json, hashlib
(root.parent / 'contracts-pass.json').write_text(json.dumps({
    'imageId': json.loads(subprocess.check_output(['docker','image','inspect',image]))[0]['Id'],
    'baselineHash': hashlib.sha256((root.parent/'baseline.json').read_bytes()).hexdigest(),
    'fixtures': ['pdo_contract_test.php','pdo_engine_composition_test.php','installer_schema_checks.php']
},indent=2))
