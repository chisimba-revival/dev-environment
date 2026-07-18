#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="/run/media/derek/main/chisimba-revival"
DEV="${ROOT}/dev-environment"

FRAMEWORK="${ROOT}/framework/app"
INSTALLER="${FRAMEWORK}/installer"
PASS="${DEV}/tools/php-moderniser/modernise-legacy-constructors.php"
REBUILD="${DEV}/scripts/rebuild-runtime.sh"
COMPOSE="${DEV}/compose/php82.yml"
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

section "Milestone 8: Finish constructor-wrapper cleanup"

echo "Started: $(date --iso-8601=seconds)"

for required in \
    "${FRAMEWORK}" \
    "${INSTALLER}" \
    "${PASS}" \
    "${REBUILD}" \
    "${COMPOSE}"
do
    [[ -e "${required}" ]] ||
        fail "Required path does not exist: ${required}"
done

section "Remove remaining generated wrapper blocks"

python3 - "${FRAMEWORK}" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])

pattern = re.compile(
    r'''
    ^[ \t]*/\*\*
    .*?
    PHP[ ]8[ ]constructor[ ]wrapper[ ]for[ ]the[ ]legacy
    .*?
    \*/[ \t]*\r?\n
    [ \t]*public[ \t]+function[ \t]+__construct[ \t]*\([ \t]*\)
    [ \t]*\r?\n
    [ \t]*\{
    [ \t]*\r?\n
    [ \t]*call_user_func_array[ \t]*\(
    [ \t]*\r?\n
    [ \t]*\[\$this,[ \t]*['"][A-Za-z_][A-Za-z0-9_]*['"]\],[ \t]*
    \r?\n
    [ \t]*func_get_args[ \t]*\([ \t]*\)[ \t]*
    \r?\n
    [ \t]*\)[ \t]*;
    [ \t]*\r?\n
    [ \t]*\}
    [ \t]*(?:\r?\n){1,2}
    ''',
    re.MULTILINE | re.DOTALL | re.VERBOSE,
)

changed_files = 0
removed = 0

for path in root.rglob("*"):
    if not path.is_file():
        continue

    name = path.name.lower()

    if not (
        name.endswith(".php")
        or name.endswith(".inc")
        or name.endswith(".inc.php")
    ):
        continue

    try:
        source = path.read_text()
    except (UnicodeDecodeError, OSError):
        continue

    if "PHP 8 constructor wrapper for the legacy" not in source:
        continue

    updated, count = pattern.subn("", source)

    if count == 0:
        print(f"UNMATCHED: {path}", file=sys.stderr)
        continue

    path.write_text(updated)

    changed_files += 1
    removed += count

    print(f"RESTORED ({count}): {path}")

print()
print(f"Files restored: {changed_files}")
print(f"Wrappers removed: {removed}")
PY

section "Verify no broad-pass markers remain"

mapfile -t REMAINING < <(
    grep -RIl \
        --include='*.php' \
        --include='*.inc' \
        --include='*.inc.php' \
        'PHP 8 constructor wrapper for the legacy' \
        "${FRAMEWORK}" \
        || true
)

echo "Files still containing generated marker: ${#REMAINING[@]}"

if (( ${#REMAINING[@]} > 0 )); then
    printf '%s\n' "${REMAINING[@]}"
    fail "Some generated wrappers could not be removed."
fi

echo "All broad-pass constructor wrappers are gone."

section "Verify manually created InstallWizard constructor remains"

INSTALLWIZARD="${INSTALLER}/installwizard.inc"

COUNT="$(
    grep -Ec \
        'function[[:space:]]+__construct[[:space:]]*\(' \
        "${INSTALLWIZARD}"
)"

echo "InstallWizard constructor count: ${COUNT}"

if [[ "${COUNT}" -ne 1 ]]; then
    fail "InstallWizard should retain exactly one constructor."
fi

section "Apply legacy-constructor pass to installer only"

php "${PASS}" --dry-run "${INSTALLER}"
php "${PASS}" --apply "${INSTALLER}"

section "Verify installer-only pass is idempotent"

RESULT="$(
    php "${PASS}" --dry-run "${INSTALLER}"
)"

printf '%s\n' "${RESULT}"

if ! grep -q 'Constructor wrappers: 0' <<<"${RESULT}"; then
    fail "Installer-only constructor pass is not idempotent."
fi

section "Verify Template constructor"

TEMPLATE="${INSTALLER}/template.inc"

grep -n -A22 -B5 \
    -E 'class[[:space:]]+Template|function[[:space:]]+(__construct|Template)' \
    "${TEMPLATE}"

if ! grep -Eq \
    'function[[:space:]]+__construct[[:space:]]*\(' \
    "${TEMPLATE}"
then
    fail "Template constructor was not added."
fi

section "Rebuild PHP 8.2 from a fresh database"

"${REBUILD}" php82 --fresh-db

section "Request installer"

sleep 3

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

section "First current PHP 8.2 failure"

PAGE_FAILURES="$(
    printf '%s\n' "${HTTP_OUTPUT}" \
    | grep -Ei \
        'fatal error|uncaught|typeerror|valueerror|parse error|compile error' \
    | head -n 30 \
    || true
)"

LOG_FAILURES="$(
    docker compose \
        -f "${COMPOSE}" \
        logs --no-color --since=2m web \
        2>/dev/null \
    | grep -Ei \
        'fatal error|uncaught|typeerror|valueerror|parse error|compile error' \
    | head -n 30 \
    || true
)"

if [[ -n "${PAGE_FAILURES}" ]]; then
    echo "--- Browser response ---"
    printf '%s\n' "${PAGE_FAILURES}"
fi

if [[ -n "${LOG_FAILURES}" ]]; then
    echo
    echo "--- Container log ---"
    printf '%s\n' "${LOG_FAILURES}"
fi

if [[ -z "${PAGE_FAILURES}" && -z "${LOG_FAILURES}" ]]; then
    echo "No fatal-pattern line was detected."
fi

section "Installer page indicators"

printf '%s\n' "${HTTP_OUTPUT}" \
    | grep -Ei \
        'chisimba|installer|welcome|licence|step|fatal error|warning' \
    | head -n 100 \
    || true

section "Recent web log"

docker compose \
    -f "${COMPOSE}" \
    logs --no-color --tail=120 web \
    || true

section "Framework status"

git -C "${ROOT}/framework" status --short

section "Cleanup and scoped migration complete"

echo "Finished: $(date --iso-8601=seconds)"
echo
echo "PHP 8.2:"
echo "  http://localhost:8082/ch/"
echo
echo "Upload:"
echo "  ${LOG}"
