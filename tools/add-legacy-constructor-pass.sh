#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="/run/media/derek/main/chisimba-revival"
DEV="${ROOT}/dev-environment"

PASS="${DEV}/tools/php-moderniser/modernise-legacy-constructors.php"
REBUILD="${DEV}/scripts/rebuild-runtime.sh"
COMPOSE="${DEV}/compose/php82.yml"
FRAMEWORK="${ROOT}/framework/app"
RUNTIME="${DEV}/runtime/php82-ch"
LOG="${ROOT}/killme.txt"

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

section "Milestone 8: Add legacy-constructor moderniser pass"

echo "Started: $(date --iso-8601=seconds)"

for required in \
    "${FRAMEWORK}" \
    "${REBUILD}" \
    "${COMPOSE}"
do
    [[ -e "${required}" ]] ||
        fail "Required path does not exist: ${required}"
done

mkdir -p "$(dirname "${PASS}")"

section "Create token-based legacy-constructor pass"

cat >"${PASS}" <<'PHP'
#!/usr/bin/env php
<?php

declare(strict_types=1);

/**
 * Add PHP 8 constructor wrappers to classes that rely on PHP 4-style
 * constructors.
 *
 * Example:
 *
 *     class Example
 *     {
 *         function Example($value)
 *         {
 *             ...
 *         }
 *     }
 *
 * becomes:
 *
 *     class Example
 *     {
 *         public function __construct()
 *         {
 *             call_user_func_array([$this, 'Example'], func_get_args());
 *         }
 *
 *         function Example($value)
 *         {
 *             ...
 *         }
 *     }
 *
 * The original legacy method is retained because application code may call it
 * directly. Classes that already define __construct() are not changed.
 *
 * Usage:
 *
 *     php modernise-legacy-constructors.php --dry-run PATH [...]
 *     php modernise-legacy-constructors.php --apply PATH [...]
 */

function usage(): never
{
    fwrite(
        STDERR,
        "Usage: modernise-legacy-constructors.php "
        . "(--dry-run|--apply) PATH [PATH ...]\n"
    );

    exit(2);
}

/**
 * @return Generator<string>
 */
function sourceFiles(array $roots): Generator
{
    foreach ($roots as $root) {
        if (is_file($root)) {
            yield $root;
            continue;
        }

        if (!is_dir($root)) {
            fwrite(STDERR, "Missing path: {$root}\n");
            continue;
        }

        $directory = new RecursiveDirectoryIterator(
            $root,
            FilesystemIterator::SKIP_DOTS
        );

        $filter = new RecursiveCallbackFilterIterator(
            $directory,
            static function (SplFileInfo $item): bool {
                if (!$item->isDir()) {
                    return true;
                }

                return !in_array(
                    $item->getFilename(),
                    [
                        '.git',
                        'runtime',
                        'backups',
                        'node_modules',
                        'vendor',
                    ],
                    true
                );
            }
        );

        $iterator = new RecursiveIteratorIterator($filter);

        foreach ($iterator as $file) {
            if (!$file instanceof SplFileInfo || !$file->isFile()) {
                continue;
            }

            $name = strtolower($file->getFilename());

            if (
                str_ends_with($name, '.php')
                || str_ends_with($name, '.inc')
                || str_ends_with($name, '.inc.php')
            ) {
                yield $file->getPathname();
            }
        }
    }
}

/**
 * Convert token_get_all() output into tokens with source offsets.
 *
 * @return array<int, array{
 *     token:int|string,
 *     text:string,
 *     offset:int,
 *     line:int
 * }>
 */
function offsetTokens(string $source): array
{
    $rawTokens = token_get_all($source);
    $tokens = [];
    $offset = 0;
    $line = 1;

    foreach ($rawTokens as $raw) {
        if (is_array($raw)) {
            [$id, $text, $tokenLine] = $raw;
            $tokens[] = [
                'token' => $id,
                'text' => $text,
                'offset' => $offset,
                'line' => $tokenLine,
            ];
        } else {
            $tokens[] = [
                'token' => $raw,
                'text' => $raw,
                'offset' => $offset,
                'line' => $line,
            ];
        }

        $offset += strlen(is_array($raw) ? $raw[1] : $raw);
        $line += substr_count(is_array($raw) ? $raw[1] : $raw, "\n");
    }

    return $tokens;
}

