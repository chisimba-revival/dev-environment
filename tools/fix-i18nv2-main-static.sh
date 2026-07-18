#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="/run/media/derek/main/chisimba-revival"
SOURCE="$ROOT/framework/app/lib/pear/I18Nv2.php"
RUNTIME="$ROOT/dev-environment/runtime/php82-ch/lib/pear/I18Nv2.php"
COMPOSE="$ROOT/dev-environment/compose/php82.yml"
OUT="$ROOT/killme.txt"

exec >"$OUT" 2>&1

echo "============================================================"
echo "PHP 8.2: Fix I18Nv2::_main() static declaration"
echo "============================================================"

python3 - "$SOURCE" "$RUNTIME" <<'PY'
from pathlib import Path
import re
import sys


def find_method_extent(text: str) -> tuple[int, int, int]:
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
        &?
        [ \t]*
        _main
        [ \t]*
        \(
        ''',
        re.IGNORECASE | re.MULTILINE | re.VERBOSE,
    )

    matches = list(pattern.finditer(text))

    if len(matches) != 1:
        raise RuntimeError(
            f"Expected exactly one I18Nv2::_main() declaration; found {len(matches)}"
        )

    match = matches[0]
    opening = text.find("{", match.end())

    if opening < 0:
        raise RuntimeError("Could not find opening brace for I18Nv2::_main()")

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
                return match.start(), opening, index

    raise RuntimeError("Could not find closing brace for I18Nv2::_main()")


for filename in sys.argv[1:]:
    path = Path(filename)

    if not path.is_file():
        raise SystemExit(f"Missing file: {path}")

    text = path.read_text(errors="replace")

    if re.search(
        r'\bstatic\s+function\s+&?\s*_main\s*\(',
        text,
        re.IGNORECASE,
    ):
        print(f"ALREADY STATIC: {path}")
        continue

    try:
        declaration_start, body_start, body_end = find_method_extent(text)
    except RuntimeError as error:
        raise SystemExit(f"{path}: {error}")

    method_body = text[body_start + 1:body_end]

    if re.search(r'\$this\b', method_body):
        print(f"REFUSED: _main() uses $this in {path}")
        print()
        print("Method body:")
        print(method_body[:4000])
        raise SystemExit(
            "I18Nv2::_main() cannot safely be made static because it uses $this."
        )

    declaration_fragment = text[declaration_start:body_start]

    updated_fragment, count = re.subn(
        r'''
        (?P<indent>^[ \t]*)
        (?:
            public|protected|private
        )?
        [ \t]*
        function
        [ \t]+
        (?P<reference>&[ \t]*)?
        _main
        ''',
        lambda match: (
            f"{match.group('indent')}public static function "
            f"{match.group('reference') or ''}_main"
        ),
        declaration_fragment,
        count=1,
        flags=re.IGNORECASE | re.MULTILINE | re.VERBOSE,
    )

    if count != 1:
        raise SystemExit(
            f"Could not rewrite I18Nv2::_main() declaration in {path}"
        )

    updated = (
        text[:declaration_start]
        + updated_fragment
        + text[body_start:]
    )

    backup = path.with_name(
        path.name + ".before-php82-i18nv2-main-static"
    )

    if not backup.exists():
        backup.write_text(text)

    path.write_text(updated)
    print(f"UPDATED: {path}")
PY

echo
echo "===== SOURCE DECLARATION ====="

grep -n -A12 -B5 \
    '_main[[:space:]]*(' \
    "$SOURCE" \
    | head -n 80

echo
echo "===== RUNTIME DECLARATION ====="

grep -n -A12 -B5 \
    '_main[[:space:]]*(' \
    "$RUNTIME" \
    | head -n 80

echo
echo "===== STATIC CALL SITES ====="

grep -n \
    'I18Nv2::_main' \
    "$SOURCE" \
    "$RUNTIME" \
    || true

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

echo
echo "============================================================"
echo "Reload: http://localhost:8082/ch/"
echo "============================================================"
