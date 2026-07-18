#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="/run/media/derek/main/chisimba-revival"
LOG="${ROOT}/killme.txt"

SOURCE="${ROOT}/framework/app/classes/core/controller_class_inc.php"
RUNTIME="${ROOT}/dev-environment/runtime/php82-ch/classes/core/controller_class_inc.php"

exec >"${LOG}" 2>&1

python3 - "${SOURCE}" "${RUNTIME}" <<'PY'
from pathlib import Path
import re
import sys

pattern = re.compile(
    r'''
    function
    \s+
    getSession
    \s*
    \(
        \s*\$name
        \s*,\s*
        \$default
        \s*=\s*
        null
    \s*
    \)
    ''',
    re.IGNORECASE | re.VERBOSE,
)

replacement = (
    "function getSession("
    "$name, $default = null, $module = '_MODULE_'"
    ")"
)

for filename in sys.argv[1:]:
    path = Path(filename)

    if not path.is_file():
        raise SystemExit(f"Missing file: {path}")

    source = path.read_text()

    if re.search(
        r"function\s+getSession\s*\("
        r"\s*\$name\s*,\s*"
        r"\$default\s*=\s*null\s*,\s*"
        r"\$module\s*=\s*['_\"]_MODULE_['_\"]",
        source,
        re.IGNORECASE,
    ):
        print(f"ALREADY COMPATIBLE: {path}")
        continue

    updated, count = pattern.subn(replacement, source, count=1)

    if count != 1:
        print(f"Could not match getSession() in: {path}")
        for number, line in enumerate(source.splitlines(), 1):
            if "getSession" in line:
                print(f"{number}: {line}")
        raise SystemExit(1)

    backup = path.with_name(path.name + ".before-php82-getsession")

    if not backup.exists():
        backup.write_text(source)

    path.write_text(updated)
    print(f"UPDATED: {path}")

PY

echo
echo "===== SOURCE DECLARATION ====="
grep -n -A5 -B3 \
    'function[[:space:]]\+getSession' \
    "${SOURCE}"

echo
echo "===== RUNTIME DECLARATION ====="
grep -n -A5 -B3 \
    'function[[:space:]]\+getSession' \
    "${RUNTIME}"

echo
echo "===== PHP 8.2 LINT ====="

docker compose \
    -f "${ROOT}/dev-environment/compose/php82.yml" \
    exec -T web \
    php -l /var/www/html/ch/classes/core/controller_class_inc.php

echo
echo "Patch complete. Reload:"
echo "http://localhost:8082/ch/"