function nextSignificantToken(array $tokens, int $start): ?int
{
    $count = count($tokens);

    for ($index = $start; $index < $count; $index++) {
        $token = $tokens[$index]['token'];

        if (
            is_int($token)
            && in_array(
                $token,
                [T_WHITESPACE, T_COMMENT, T_DOC_COMMENT],
                true
            )
        ) {
            continue;
        }

        return $index;
    }

    return null;
}

function indentationBeforeOffset(string $source, int $offset): string
{
    $lineStart = strrpos(substr($source, 0, $offset), "\n");

    if ($lineStart === false) {
        $lineStart = 0;
    } else {
        $lineStart++;
    }

    $prefix = substr($source, $lineStart, $offset - $lineStart);

    if (preg_match('/^[ \t]*/', $prefix, $matches)) {
        return $matches[0];
    }

    return '';
}

/**
 * Find class declarations and their methods.
 *
 * @return array<int, array{
 *     class:string,
 *     legacy:string,
 *     insertion_offset:int,
 *     indentation:string,
 *     line:int
 * }>
 */
function findLegacyConstructors(string $source): array
{
    $tokens = offsetTokens($source);
    $count = count($tokens);

    $braceDepth = 0;
    $pendingClass = null;
    $classStack = [];
    $classes = [];

    for ($index = 0; $index < $count; $index++) {
        $token = $tokens[$index]['token'];
        $text = $tokens[$index]['text'];

        if ($token === T_CLASS) {
            $nameIndex = nextSignificantToken($tokens, $index + 1);

            if (
                $nameIndex !== null
                && $tokens[$nameIndex]['token'] === T_STRING
            ) {
                $pendingClass = [
                    'name' => $tokens[$nameIndex]['text'],
                    'line' => $tokens[$nameIndex]['line'],
                ];
            }

            continue;
        }

        if ($text === '{') {
            $braceDepth++;

            if ($pendingClass !== null) {
                $classStack[] = [
                    'name' => $pendingClass['name'],
                    'depth' => $braceDepth,
                    'line' => $pendingClass['line'],
                    'has_construct' => false,
                    'legacy' => null,
                ];

                $pendingClass = null;
            }

            continue;
        }

        if ($text === '}') {
            if ($classStack !== []) {
                $topIndex = array_key_last($classStack);

                if ($classStack[$topIndex]['depth'] === $braceDepth) {
                    $class = array_pop($classStack);

                    if (
                        !$class['has_construct']
                        && $class['legacy'] !== null
                    ) {
                        $classes[] = [
                            'class' => $class['name'],
                            'legacy' => $class['legacy']['name'],
                            'insertion_offset' =>
                                $class['legacy']['offset'],
                            'indentation' =>
                                $class['legacy']['indentation'],
                            'line' => $class['legacy']['line'],
                        ];
                    }
                }
            }

            $braceDepth--;
            continue;
        }

        if ($token !== T_FUNCTION || $classStack === []) {
            continue;
        }

        $topIndex = array_key_last($classStack);

        /*
         * Ignore functions nested inside methods or closures.
         */
        if ($classStack[$topIndex]['depth'] !== $braceDepth) {
            continue;
        }

        $nameIndex = nextSignificantToken($tokens, $index + 1);

        if ($nameIndex === null) {
            continue;
        }

        /*
         * Account for functions declared by reference:
         *
         *     function &Example()
         */
        if ($tokens[$nameIndex]['text'] === '&') {
            $nameIndex = nextSignificantToken($tokens, $nameIndex + 1);
        }

        if (
            $nameIndex === null
            || $tokens[$nameIndex]['token'] !== T_STRING
        ) {
            continue;
        }

        $methodName = $tokens[$nameIndex]['text'];

        if (strcasecmp($methodName, '__construct') === 0) {
            $classStack[$topIndex]['has_construct'] = true;
            continue;
        }

        if (
            strcasecmp(
                $methodName,
                $classStack[$topIndex]['name']
            ) !== 0
        ) {
            continue;
        }

        /*
         * Insert before modifiers/docblock associated with the legacy
         * constructor where possible.
         */
        $insertionOffset = $tokens[$index]['offset'];
        $scan = $index - 1;

        while ($scan >= 0) {
            $previousToken = $tokens[$scan]['token'];

            if (
                is_int($previousToken)
                && in_array(
                    $previousToken,
                    [
                        T_WHITESPACE,
                        T_PUBLIC,
                        T_PROTECTED,
                        T_PRIVATE,
                        T_STATIC,
                        T_FINAL,
                        T_ABSTRACT,
                    ],
                    true
                )
            ) {
                if (
                    in_array(
                        $previousToken,
                        [
                            T_PUBLIC,
                            T_PROTECTED,
                            T_PRIVATE,
                            T_STATIC,
                            T_FINAL,
                            T_ABSTRACT,
                        ],
                        true
                    )
                ) {
                    $insertionOffset = $tokens[$scan]['offset'];
                }

                $scan--;
                continue;
            }

            break;
        }

        $classStack[$topIndex]['legacy'] = [
            'name' => $methodName,
            'offset' => $insertionOffset,
            'indentation' =>
                indentationBeforeOffset($source, $insertionOffset),
            'line' => $tokens[$nameIndex]['line'],
        ];
    }

    return $classes;
}

