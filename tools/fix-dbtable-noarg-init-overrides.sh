#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="/run/media/derek/main/chisimba-revival"
SOURCE_ROOT="${ROOT}/framework/app"
RUNTIME_ROOT="${ROOT}/dev-environment/runtime/php82-ch"
COMPOSE="${ROOT}/dev-environment/compose/php82.yml"
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

section "PHP 8.2: Align no-argument dbTable::init() overrides"

python3 - "${SOURCE_ROOT}" "${RUNTIME_ROOT}" <<'PY'
from pathlib import Path
import re
import sys

source_root = Path(sys.argv[1])
runtime_root = Path(sys.argv[2])

class_pattern = re.compile(
    r'\bclass\s+([A-Za-z_][A-Za-z0-9_]*)\s+extends\s+dbTable\b',
    re.IGNORECASE,
)

init_pattern = re.compile(
    r'''
    (?P<prefix>
        (?:
            public|protected|private
        )?
        [ \t]*
        function
        [ \t]+
        init
        [ \t]*
    )
    \(
        [ \t\r\n]*
    \)
    ''',
    re.IGNORECASE | re.VERBOSE,
)

replacement_signature = (
    r"\g<prefix>("
    r"$tableName = null, "
    r"$pearDb = null, "
    r"$errorCallback = 'globalPearErrorCallback'"
    r")"
)

changed_source_files: list[Path] = []
changed_runtime_files: list[Path] = []
candidates: list[tuple[Path, list[str]]] = []

for source_file in sorted(source_root.rglob("*.php")):
    try:
        text = source_file.read_text(errors="replace")
    except OSError:
        continue

    classes = class_pattern.findall(text)

    if not classes:
        continue

    if not init_pattern.search(text):
        continue

    candidates.append((source_file, classes))

print("Candidate source files:")
for path, classes in candidates:
    print(f"  {path}")
    print(f"    dbTable subclass(es): {', '.join(classes)}")

print()

for source_file, classes in candidates:
    source_text = source_file.read_text(errors="replace")

    updated_source, count = init_pattern.subn(
        replacement_signature,
        source_text,
    )

    if count == 0:
        continue

    backup = source_file.with_name(
        source_file.name + ".before-php82-dbtable-init-pass"
    )

    if not backup.exists():
        backup.write_text(source_text)

    source_file.write_text(updated_source)
    changed_source_files.append(source_file)

    relative = source_file.relative_to(source_root)
    runtime_file = runtime_root / relative

    if not runtime_file.is_file():
        raise SystemExit(
            f"Runtime counterpart missing for {source_file}: "
            f"{runtime_file}"
        )

    runtime_text = runtime_file.read_text(errors="replace")

    updated_runtime, runtime_count = init_pattern.subn(
        replacement_signature,
        runtime_text,
    )

    if runtime_count != count:
        raise SystemExit(
            f"Source/runtime replacement count differs for {relative}: "
            f"source={count}, runtime={runtime_count}"
        )

    runtime_backup = runtime_file.with_name(
        runtime_file.name + ".before-php82-dbtable-init-pass"
    )

    if not runtime_backup.exists():
        runtime_backup.write_text(runtime_text)

    runtime_file.write_text(updated_runtime)
    changed_runtime_files.append(runtime_file)

    print(
        f"UPDATED: {relative} "
        f"({count} no-argument init override(s))"
    )

manifest = runtime_root.parent / "php82-dbtable-init-changed.txt"
manifest.write_text(
    "\n".join(str(path) for path in changed_runtime_files) + "\n"
)

print()
print(f"Changed source files: {len(changed_source_files)}")
print(f"Changed runtime files: {len(changed_runtime_files)}")
print(f"Manifest: {manifest}")
PY

MANIFEST="${ROOT}/dev-environment/runtime/php82-dbtable-init-changed.txt"

[[ -f "${MANIFEST}" ]] ||
    fail "Changed-file manifest was not created."

section "Changed declarations"

while IFS= read -r FILE; do
    [[ -n "${FILE}" ]] || continue

    echo
    echo "FILE: ${FILE}"

    grep -n -A6 -B4 \
        'function[[:space:]]\+init' \
        "${FILE}" \
        | head -n 80
done < "${MANIFEST}"

section "PHP 8.2 lint of every changed runtime file"

LINT_FAILURE=0

while IFS= read -r FILE; do
    [[ -n "${FILE}" ]] || continue

    CONTAINER_FILE="${FILE#${RUNTIME_ROOT}}"
    CONTAINER_FILE="/var/www/html/ch${CONTAINER_FILE}"

    echo
    echo "Linting: ${CONTAINER_FILE}"

    if ! docker compose \
        -f "${COMPOSE}" \
        exec -T web \
        php -l "${CONTAINER_FILE}"
    then
        LINT_FAILURE=1
    fi
done < "${MANIFEST}"

if [[ "${LINT_FAILURE}" -ne 0 ]]; then
    fail "One or more changed PHP files failed lint."
fi

section "Check for remaining exact no-argument init overrides"

python3 - "${SOURCE_ROOT}" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])

class_pattern = re.compile(
    r'\bclass\s+[A-Za-z_][A-Za-z0-9_]*\s+extends\s+dbTable\b',
    re.IGNORECASE,
)

init_pattern = re.compile(
    r'\bfunction\s+init\s*\(\s*\)',
    re.IGNORECASE,
)

remaining = []

for path in sorted(root.rglob("*.php")):
    try:
        text = path.read_text(errors="replace")
    except OSError:
        continue

    if class_pattern.search(text) and init_pattern.search(text):
        remaining.append(path)

if remaining:
    print("Remaining files:")
    for path in remaining:
        print(path)
    raise SystemExit(1)

print("No exact no-argument init() overrides remain in dbTable subclasses.")
PY

section "Request Chisimba"

curl \
    --silent \
    --show-error \
    --location \
    --max-time 30 \
    --write-out '\nHTTP_STATUS:%{http_code}\n' \
    "http://localhost:8082/ch/" \
    || true

section "Recent PHP 8.2 web log"

docker compose \
    -f "${COMPOSE}" \
    logs --no-color --tail=120 web

section "Pass complete"

echo "Reload:"
echo "  http://localhost:8082/ch/"
