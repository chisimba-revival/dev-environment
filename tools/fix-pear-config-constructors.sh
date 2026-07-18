#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="/run/media/derek/main/chisimba-revival"
DEV="${ROOT}/dev-environment"
FRAMEWORK="${ROOT}/framework/app"

PASS="${DEV}/tools/php-moderniser/modernise-targeted-constructor.py"
REBUILD="${DEV}/scripts/rebuild-runtime.sh"
COMPOSE="${DEV}/compose/php82.yml"
LOG="${ROOT}/killme.txt"

CONFIG="${FRAMEWORK}/lib/pear/Config.php"
CONTAINER="${FRAMEWORK}/lib/pear/Config/Container.php"
PHPARRAY="${FRAMEWORK}/lib/pear/Config/Container/PHPArray.php"

exec > >(tee "${LOG}") 2>&1

section()
{
    echo
    echo "============================================================"
    echo "$1"
    echo "============================================================"
}

fail()
{
    echo
    echo "ERROR: $*" >&2
    exit 1
}

section "Milestone 8: Targeted PEAR Config constructor modernisation"

echo "Started: $(date --iso-8601=seconds)"

for required in \
    "${CONFIG}" \
    "${CONTAINER}" \
    "${PHPARRAY}" \
    "${REBUILD}" \
    "${COMPOSE}"
do
    [[ -f "${required}" ]] ||
        fail "Required file not found: ${required}"
done

mkdir -p "$(dirname "${PASS}")"

section "Create reusable exact-class constructor moderniser"

cat >"${PASS}" <<'PY'
#!/usr/bin/env python3