/**
 * @return array{string, array<int, array<string, mixed>>}
 */
function transform(string $source): array
{
    $constructors = findLegacyConstructors($source);

    if ($constructors === []) {
        return [$source, []];
    }

    /*
     * Apply insertions from the end of the source backwards so offsets remain
     * valid.
     */
    usort(
        $constructors,
        static fn(array $left, array $right): int =>
            $right['insertion_offset'] <=> $left['insertion_offset']
    );

    $updated = $source;

    foreach ($constructors as $constructor) {
        $indent = $constructor['indentation'];
        $legacy = $constructor['legacy'];

        $wrapper =
            $indent . "/**\n"
            . $indent . " * PHP 8 constructor wrapper for the legacy "
            . "{$legacy}() constructor.\n"
            . $indent . " */\n"
            . $indent . "public function __construct()\n"
            . $indent . "{\n"
            . $indent . "    call_user_func_array(\n"
            . $indent . "        [\$this, '{$legacy}'],\n"
            . $indent . "        func_get_args()\n"
            . $indent . "    );\n"
            . $indent . "}\n\n";

        $updated =
            substr($updated, 0, $constructor['insertion_offset'])
            . $wrapper
            . substr($updated, $constructor['insertion_offset']);
    }

    return [$updated, $constructors];
}

$args = $argv;
array_shift($args);

$mode = array_shift($args);

if (
    !in_array($mode, ['--dry-run', '--apply'], true)
    || $args === []
) {
    usage();
}

$apply = $mode === '--apply';

$changedFiles = [];
$totalConstructors = 0;
$failures = [];

foreach (sourceFiles($args) as $file) {
    $source = file_get_contents($file);

    if ($source === false) {
        $failures[] = "Unable to read: {$file}";
        continue;
    }

    [$updated, $constructors] = transform($source);

    if ($constructors === [] || $updated === $source) {
        continue;
    }

    $changedFiles[$file] = $constructors;
    $totalConstructors += count($constructors);

    if (!$apply) {
        continue;
    }

    $temporary = $file . '.legacy-constructor-moderniser.tmp';

    if (file_put_contents($temporary, $updated) === false) {
        $failures[] = "Unable to write: {$temporary}";
        continue;
    }

    $lintOutput = [];
    $lintStatus = 0;

    exec(
        sprintf('php -l %s 2>&1', escapeshellarg($temporary)),
        $lintOutput,
        $lintStatus
    );

    if ($lintStatus !== 0) {
        @unlink($temporary);

        $failures[] =
            "Lint failed after constructor transformation: {$file}\n"
            . implode("\n", $lintOutput);

        continue;
    }

    if (!rename($temporary, $file)) {
        @unlink($temporary);
        $failures[] = "Unable to replace: {$file}";
    }
}

ksort($changedFiles);

echo "Legacy-constructor compatibility pass\n";
echo "Mode: " . ($apply ? 'apply' : 'dry-run') . "\n";
echo "Changed files: " . count($changedFiles) . "\n";
echo "Constructor wrappers: {$totalConstructors}\n";

foreach ($changedFiles as $file => $constructors) {
    foreach ($constructors as $constructor) {
        echo sprintf(
            "CHANGED: %s:%d class %s legacy %s()\n",
            $file,
            $constructor['line'],
            $constructor['class'],
            $constructor['legacy']
        );
    }
}

if ($failures !== []) {
    fwrite(STDERR, "\nFailures:\n");

    foreach ($failures as $failure) {
        fwrite(STDERR, $failure . "\n");
    }

    exit(1);
}
PHP

