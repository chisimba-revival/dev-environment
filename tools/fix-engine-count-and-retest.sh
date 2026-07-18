#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="/run/media/derek/main/chisimba-revival"
FRAMEWORK_FILE="${PROJECT_ROOT}/framework/app/classes/core/engine_class_inc.php"
SMOKE_SCRIPT="${PROJECT_ROOT}/tools/authenticated-smoke-test.sh"
OUTPUT_FILE="${PROJECT_ROOT}/killme.txt"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${FRAMEWORK_FILE}.before-php82-count-${STAMP}"

fail()
{
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

[ -f "${FRAMEWORK_FILE}" ] ||
    fail "Framework engine file not found: ${FRAMEWORK_FILE}"

[ -f "${SMOKE_SCRIPT}" ] ||
    fail "Smoke-test script not found: ${SMOKE_SCRIPT}"

printf '============================================================\n'
printf 'PHP 8.2 ENGINE count() REPAIR\n'
printf '============================================================\n'
printf 'Source file: %s\n' "${FRAMEWORK_FILE}"
printf 'Backup:      %s\n\n' "${BACKUP}"

printf '%s\n' 'Context around reported line 1832:'
nl -ba "${FRAMEWORK_FILE}" | sed -n '1818,1842p'

cp -a "${FRAMEWORK_FILE}" "${BACKUP}"

python3 - "${FRAMEWORK_FILE}" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
lines = text.splitlines(keepends=True)

reported_index = 1832 - 1

if reported_index >= len(lines):
    raise SystemExit(
        f"Reported line 1832 is beyond the file length ({len(lines)} lines)."
    )

line = lines[reported_index]

if "count(" not in line:
    nearby = []
    for index in range(max(0, reported_index - 8), min(len(lines), reported_index + 9)):
        if "count(" in lines[index]:
            nearby.append(index)

    if len(nearby) != 1:
        details = ", ".join(str(index + 1) for index in nearby) or "none"
        raise SystemExit(
            "Could not safely identify one count() call near line 1832. "
            f"Nearby count() lines: {details}"
        )

    reported_index = nearby[0]
    line = lines[reported_index]

def find_matching_parenthesis(source: str, opening: int) -> int:
    depth = 0
    quote = None
    escaped = False

    for pos in range(opening, len(source)):
        char = source[pos]

        if quote is not None:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == quote:
                quote = None
            continue

        if char in ("'", '"'):
            quote = char
        elif char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
            if depth == 0:
                return pos

    raise ValueError("Unbalanced parentheses in count() expression")

start = line.find("count(")

if start < 0:
    raise SystemExit("No count() expression found on selected line.")

opening = start + len("count")
closing = find_matching_parenthesis(line, opening)
argument = line[opening + 1:closing].strip()

if not argument:
    raise SystemExit("The selected count() call has no argument.")

compatibility_expression = (
    f"(is_countable({argument}) "
    f"? count({argument}) "
    f": (({argument}) === null ? 0 : 1))"
)

patched_line = line[:start] + compatibility_expression + line[closing + 1:]

if patched_line == line:
    raise SystemExit("Patch produced no change.")

lines[reported_index] = patched_line
path.write_text("".join(lines), encoding="utf-8")

print(f"Patched source line {reported_index + 1}.")
print("Before:")
print(line.rstrip())
print("After:")
print(patched_line.rstrip())
PY

printf '\nPHP syntax check:\n'

if command -v php >/dev/null 2>&1; then
    php -l "${FRAMEWORK_FILE}"
else
    printf 'Host PHP is unavailable; container syntax check will be used.\n'
fi

printf '\nCorrecting Compose-file discovery in smoke-test harness:\n'

python3 - "${SMOKE_SCRIPT}" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

anchor = '''    for candidate in \\
        "${PROJECT_ROOT}/compose/php82.yml" \\
'''

replacement = '''    for candidate in \\
        "${PROJECT_ROOT}/dev-environment/compose/php82.yml" \\
        "${PROJECT_ROOT}/compose/php82.yml" \\
'''

if anchor in text:
    path.write_text(text.replace(anchor, replacement, 1), encoding="utf-8")
    print("Added dev-environment/compose/php82.yml to Compose discovery.")
elif '${PROJECT_ROOT}/dev-environment/compose/php82.yml' in text:
    print("Compose discovery was already corrected.")
else:
    raise SystemExit(
        "Could not safely locate the Compose discovery block in the smoke script."
    )
PY

COMPOSE_FILE="${PROJECT_ROOT}/dev-environment/compose/php82.yml"

[ -f "${COMPOSE_FILE}" ] ||
    fail "PHP 8.2 Compose file not found: ${COMPOSE_FILE}"

printf '\nLocating the running PHP 8.2 web container:\n'

WEB_CONTAINER="$(
    docker ps \
        --filter publish=8082 \
        --format '{{.Names}}' |
    head -n 1
)"

[ -n "${WEB_CONTAINER}" ] ||
    fail "No running Docker container publishing port 8082 was found."

printf 'Web container: %s\n' "${WEB_CONTAINER}"

RUNTIME_FILE="/var/www/html/ch/classes/core/engine_class_inc.php"

printf '\nCopying the repaired source file into the current runtime:\n'
docker cp "${FRAMEWORK_FILE}" "${WEB_CONTAINER}:${RUNTIME_FILE}"

printf '\nContainer syntax check:\n'
docker exec "${WEB_CONTAINER}" php -l "${RUNTIME_FILE}"

printf '\nRuntime context around the repaired line:\n'
docker exec "${WEB_CONTAINER}" sh -lc \
    "nl -ba '${RUNTIME_FILE}' | sed -n '1826,1838p'"

printf '\nRerunning authenticated smoke tests:\n'
"${SMOKE_SCRIPT}"

printf '\n============================================================\n'
printf 'REPAIR COMPLETE\n'
printf '============================================================\n'
printf 'Evidence: %s\n' "${OUTPUT_FILE}"
printf 'Backup:   %s\n' "${BACKUP}"
