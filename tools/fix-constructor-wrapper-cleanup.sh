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

section "Milestone 8: Correct constructor-wrapper cleanup"

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

section "Remove abandoned temporary files"

find "${FRAMEWORK}" \
    -type f \
    -name '*.legacy-constructor-moderniser.tmp' \
    -print \
    -delete

section "Remove generated broad-pass wrappers robustly"

python3 - "${FRAMEWORK}" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])

marker = "PHP 8 constructor wrapper for the legacy"

changed_files = 0
removed_wrappers = 0
failures = []

for path in root.rglob("*"):
    if not path.is_file():
        continue

    lower_name = path.name.lower()

    if not (
        lower_name.endswith(".php")
        or lower_name.endswith(".inc")
        or lower_name.endswith(".inc.php")
    ):
        continue

    try:
        source = path.read_text()
    except (UnicodeDecodeError, OSError):
        continue

    if marker not in source:
        continue

    updated = source
    file_removals = 0

    while marker in updated:
        marker_pos = updated.find(marker)

        # Find the opening /** belonging to the generated comment.
        comment_start = updated.rfind("/**", 0, marker_pos)

        if comment_start == -1:
            failures.append(
                f"Could not find comment start for marker in {path}"
            )
            break

        comment_end = updated.find("*/", marker_pos)

        if comment_end == -1:
            failures.append(
                f"Could not find comment end for marker in {path}"
            )
            break

        construct_pos = updated.find(
            "function __construct",
            comment_end
        )

        if construct_pos == -1:
            failures.append(
                f"Could not find __construct after marker in {path}"
            )
            break

        open_brace = updated.find("{", construct_pos)

        if open_brace == -1:
            failures.append(
                f"Could not find constructor opening brace in {path}"
            )
            break

        depth = 0
        close_brace = None
        index = open_brace

        while index < len(updated):
            char = updated[index]

            if char == "{":
                depth += 1
            elif char == "}":
                depth -= 1

                if depth == 0:
                    close_brace = index
                    break

            index += 1

        if close_brace is None:
            failures.append(
                f"Could not find constructor closing brace in {path}"
            )
            break

        removal_end = close_brace + 1

        # Remove whitespace through the following blank line, but do not
        # consume indentation belonging to the legacy constructor itself.
        while (
            removal_end < len(updated)
            and updated[removal_end] in " \t"
        ):
            removal_end += 1

        if (
            removal_end < len(updated)
            and updated[removal_end] == "\r"
        ):
            removal_end += 1

        if (
            removal_end < len(updated)
            and updated[removal_end] == "\n"
        ):
            removal_end += 1

        # Remove at most one additional blank line.
        probe = removal_end

        while probe < len(updated) and updated[probe] in " \t":
            probe += 1

        if probe < len(updated) and updated[probe] == "\r":
            probe += 1

        if probe < len(updated) and updated[probe] == "\n":
            removal_end = probe + 1

        updated = (
            updated[:comment_start]
            + updated[removal_end:]
        )

        file_removals += 1
        removed_wrappers += 1

    if updated != source:
        path.write_text(updated)
        changed_files += 1
        print(f"RESTORED ({file_removals}): {path}")

if failures:
    print("\nCleanup failures:", file=sys.stderr)

    for failure in failures:
        print(failure, file=sys.stderr)

    raise SystemExit(1)

print()
print(f"Files restored: {changed_files}")
print(f"Generated wrappers removed: {removed_wrappers}")
PY

section "Verify broad generated markers are gone"

REMAINING_COUNT="$(
    grep -RIl \
        --include='*.php' \
        --include='*.inc' \
        --include='*.inc.php' \
        'PHP 8 constructor wrapper for the legacy' \
        "${FRAMEWORK}" \
    | wc -l
)"

echo "Files still containing broad-pass marker: ${REMAINING_COUNT}"

if [[ "${REMAINING_COUNT}" -ne 0 ]]; then
    grep -RIl \
        --include='*.php' \
        --include='*.inc' \
        --include='*.inc.php' \
        'PHP 8 constructor wrapper for the legacy' \
        "${FRAMEWORK}"

    fail "Generated broad-pass wrappers still remain."
fi

echo "All generated broad-pass wrappers have been removed."

section "Verify manually added InstallWizard constructor remains"

INSTALLWIZARD="${INSTALLER}/installwizard.inc"

INSTALLWIZARD_COUNT="$(
    grep -Ec \
        'function[[:space:]]+__construct[[:space:]]*\(' \
        "${INSTALLWIZARD}"
)"

echo "InstallWizard __construct() count: ${INSTALLWIZARD_COUNT}"

if [[ "${INSTALLWIZARD_COUNT}" -ne 1 ]]; then
    fail "InstallWizard should retain exactly one constructor."
fi

section "Apply constructor pass only to installer"

php "${PASS}" \
    --dry-run \
    "${INSTALLER}"

php "${PASS}" \
    --apply \
    "${INSTALLER}"

section "Verify installer pass is idempotent"

SECOND_RUN="$(
    php "${PASS}" \
        --dry-run \
        "${INSTALLER}"
)"

printf '%s\n' "${SECOND_RUN}"

if ! grep -q 'Constructor wrappers: 0' <<<"${SECOND_RUN}"; then
    fail "Installer-only constructor pass is not idempotent."
fi

section "Confirm Template now has a constructor"

TEMPLATE="${INSTALLER}/template.inc"

grep -n -A22 -B5 \
    -E 'class[[:space:]]+Template|function[[:space:]]+(__construct|Template)' \
    "${TEMPLATE}"

if ! grep -Eq \
    'function[[:space:]]+__construct[[:space:]]*\(' \
    "${TEMPLATE}"
then
    fail "Template constructor wrapper was not added."
fi

section "Rebuild fresh PHP 8.2 environment"

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

section "Recent PHP 8.2 web log"

docker compose \
    -f "${COMPOSE}" \
    logs --no-color --tail=120 web \
    || true

section "Repository status"

git -C "${ROOT}/framework" status --short

section "Corrected cleanup complete"

echo "Finished: $(date --iso-8601=seconds)"
echo
echo "PHP 8.2:"
echo "  http://localhost:8082/ch/"
echo
echo "Upload:"
echo "  ${LOG}"