chmod +x "${PASS}"

php -l "${PASS}"

section "Remove abandoned constructor temporary files"

find "${FRAMEWORK}" \
    -type f \
    -name '*.legacy-constructor-moderniser.tmp' \
    -print \
    -delete

section "Dry-run legacy-constructor pass on framework"

php "${PASS}" \
    --dry-run \
    "${FRAMEWORK}"

section "Apply legacy-constructor pass to framework"

php "${PASS}" \
    --apply \
    "${FRAMEWORK}"

section "Verify pass is idempotent"

SECOND_DRY_RUN="$(
    php "${PASS}" \
        --dry-run \
        "${FRAMEWORK}"
)"

printf '%s\n' "${SECOND_DRY_RUN}"

if ! grep -q 'Constructor wrappers: 0' <<<"${SECOND_DRY_RUN}"; then
    fail "Legacy-constructor pass is not idempotent."
fi

echo "Confirmed: running the pass again produces no changes."

section "Confirm Template constructor wrapper"

grep -n -A25 -B8 \
    -E 'class[[:space:]]+Template|function[[:space:]]+(__construct|Template)' \
    "${FRAMEWORK}/installer/template.inc" \
    | head -n 120

section "Confirm InstallWizard was not duplicated"

INSTALLWIZARD_CONSTRUCTORS="$(
    grep -Ec \
        'function[[:space:]]+__construct[[:space:]]*\(' \
        "${FRAMEWORK}/installer/installwizard.inc"
)"

echo "InstallWizard __construct() count: ${INSTALLWIZARD_CONSTRUCTORS}"

if [[ "${INSTALLWIZARD_CONSTRUCTORS}" -ne 1 ]]; then
    fail "InstallWizard should contain exactly one __construct()."
fi

section "Rebuild completely fresh PHP 8.2 runtime"

"${REBUILD}" php82 --fresh-db

section "Request installer after constructor modernisation"

sleep 3

set +e

HTTP_OUTPUT="$(
    curl \
        --silent \
        --show-error \
        --location \
        --max-time 30 \
        --write-out '\nHTTP_STATUS:%{http_code}\n' \
        "http://localhost:8082/ch/" \
        2>&1
)"

CURL_STATUS=$?

set -e

echo "curl exit status: ${CURL_STATUS}"
echo
printf '%s\n' "${HTTP_OUTPUT}"

section "First failure after legacy-constructor pass"

PAGE_FAILURES="$(
    printf '%s\n' "${HTTP_OUTPUT}" \
    | grep -Ei \
        'fatal error|uncaught|typeerror|valueerror|parse error|compile error|warning' \
    | head -n 40 \
    || true
)"

LOG_FAILURES="$(
    docker compose \
        -f "${COMPOSE}" \
        logs --no-color --since=2m web \
        2>/dev/null \
    | grep -Ei \
        'fatal error|uncaught|typeerror|valueerror|parse error|compile error' \
    | head -n 40 \
    || true
)"

if [[ -n "${PAGE_FAILURES}" ]]; then
    echo "--- Browser response ---"
    printf '%s\n' "${PAGE_FAILURES}"
fi

if [[ -n "${LOG_FAILURES}" ]]; then
    echo
    echo "--- Container log ---"
    printf '%s\n' "${LOG_FAILURES}"
fi

if [[ -z "${PAGE_FAILURES}" && -z "${LOG_FAILURES}" ]]; then
    echo "No fatal-pattern line was detected."
fi

section "Installer page indicators"

printf '%s\n' "${HTTP_OUTPUT}" \
    | grep -Ei \
        'chisimba|installer|welcome|licence|performing step|fatal error|warning' \
    | head -n 100 \
    || true

section "Recent PHP 8.2 web log"

docker compose \
    -f "${COMPOSE}" \
    logs --no-color --tail=120 web \
    || true

section "Framework repository status summary"

git -C "${ROOT}/framework" status --short

section "Legacy-constructor migration pass complete"

echo "Finished: $(date --iso-8601=seconds)"
echo
echo "PHP 8.2:"
echo "  http://localhost:8082/ch/"
echo
echo "Reusable constructor pass:"
echo "  ${PASS} --apply ${FRAMEWORK}"
echo
echo "Reusable clean rebuild:"
echo "  ${REBUILD} php82 --fresh-db"
echo
echo "Upload:"
echo "  ${LOG}"
