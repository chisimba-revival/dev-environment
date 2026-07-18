#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="/run/media/derek/main/chisimba-revival"
SOURCE="$ROOT/framework/app/lib/pear/Translation2.php"
RUNTIME="$ROOT/dev-environment/runtime/php82-ch/lib/pear/Translation2.php"
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

section "PHP 8.2: Fix Translation2::factory() static declaration"

for FILE in "$SOURCE" "$RUNTIME"; do
    [[ -f "$FILE" ]] || fail "Missing file: $FILE"
done

python3 - "$SOURCE" "$RUNTIME" <<'PY'
from pathlib import Path
import re
import sys


def find_method(text: str):
    pattern = re.compile(
        r'''
        (?P<indent>^[ \t]*)
        (?:
            public|protected|private
        )?
        [ \t]*
        (?:
            static
            [ \t]+
        )?
        function
        [ \t]+
        (?P<reference>&[ \t]*)?
        factory
        [ \t]*
        \(
        ''',
        re.IGNORECASE | re.MULTILINE | re.VERBOSE,
    )

    matches = list(pattern.finditer(text))

    if len(matches) != 1:
        raise RuntimeError(
            f"Expected exactly one factory() declaration; found {len(matches)}"
        )

    match = matches[0]
    opening = text.find("{", match.end())

    if opening < 0:
        raise RuntimeError("Could not find factory() opening brace")

    depth = 0
    quote = None
    escaped = False

    for index in range(opening, len(text)):
        char = text[index]

        if quote is not None:
            if escaped:
                escaped = False
                continue

            if char == "\\":
                escaped = True
                continue

            if char == quote:
                quote = None

            continue

        if char in ("'", '"'):
            quote = char
            continue

        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1

            if depth == 0:
                return match, opening, index

    raise RuntimeError("Could not find factory() closing brace")


for filename in sys.argv[1:]:
    path = Path(filename)
    text = path.read_text(errors="replace")

    if re.search(
        r'\bstatic\s+function\s+&?\s*factory\s*\(',
        text,
        re.IGNORECASE,
    ):
        print(f"ALREADY STATIC: {path}")
        continue

    try:
        match, body_start, body_end = find_method(text)
    except RuntimeError as error:
        raise SystemExit(f"{path}: {error}")

    body = text[body_start + 1:body_end]

    if re.search(r'\$this\b', body):
        print(f"REFUSED: Translation2::factory() uses $this in {path}")
        print()
        print(body[:5000])
        raise SystemExit(
            "factory() cannot safely be declared static."
        )

    declaration = text[match.start():body_start]

    updated_declaration, count = re.subn(
        r'''
        (?P<indent>^[ \t]*)
        (?:
            public|protected|private
        )?
        [ \t]*
        function
        [ \t]+
        (?P<reference>&[ \t]*)?
        factory
        ''',
        lambda item: (
            f"{item.group('indent')}public static function "
            f"{item.group('reference') or ''}factory"
        ),
        declaration,
        count=1,
        flags=re.IGNORECASE | re.MULTILINE | re.VERBOSE,
    )

    if count != 1:
        raise SystemExit(
            f"Could not rewrite factory() declaration in {path}"
        )

    backup = path.with_name(
        path.name + ".before-php82-translation2-factory-static"
    )

    if not backup.exists():
        backup.write_text(text)

    updated = (
        text[:match.start()]
        + updated_declaration
        + text[body_start:]
    )

    path.write_text(updated)
    print(f"UPDATED: {path}")
PY

section "Factory declarations"

echo "--- Source ---"
grep -n -A22 -B8 \
    'factory[[:space:]]*(' \
    "$SOURCE" \
    | head -n 100

echo
echo "--- Runtime ---"
grep -n -A22 -B8 \
    'factory[[:space:]]*(' \
    "$RUNTIME" \
    | head -n 100

section "Static call sites"

grep -RIn \
    --include='*.php' \
    --include='*.inc' \
    --include='*.inc.php' \
    'Translation2::factory' \
    "$ROOT/framework/app" \
    | head -n 100 \
    || true

section "PHP 8.2 lint"

docker compose \
    -f "$COMPOSE" \
    exec -T web \
    php -l /var/www/html/ch/lib/pear/Translation2.php

section "Direct factory declaration check"

docker compose \
    -f "$COMPOSE" \
    exec -T web \
    php -r '
        require_once "/var/www/html/ch/lib/pear/Translation2.php";

        $method = new ReflectionMethod("Translation2", "factory");

        echo "Translation2::factory static: ",
            $method->isStatic() ? "yes" : "no",
            PHP_EOL;

        if (!$method->isStatic()) {
            exit(1);
        }
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

section "Recent PHP 8.2 web log"

docker compose \
    -f "$COMPOSE" \
    logs --no-color --tail=120 web

section "Patch complete"

echo "Reload:"
echo "  http://localhost:8082/ch/"
