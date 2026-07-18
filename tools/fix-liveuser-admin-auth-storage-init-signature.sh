#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="/run/media/derek/main/chisimba-revival"
SOURCE="$ROOT/framework/app/lib/pear/LiveUser/Admin/Auth/Storage/MDB2.php"
RUNTIME="$ROOT/dev-environment/runtime/php82-ch/lib/pear/LiveUser/Admin/Auth/Storage/MDB2.php"
COMPOSE="$ROOT/dev-environment/compose/php82.yml"
OUT="$ROOT/killme.txt"

exec >"$OUT" 2>&1

section()
{
    echo
    echo "============================================================"
    echo "$1"
    echo "============================================================"
}

fail()
{
    echo "ERROR: $*" >&2
    exit 1
}

section "PHP 8.2: Align LiveUser MDB2 init signature"

for FILE in "$SOURCE" "$RUNTIME"; do
    [[ -f "$FILE" ]] || fail "Missing file: $FILE"
done

python3 - "$SOURCE" "$RUNTIME" <<'PY'
from pathlib import Path
import re
import sys

pattern = re.compile(
    r'''
    function
    \s+
    init
    \s*
    \(
        \s*&\s*\$storageConf
    \s*
    \)
    ''',
    re.IGNORECASE | re.VERBOSE,
)

replacement = (
    "function init(&$storageConf, $structure = null)"
)

for filename in sys.argv[1:]:
    path = Path(filename)
    text = path.read_text(errors="replace")

    if re.search(
        r'''
        function
        \s+
        init
        \s*
        \(
            \s*&\s*\$storageConf
            \s*,\s*
            \$structure
        ''',
        text,
        re.IGNORECASE | re.VERBOSE,
    ):
        print(f"ALREADY COMPATIBLE: {path}")
        continue

    updated, count = pattern.subn(
        replacement,
        text,
        count=1,
    )

    if count != 1:
        print(f"Could not match init(&$storageConf) in {path}")

        for number, line in enumerate(
            text.splitlines(),
            start=1,
        ):
            if re.search(r"\bfunction\s+init\s*\(", line):
                print(f"{number}: {line}")

        raise SystemExit(1)

    backup = path.with_name(
        path.name + ".before-php82-init-signature"
    )

    if not backup.exists():
        backup.write_text(text)

    path.write_text(updated)
    print(f"UPDATED: {path}")
PY

section "Updated declarations"

echo "--- Child source ---"

grep -n -A18 -B8 \
    'function[[:space:]]\+init' \
    "$SOURCE"

echo
echo "--- Parent source ---"

grep -n -A18 -B8 \
    'function[[:space:]]\+init' \
    "$ROOT/framework/app/lib/pear/LiveUser/Admin/Storage/MDB2.php"

section "PHP 8.2 lint"

docker compose \
    -f "$COMPOSE" \
    exec -T web \
    php -l \
    /var/www/html/ch/lib/pear/LiveUser/Admin/Auth/Storage/MDB2.php

section "Inheritance validation"

docker compose \
    -f "$COMPOSE" \
    exec -T web \
    php -d include_path=/var/www/html/ch/lib/pear <<'PHP'
<?php

require_once 'LiveUser/Admin/Storage/MDB2.php';
require_once 'LiveUser/Admin/Auth/Storage/MDB2.php';

$parent = new ReflectionMethod(
    'LiveUser_Admin_Storage_MDB2',
    'init'
);

$child = new ReflectionMethod(
    'LiveUser_Admin_Auth_Storage_MDB2',
    'init'
);

echo 'Parent parameters: ',
    $parent->getNumberOfParameters(),
    PHP_EOL;

echo 'Parent required: ',
    $parent->getNumberOfRequiredParameters(),
    PHP_EOL;

echo 'Child parameters: ',
    $child->getNumberOfParameters(),
    PHP_EOL;

echo 'Child required: ',
    $child->getNumberOfRequiredParameters(),
    PHP_EOL;
PHP

section "Request Chisimba"

curl \
    --silent \
    --show-error \
    --location \
    --max-time 45 \
    --write-out '\nHTTP_STATUS:%{http_code}\n' \
    "http://localhost:8082/ch/" \
    || true

section "Recent web log"

docker compose \
    -f "$COMPOSE" \
    logs --no-color --tail=150 web

section "Patch complete"

echo "Reload:"
echo "  http://localhost:8082/ch/"
