#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="/run/media/derek/main/chisimba-revival"
MODERNISER="$ROOT/dev-environment/tools/php-moderniser"
MAIN="$MODERNISER/modernise.php"
CORE="$MODERNISER/modernise-core.php"
TARGETED="$MODERNISER/modernise-targeted-constructor.py"
SAFE_PASS="$MODERNISER/modernise-legacy-constructors-safe.py"
REPORT_DIR="$ROOT/dev-environment/reports"
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

section "Install safe constructor-modernisation pipeline"

for FILE in "$MAIN" "$TARGETED"; do
    [[ -f "$FILE" ]] || fail "Missing required file: $FILE"
done

mkdir -p "$REPORT_DIR"

section "Preserve the existing moderniser"

if [[ ! -f "$CORE" ]]; then
    cp -a "$MAIN" "$CORE"
    echo "Created: $CORE"
else
    echo "Already present: $CORE"
fi

section "Create safe constructor discovery pass"

cat > "$SAFE_PASS" <<'PY'
#!/usr/bin/env python3

"""
Safely discover and modernise PHP 4-style constructors.

For each class:

* detect a method with the same name as the class;
* skip classes that already define __construct();
* invoke modernise-targeted-constructor.py for that exact class;
* lint the transformed file;
* retain successful changes;
* restore the original file after any failed transformation;
* write a consolidated report.

The targeted constructor transformer remains the single implementation
responsible for copying signatures and forwarding parameters.
"""

from __future__ import annotations

import argparse
import datetime
import json
import re
import shutil
import subprocess
import sys
from dataclasses import asdict, dataclass
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
TARGETED = SCRIPT_DIR / "modernise-targeted-constructor.py"

DEFAULT_ROOTS = [
    Path("/run/media/derek/main/chisimba-revival/framework/app"),
    Path("/run/media/derek/main/chisimba-revival/modules"),
    Path("/run/media/derek/main/chisimba-revival/canvases"),
]

DEFAULT_REPORT = Path(
    "/run/media/derek/main/chisimba-revival/"
    "dev-environment/reports/constructor-moderniser-latest.json"
)

SOURCE_SUFFIXES = {
    ".php",
    ".inc",
}


@dataclass
class Result:
    file: str
    class_name: str
    status: str
    detail: str = ""


def source_files(roots: list[Path]):
    seen: set[Path] = set()

    for root in roots:
        if not root.exists():
            continue

        if root.is_file():
            candidates = [root]
        else:
            candidates = root.rglob("*")

        for path in candidates:
            if not path.is_file():
                continue

            name = path.name.lower()

            if not (
                path.suffix.lower() in SOURCE_SUFFIXES
                or name.endswith(".inc.php")
                or name.endswith("_class_inc.php")
            ):
                continue

            if any(
                part in {
                    ".git",
                    "vendor",
                    "node_modules",
                    "__pycache__",
                    ".constructor-moderniser-backups",
                }
                for part in path.parts
            ):
                continue

            resolved = path.resolve()

            if resolved in seen:
                continue

            seen.add(resolved)
            yield path


def matching_brace(text: str, opening: int) -> int:
    depth = 0
    quote: str | None = None
    escaped = False
    line_comment = False
    block_comment = False

    index = opening

    while index < len(text):
        char = text[index]
        next_char = text[index + 1] if index + 1 < len(text) else ""

        if line_comment:
            if char in "\r\n":
                line_comment = False
            index += 1
            continue

        if block_comment:
            if char == "*" and next_char == "/":
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

        if char == "/" and next_char == "/":
            line_comment = True
            index += 2
            continue

        if char == "#":
            line_comment = True
            index += 1
            continue

        if char == "/" and next_char == "*":
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

    raise ValueError(f"Could not match brace at offset {opening}")


def class_candidates(text: str) -> list[tuple[str, int, int]]:
    pattern = re.compile(
        r"""
        (?<![A-Za-z0-9_])
        class
        \s+
        (?P<name>[A-Za-z_][A-Za-z0-9_]*)
        (?:\s+extends\s+[A-Za-z_\\][A-Za-z0-9_\\]*)?
        (?:\s+implements\s+[^{]+)?
        \s*
        \{
        """,
        re.IGNORECASE | re.VERBOSE,
    )

    classes: list[tuple[str, int, int]] = []

    for match in pattern.finditer(text):
        opening = text.find("{", match.start())

        try:
            closing = matching_brace(text, opening)
        except ValueError:
            continue

        classes.append(
            (
                match.group("name"),
                opening + 1,
                closing,
            )
        )

    return classes


def needs_wrapper(body: str, class_name: str) -> bool:
    if re.search(
        r"\bfunction\s+&?\s*__construct\s*\(",
        body,
        re.IGNORECASE,
    ):
        return False

    legacy_pattern = re.compile(
        rf"""
        (?:
            public|protected|private|static|final|abstract
        )?
        \s*
        function
        \s+
        &?
        \s*
        {re.escape(class_name)}
        \s*
        \(
        """,
        re.IGNORECASE | re.VERBOSE,
    )

    return legacy_pattern.search(body) is not None


