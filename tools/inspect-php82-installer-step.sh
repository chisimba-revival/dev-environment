#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="/run/media/derek/main/chisimba-revival"
DEV="${ROOT}/dev-environment"
COMPOSE="${DEV}/compose/php82.yml"
RUNTIME="${DEV}/runtime/php82-ch"
SOURCE="${ROOT}/framework/app"
LOG="${ROOT}/killme.txt"

RUNTIME_FILE="${RUNTIME}/installer/installwizard.inc"
SOURCE_FILE="${SOURCE}/installer/installwizard.inc"
WIZARD_FILE="${SOURCE}/installer/wizard.inc"
INDEX_FILE="${SOURCE}/installer/index.php"

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

section "Milestone 8: Inspect PHP 8.2 installer step-object failure"

echo "Started: $(date --iso-8601=seconds)"

for required in \
    "${COMPOSE}" \
    "${RUNTIME_FILE}" \
    "${SOURCE_FILE}" \
    "${WIZARD_FILE}" \
    "${INDEX_FILE}"
do
    [[ -f "${required}" ]] ||
        fail "Required file not found: ${required}"
done

section "PHP 8.2 container status"

docker compose \
    -f "${COMPOSE}" \
    ps -a

section "Fatal location in source repository"

echo "File: ${SOURCE_FILE}"
echo

nl -ba "${SOURCE_FILE}" |
    sed -n '360,440p'

section "Fatal location in assembled runtime"

echo "File: ${RUNTIME_FILE}"
echo

nl -ba "${RUNTIME_FILE}" |
    sed -n '360,440p'

section "Confirm source and runtime are identical"

if cmp -s "${SOURCE_FILE}" "${RUNTIME_FILE}"; then
    echo "Source and runtime installwizard.inc files are identical."
else
    echo "WARNING: Source and runtime installwizard.inc files differ."
    diff -u "${SOURCE_FILE}" "${RUNTIME_FILE}" |
        head -n 200 ||
        true
fi

section "InstallWizard class structure"

grep -nE \
    'class[[:space:]]+InstallWizard|function[[:space:]]+|current|step|paint|get_class' \
    "${SOURCE_FILE}" \
    | head -n 250

section "Wizard run logic around the caller"

echo "File: ${WIZARD_FILE}"
echo

nl -ba "${WIZARD_FILE}" |
    sed -n '160,250p'

section "Installer entry point"

echo "File: ${INDEX_FILE}"
echo

nl -ba "${INDEX_FILE}" |
    sed -n '1,120p'

section "All get_class calls in installer"

grep -RInE \
    --include='*.php' \
    --include='*.inc' \
    --include='*.inc.php' \
    '\bget_class[[:space:]]*\(' \
    "${SOURCE}/installer" \
    || true

section "Step-object assignments and registrations"

grep -RInE \
    --include='*.php' \
    --include='*.inc' \
    --include='*.inc.php' \
    '(_steps|steps\[|addStep|setStep|currentStep|stepObject|stepClass)' \
    "${SOURCE}/installer" \
    | head -n 400 \
    || true

section "Installer step files"

find "${SOURCE}/installer" \
    -maxdepth 3 \
    -type f \
    \( \
        -name '*.php' -o \
        -name '*.inc' -o \
        -name '*.inc.php' \
    \) \
    -printf '%p\n' \
    | sort

section "PHP 8.2 syntax check of core installer files"

for file in \
    "${INDEX_FILE}" \
    "${WIZARD_FILE}" \
    "${SOURCE_FILE}"
do
    echo
    echo "FILE: ${file}"

    docker compose \
        -f "${COMPOSE}" \
        exec -T web \
        php -l "/var/www/html/ch/${file#${SOURCE}/}"
done

section "Fresh request and concise fatal extraction"

docker compose \
    -f "${COMPOSE}" \
    logs --no-color --tail=0 web \
    >/dev/null 2>&1 ||
    true

set +e

curl \
    --silent \
    --show-error \
    --location \
    --max-time 30 \
    "http://localhost:8082/ch/" \
    >/dev/null

CURL_STATUS=$?

set -e

echo "curl exit status: ${CURL_STATUS}"
echo

docker compose \
    -f "${COMPOSE}" \
    logs --no-color --since=30s web \
    | grep -Ei \
        'fatal error|uncaught|typeerror|parse error|compile error|stack trace|installwizard|wizard\.inc|installer/index' \
    || true

section "Runtime textual log files only"

find "${RUNTIME}" \
    -maxdepth 4 \
    -type f \
    \( \
        -name '*.log' -o \
        -name 'php_errors.log' -o \
        -name 'error_log' -o \
        -name 'apache_error.log' \
    \) \
    -print0 \
    | while IFS= read -r -d '' file; do
        mime="$(
            file \
                --brief \
                --mime-type \
                "${file}" \
                2>/dev/null ||
            true
        )"

        case "${mime}" in
            text/*|application/json|application/xml|inode/x-empty)
                echo
                echo "------------------------------------------------------------"
                echo "FILE: ${file}"
                echo "MIME: ${mime}"
                echo "------------------------------------------------------------"
                tail -n 120 "${file}" || true
                ;;
            *)
                echo "SKIPPED NON-TEXT FILE: ${file} (${mime})"
                ;;
        esac
    done

section "Repository status"

git -C "${ROOT}/framework" status --short

section "Inspection complete"

echo "Finished: $(date --iso-8601=seconds)"
echo
echo "No source file was modified."
echo "No runtime was rebuilt."
echo
echo "Upload:"
echo "  ${LOG}"
