#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="/run/media/derek/main/chisimba-revival"
DEV="${ROOT}/dev-environment"

SOURCE="${ROOT}/framework/app/installer/steps/createconfigs.inc"
REBUILD="${DEV}/scripts/rebuild-runtime.sh"
COMPOSE="${DEV}/compose/php82.yml"
RUNTIME="${DEV}/runtime/php82-ch"
LOG="${ROOT}/killme.txt"

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

section "PHP 8.2 installer config.xml compatibility"

echo "Started: $(date --iso-8601=seconds)"

for REQUIRED in \
    "${SOURCE}" \
    "${REBUILD}" \
    "${COMPOSE}"
do
    [[ -e "${REQUIRED}" ]] ||
        fail "Missing required path: ${REQUIRED}"
done

section "Patch createconfigs.inc"

python3 - "${SOURCE}" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
source = path.read_text()

marker = "PHP 8 compatibility: ensure config.xml has one document root"

if marker in source:
    print("Config XML compatibility patch is already present.")
    raise SystemExit(0)

needle = '''        $write = $this->_root->writeConfig("{$path}config.xml", 'XML', $options);
'''

replacement = '''        $write = $this->_root->writeConfig("{$path}config.xml", 'XML', $options);

        /*
         * PHP 8 compatibility: ensure config.xml has one document root.
         *
         * The legacy PEAR Config XML writer can emit the individual
         * configuration directives as adjacent top-level XML elements.
         * XML documents require exactly one root element.
         */
        $configFile = "{$path}config.xml";
        $configXml = @file_get_contents($configFile);

        if ($configXml !== false) {
            libxml_use_internal_errors(true);
            $validConfigXml = simplexml_load_string($configXml);

            if ($validConfigXml === false) {
                $configBody = preg_replace(
                    '/^\\\\s*<\\\\?xml[^>]*\\\\?>\\\\s*/i',
                    '',
                    $configXml
                );

                $configXml = "<?xml version=\\"1.0\\" encoding=\\"ISO-8859-1\\"?>\\n"
                    . "<Settings>\\n"
                    . trim($configBody)
                    . "\\n</Settings>\\n";

                if (@file_put_contents($configFile, $configXml) === false) {
                    $this->errors[] = 'Could not write a valid config.xml file.';
                }
            }

            libxml_clear_errors();
        }
'''

if needle not in source:
    raise SystemExit(
        "Expected writeConfig() statement was not found. No change made."
    )

backup = path.with_name(path.name + ".before-php82-config-root")

if not backup.exists():
    backup.write_text(source)
    print(f"Backup: {backup}")

path.write_text(source.replace(needle, replacement, 1))
print(f"Updated: {path}")
PY

section "Verify patched source"

grep -n -A55 -B8 \
    'PHP 8 compatibility: ensure config.xml has one document root' \
    "${SOURCE}"

php -l "${SOURCE}"

section "Restart Docker and rebuild a completely fresh runtime"

docker compose \
    -f "${COMPOSE}" \
    up -d \
    || true

"${REBUILD}" php82 --fresh-db

section "Verify clean installer state"

for FILE in \
    "${RUNTIME}/config/config.xml" \
    "${RUNTIME}/config/dbdetails_inc.php" \
    "${RUNTIME}/config/installdone.txt" \
    "${RUNTIME}/tmpinstallfile"
do
    if [[ -e "${FILE}" ]]; then
        echo "UNEXPECTED PRESENT: ${FILE}"
        exit 1
    else
        echo "ABSENT AS EXPECTED: ${FILE}"
    fi
done

section "Verify empty Chisimba database"

TABLE_COUNT="$(
    docker compose \
        -f "${COMPOSE}" \
        exec -T db \
        mysql -uroot -proot -N -e \
        "SELECT COUNT(*)
         FROM information_schema.tables
         WHERE table_schema='chisimba';"
)"

echo "Chisimba table count: ${TABLE_COUNT}"

if [[ "${TABLE_COUNT}" != "0" ]]; then
    fail "Fresh database is not empty."
fi

section "Container status"

docker compose \
    -f "${COMPOSE}" \
    ps -a

section "Fresh PHP 8.2 installer ready"

echo "Finished: $(date --iso-8601=seconds)"
echo
echo "Open a new incognito window:"
echo "  http://localhost:8082/ch/"
echo
echo "Do not reuse an earlier installer tab."