def run(command: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )


def lint(path: Path) -> subprocess.CompletedProcess[str]:
    return run(["php", "-l", str(path)])


def main() -> int:
    parser = argparse.ArgumentParser()

    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument(
        "--dry-run",
        action="store_true",
    )
    mode.add_argument(
        "--apply",
        action="store_true",
    )

    parser.add_argument(
        "roots",
        nargs="*",
        type=Path,
    )

    parser.add_argument(
        "--report",
        type=Path,
        default=DEFAULT_REPORT,
    )

    args = parser.parse_args()

    roots = args.roots or DEFAULT_ROOTS
    mode_arg = "--apply" if args.apply else "--dry-run"

    results: list[Result] = []
    candidate_count = 0
    changed_count = 0
    failed_count = 0

    print("Safe PHP 4 constructor pass")
    print(f"Mode: {mode_arg}")
    print("Roots:")

    for root in roots:
        print(f"  {root}")

    for path in source_files(roots):
        try:
            text = path.read_text(errors="replace")
        except OSError as error:
            results.append(
                Result(
                    str(path),
                    "",
                    "read-failed",
                    str(error),
                )
            )
            failed_count += 1
            continue

        classes = class_candidates(text)

        for class_name, start, end in classes:
            body = text[start:end]

            if not needs_wrapper(body, class_name):
                continue

            candidate_count += 1

            print()
            print(f"CANDIDATE: {path}")
            print(f"CLASS: {class_name}")

            dry = run(
                [
                    sys.executable,
                    str(TARGETED),
                    "--dry-run",
                    str(path),
                    class_name,
                ]
            )

            print(dry.stdout.rstrip())

            if dry.returncode != 0:
                results.append(
                    Result(
                        str(path),
                        class_name,
                        "dry-run-failed",
                        dry.stdout,
                    )
                )
                failed_count += 1
                continue

            if not args.apply:
                results.append(
                    Result(
                        str(path),
                        class_name,
                        "candidate",
                    )
                )
                continue

            original = path.read_bytes()

            applied = run(
                [
                    sys.executable,
                    str(TARGETED),
                    "--apply",
                    str(path),
                    class_name,
                ]
            )

            print(applied.stdout.rstrip())

            if applied.returncode != 0:
                path.write_bytes(original)

                results.append(
                    Result(
                        str(path),
                        class_name,
                        "apply-failed-restored",
                        applied.stdout,
                    )
                )

                failed_count += 1
                continue

            linted = lint(path)
            print(linted.stdout.rstrip())

            if linted.returncode != 0:
                path.write_bytes(original)

                results.append(
                    Result(
                        str(path),
                        class_name,
                        "lint-failed-restored",
                        linted.stdout,
                    )
                )

                failed_count += 1
                continue

            results.append(
                Result(
                    str(path),
                    class_name,
                    "modernised",
                )
            )

            changed_count += 1

            # Refresh the text before examining any later class in the file.
            text = path.read_text(errors="replace")

    report = {
        "generated_at": datetime.datetime.now(
            datetime.timezone.utc
        ).isoformat(),
        "mode": mode_arg,
        "roots": [str(root) for root in roots],
        "candidate_count": candidate_count,
        "changed_count": changed_count,
        "failed_count": failed_count,
        "results": [asdict(result) for result in results],
    }

    args.report.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    args.report.write_text(
        json.dumps(report, indent=2) + "\n"
    )

    text_report = args.report.with_suffix(".txt")

    with text_report.open("w") as handle:
        handle.write("Safe PHP 4 constructor pass\n")
        handle.write(f"Mode: {mode_arg}\n")
        handle.write(f"Candidates: {candidate_count}\n")
        handle.write(f"Modernised: {changed_count}\n")
        handle.write(f"Failures restored: {failed_count}\n\n")

        for result in results:
            handle.write(
                f"{result.status}: "
                f"{result.file}"
            )

            if result.class_name:
                handle.write(
                    f" :: {result.class_name}"
                )

            handle.write("\n")

            if result.detail:
                handle.write(result.detail.rstrip())
                handle.write("\n")

    print()
    print("Summary")
    print(f"Candidates: {candidate_count}")
    print(f"Modernised: {changed_count}")
    print(f"Failures restored: {failed_count}")
    print(f"JSON report: {args.report}")
    print(f"Text report: {text_report}")

    return 1 if failed_count else 0


if __name__ == "__main__":
    raise SystemExit(main())
PY

chmod +x "$SAFE_PASS"

echo "Created: $SAFE_PASS"

section "Create modernise.php orchestration wrapper"

cat > "$MAIN" <<'PHP'
#!/usr/bin/env php
<?php

declare(strict_types=1);

/**
 * Chisimba moderniser orchestration wrapper.
 *
 * Constructor modernisation runs first because later PHP 8 compatibility
 * transformations assume that objects initialise correctly.
 */

