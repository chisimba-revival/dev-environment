#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="/run/media/derek/main/chisimba-revival"
SOURCE="$ROOT/framework/app/lib/pear/Translation2/Decorator.php"
RUNTIME="$ROOT/dev-environment/runtime/php82-ch/lib/pear/Translation2/Decorator.php"
COMPOSE="$ROOT/dev-environment/compose/php82.yml"
OUT="$ROOT/killme.txt"

exec >"$OUT" 2>&1

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

section "PHP 8.2: Restore Translation2_Decorator constructor"

for FILE in "$SOURCE" "$RUNTIME"; do
    [[ -f "$FILE" ]] || fail "Missing file: $FILE"
done

python3 - "$SOURCE" "$RUNTIME" <<'PY'
from pathlib import Path
import re
import sys

legacy_pattern = re.compile(
    r'''
    (?P<indent>^[ \t]*)
    function
    [ \t]+
    Translation2_Decorator
    [ \t]*
    \(
        (?P<params>[^)]*)
    \)
    ''',
    re.IGNORECASE | re.MULTILINE | re.VERBOSE,
)

constructor_pattern = re.compile(
    r'\bfunction\s+__construct\s*\(',
    re.IGNORECASE,
)

for filename in sys.argv[1:]:
    path = Path(filename)
    text = path.read_text(errors="replace")

    if constructor_pattern.search(text):
        print(f"ALREADY HAS __construct(): {path}")
        continue

    match = legacy_pattern.search(text)

    if match is None:
        print(f"Could not find Translation2_Decorator() in {path}")

        for number, line in enumerate(text.splitlines(), start=1):
            if "function" in line and "Decorator" in line:
                print(f"{number}: {line}")

        raise SystemExit(1)

    params = match.group("params").strip()
    indent = match.group("indent")

    parameter_names = re.findall(
        r'\$[A-Za-z_][A-Za-z0-9_]*',
        params,
    )

    if not parameter_names:
        raise SystemExit(
            f"Could not determine constructor parameters in {path}"
        )

    wrapper = (
        f"{indent}public function __construct({params})\n"
        f"{indent}{{\n"
        f"{indent}    $this->Translation2_Decorator("
        + ", ".join(parameter_names)
        + ");\n"
        f"{indent}}}\n\n"
    )

    backup = path.with_name(
        path.name + ".before-php82-decorator-constructor"
    )

    if not backup.exists():
        backup.write_text(text)

    updated = text[:match.start()] + wrapper + text[match.start():]
    path.write_text(updated)

    print(f"UPDATED: {path}")
    print(f"Wrapper arguments: {', '.join(parameter_names)}")
PY

section "Constructor declarations"

echo "--- Source ---"

grep -n -A28 -B8 \
    -E 'function[[:space:]]+(__construct|Translation2_Decorator)[[:space:]]*\(' \
    "$SOURCE" \
    | head -n 160

echo
echo "--- Runtime ---"

grep -n -A28 -B8 \
    -E 'function[[:space:]]+(__construct|Translation2_Decorator)[[:space:]]*\(' \
    "$RUNTIME" \
    | head -n 160

section "PHP 8.2 lint"

docker compose \
    -f "$COMPOSE" \
    exec -T web \
    php -l /var/www/html/ch/lib/pear/Translation2/Decorator.php

section "Direct constructor test"

docker compose \
    -f "$COMPOSE" \
    exec -T web \
    php -d include_path=/var/www/html/ch/lib/pear -r '
        require_once "Translation2.php";
        require_once "Translation2/Decorator.php";

        $translation = new Translation2();
        $decorator = new Translation2_Decorator($translation);

        $reflection = new ReflectionObject($decorator);

        echo "Decorator class: ", get_class($decorator), PHP_EOL;
        echo "Constructor present: ",
            $reflection->hasMethod("__construct") ? "yes" : "no",
            PHP_EOL;
    '

section "Request Chisimba"

curl \
    --silent \
    --show-error \
    --location \
    --max-time 30 \
    --write-out '\nHTTP_STATUS:%{http_code}\n' \
    "http://localhost:8082/ch/" \
    || true

section "Recent web log"

docker compose \
    -f "$COMPOSE" \
    logs --no-color --tail=120 web

section "Patch complete"

echo "Reload:"
echo "  http://localhost:8082/ch/"
