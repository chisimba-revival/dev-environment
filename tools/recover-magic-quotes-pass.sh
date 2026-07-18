#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="/run/media/derek/main/chisimba-revival"
DEV="${ROOT}/dev-environment"

MODERNISER="${DEV}/tools/php-moderniser/modernise-removed-magic-quotes.php"
RUNNER="${DEV}/scripts/php82-modernise.sh"

COMPOSE="${DEV}/compose/php82.yml"
RUNTIME="${DEV}/runtime/php82-ch"
LOG="${ROOT}/killme.txt"

exec > >(tee "${LOG}") 2>&1

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

section "Milestone 8: Recover magic-quotes pass and continue PHP 8.2"

echo "Started: $(date --iso-8601=seconds)"

for required in \
    "${MODERNISER}" \
    "${COMPOSE}" \
    "${ROOT}/framework/app" \
    "${ROOT}/modules" \
    "${ROOT}/canvases"
do
    [[ -e "${required}" ]] ||
        fail "Required path does not exist: ${required}"
done

section "Remove abandoned temporary moderniser files"

find \
    "${ROOT}/framework/app" \
    "${ROOT}/modules" \
    "${ROOT}/canvases" \
    -type f \
    -name '*.magic-quotes-moderniser.tmp' \
    -print \
    -delete

echo "Temporary files removed."

section "Correct accumulated lint-output reporting bug"

python3 - "${MODERNISER}" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()

old = """    $lintCommand = sprintf(
        'php -l %s 2>&1',
        escapeshellarg($temporary)
    );

    exec($lintCommand, $lintOutput, $lintStatus);
"""

new = """    $lintCommand = sprintf(
        'php -l %s 2>&1',
        escapeshellarg($temporary)
    );

    $lintOutput = [];
    $lintStatus = 0;

    exec($lintCommand, $lintOutput, $lintStatus);
"""

if new in text:
    print("Lint-output reset is already installed.")
elif old in text:
    path.write_text(text.replace(old, new, 1))
    print("Installed per-file lint-output reset.")
else:
    raise SystemExit(
        "Could not find the expected lint execution block."
    )
PY

php -l "${MODERNISER}"

section "Limit current PHP 8.2 pass to framework core"

cat >"${RUNNER}" <<'BASH'
#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="/run/media/derek/main/chisimba-revival"
DEV="${ROOT}/dev-environment"

MODE="${1:---apply}"

case "${MODE}" in
    --apply|--dry-run)
        ;;
    *)
        echo "Usage: $0 [--apply|--dry-run]" >&2
        exit 2
        ;;
esac

php \
    "${DEV}/tools/php-moderniser/modernise-removed-magic-quotes.php" \
    "${MODE}" \
    "${ROOT}/framework/app"
BASH

chmod +x "${RUNNER}"

echo "The PHP 8.2 core pass now targets framework/app only."

section "Verify installer transformation"

INSTALLER="${ROOT}/framework/app/installer/index.php"

grep -n -C 3 \
    -E 'magic_quotes|get_magic_quotes_gpc|install_gpc_stripslashes' \
    "${INSTALLER}" \
    || true

echo

php -l "${INSTALLER}"

if grep -Eq \
    '\bget_magic_quotes_gpc[[:space:]]*\(' \
    "${INSTALLER}"
then
    fail "installer/index.php still calls get_magic_quotes_gpc()."
fi

echo "The removed installer function call is gone."

section "Run corrected framework-only dry run"

"${RUNNER}" --dry-run

section "Run corrected framework-only apply pass"

"${RUNNER}" --apply

section "Check remaining framework magic-quotes calls"

REMAINING="$(
    grep -RInE \
        --include='*.php' \
        --include='*_class_inc.php' \
        --include='*_tpl.php' \
        --exclude='*.before-*' \
        --exclude='*.failed-*' \
        '\b(get_magic_quotes_gpc|get_magic_quotes_runtime|set_magic_quotes_runtime)[[:space:]]*\(' \
        "${ROOT}/framework/app" \
        || true
)"