$root = '/run/media/derek/main/chisimba-revival';
$toolDir = $root . '/dev-environment/tools/php-moderniser';

$safeConstructorPass =
    $toolDir . '/modernise-legacy-constructors-safe.py';

$coreModerniser =
    $toolDir . '/modernise-core.php';

$arguments = array_slice($argv, 1);

$mode = null;

if (in_array('--apply', $arguments, true)) {
    $mode = '--apply';
} elseif (in_array('--dry-run', $arguments, true)) {
    $mode = '--dry-run';
}

if ($mode === null) {
    fwrite(
        STDERR,
        "ERROR: modernise.php requires --dry-run or --apply.\n"
    );
    exit(2);
}

/*
 * The constructor pass uses the canonical repository roots.
 * This avoids treating option values belonging to the core moderniser
 * as source paths.
 */
$constructorRoots = [
    $root . '/framework/app',
    $root . '/modules',
    $root . '/canvases',
];

$constructorCommand = array_merge(
    [
        'python3',
        $safeConstructorPass,
        $mode,
    ],
    $constructorRoots
);

function runCommand(array $command): int
{
    $escaped = array_map(
        'escapeshellarg',
        $command
    );

    $process = proc_open(
        implode(' ', $escaped),
        [
            0 => STDIN,
            1 => STDOUT,
            2 => STDERR,
        ],
        $pipes
    );

    if (!is_resource($process)) {
        fwrite(
            STDERR,
            "ERROR: Could not start command.\n"
        );

        return 1;
    }

    return proc_close($process);
}

echo PHP_EOL;
echo "============================================================", PHP_EOL;
echo "PASS 1: Safe legacy constructor modernisation", PHP_EOL;
echo "============================================================", PHP_EOL;

$constructorStatus = runCommand($constructorCommand);

if ($constructorStatus !== 0) {
    fwrite(
        STDERR,
        PHP_EOL
        . "ERROR: Constructor pass reported failures. "
        . "Failed files were restored; stopping before later passes."
        . PHP_EOL
    );

    exit($constructorStatus);
}

echo PHP_EOL;
echo "============================================================", PHP_EOL;
echo "PASS 2+: Existing Chisimba moderniser", PHP_EOL;
echo "============================================================", PHP_EOL;

$coreCommand = array_merge(
    [
        PHP_BINARY,
        $coreModerniser,
    ],
    $arguments
);

exit(runCommand($coreCommand));
PHP

chmod +x "$MAIN"

echo "Updated orchestration wrapper: $MAIN"

section "Syntax checks"

php -l "$MAIN"
php -l "$CORE"
python3 -m py_compile "$SAFE_PASS" "$TARGETED"

section "Dry-run constructor discovery"

python3 \
    "$SAFE_PASS" \
    --dry-run \
    "$ROOT/framework/app" \
    "$ROOT/modules" \
    "$ROOT/canvases" \
    --report \
    "$REPORT_DIR/constructor-moderniser-dry-run.json"

section "Apply safe constructor pass"

python3 \
    "$SAFE_PASS" \
    --apply \
    "$ROOT/framework/app" \
    "$ROOT/modules" \
    "$ROOT/canvases" \
    --report \
    "$REPORT_DIR/constructor-moderniser-apply.json"

section "Apply the LiveUser fix to the current PHP 8.2 runtime"

python3 \
    "$TARGETED" \
    --apply \
    "$ROOT/dev-environment/runtime/php82-ch/lib/pear/LiveUser.php" \
    LiveUser

section "Validate source and runtime LiveUser"

grep -n -A24 -B8 \
    -E \
    'function[[:space:]]+(__construct|LiveUser)[[:space:]]*\(' \
    "$ROOT/framework/app/lib/pear/LiveUser.php" \
    "$ROOT/dev-environment/runtime/php82-ch/lib/pear/LiveUser.php"

docker compose \
    -f "$ROOT/dev-environment/compose/php82.yml" \
    exec -T web \
    php -l /var/www/html/ch/lib/pear/LiveUser.php

section "Verify wrapper initialises dispatcher"

docker compose \
    -f "$ROOT/dev-environment/compose/php82.yml" \
    exec -T web \
    php -d include_path=/var/www/html/ch/lib/pear -r '
        require_once "LiveUser.php";

        $debug = false;
        $liveUser = new LiveUser($debug);

        echo "LiveUser class: ",
            get_class($liveUser),
            PHP_EOL;

        echo "Dispatcher initialised: ",
            is_object($liveUser->dispatcher)
                ? "yes"
                : "no",
            PHP_EOL;

        if (!is_object($liveUser->dispatcher)) {
            exit(1);
        }
    '

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
    -f "$ROOT/dev-environment/compose/php82.yml" \
    logs --no-color --tail=140 web

section "Safe constructor pipeline installed"

echo "Reports:"
echo "  $REPORT_DIR/constructor-moderniser-dry-run.txt"
echo "  $REPORT_DIR/constructor-moderniser-apply.txt"
echo
echo "Reload:"
echo "  http://localhost:8082/ch/"
