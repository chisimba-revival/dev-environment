#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="/run/media/derek/main/chisimba-revival"
DEV="${ROOT}/dev-environment"

SOURCE="${ROOT}/framework/app/installer/installwizard.inc"
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

section "Milestone 8: Restore PHP 8 constructor execution"

echo "Started: $(date --iso-8601=seconds)"

for required in \
    "${SOURCE}" \
    "${COMPOSE}" \
    "${ROOT}/framework/app" \
    "${ROOT}/modules" \
    "${ROOT}/canvases"
do
    [[ -e "${required}" ]] ||
        fail "Required path does not exist: ${required}"
done

section "Inspect legacy InstallWizard constructor"

grep -n -A30 -B5 \
    'function[[:space:]]\+InstallWizard' \
    "${SOURCE}" \
    || fail "Legacy InstallWizard constructor was not found."

section "Back up installer source"

BACKUP="${SOURCE}.before-php82-constructor-$(date '+%Y%m%d-%H%M%S')"

cp -a "${SOURCE}" "${BACKUP}"

echo "Backup:"
echo "  ${BACKUP}"

section "Add PHP 8 constructor wrapper"

python3 - "${SOURCE}" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text()

class_match = re.search(
    r'class\s+InstallWizard\s+extends\s+Wizard\s*\{',
    text,
    flags=re.IGNORECASE,
)

if not class_match:
    raise SystemExit("InstallWizard class declaration was not found.")

class_start = class_match.end()

next_class = re.search(
    r'\nclass\s+\w+',
    text[class_start:],
    flags=re.IGNORECASE,
)

if next_class:
    class_end = class_start + next_class.start()
else:
    class_end = len(text)

class_text = text[class_start:class_end]

if re.search(
    r'function\s+__construct\s*\(',
    class_text,
    flags=re.IGNORECASE,
):
    print("InstallWizard already has __construct(); no change required.")
    raise SystemExit(0)

legacy = re.search(
    r'(?P<indent>^[ \t]*)'
    r'public\s+function\s+InstallWizard\s*\(\s*\)',
    class_text,
    flags=re.IGNORECASE | re.MULTILINE,
)

if not legacy:
    legacy = re.search(
        r'(?P<indent>^[ \t]*)'
        r'function\s+InstallWizard\s*\(\s*\)',
        class_text,
        flags=re.IGNORECASE | re.MULTILINE,
    )

if not legacy:
    raise SystemExit(
        "Could not find the legacy InstallWizard() method."
    )

indent = legacy.group("indent")

wrapper = (
    f"{indent}/**\n"
    f"{indent} * PHP 8 constructor wrapper.\n"
    f"{indent} *\n"
    f"{indent} * PHP 8 no longer invokes methods named after their class\n"
    f"{indent} * as constructors. Preserve the existing initialization\n"
    f"{indent} * logic by calling the legacy constructor explicitly.\n"
    f"{indent} */\n"
    f"{indent}public function __construct()\n"
    f"{indent}{{\n"
    f"{indent}    $this->InstallWizard();\n"
    f"{indent}}}\n\n"
)

absolute_position = class_start + legacy.start()

updated = (
    text[:absolute_position]
    + wrapper
    + text[absolute_position:]
)

path.write_text(updated)

print("Added InstallWizard::__construct() wrapper.")
PY

section "Verify constructor source"

grep -n -A35 -B5 \
    -E 'function[[:space:]]+(__construct|InstallWizard)' \
    "${SOURCE}"

echo

docker compose \
    -f "${COMPOSE}" \
    run --rm --no-deps web \
    php -l /var/www/html/ch/installer/installwizard.inc \
    2>/dev/null \
    || php -l "${SOURCE}"

section "Create reusable profile-driven runtime rebuild script"

mkdir -p "$(dirname "${REBUILD}")"

cat >"${REBUILD}" <<'BASH'
#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="/run/media/derek/main/chisimba-revival"
DEV="${ROOT}/dev-environment"

PROFILE="${1:-}"
MODE="${2:---preserve-db}"

usage()
{
    echo "Usage:"
    echo "  $0 php74 [--preserve-db|--fresh-db]"
    echo "  $0 php82 [--preserve-db|--fresh-db]"
}

case "${PROFILE}" in
    php74|php82)
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac

case "${MODE}" in
    --preserve-db|--fresh-db)
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac

