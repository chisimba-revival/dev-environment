#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="/run/media/derek/main/chisimba-revival"
SOURCE="$ROOT/framework/app/lib/pear/I18Nv2.php"
RUNTIME="$ROOT/dev-environment/runtime/php82-ch/lib/pear/I18Nv2.php"
COMPOSE="$ROOT/dev-environment/compose/php82.yml"
OUT="$ROOT/killme.txt"

exec >"$OUT" 2>&1

python3 - "$SOURCE" "$RUNTIME" <<'PY'
from pathlib import Path
import re
import sys


def method_extent(text: str, name: str):
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
        {re.escape(name)}
        [ \t]*
        \(
        ''',
        re.IGNORECASE | re.MULTILINE | re.VERBOSE,
    )

    matches = list(pattern.finditer(text))

    if len(matches) != 1:
        raise RuntimeError(
            f"Expected exactly one {name}() declaration; found {len(matches)}"
        )

    match = matches[0]
    opening = text.find("{", match.end())

    if opening < 0:
        raise RuntimeError(f"Could not find opening brace for {name}()")

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

    raise RuntimeError(f"Could not find closing brace for {name}()")


methods = [
    "getStaticProperty",
    "setStaticProperty",
]

for filename in sys.argv[1:]:
    path = Path(filename)

    if not path.is_file():
        raise SystemExit(f"Missing file: {path}")

    text = path.read_text(errors="replace")
    changed = False

    for method_name in methods:
        if re.search(
            rf'\bstatic\s+function\s+&?\s*{re.escape(method_name)}\s*\(',
            text,
            re.IGNORECASE,
        ):
            print(f"ALREADY STATIC: {path}::{method_name}()")
            continue

        try:
            match, body_start, body_end = method_extent(text, method_name)
        except RuntimeError as error:
            raise SystemExit(f"{path}: {error}")

        body = text[body_start + 1:body_end]

        if re.search(r'\$this\b', body):
            print(f"REFUSED: {path}::{method_name}() uses $this")
            print(body[:4000])
            raise SystemExit(
                f"{method_name}() cannot safely be made static."
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
            {re.escape(method_name)}
            ''',
            lambda item: (
                f"{item.group('indent')}public static function "
                f"{item.group('reference') or ''}{method_name}"
            ),
            declaration,
            count=1,
            flags=re.IGNORECASE | re.MULTILINE | re.VERBOSE,
        )

        if count != 1:
            raise SystemExit(
                f"Could not rewrite {method_name}() in {path}"
            )

        text = (
            text[:match.start()]
            + updated_declaration
            + text[body_start:]
        )

        changed = True
        print(f"UPDATED: {path}::{method_name}()")

    if changed:
        backup = path.with_name(
            path.name + ".before-php82-i18nv2-static-helpers"
        )

        if not backup.exists():
            backup.write_text(path.read_text(errors="replace"))

        path.write_text(text)
PY

echo
echo "===== STATIC HELPER DECLARATIONS ====="

grep -n -A12 -B5 \
    -E 'getStaticProperty[[:space:]]*\(|setStaticProperty[[:space:]]*\(' \
    "$SOURCE" \
    | head -n 160

echo
echo "===== PHP 8.2 LINT ====="

docker compose \
    -f "$COMPOSE" \
    exec -T web \
    php -l /var/www/html/ch/lib/pear/I18Nv2.php

echo
echo "===== REQUEST CHISIMBA ====="

curl \
    --silent \
    --show-error \
    --location \
    --max-time 30 \
    --write-out '\nHTTP_STATUS:%{http_code}\n' \
    "http://localhost:8082/ch/" \
    || true

echo
echo "===== RECENT WEB LOG ====="

docker compose \
    -f "$COMPOSE" \
    logs --no-color --tail=120 web
