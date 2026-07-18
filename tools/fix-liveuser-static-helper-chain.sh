#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="/run/media/derek/main/chisimba-revival"
SOURCE="$ROOT/framework/app/lib/pear/LiveUser.php"
SOURCE_ADMIN="$ROOT/framework/app/lib/pear/LiveUser/Admin.php"
RUNTIME="$ROOT/dev-environment/runtime/php82-ch/lib/pear/LiveUser.php"
RUNTIME_ADMIN="$ROOT/dev-environment/runtime/php82-ch/lib/pear/LiveUser/Admin.php"
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

section "PHP 8.2: Modernise LiveUser static helper chain"

for FILE in \
    "$SOURCE" \
    "$SOURCE_ADMIN" \
    "$RUNTIME" \
    "$RUNTIME_ADMIN"
do
    [[ -f "$FILE" ]] || fail "Missing file: $FILE"
done

python3 - \
    "$SOURCE" \
    "$SOURCE_ADMIN" \
    "$RUNTIME" \
    "$RUNTIME_ADMIN" <<'PY'
from pathlib import Path
import re
import sys

source = Path(sys.argv[1])
source_admin = Path(sys.argv[2])
runtime = Path(sys.argv[3])
runtime_admin = Path(sys.argv[4])

pairs = [
    (source, source_admin),
    (runtime, runtime_admin),
]


def find_matching_brace(text: str, opening: int) -> int:
    depth = 0
    quote = None
    escaped = False
    line_comment = False
    block_comment = False
    index = opening

    while index < len(text):
        char = text[index]
        nxt = text[index + 1] if index + 1 < len(text) else ""

        if line_comment:
            if char in "\r\n":
                line_comment = False
            index += 1
            continue

        if block_comment:
            if char == "*" and nxt == "/":
                block_comment = False
                index += 2
                continue

            index += 1
            continue

        if quote is not None:
            if escaped:
                escaped = False
                index += 1
                continue

            if char == "\\":
                escaped = True
                index += 1
                continue

            if char == quote:
                quote = None

            index += 1
            continue

        if char == "/" and nxt == "/":
            line_comment = True
            index += 2
            continue

        if char == "#":
            line_comment = True
            index += 1
            continue

        if char == "/" and nxt == "*":
            block_comment = True
            index += 2
            continue

        if char in ("'", '"'):
            quote = char
            index += 1
            continue

        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1

            if depth == 0:
                return index

        index += 1

    raise ValueError("Could not locate matching method brace")


