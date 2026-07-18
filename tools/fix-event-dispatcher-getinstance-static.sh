#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="/run/media/derek/main/chisimba-revival"
SOURCE="$ROOT/framework/app/lib/pear/Event/Dispatcher.php"
RUNTIME="$ROOT/dev-environment/runtime/php82-ch/lib/pear/Event/Dispatcher.php"
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

section "PHP 8.2: Fix Event_Dispatcher::getInstance()"

for FILE in "$SOURCE" "$RUNTIME"; do
    [[ -f "$FILE" ]] || fail "Missing file: $FILE"
done

python3 - "$SOURCE" "$RUNTIME" <<'PY'
from pathlib import Path
import re
import sys

METHOD = "getInstance"


def locate_method(text: str):
    pattern = re.compile(
        rf'''
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
        {METHOD}
        [ \t]*
        \(
        ''',
        re.IGNORECASE | re.MULTILINE | re.VERBOSE,
    )

    matches = list(pattern.finditer(text))

    if len(matches) != 1:
        raise RuntimeError(
            f"Expected exactly one {METHOD}() declaration; "
            f"found {len(matches)}"
        )

    match = matches[0]
    opening = text.find("{", match.end())

    if opening < 0:
        raise RuntimeError(
            f"Could not locate {METHOD}() opening brace"
        )

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

    raise RuntimeError(
        f"Could not locate {METHOD}() closing brace"
    )


for filename in sys.argv[1:]:
    path = Path(filename)
    text = path.read_text(errors="replace")

    if re.search(
        rf'\bstatic\s+function\s+&?\s*{METHOD}\s*\(',
        text,
        re.IGNORECASE,
    ):
        print(f"ALREADY STATIC: {path}")
        continue

    try:
        match, body_start, body_end = locate_method(text)
    except RuntimeError as error:
        raise SystemExit(f"{path}: {error}")

    body = text[body_start + 1:body_end]

    if re.search(r'\$this\b', body):
        print(f"REFUSED: {METHOD}() uses $this in {path}")
        print()
        print(body[:6000])
        raise SystemExit(
            f"{METHOD}() cannot safely be declared static."
        )

    declaration = text[match.start():body_start]

    updated_declaration, count = re.subn(
        rf'''
        (?P<indent>^[ \t]*)
        (?:
            public|protected|private
        )?
        [ \t]*
        function
        [ \t]+
        (?P<reference>&[ \t]*)?
        {METHOD}
        ''',
        lambda item: (
            f"{item.group('indent')}public static function "
            f"{item.group('reference') or ''}{METHOD}"
        ),
        declaration,
        count=1,
        flags=re.IGNORECASE | re.MULTILINE | re.VERBOSE,
    )

    if count != 1:
        raise SystemExit(
            f"Could not rewrite {METHOD}() in {path}"
        )

    backup = path.with_name(
        path.name + ".before-php82-getinstance-static"
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

section "Declaration"

grep -n -A35 -B10 \
    'getInstance[[:space:]]*(' \
    "$SOURCE" \
    | head -n 180

section "PHP 8.2 lint"

docker compose \
    -f "$COMPOSE" \
    exec -T web \
    php -l /var/www/html/ch/lib/pear/Event/Dispatcher.php

section "Reflection and return-value test"

docker compose \
    -f "$COMPOSE" \
    exec -T web \
    php -d include_path=/var/www/html/ch/lib/pear <<'PHP'
<?php

require_once 'Event/Dispatcher.php';

$method = new ReflectionMethod(
    'Event_Dispatcher',
    'getInstance'
);

echo 'getInstance static: ',
    $method->isStatic() ? 'yes' : 'no',
    PHP_EOL;

$dispatcher = Event_Dispatcher::getInstance();

echo 'Returned: ',
    is_object($dispatcher)
        ? get_class($dispatcher)
        : gettype($dispatcher),
    PHP_EOL;

if (!$method->isStatic() || !is_object($dispatcher)) {
    exit(1);
}
PHP

section "Request Chisimba"

curl \
    --silent \
    --show-error \
    --location \
    --max-time 45 \
    --write-out '\nHTTP_STATUS:%{http_code}\n' \
    "http://localhost:8082/ch/" \
    || true

section "Recent web log"

docker compose \
    -f "$COMPOSE" \
    logs --no-color --tail=140 web

section "Patch complete"

echo "Reload:"
echo "  http://localhost:8082/ch/"
