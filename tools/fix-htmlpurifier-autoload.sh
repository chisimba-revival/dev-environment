#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="/run/media/derek/main/chisimba-revival"
LOG="${ROOT}/killme.txt"

SOURCE="${ROOT}/framework/app/lib/HTMLPurifier.autoload.php"
RUNTIME="${ROOT}/dev-environment/runtime/php82-ch/lib/HTMLPurifier.autoload.php"
COMPOSE="${ROOT}/dev-environment/compose/php82.yml"

exec >"${LOG}" 2>&1

fail()
{
    echo "ERROR: $*" >&2
    exit 1
}

echo "============================================================"
echo "PHP 8.2: Replace HTML Purifier __autoload()"
echo "============================================================"
echo

for FILE in "${SOURCE}" "${RUNTIME}"; do
    [[ -f "${FILE}" ]] || fail "Missing file: ${FILE}"
done

python3 - "${SOURCE}" "${RUNTIME}" <<'PY'
from pathlib import Path
import re
import sys

for filename in sys.argv[1:]:
    path = Path(filename)
    source = path.read_text()

    if (
        "spl_autoload_register" in source
        and "function HTMLPurifier_autoload" in source
        and not re.search(
            r"\bfunction\s+__autoload\s*\(",
            source,
            re.IGNORECASE,
        )
    ):
        print(f"ALREADY MODERNISED: {path}")
        continue

    backup = path.with_name(
        path.name + ".before-php82-spl-autoload"
    )

    if not backup.exists():
        backup.write_text(source)

    updated, count = re.subn(
        r"\bfunction\s+__autoload\s*\(",
        "function HTMLPurifier_autoload(",
        source,
        count=1,
        flags=re.IGNORECASE,
    )

    if count != 1:
        print(f"\nCurrent contents of {path}:")
        print(source[:2000])
        raise SystemExit(
            f"Could not find exactly one __autoload() declaration in {path}"
        )

    # Register the renamed function after its declaration. Insert before the
    # closing PHP tag when one exists, otherwise append to the file.
    registration = """
if (
    function_exists('spl_autoload_register')
    && !in_array(
        'HTMLPurifier_autoload',
        spl_autoload_functions() ?: array(),
        true
    )
) {
    spl_autoload_register('HTMLPurifier_autoload');
}
"""

    if "spl_autoload_register('HTMLPurifier_autoload')" not in updated:
        closing = updated.rfind("?>")

        if closing >= 0:
            updated = (
                updated[:closing]
                + registration
                + "\n"
                + updated[closing:]
            )
        else:
            updated = updated.rstrip() + "\n\n" + registration

    path.write_text(updated)

    print(f"UPDATED: {path}")

PY

echo
echo "===== SOURCE FILE ====="
nl -ba "${SOURCE}" | sed -n '1,90p'

echo
echo "===== RUNTIME FILE ====="
nl -ba "${RUNTIME}" | sed -n '1,90p'

echo
echo "===== VERIFY __autoload IS GONE ====="

if grep -En \
    '\bfunction[[:space:]]+__autoload[[:space:]]*\(' \
    "${SOURCE}" "${RUNTIME}"
then
    fail "__autoload() declarations remain."
fi

echo "No __autoload() declaration remains."

echo
echo "===== PHP 8.2 LINT ====="

docker compose \
    -f "${COMPOSE}" \
    exec -T web \
    php -l /var/www/html/ch/lib/HTMLPurifier.autoload.php

echo
echo "===== DIRECT AUTOLOADER TEST ====="

docker compose \
    -f "${COMPOSE}" \
    exec -T web \
    php -r '
        require "/var/www/html/ch/lib/HTMLPurifier.autoload.php";

        $loaders = spl_autoload_functions() ?: array();

        echo "Registered: ",
            in_array("HTMLPurifier_autoload", $loaders, true)
                ? "yes"
                : "no",
            PHP_EOL;

        if (!in_array("HTMLPurifier_autoload", $loaders, true)) {
            exit(1);
        }
    '

echo
echo "============================================================"
echo "HTML Purifier autoloader modernised."
echo "Reload: http://localhost:8082/ch/"
echo "============================================================"