def locate_method(text: str, method_name: str):
    pattern = re.compile(
        rf'''
        (?P<indent>^[ \t]*)
        (?P<modifiers>
            (?:
                public|protected|private|static|final|abstract
            )
            (?:[ \t]+
                (?:
                    public|protected|private|static|final|abstract
                )
            )*
        )?
        [ \t]*
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
        return None

    match = matches[0]
    opening = text.find("{", match.end())

    if opening < 0:
        return None

    closing = find_matching_brace(text, opening)

    return match, opening, closing


def static_calls(*texts: str) -> list[str]:
    methods = set()

    pattern = re.compile(
        r'\bLiveUser::([A-Za-z_][A-Za-z0-9_]*)\s*\(',
        re.IGNORECASE,
    )

    for text in texts:
        for method in pattern.findall(text):
            methods.add(method)

    return sorted(methods, key=str.lower)


for liveuser_file, admin_file in pairs:
    liveuser_text = liveuser_file.read_text(errors="replace")
    admin_text = admin_file.read_text(errors="replace")

    methods = static_calls(liveuser_text, admin_text)

    print()
    print(f"PAIR: {liveuser_file}")
    print(f"      {admin_file}")
    print("Static call targets:")

    for method in methods:
        print(f"  {method}")

    original = liveuser_text
    changed_methods = []
    skipped_methods = []
    refused_methods = []

    for method in methods:
        located = locate_method(liveuser_text, method)

        if located is None:
            skipped_methods.append(
                (method, "declaration not uniquely found")
            )
            continue

        match, body_start, body_end = located
        declaration = liveuser_text[match.start():body_start]
        body = liveuser_text[body_start + 1:body_end]

        if re.search(
            r'\bstatic\b',
            declaration,
            re.IGNORECASE,
        ):
            skipped_methods.append((method, "already static"))
            continue

        if re.search(r'\$this\b', body):
            refused_methods.append((method, "method body uses $this"))
            continue

        modifiers = match.group("modifiers") or ""
        modifier_words = re.findall(
            r'public|protected|private|static|final|abstract',
            modifiers,
            re.IGNORECASE,
        )

        visibility = next(
            (
                word.lower()
                for word in modifier_words
                if word.lower() in {
                    "public",
                    "protected",
                    "private",
                }
            ),
            "public",
        )

        other_modifiers = [
            word.lower()
            for word in modifier_words
            if word.lower() in {"final"}
        ]

        prefix_parts = other_modifiers + [visibility, "static"]
        prefix = " ".join(prefix_parts)

        rewritten_declaration, count = re.subn(
            rf'''
            (?P<indent>^[ \t]*)
            (?:
                (?:
                    public|protected|private|static|final|abstract
                )
                [ \t]+
            )*
            function
            [ \t]+
            (?P<reference>&[ \t]*)?
            {re.escape(method)}
            ''',
            lambda item: (
                f"{item.group('indent')}{prefix} function "
                f"{item.group('reference') or ''}{method}"
            ),
            declaration,
            count=1,
            flags=re.IGNORECASE | re.MULTILINE | re.VERBOSE,
        )

        if count != 1:
            refused_methods.append(
                (method, "could not rewrite declaration")
            )
            continue

        liveuser_text = (
            liveuser_text[:match.start()]
            + rewritten_declaration
            + liveuser_text[body_start:]
        )

        changed_methods.append(method)

    backup = liveuser_file.with_name(
        liveuser_file.name + ".before-php82-static-helper-chain"
    )

    if changed_methods:
        if not backup.exists():
            backup.write_text(original)

        liveuser_file.write_text(liveuser_text)

    print()
    print("Changed:")
    for method in changed_methods:
        print(f"  {method}")

    print("Skipped:")
    for method, reason in skipped_methods:
        print(f"  {method}: {reason}")

    print("Refused:")
    for method, reason in refused_methods:
        print(f"  {method}: {reason}")

    # A refused method is not necessarily an error: it may legitimately
    # require an object call. The current fatal chain will reveal whether
    # a specific call site must be corrected instead.
PY

section "Updated LiveUser declarations"

grep -n -A18 -B8 \
    -E \
    'function[[:space:]]+&?[[:space:]]*(loadClass|authFactory|permFactory|storageFactory|PEARLogFactory|singleton|factory)[[:space:]]*\(' \
    "$SOURCE" \
    | head -n 420 \
    || true

section "PHP 8.2 lint"

if ! docker compose \
    -f "$COMPOSE" \
    exec -T web \
    php -l /var/www/html/ch/lib/pear/LiveUser.php
then
    echo "ERROR: Runtime LiveUser.php failed lint."
    exit 1
fi

if ! docker compose \
    -f "$COMPOSE" \
    exec -T web \
    php -l /var/www/html/ch/lib/pear/LiveUser/Admin.php
then
    echo "ERROR: Runtime LiveUser/Admin.php failed lint."
    exit 1
fi

section "Reflection summary"

docker compose \
    -f "$COMPOSE" \
    exec -T web \
    php -d include_path=/var/www/html/ch/lib/pear <<'PHP'
<?php

require_once 'LiveUser.php';

$methods = array(
    'factory',
    'singleton',
    'authFactory',
    'loadClass',
);

foreach ($methods as $name) {
    if (!method_exists('LiveUser', $name)) {
        echo $name, ': missing', PHP_EOL;
        continue;
    }

    $method = new ReflectionMethod('LiveUser', $name);

    echo 'LiveUser::',
        $name,
        ' static: ',
        $method->isStatic() ? 'yes' : 'no',
        PHP_EOL;
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
    logs --no-color --tail=150 web

section "Static-helper pass complete"

echo "Reload:"
echo "  http://localhost:8082/ch/"
