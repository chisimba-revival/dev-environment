#!/usr/bin/env python3
"""Run PDO prerequisites in disposable containers, never the installed database.

Usage: python3 tests/pdo/run-readiness.py [local-image-name]
The fixture uses an internal Docker network, no published ports and tmpfs data.
"""
import pathlib
import secrets
import subprocess
import sys
import time

image = sys.argv[1] if len(sys.argv) > 1 else 'chisimba-php85-web'
name = 'chisimba-pdo-fixture-' + secrets.token_hex(6)
password = secrets.token_hex(24)
root = pathlib.Path(__file__).resolve().parent

def run(args, **options):
    return subprocess.run(args, check=True, **options)

run(['docker', 'network', 'create', '--internal', name], stdout=subprocess.DEVNULL)
try:
    run(['docker', 'run', '--rm', '-d', '--name', name, '--network', name,
         '--network-alias', 'pdo-db', '--tmpfs', '/var/lib/mysql',
         '-e', 'MARIADB_ROOT_PASSWORD=' + password,
         '-e', 'MARIADB_DATABASE=pdo_fixture', 'mariadb:10.11.18'],
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
    run(['docker', 'run', '--rm', '--network', name, '--entrypoint', 'php',
         '-e', 'CHISIMBA_PDO_FIXTURE=1', '-e', 'CHISIMBA_PDO_PASSWORD=' + password,
         '-v', str(root) + ':/pdo-tests:ro', image,
         '-d', 'display_errors=1', '-d', 'auto_prepend_file=', '/pdo-tests/readiness.php'])
finally:
    subprocess.run(['docker', 'rm', '-f', name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(['docker', 'network', 'rm', name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
