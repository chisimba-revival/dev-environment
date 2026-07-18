#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="/run/media/derek/main/chisimba-revival"
DEV="${ROOT}/dev-environment"

PHP74="${DEV}/runtime/php74-ch"
PHP82="${DEV}/runtime/php82-ch"
COMPOSE="${DEV}/compose/php82.yml"
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
    echo
    echo "ERROR: $*" >&2
    exit 1
}

section "Recover PHP 8.2 generated configuration"

echo "Started: $(date --iso-8601=seconds)"

for file in \
    "${PHP74}/config/config.xml" \
    "${PHP74}/config/dbdetails_inc.php" \
    "${PHP82}/config/installdone.txt" \
    "${COMPOSE}"
do
    [[ -f "${file}" ]] ||
        fail "Required file not found: ${file}"
done

section "Back up current PHP 8.2 configuration directory"

BACKUP="${DEV}/runtime/.php82-config-backup-$(date '+%Y%m%d-%H%M%S')"

mkdir -p "${BACKUP}"
cp -a "${PHP82}/config/." "${BACKUP}/"

echo "Backup created:"
echo "  ${BACKUP}"

section "Inspect PHP 7.4 configuration paths"

echo "--- Relevant config.xml values ---"

grep -nE \
    'KEWL_SITEROOT_PATH|KEWL_SYSTEM_ROOT|KEWL_MODULE_PATH|MODULE_URI|KEWL_PEAR_PATH|KEWL_SITEROOT' \
    "${PHP74}/config/config.xml" \
    || true

echo
echo "--- Database details without password values ---"

grep -nE \
    'dbType|dbHost|dbName|database|hostspec|phptype|username' \
    "${PHP74}/config/dbdetails_inc.php" \
    || true

section "Copy generated configuration into PHP 8.2 runtime"

cp -a \
    "${PHP74}/config/config.xml" \
    "${PHP82}/config/config.xml"

cp -a \
    "${PHP74}/config/dbdetails_inc.php" \
    "${PHP82}/config/dbdetails_inc.php"

touch "${PHP82}/config/installdone.txt"

chown www-data:www-data \
    "${PHP82}/config/config.xml" \
    "${PHP82}/config/dbdetails_inc.php" \
    "${PHP82}/config/installdone.txt" \
    2>/dev/null \
    || true

chmod 0644 \
    "${PHP82}/config/config.xml" \
    "${PHP82}/config/dbdetails_inc.php" \
    "${PHP82}/config/installdone.txt"

section "Verify recovered files"

ls -l \
    "${PHP82}/config/config.xml" \
    "${PHP82}/config/dbdetails_inc.php" \
    "${PHP82}/config/installdone.txt"

echo
echo "--- PHP 8.2 relevant config values ---"

grep -nE \
    'KEWL_SITEROOT_PATH|KEWL_SYSTEM_ROOT|KEWL_MODULE_PATH|MODULE_URI|KEWL_PEAR_PATH|KEWL_SITEROOT' \
    "${PHP82}/config/config.xml" \
    || true

section "Verify PHP 8.2 database remains populated"

docker compose \
    -f "${COMPOSE}" \
    exec -T db \
    mysql -uroot -proot -N -e \
    "SELECT COUNT(*) FROM information_schema.tables
     WHERE table_schema='chisimba';"

section "Restart PHP 8.2 web container"

docker compose \
    -f "${COMPOSE}" \
    restart web

sleep 3

docker compose \
    -f "${COMPOSE}" \
    ps -a

section "Request Chisimba root"

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

section "Recent PHP 8.2 log"

docker compose \
    -f "${COMPOSE}" \
    logs --no-color --tail=150 web

section "Recovery complete"

echo "Finished: $(date --iso-8601=seconds)"
echo
echo "Open:"
echo "  http://localhost:8082/ch/"
echo
echo "Output:"
echo "  ${LOG}"