COMPOSE="${DEV}/compose/${PROFILE}.yml"
RUNTIME="${DEV}/runtime/${PROFILE}-ch"

FRAMEWORK="${ROOT}/framework/app"
MODULES="${ROOT}/modules"
CANVASES="${ROOT}/canvases"

for required in \
    "${COMPOSE}" \
    "${FRAMEWORK}" \
    "${MODULES}" \
    "${CANVASES}"
do
    if [[ ! -e "${required}" ]]; then
        echo "ERROR: Missing required path: ${required}" >&2
        exit 1
    fi
done

echo "============================================================"
echo "Rebuild Chisimba runtime"
echo "Profile: ${PROFILE}"
echo "Mode: ${MODE}"
echo "Runtime: ${RUNTIME}"
echo "============================================================"

if [[ "${MODE}" == "--fresh-db" ]]; then
    echo "Stopping stack and deleting only the ${PROFILE} volumes..."

    docker compose \
        -f "${COMPOSE}" \
        down -v --remove-orphans
else
    echo "Stopping ${PROFILE} web container..."

    docker compose \
        -f "${COMPOSE}" \
        stop web \
        || true
fi

echo "Removing disposable runtime..."

if [[ -e "${RUNTIME}" ]]; then
    chmod -R u+rwX "${RUNTIME}" 2>/dev/null || true
    rm -rf "${RUNTIME}"
fi

mkdir -p "${RUNTIME}"

echo "Copying framework..."
cp -a "${FRAMEWORK}/." "${RUNTIME}/"

echo "Copying modules..."
rm -rf "${RUNTIME}/packages"
mkdir -p "${RUNTIME}/packages"
cp -a "${MODULES}/." "${RUNTIME}/packages/"

echo "Copying canvases..."
rm -rf "${RUNTIME}/canvases"
mkdir -p "${RUNTIME}/canvases"
cp -a "${CANVASES}/." "${RUNTIME}/canvases/"

echo "Removing installer completion state..."
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

echo "Starting ${PROFILE} stack..."

docker compose \
    -f "${COMPOSE}" \
    up -d

echo
docker compose \
    -f "${COMPOSE}" \
    ps -a

echo
echo "Runtime rebuild complete."
BASH

chmod +x "${REBUILD}"

echo "Reusable rebuild command created:"
echo "  ${REBUILD} php82 --fresh-db"

section "Rebuild PHP 8.2 from a completely fresh state"

"${REBUILD}" php82 --fresh-db

section "Confirm constructor exists in assembled runtime"

grep -n -A15 -B3 \
    'function[[:space:]]\+__construct' \
    "${DEV}/runtime/php82-ch/installer/installwizard.inc"

section "Request PHP 8.2 installer"

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

section "First fatal after constructor fix"

FATAL_OUTPUT="$(
    docker compose \
        -f "${COMPOSE}" \
        logs --no-color --since=2m web \
        2>/dev/null \
    | grep -Ei \
        'fatal error|uncaught|typeerror|valueerror|parse error|compile error' \
    | head -n 30 \
    || true
)"

if [[ -n "${FATAL_OUTPUT}" ]]; then
    printf '%s\n' "${FATAL_OUTPUT}"
else
    echo "No fatal-pattern line was detected."
fi

section "Recent PHP 8.2 web log"

docker compose \
    -f "${COMPOSE}" \
    logs --no-color --tail=150 web \
    || true

section "Installer page indicators"

printf '%s\n' "${HTTP_OUTPUT}" \
    | grep -Ei \
        'chisimba|installer|performing step|welcome|fatal error|warning|notice' \
    | head -n 80 \
    || true

section "Repository status"

echo "--- framework ---"
git -C "${ROOT}/framework" status --short

echo
echo "--- dev-environment ---"
git -C "${DEV}" status --short

section "Constructor migration pass complete"

echo "Finished: $(date --iso-8601=seconds)"
echo
echo "PHP 8.2:"
echo "  http://localhost:8082/ch/"
echo
echo "Future PHP 8.2 clean rebuild command:"
echo "  ${REBUILD} php82 --fresh-db"
echo
echo "Future PHP 8.2 runtime-only rebuild command:"
echo "  ${REBUILD} php82 --preserve-db"
echo
echo "Upload:"
echo "  ${LOG}"
