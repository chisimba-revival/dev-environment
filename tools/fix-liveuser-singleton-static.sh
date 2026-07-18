#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="/run/media/derek/main/chisimba-revival"
SOURCE_ROOT="$ROOT/framework/app"
RUNTIME_ROOT="$ROOT/dev-environment/runtime/php82-ch"
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

section "Locate LiveUser class"

SOURCE="$(
    grep -RIl \
        --include='*.php' \
        --include='*.inc' \
        --include='*.inc.php' \
        -E 'class[[:space:]]+LiveUser([[:space:]]|$)' \
        "$SOURCE_ROOT" \
        | head -n 1
)"

[[ -n "$SOURCE" ]] ||
    fail "Could not locate the LiveUser class."

RELATIVE="${SOURCE#${SOURCE_ROOT}/}"
RUNTIME="${RUNTIME_ROOT}/${RELATIVE}"

echo "Source:  $SOURCE"
echo "Runtime: $RUNTIME"

[[ -f "$RUNTIME" ]] ||
    fail "Runtime counterpart is missing: $RUNTIME"

section "Patch LiveUser::singleton()"

python3 - "$SOURCE" "$RUNTIME" <<'PY'
from pathlib import Path
import re
import sys

METHOD = "singleton"

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

    if not path.is_file():
        raise SystemExit(f"Missing file: {path}")

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
        path.name + ".before-php82-liveuser-singleton-static"
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

section "LiveUser singleton declaration"

echo "--- Source ---"

grep -n -A35 -B10 \
    'singleton[[:space:]]*(' \
    "$SOURCE" \
    | head -n 180

echo
echo "--- Runtime ---"

grep -n -A35 -B10 \
    'singleton[[:space:]]*(' \
    "$RUNTIME" \
    | head -n 180

section "Find LiveUser child overrides"

grep -RIn \
    --include='*.php' \
    --include='*.inc' \
    --include='*.inc.php' \
    -E \
    'class[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]+extends[[:space:]]+LiveUser|function[[:space:]]+&?[[:space:]]*singleton[[:space:]]*\(' \
    "$SOURCE_ROOT" \
    | head -n 250 \
    || true

section "PHP 8.2 lint"

CONTAINER_FILE="/var/www/html/ch/${RELATIVE}"

docker compose \
    -f "$COMPOSE" \
    exec -T web \
    php -l "$CONTAINER_FILE"

section "Reflection check"

docker compose \
    -f "$COMPOSE" \
    exec -T web \
    php -d include_path=/var/www/html/ch/lib/pear -r '
        require_once "LiveUser.php";

        $method = new ReflectionMethod(
            "LiveUser",
            "singleton"
        );

        echo "LiveUser::singleton static: ",
            $method->isStatic() ? "yes" : "no",
            PHP_EOL;

        if (!$method->isStatic()) {
            exit(1);
        }
    ' \
    || true

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