"""
Add a PHP 8 __construct() wrapper to one explicitly named legacy class.

The pass:

* modifies only the specified class in the specified file;
* preserves the legacy constructor;
* copies its complete parameter declaration;
* forwards its named parameters directly;
* supports parameters declared by reference;
* is idempotent;
* refuses ambiguous files with multiple matching classes or methods.

Usage:

    modernise-targeted-constructor.py --dry-run FILE CLASS
    modernise-targeted-constructor.py --apply FILE CLASS
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


def find_matching(
    text: str,
    opening: int,
    open_char: str,
    close_char: str,
) -> int:
    depth = 0
    quote: str | None = None
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

        if char == open_char:
            depth += 1
        elif char == close_char:
            depth -= 1

            if depth == 0:
                return index

    raise ValueError(
        f"Could not find closing {close_char!r} after offset {opening}"
    )


def extract_parameter_names(parameters: str) -> list[str]:
    """
    Extract top-level PHP parameter variable names.

    This deliberately returns only variable names, not '&' or defaults.
    A variable passed to a legacy reference parameter remains a variable and
    can therefore be accepted by reference.
    """

    names: list[str] = []
    depth_round = 0
    depth_square = 0
    depth_curly = 0
    quote: str | None = None
    escaped = False
    current = ""

    parts: list[str] = []

    for char in parameters:
        if quote is not None:
            current += char

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
            current += char
            continue

        if char == "(":
            depth_round += 1
        elif char == ")":
            depth_round -= 1
        elif char == "[":
            depth_square += 1
        elif char == "]":
            depth_square -= 1
        elif char == "{":
            depth_curly += 1
        elif char == "}":
            depth_curly -= 1

        if (
            char == ","
            and depth_round == 0
            and depth_square == 0
            and depth_curly == 0
        ):
            parts.append(current)
            current = ""
            continue

        current += char

    if current.strip():
        parts.append(current)

    for part in parts:
        variables = re.findall(r"\$[A-Za-z_][A-Za-z0-9_]*", part)

        if not variables:
            raise ValueError(
                f"Could not identify a parameter variable in: {part!r}"
            )

        names.append(variables[0])

    return names


def class_extent(text: str, class_name: str) -> tuple[int, int, int]:
    class_pattern = re.compile(
        rf"\bclass\s+{re.escape(class_name)}\b[^{{]*\{{",
        re.IGNORECASE,
    )

    matches = list(class_pattern.finditer(text))

    if len(matches) != 1:
        raise ValueError(
            f"Expected exactly one class {class_name}; found {len(matches)}"
        )

    match = matches[0]
    opening = text.find("{", match.start())
    closing = find_matching(text, opening, "{", "}")

    return match.start(), opening, closing


def transform(text: str, class_name: str) -> tuple[str, bool, str]:
    _, class_open, class_close = class_extent(text, class_name)
    class_body = text[class_open + 1 : class_close]

    if re.search(
        r"\bfunction\s+__construct\s*\(",
        class_body,
        re.IGNORECASE,
    ):
        return text, False, "already modernised"

    method_pattern = re.compile(
        rf"""
        (?P<indent>^[ \t]*)
        (?:
            public|protected|private|static|final|abstract
        )?
        [ \t]*
        function
        [ \t]+
        &?
        [ \t]*
        {re.escape(class_name)}
        [ \t]*
        \(
        """,
        re.IGNORECASE | re.MULTILINE | re.VERBOSE,
    )

    matches = list(method_pattern.finditer(class_body))

    if len(matches) != 1:
        raise ValueError(
            f"Expected exactly one legacy {class_name}() method; "
            f"found {len(matches)}"
        )

    method = matches[0]
    absolute_method_start = class_open + 1 + method.start()
    absolute_open_paren = (
        class_open
        + 1
        + class_body.find("(", method.start(), method.end())
    )

    absolute_close_paren = find_matching(
        text,
        absolute_open_paren,
        "(",
        ")",
    )

    parameters = text[
        absolute_open_paren + 1 : absolute_close_paren
    ]

    parameter_names = extract_parameter_names(parameters)
    indent = method.group("indent")

    if parameter_names:
        forwarded = ", ".join(parameter_names)
        call = f"$this->{class_name}({forwarded});"
    else:
        call = f"$this->{class_name}();"

    wrapper = (
        f"{indent}/**\n"
        f"{indent} * PHP 8 constructor wrapper generated by the targeted\n"
        f"{indent} * legacy-constructor moderniser.\n"
        f"{indent} */\n"
        f"{indent}public function __construct({parameters})\n"
        f"{indent}{{\n"
        f"{indent}    {call}\n"
        f"{indent}}}\n\n"
    )

    updated = (
        text[:absolute_method_start]
        + wrapper
        + text[absolute_method_start:]
    )

    return updated, True, parameters.strip()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "mode",
        choices=("--dry-run", "--apply"),
    )
    parser.add_argument("file")
    parser.add_argument("class_name")
    args = parser.parse_args()

    path = Path(args.file)

    if not path.is_file():
        print(f"ERROR: File not found: {path}", file=sys.stderr)
        return 2

    source = path.read_text()

    try:
        updated, changed, parameters = transform(
            source,
            args.class_name,
        )
    except ValueError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1

    print(f"File: {path}")
    print(f"Class: {args.class_name}")
    print(f"Mode: {args.mode}")

    if not changed:
        print("Result: no change required")
        return 0

    print("Result: constructor wrapper required")
    print(f"Parameters: ({parameters})")

    if args.mode == "--dry-run":
        return 0

    backup = path.with_name(path.name + ".before-targeted-constructor")

    if not backup.exists():
        backup.write_text(source)
        print(f"Backup: {backup}")

    temporary = path.with_name(path.name + ".targeted-constructor.tmp")
    temporary.write_text(updated)
    temporary.replace(path)

    print("Applied: yes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
PY

chmod +x "${PASS}"

python3 -m py_compile "${PASS}"

section "Dry-run the three confirmed PEAR classes"

python3 "${PASS}" --dry-run "${CONFIG}" Config
echo
python3 "${PASS}" --dry-run "${CONTAINER}" Config_Container
echo
python3 "${PASS}" --dry-run "${PHPARRAY}" Config_Container_PHPArray

section "Apply targeted constructor wrappers"

python3 "${PASS}" --apply "${CONFIG}" Config
echo
python3 "${PASS}" --apply "${CONTAINER}" Config_Container
echo
python3 "${PASS}" --apply "${PHPARRAY}" Config_Container_PHPArray

section "Verify generated constructor signatures"

for specification in \
    "${CONFIG}:Config" \
    "${CONTAINER}:Config_Container" \
    "${PHPARRAY}:Config_Container_PHPArray"
do
    FILE="${specification%%:*}"
    CLASS="${specification##*:}"

    echo
    echo "------------------------------------------------------------"
    echo "${CLASS} in ${FILE}"
    echo "------------------------------------------------------------"

    grep -n -A20 -B5 \
        -E "class[[:space:]]+${CLASS}|function[[:space:]]+(__construct|${CLASS})" \
        "${FILE}" \
        | head -n 100
done

section "Run PHP 8.2 syntax validation on changed files"

for FILE in \
    "${CONFIG}" \
    "${CONTAINER}" \
    "${PHPARRAY}"
do
    php -l "${FILE}"
done

section "Verify targeted pass is idempotent"

for specification in \
    "${CONFIG}:Config" \
    "${CONTAINER}:Config_Container" \
    "${PHPARRAY}:Config_Container_PHPArray"
do
    FILE="${specification%%:*}"
    CLASS="${specification##*:}"

    RESULT="$(
        python3 "${PASS}" --dry-run "${FILE}" "${CLASS}"
    )"

    printf '%s\n' "${RESULT}"

    if ! grep -q 'Result: no change required' <<<"${RESULT}"; then
        fail "Targeted constructor pass is not idempotent for ${CLASS}."
    fi

    echo
done

section "Rebuild PHP 8.2 from a completely fresh database"

"${REBUILD}" php82 --fresh-db

section "Confirm constructors in assembled runtime"

for FILE in \
    "lib/pear/Config.php" \
    "lib/pear/Config/Container.php" \
    "lib/pear/Config/Container/PHPArray.php"
do
    echo
    echo "FILE: ${FILE}"

    grep -n -A12 -B3 \
        'function[[:space:]]\+__construct' \
        "${DEV}/runtime/php82-ch/${FILE}"
done

section "PHP 8.2 container status"

docker compose \
    -f "${COMPOSE}" \
    ps -a

section "Ready for clean installer retest"

echo "Finished: $(date --iso-8601=seconds)"
echo
echo "The following constructor chains are now initialised:"
echo "  Config"
echo "  Config_Container"
echo "  Config_Container_PHPArray"
echo
echo "Open a new incognito window at:"
echo "  http://localhost:8082/ch/"
echo
echo "Proceed from installer screen 1."
echo
echo "Do not reuse the prior installer tab because the database and session"
echo "state were recreated."
echo
echo "Capture the next fatal with:"
echo
echo "docker compose -f ${COMPOSE} logs --no-color --tail=200 web \\"
echo "  > ${LOG}"
