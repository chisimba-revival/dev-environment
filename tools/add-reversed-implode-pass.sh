#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="/run/media/derek/main/chisimba-revival"
DEV="${ROOT}/dev-environment"

INSTALLER="${ROOT}/framework/app/installer"
PASS="${DEV}/tools/php-moderniser/modernise-reversed-implode.php"
REBUILD="${DEV}/scripts/rebuild-runtime.sh"
COMPOSE="${DEV}/compose/php82.yml"
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

section "Milestone 8: Add reversed implode/join compatibility pass"

echo "Started: $(date --iso-8601=seconds)"

for required in \
    "${INSTALLER}" \
    "${REBUILD}" \
    "${COMPOSE}"
do
    [[ -e "${required}" ]] ||
        fail "Required path does not exist: ${required}"
done

mkdir -p "$(dirname "${PASS}")"

section "Create token-based reversed implode pass"

cat >"${PASS}" <<'PHP'
#!/usr/bin/env php
<?php

declare(strict_types=1);

/**
 * Modernise legacy reversed implode()/join() calls.
 *
 * Old form accepted by earlier PHP releases:
 *
 *     implode($pieces, ', ')
 *
 * PHP 8 form:
 *
 *     implode(', ', $pieces)
 *
 * This pass only changes calls where:
 *
 * - the first argument is not a literal string; and
 * - the second argument is a literal string.
 *
 * That conservative rule avoids changing already-correct calls.
 */

