#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="/run/media/derek/main/chisimba-revival"
LOG="${ROOT}/killme.txt"

SOURCE="${ROOT}/framework/app/lib/pear/Config/Container.php"
RUNTIME="${ROOT}/dev-environment/runtime/php82-ch/lib/pear/Config/Container.php"
COMPOSE="${ROOT}/dev-environment/compose/php82.yml"

exec >"${LOG}" 2>&1

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

section "PHP 8.2: Make PEAR Config count() null-safe"

for FILE in "${SOURCE}" "${RUNTIME}"; do
    [[ -f "${FILE}" ]] || fail "Missing file: ${FILE}"
done

section "Inspect the failing source context"

echo "--- Repository source ---"
nl -ba "${SOURCE}" | sed -n '680,735p'

echo
echo "--- Live runtime ---"
nl -ba "${RUNTIME}" | sed -n '680,735p'

section "Apply a targeted null-safe count transformation"

python3 - "${SOURCE}" "${RUNTIME}" <<'PY'
from pathlib import Path
import re
import sys

for filename in sys.argv[1:]:
    path = Path(filename)
    source = path.read_text()

    # Restrict the change to Config_Container::toArray().
    method_match = re.search(
        r'function\s+toArray\s*\([^)]*\)\s*\{',
        source,
        re.IGNORECASE,
    )

    if not method_match:
        raise SystemExit(f"Could not find Config_Container::toArray() in {path}")

    body_start = source.find("{", method_match.start())
    depth = 0
    body_end = None

    for index in range(body_start, len(source)):
        char = source[index]

        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                body_end = index
                break

    if body_end is None:
        raise SystemExit(f"Could not locate the end of toArray() in {path}")

    prefix = source[:body_start + 1]
    body = source[body_start + 1:body_end]
    suffix = source[body_end:]

    # Convert count($value) to count((array) $value) only inside toArray().
    # Casting null to an empty array preserves the historical PHP 7 behaviour:
    # count(null) effectively meant zero.
    updated_body, count = re.subn(
        r'count\s*\(\s*(\$[A-Za-z_][A-Za-z0-9_]*(?:->[A-Za-z_][A-Za-z0-9_]*)*)\s*\)',
        r'count((array) \1)',
        body,
    )

    if count == 0:
        if "count((array)" in body:
            print(f"ALREADY COMPATIBLE: {path}")
            continue

        print(f"No count() expression found inside toArray() in {path}")
        print(body)
        raise SystemExit(1)

    backup = path.with_name(path.name + ".before-php82-null-count")

    if not backup.exists():
        backup.write_text(source)

    path.write_text(prefix + updated_body + suffix)

    print(f"UPDATED ({count} count call(s)): {path}")
PY

section "Verify the changed method"

echo "--- Repository source ---"
nl -ba "${SOURCE}" | sed -n '690,730p'

echo
echo "--- Live runtime ---"
nl -ba "${RUNTIME}" | sed -n '690,730p'

section "PHP 8.2 syntax validation"

docker compose \
    -f "${COMPOSE}" \
    exec -T web \
    php -l /var/www/html/ch/lib/pear/Config/Container.php

section "Request Chisimba and capture the next result"

set +e

curl \
    --silent \
    --show-error \
    --location \
    --max-time 30 \
    --write-out '\nHTTP_STATUS:%{http_code}\n' \
    "http://localhost:8082/ch/"

CURL_STATUS=$?

set -e

echo
echo "curl exit status: ${CURL_STATUS}"

section "Recent PHP 8.2 web log"

docker compose \
    -f "${COMPOSE}" \
    logs --no-color --tail=120 web

section "Patch complete"

echo "Reload in the browser:"
echo "  http://localhost:8082/ch/"
