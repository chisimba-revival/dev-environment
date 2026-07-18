#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="/run/media/derek/main/chisimba-revival"
COMPOSE="$ROOT/dev-environment/compose/php82.yml"
OUT="$ROOT/killme.txt"

FILES=(
    "$ROOT/framework/app/lib/pear/Translation2.php"
    "$ROOT/framework/app/lib/pear/Translation2/Admin.php"
    "$ROOT/dev-environment/runtime/php82-ch/lib/pear/Translation2.php"
    "$ROOT/dev-environment/runtime/php82-ch/lib/pear/Translation2/Admin.php"
)

exec >"$OUT" 2>&1

python3 - "${FILES[@]}" <<'PY'
from pathlib import Path
import re
import sys


def locate_method(text: str, method_name: str):
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
        {re.escape(method_name)}
        [ \t]*
        \(
        ''',
        re.IGNORECASE | re.MULTILINE | re.VERBOSE,
    )

    matches = list(pattern.finditer(text))

    if len(matches) != 1:
        raise RuntimeError(
            f"Expected one {method_name}() declaration; found {len(matches)}"
        )

    match = matches[0]
    opening = text.find("{", match.end())

    if opening < 0:
        raise RuntimeError(
            f"Could not locate {method_name}() opening brace"
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
        f"Could not locate {method_name}() closing brace"
    )


for filename in sys.argv[1:]:
    path = Path(filename)

    if not path.is_file():
        raise SystemExit(f"Missing file: {path}")

    text = path.read_text(errors="replace")

    if re.search(
        r'\bstatic\s+function\s+&?\s*_storageFactory\s*\(',
        text,
        re.IGNORECASE,
    ):
        print(f"ALREADY STATIC: {path}")
        continue

    try:
        match, body_start, body_end = locate_method(
            text,
            "_storageFactory",
        )
    except RuntimeError as error:
        raise SystemExit(f"{path}: {error}")

    body = text[body_start + 1:body_end]

    if re.search(r'\$this\b', body):
        print(f"REFUSED: _storageFactory() uses $this in {path}")
        print(body[:5000])
        raise SystemExit(
            "_storageFactory() cannot safely be static."
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
        _storageFactory
        ''',
        lambda item: (
            f"{item.group('indent')}public static function "
            f"{item.group('reference') or ''}_storageFactory"
        ),
        declaration,
        count=1,
        flags=re.IGNORECASE | re.MULTILINE | re.VERBOSE,
    )

    if count != 1:
        raise SystemExit(
            f"Could not rewrite _storageFactory() in {path}"
        )

    backup = path.with_name(
        path.name + ".before-php82-storagefactory-static"
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

echo
echo "===== DECLARATIONS ====="

grep -n -A28 -B8 \
    '_storageFactory[[:space:]]*(' \
    "$ROOT/framework/app/lib/pear/Translation2.php" \
    "$ROOT/framework/app/lib/pear/Translation2/Admin.php" \
    | head -n 220

echo
echo "===== PHP 8.2 LINT ====="

docker compose \
    -f "$COMPOSE" \
    exec -T web \
    php -l /var/www/html/ch/lib/pear/Translation2.php

docker compose \
    -f "$COMPOSE" \
    exec -T web \
    php -l /var/www/html/ch/lib/pear/Translation2/Admin.php

echo
echo "===== REFLECTION CHECK ====="

docker compose \
    -f "$COMPOSE" \
    exec -T web \
    php -d include_path=/var/www/html/ch/lib/pear -r '
        require_once "Translation2.php";
        require_once "Translation2/Admin.php";

        foreach (
            array(
                array("Translation2", "_storageFactory"),
                array("Translation2_Admin", "_storageFactory"),
            ) as $item
        ) {
            [$class, $method] = $item;
            $reflection = new ReflectionMethod($class, $method);

            echo $class,
                "::",
                $method,
                " static: ",
                $reflection->isStatic() ? "yes" : "no",
                PHP_EOL;

            if (!$reflection->isStatic()) {
                exit(1);
            }
        }
    '

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