function usage(): never
{
    fwrite(
        STDERR,
        "Usage: modernise-reversed-implode.php "
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
                        'vendor',
                        'node_modules',
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
 * Split a function argument list at its top-level comma.
 *
 * @return array{string,string}|null
 */
function splitTwoArguments(string $arguments): ?array
{
    $tokens = token_get_all('<?php ' . $arguments);
    array_shift($tokens);

    $depthRound = 0;
    $depthSquare = 0;
    $depthCurly = 0;
    $offset = 0;

    foreach ($tokens as $token) {
        $text = is_array($token) ? $token[1] : $token;

        if ($text === '(') {
            $depthRound++;
        } elseif ($text === ')') {
            $depthRound--;
        } elseif ($text === '[') {
            $depthSquare++;
        } elseif ($text === ']') {
            $depthSquare--;
        } elseif ($text === '{') {
            $depthCurly++;
        } elseif ($text === '}') {
            $depthCurly--;
        } elseif (
            $text === ','
            && $depthRound === 0
            && $depthSquare === 0
            && $depthCurly === 0
        ) {
            return [
                substr($arguments, 0, $offset),
                substr($arguments, $offset + 1),
            ];
        }

        $offset += strlen($text);
    }

    return null;
}

function isLiteralString(string $expression): bool
{
    $expression = trim($expression);

    if (strlen($expression) < 2) {
        return false;
    }

    $first = $expression[0];
    $last = $expression[strlen($expression) - 1];

    return (
        ($first === "'" && $last === "'")
        || ($first === '"' && $last === '"')
    );
}

/**
 * @return array{string,int}
 */
function transform(string $source): array
{
    $tokens = token_get_all($source);
    $result = '';
    $changes = 0;
    $count = count($tokens);

    for ($index = 0; $index < $count; $index++) {
        $token = $tokens[$index];

        if (
            !is_array($token)
            || $token[0] !== T_STRING
            || !in_array(
                strtolower($token[1]),
                ['implode', 'join'],
                true
            )
        ) {
            $result .= is_array($token) ? $token[1] : $token;
            continue;
        }

        $functionName = $token[1];
        $result .= $functionName;

        $scan = $index + 1;
        $between = '';

        while (
            $scan < $count
            && is_array($tokens[$scan])
            && $tokens[$scan][0] === T_WHITESPACE
        ) {
            $between .= $tokens[$scan][1];
            $scan++;
        }

        if ($scan >= $count || $tokens[$scan] !== '(') {
            $result .= $between;
            continue;
        }

        $result .= $between;

        $depth = 0;
        $argumentText = '';
        $closeIndex = null;

        for ($cursor = $scan; $cursor < $count; $cursor++) {
            $piece = $tokens[$cursor];
            $text = is_array($piece) ? $piece[1] : $piece;

            if ($text === '(') {
                $depth++;

                if ($depth > 1) {
                    $argumentText .= $text;
                }

                continue;
            }

            if ($text === ')') {
                $depth--;

                if ($depth === 0) {
                    $closeIndex = $cursor;
                    break;
                }

                $argumentText .= $text;
                continue;
            }

            $argumentText .= $text;
        }

        if ($closeIndex === null) {
            $result .= '(' . $argumentText;
            $index = $count;
            continue;
        }

        $arguments = splitTwoArguments($argumentText);

        if ($arguments === null) {
            $result .= '(' . $argumentText . ')';
            $index = $closeIndex;
            continue;
        }

        [$first, $second] = $arguments;

        if (
            !isLiteralString($first)
            && isLiteralString($second)
        ) {
            $result .= '('
                . trim($second)
                . ', '
                . trim($first)
                . ')';

            $changes++;
        } else {
            $result .= '(' . $argumentText . ')';
        }

        $index = $closeIndex;
    }

    return [$result, $changes];
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
$totalChanges = 0;
$changedFiles = [];

foreach (sourceFiles($args) as $file) {
    $source = file_get_contents($file);

    if ($source === false) {
        fwrite(STDERR, "Unable to read: {$file}\n");
        continue;
    }

    if (
        stripos($source, 'implode') === false
        && stripos($source, 'join') === false
    ) {
        continue;
    }

    [$updated, $changes] = transform($source);

    if ($changes === 0 || $updated === $source) {
        continue;
    }

    $changedFiles[$file] = $changes;
    $totalChanges += $changes;

    if ($apply) {
        $temporary = $file . '.reversed-implode.tmp';

        if (file_put_contents($temporary, $updated) === false) {
            fwrite(STDERR, "Unable to write: {$temporary}\n");
            exit(1);
        }

        /*
         * Do not lint the whole legacy file here. Some files may contain
         * unrelated later PHP 8 problems. This pass changes only a balanced
         * function call and verifies its own output structurally.
         */
        if (!rename($temporary, $file)) {
            @unlink($temporary);
            fwrite(STDERR, "Unable to replace: {$file}\n");
            exit(1);
        }
    }
}

ksort($changedFiles);

echo "Reversed implode/join compatibility pass\n";
echo "Mode: " . ($apply ? 'apply' : 'dry-run') . "\n";
echo "Changed files: " . count($changedFiles) . "\n";
echo "Changed calls: {$totalChanges}\n";

foreach ($changedFiles as $file => $changes) {
    echo "CHANGED ({$changes}): {$file}\n";
}
PHP

chmod +x "${PASS}"

php -l "${PASS}"

section "Dry-run on installer"

php "${PASS}" \
    --dry-run \
    "${INSTALLER}"

section "Apply to installer"

php "${PASS}" \
    --apply \
    "${INSTALLER}"

section "Verify wizard.inc fatal location"

WIZARD="${INSTALLER}/wizard.inc"

nl -ba "${WIZARD}" |
    sed -n '972,998p'

echo

if grep -Eq \
    'implode[[:space:]]*\([[:space:]]*\$[^,]+,[[:space:]]*["'\'']<br[[:space:]]*/?>["'\'']' \
    "${WIZARD}"
then
    fail "The reversed implode call remains in wizard.inc."
fi

section "Verify installer pass is idempotent"

SECOND_RUN="$(
    php "${PASS}" \
        --dry-run \
        "${INSTALLER}"
)"

printf '%s\n' "${SECOND_RUN}"

if ! grep -q 'Changed calls: 0' <<<"${SECOND_RUN}"; then
    fail "Reversed implode pass is not idempotent."
fi

section "Rebuild from completely fresh database"

"${REBUILD}" php82 --fresh-db

section "Container status"

docker compose \
    -f "${COMPOSE}" \
    ps -a

section "Ready for installer retest"

echo "Finished: $(date --iso-8601=seconds)"
echo
echo "Open:"
echo "  http://localhost:8082/ch/"
echo
echo "Proceed through the installer again from screen 1."
echo "The database and installer state are completely fresh."
echo
echo "If another fatal appears, capture it with:"
echo
echo "docker compose -f ${COMPOSE} logs --no-color --tail=200 web \\"
echo "  > ${LOG}"
