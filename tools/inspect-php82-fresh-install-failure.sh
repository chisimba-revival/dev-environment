#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="/run/media/derek/main/chisimba-revival"
DEV="${ROOT}/dev-environment"
RUNTIME="${DEV}/runtime/php82-ch"
COMPOSE="${DEV}/compose/php82.yml"
OUT="${ROOT}/killme.txt"

exec >"${OUT}" 2>&1

section()
{
    echo
    echo "============================================================"
    echo "$1"
    echo "============================================================"
}

section "PHP 8.2 fresh-install failure inspection"
echo "Generated: $(date --iso-8601=seconds)"

section "Generated configuration files"

for FILE in \
    "${RUNTIME}/config/config.xml" \
    "${RUNTIME}/config/dbdetails_inc.php" \
    "${RUNTIME}/config/installdone.txt"
do
    echo
    echo "FILE: ${FILE}"

    if [[ ! -e "${FILE}" ]]; then
        echo "MISSING"
        continue
    fi

    ls -l "${FILE}"
    file "${FILE}" || true
    wc -c -l "${FILE}" || true
done

section "config.xml with visible line endings"

CONFIG="${RUNTIME}/config/config.xml"

if [[ -f "${CONFIG}" ]]; then
    nl -ba "${CONFIG}" | sed -n '1,120p'

    echo
    echo "--- Visible control characters ---"
    sed -n '1,40l' "${CONFIG}"

    echo
    echo "--- Hexadecimal beginning and end ---"
    xxd -g 1 -l 512 "${CONFIG}" || true

    SIZE="$(stat -c '%s' "${CONFIG}")"

    if (( SIZE > 512 )); then
        START=$(( SIZE - 512 ))
        xxd -g 1 -s "${START}" "${CONFIG}" || true
    fi

    echo
    echo "--- XML validation ---"

    docker compose \
        -f "${COMPOSE}" \
        exec -T web \
        php -r '
            libxml_use_internal_errors(true);

            $file = "/var/www/html/ch/config/config.xml";
            $xml = simplexml_load_file($file);

            if ($xml !== false) {
                echo "simplexml_load_file: VALID", PHP_EOL;
                exit(0);
            }

            echo "simplexml_load_file: INVALID", PHP_EOL;

            foreach (libxml_get_errors() as $error) {
                echo trim($error->message),
                    " at line ",
                    $error->line,
                    ", column ",
                    $error->column,
                    PHP_EOL;
            }

            exit(1);
        ' || true
else
    echo "config.xml is missing."
fi

section "Current chisimba database tables"

docker compose \
    -f "${COMPOSE}" \
    exec -T db \
    mysql -uroot -proot -N -e '
        SELECT table_name
        FROM information_schema.tables
        WHERE table_schema = "chisimba"
        ORDER BY table_name;
    ' || true

section "Exact tbl_en state"

docker compose \
    -f "${COMPOSE}" \
    exec -T db \
    mysql -uroot -proot -e '
        SELECT table_name, engine, table_rows
        FROM information_schema.tables
        WHERE table_schema = "chisimba"
          AND table_name = "tbl_en";

        SHOW CREATE TABLE chisimba.tbl_en;
    ' || true

section "Source definitions that create tbl_en"

grep -RIn \
    --include='*.sql' \
    --include='*.xml' \
    --include='*.inc' \
    --include='*.php' \
    -E 'CREATE[[:space:]]+TABLE[[:space:]]+`?tbl_en|tbl_en' \
    "${ROOT}/framework/app" \
    "${ROOT}/modules" \
    | head -n 300 \
    || true

section "English language SQL file"

for FILE in \
    "${ROOT}/framework/app/core_modules/language/sql/tbl_english.sql" \
    "${RUNTIME}/core_modules/language/sql/tbl_english.sql"
do
    echo
    echo "FILE: ${FILE}"

    if [[ -f "${FILE}" ]]; then
        nl -ba "${FILE}" | sed -n '1,220p'
    else
        echo "MISSING"
    fi
done

section "Installer database-create error handling"

nl -ba \
    "${ROOT}/framework/app/installer/steps/databasecreate.inc" \
    | sed -n '130,340p'

section "Installer config-writing code"

nl -ba \
    "${ROOT}/framework/app/installer/steps/createconfigs.inc" \
    | sed -n '430,590p'

section "Textual runtime error logs"

find "${RUNTIME}" \
    -maxdepth 4 \
    -type f \
    \( \
        -name '*.log' \
        -o -name 'error_log' \
        -o -name 'php_errors.log' \
    \) \
    -print0 \
    | while IFS= read -r -d '' FILE; do
        MIME="$(file --brief --mime-type "${FILE}" 2>/dev/null || true)"

        case "${MIME}" in
            text/*|inode/x-empty|application/json|application/xml)
                echo
                echo "FILE: ${FILE}"
                tail -n 160 "${FILE}" || true
                ;;
        esac
    done

section "Recent container log"

docker compose \
    -f "${COMPOSE}" \
    logs --no-color --tail=250 web \
    || true

section "Database server log"

docker compose \
    -f "${COMPOSE}" \
    logs --no-color --tail=150 db \
    || true

section "Inspection complete"
echo "No files or database records were changed."