if [[ -n "${REMAINING}" ]]; then
    echo "${REMAINING}"
    fail "Active framework magic-quotes calls remain."
fi

echo "No active framework magic-quotes calls remain."

section "Record deferred module PHP 8.2 blockers"

echo "The following optional-module files have an independent PHP 8 issue:"
echo

grep -RIn \
    --include='*.php' \
    --include='*.inc.php' \
    'unset[[:space:]]*([[:space:]]*\$this[[:space:]]*)' \
    "${ROOT}/modules/foaf/resources/rdfapi-php/api/util/adodb" \
    "${ROOT}/modules/rdfgen/resources/api/util/adodb" \
    || true

echo
echo "These are not required to test the core installer and are deferred."

section "Stop PHP 8.2 web container"

docker compose \
    -f "${COMPOSE}" \
    stop web \
    || true

section "Reassemble fresh PHP 8.2 runtime"

if [[ -e "${RUNTIME}" ]]; then
    chmod -R u+rwX "${RUNTIME}" 2>/dev/null || true
    rm -rf "${RUNTIME}"
fi

mkdir -p "${RUNTIME}"

echo "Copying framework..."
cp -a "${ROOT}/framework/app/." "${RUNTIME}/"

echo "Copying modules..."
rm -rf "${RUNTIME}/packages"
mkdir -p "${RUNTIME}/packages"
cp -a "${ROOT}/modules/." "${RUNTIME}/packages/"

echo "Copying canvases..."
rm -rf "${RUNTIME}/canvases"
mkdir -p "${RUNTIME}/canvases"
cp -a "${ROOT}/canvases/." "${RUNTIME}/canvases/"

echo "Ensuring fresh installer state..."
rm -f \
    "${RUNTIME}/config/installdone.txt" \
    "${RUNTIME}/tmpinstallfile"

mkdir -p \
    "${RUNTIME}/config" \
    "${RUNTIME}/error_log" \
    "${RUNTIME}/error_logs" \
    "${RUNTIME}/usrfiles" \
    "${RUNTIME}/user_images"

chmod -R a+rwX "${RUNTIME}"

echo "Fresh runtime assembled."

section "Clear prior PHP 8.2 web logs by recreating web container"

docker compose \
    -f "${COMPOSE}" \
    rm -f web \
    || true

docker compose \
    -f "${COMPOSE}" \
    up -d web

docker compose \
    -f "${COMPOSE}" \
    ps -a

section "Request installer after magic-quotes fix"

set +e

HTTP_OUTPUT="$(
    curl \
        --silent \
        --show-error \
        --location \
        --max-time 30 \
        --write-out '\nHTTP_STATUS:%{http_code}\n' \
        "http://localhost:8082/ch/" \
        2>&1
)"

CURL_STATUS=$?

set -e

echo "curl exit status: ${CURL_STATUS}"
echo
printf '%s\n' "${HTTP_OUTPUT}"

section "New first PHP 8.2 fatal"

LOG_EVIDENCE="$(
    {
        docker compose \
            -f "${COMPOSE}" \
            logs --no-color web \
            2>/dev/null

        find "${RUNTIME}" \
            -maxdepth 4 \
            -type f \
            \( -iname '*error*' -o -iname '*.log' \) \
            -exec cat {} + \
            2>/dev/null
    } \
        | grep -Ei \
            'fatal error|parse error|uncaught|compile error|typeerror|valueerror' \
        | head -n 30 \
        || true
)"

if [[ -n "${LOG_EVIDENCE}" ]]; then
    printf '%s\n' "${LOG_EVIDENCE}"
else
    echo "No fatal-pattern line was detected."
fi

section "Recent PHP 8.2 web logs"

docker compose \
    -f "${COMPOSE}" \
    logs --no-color --tail=150 web \
    || true

section "Core source status"

git -C "${ROOT}/framework" status --short

section "PHP 8.2 recovery pass complete"

echo "Finished: $(date --iso-8601=seconds)"
echo
echo "PHP 8.2:"
echo "  http://localhost:8082/ch/"
echo
echo "Upload:"
echo "  ${LOG}"
