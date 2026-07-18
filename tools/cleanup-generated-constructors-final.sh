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

section "Milestone 8: Final generated-constructor cleanup"

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

section "Remove remaining generated wrappers using line structure"

python3 - "${FRAMEWORK}" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])

marker = "PHP 8 constructor wrapper for the legacy"

changed_files = 0
removed_wrappers = 0
failed_files = []

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
        lines = path.read_text().splitlines(keepends=True)
    except (UnicodeDecodeError, OSError):
        continue

    if not any(marker in line for line in lines):
        continue

    output = []
    index = 0
    file_removals = 0

    while index < len(lines):
        if marker not in lines[index]:
            output.append(lines[index])
            index += 1
            continue

        marker_index = index

        # Locate the /** that begins the generated marker comment.
        comment_start = marker_index

        while comment_start >= 0:
            if "/**" in lines[comment_start]:
                break
            comment_start -= 1

        if comment_start < 0:
            failed_files.append(
                f"{path}: could not find generated comment start"
            )
            output.append(lines[index])
            index += 1
            continue

        # Remove any lines already copied from the generated comment start.
        copied_count = marker_index - comment_start

        if copied_count > 0:
            del output[-copied_count:]

        # Find the generated comment end.
        comment_end = marker_index

        while comment_end < len(lines):
            if "*/" in lines[comment_end]:
                break
            comment_end += 1

        if comment_end >= len(lines):
            failed_files.append(
                f"{path}: could not find generated comment end"
            )
            output.extend(lines[comment_start:marker_index + 1])
            index = marker_index + 1
            continue

        # Find the following generated __construct declaration.
        construct_start = comment_end + 1

        while (
            construct_start < len(lines)
            and "function __construct" not in lines[construct_start]
        ):
            # Permit whitespace-only lines between comment and method.
            if lines[construct_start].strip() != "":
                failed_files.append(
                    f"{path}: unexpected content before __construct(): "
                    f"{lines[construct_start].strip()}"
                )
                break

            construct_start += 1

        if (
            construct_start >= len(lines)
            or "function __construct" not in lines[construct_start]
        ):
            output.extend(lines[comment_start:marker_index + 1])
            index = marker_index + 1
            continue

        # Find the opening brace.
        brace_line = construct_start
        found_opening = False

        while brace_line < len(lines):
            if "{" in lines[brace_line]:
                found_opening = True
                break

            brace_line += 1

        if not found_opening:
            failed_files.append(
                f"{path}: could not find generated constructor opening brace"
            )
            output.extend(lines[comment_start:marker_index + 1])
            index = marker_index + 1
            continue

        # Count braces until the generated constructor closes.
        depth = 0
        construct_end = None

        for scan in range(brace_line, len(lines)):
            line = lines[scan]

            depth += line.count("{")
            depth -= line.count("}")

            if depth == 0:
                construct_end = scan
                break

        if construct_end is None:
            failed_files.append(
                f"{path}: could not find generated constructor closing brace"
            )
            output.extend(lines[comment_start:marker_index + 1])
            index = marker_index + 1
            continue

        index = construct_end + 1

        # Remove one blank line following the generated wrapper.
        if index < len(lines) and lines[index].strip() == "":
            index += 1

        file_removals += 1
        removed_wrappers += 1

    if file_removals:
        path.write_text("".join(output))
        changed_files += 1
        print(f"RESTORED ({file_removals}): {path}")

print()
print(f"Files restored: {changed_files}")
print(f"Generated wrappers removed: {removed_wrappers}")

if failed_files:
    print("\nFailures:", file=sys.stderr)

    for failure in failed_files:
        print(failure, file=sys.stderr)

    raise SystemExit(1)
PY

section "Verify all broad generated markers are gone"

mapfile -t REMAINING < <(
    grep -RIl \
        --include='*.php' \
        --include='*.inc' \
        --include='*.inc.php' \
        'PHP 8 constructor wrapper for the legacy' \
        "${FRAMEWORK}" \
        || true
)

echo "Files containing generated marker: ${#REMAINING[@]}"

if (( ${#REMAINING[@]} > 0 )); then
    printf '%s\n' "${REMAINING[@]}"
    fail "Generated wrappers remain."
fi

echo "All broad-pass generated wrappers have been removed."

section "Verify manual InstallWizard constructor remains"

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

section "Confirm Template constructor"

TEMPLATE="${INSTALLER}/template.inc"

grep -n -A22 -B6 \
    -E 'class[[:space:]]+Template|function[[:space:]]+(__construct|Template)' \
    "${TEMPLATE}"

if ! grep -Eq \
    'function[[:space:]]+__construct[[:space:]]*\(' \
    "${TEMPLATE}"
then
    fail "Template constructor was not added."
fi

section "Rebuild PHP 8.2 from fresh database"

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

section "Framework repository status"

git -C "${ROOT}/framework" status --short

section "Final cleanup complete"

echo "Finished: $(date --iso-8601=seconds)"
echo
echo "PHP 8.2:"
echo "  http://localhost:8082/ch/"
echo
echo "Upload:"
echo "  ${LOG}"
