#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="/run/media/derek/main/chisimba-revival"
LOG="${ROOT}/killme.txt"

SOURCE="${ROOT}/framework/app/core_modules/config/classes/altconfig_class_inc.php"
RUNTIME="${ROOT}/dev-environment/runtime/php82-ch/core_modules/config/classes/altconfig_class_inc.php"
COMPOSE="${ROOT}/dev-environment/compose/php82.yml"

exec >"${LOG}" 2>&1

fail()
{
    echo "ERROR: $*" >&2
    exit 1
}

echo "============================================================"
echo "PHP 8.2: Fix altconfig::getParam() signature"
echo "============================================================"

python3 - "${SOURCE}" "${RUNTIME}" <<'PY'
from pathlib import Path
import re
import sys

pattern = re.compile(
    r'''
    function
    \s+
    getParam
    \s*
    \(
        \s*\$pname
        \s*,\s*
        \$pmodule
    \s*
    \)
    ''',
    re.IGNORECASE | re.VERBOSE,
)

replacement = "function getParam($pname, $pmodule = null)"

for filename in sys.argv[1:]:
    path = Path(filename)

    if not path.is_file():
        raise SystemExit(f"Missing file: {path}")

    source = path.read_text()

    if re.search(
        r'''
        function
        \s+
        getParam
        \s*
        \(
            \s*\$pname
            \s*,\s*
            \$pmodule
            \s*=\s*null
        \s*
        \)
        ''',
        source,
        re.IGNORECASE | re.VERBOSE,
    ):
        print(f"ALREADY COMPATIBLE: {path}")
        continue

    updated, count = pattern.subn(replacement, source, count=1)

    if count != 1:
        print(f"\nActual getParam declarations in {path}:")

        for number, line in enumerate(source.splitlines(), start=1):
            if re.search(r"\bfunction\s+getParam\s*\(", line):
                print(f"{number}: {line}")

        raise SystemExit(
            f"Could not update altconfig::getParam() in {path}"
        )

    backup = path.with_name(
        path.name + ".before-php82-getparam-signature"
    )

    if not backup.exists():
        backup.write_text(source)

    path.write_text(updated)
    print(f"UPDATED: {path}")
PY

echo
echo "===== SOURCE DECLARATION ====="

grep -n -A6 -B4 \
    'function[[:space:]]\+getParam' \
    "${SOURCE}"

echo
echo "===== LIVE RUNTIME DECLARATION ====="

grep -n -A6 -B4 \
    'function[[:space:]]\+getParam' \
    "${RUNTIME}"

echo
echo "===== PHP 8.2 LINT ====="

docker compose \
    -f "${COMPOSE}" \
    exec -T web \
    php -l \
    /var/www/html/ch/core_modules/config/classes/altconfig_class_inc.php

echo
echo "Patch complete."
echo "Reload: http://localhost:8082/ch/"
