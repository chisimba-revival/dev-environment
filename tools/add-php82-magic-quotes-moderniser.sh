#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="/run/media/derek/main/chisimba-revival"
DEV="${ROOT}/dev-environment"
MODERNISER_DIR="${DEV}/tools/php-moderniser"

MODERNISER="${MODERNISER_DIR}/modernise-removed-magic-quotes.php"
RUNNER="${DEV}/scripts/php82-modernise.sh"

COMPOSE="${DEV}/compose/php82.yml"
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

section "Milestone 8: Add PHP 8.2 magic-quotes moderniser"

echo "Started: $(date --iso-8601=seconds)"

mkdir -p "${MODERNISER_DIR}"

section "Create repeatable magic-quotes transformation"

cat >"${MODERNISER}" <<'PHP'
#!/usr/bin/env php
<?php

declare(strict_types=1);

/**
 * Modernise PHP magic-quotes calls removed from PHP 8.
 *
 * Transformations:
 *
 *     get_magic_quotes_gpc()
 *         becomes
 *     false
 *
 *     get_magic_quotes_runtime()
 *         becomes
 *     false
 *
 *     set_magic_quotes_runtime(...)
 *         becomes
 *     false
 *
 * Magic quotes no longer exist. Therefore:
 *
 * - code asking whether they are enabled must receive false;
 * - code attempting to enable or disable them becomes a harmless false
 *   expression.
 *
 * Usage:
 *
 *     php modernise-removed-magic-quotes.php --dry-run PATH [...]
 *     php modernise-removed-magic-quotes.php --apply PATH [...]
 */

function usage(): never
{
    fwrite(
        STDERR,
        "Usage: php modernise-removed-magic-quotes.php "
        . "(--dry-run|--apply) PATH [PATH ...]\n"
    );

    exit(2);
}

/**
 * @return Generator<string>
 */
function phpFiles(array $roots): Generator
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
            static function (
                SplFileInfo $item,
                string $key,
                RecursiveIterator $iterator
            ): bool {
                if ($item->isDir()) {
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

                return true;
            }
        );

        $iterator = new RecursiveIteratorIterator($filter);

        foreach ($iterator as $file) {
            if (!$file instanceof SplFileInfo || !$file->isFile()) {
                continue;
            }

            $name = $file->getFilename();

            if (
                str_ends_with($name, '.php')
                || str_ends_with($name, '_class_inc.php')
                || str_ends_with($name, '_tpl.php')
            ) {
                yield $file->getPathname();
            }
        }
    }
}

/**
 * Replace exact removed-function calls while avoiding comments and strings.
 *
 * @return array{string, int}
 */
function transform(string $source): array
{
    $tokens = token_get_all($source);
    $output = '';
    $changes = 0;
    $count = count($tokens);

    for ($index = 0; $index < $count; $index++) {
        $token = $tokens[$index];

        if (!is_array($token) || $token[0] !== T_STRING) {
            $output .= is_array($token) ? $token[1] : $token;
            continue;
        }

        $function = strtolower($token[1]);

        if (
            !in_array(
                $function,
                [
                    'get_magic_quotes_gpc',
                    'get_magic_quotes_runtime',
                    'set_magic_quotes_runtime',
                ],
                true
            )
        ) {
            $output .= $token[1];
            continue;
        }

        /*
         * Do not transform method calls, static calls or declarations.
         */
        $previousSignificant = null;

        for ($back = $index - 1; $back >= 0; $back--) {
            $candidate = $tokens[$back];

            if (
                is_array($candidate)
                && in_array(
                    $candidate[0],
                    [T_WHITESPACE, T_COMMENT, T_DOC_COMMENT],
                    true
                )
            ) {
                continue;
            }

            $previousSignificant = $candidate;
            break;
        }

        if (
            $previousSignificant === '->'
            || $previousSignificant === '::'
            || (
                is_array($previousSignificant)
                && in_array(
                    $previousSignificant[0],
                    [T_FUNCTION, T_OBJECT_OPERATOR, T_DOUBLE_COLON],
                    true
                )
            )
        ) {
            $output .= $token[1];
            continue;
        }

        $openIndex = $index + 1;

        while (
            $openIndex < $count
            && is_array($tokens[$openIndex])
            && $tokens[$openIndex][0] === T_WHITESPACE
        ) {
            $openIndex++;
        }

        if ($openIndex >= $count || $tokens[$openIndex] !== '(') {
            $output .= $token[1];
            continue;
        }

        $depth = 0;
        $closeIndex = null;

        for ($scan = $openIndex; $scan < $count; $scan++) {
            $piece = $tokens[$scan];

            if ($piece === '(') {
                $depth++;
            } elseif ($piece === ')') {
                $depth--;

                if ($depth === 0) {
                    $closeIndex = $scan;
                    break;
                }
            }
        }

        if ($closeIndex === null) {
            $output .= $token[1];
            continue;
        }

        $output .= 'false';
        $changes++;
        $index = $closeIndex;
    }

    return [$output, $changes];
}

$args = $argv;
array_shift($args);

$mode = array_shift($args);

if (!in_array($mode, ['--dry-run', '--apply'], true) || $args === []) {
    usage();
}

$apply = $mode === '--apply';
$totalChanges = 0;
$changedFiles = [];
$failures = [];

foreach (phpFiles($args) as $file) {
    $source = file_get_contents($file);

    if ($source === false) {
        $failures[] = "Unable to read: {$file}";
        continue;
    }

    if (
        stripos($source, 'magic_quotes') === false
    ) {
        continue;
    }

    [$updated, $changes] = transform($source);

    if ($changes === 0 || $updated === $source) {
        continue;
    }

    $changedFiles[$file] = $changes;
    $totalChanges += $changes;

    if (!$apply) {
        continue;
    }

    $temporary = $file . '.magic-quotes-moderniser.tmp';

    if (file_put_contents($temporary, $updated) === false) {
        $failures[] = "Unable to write temporary file: {$temporary}";
        continue;
    }

    $lintCommand = sprintf(
        'php -l %s 2>&1',
        escapeshellarg($temporary)
    );

    exec($lintCommand, $lintOutput, $lintStatus);

    if ($lintStatus !== 0) {
        @unlink($temporary);

        $failures[] =
            "Transformation failed syntax validation: {$file}\n"
            . implode("\n", $lintOutput);

        continue;
    }

    if (!rename($temporary, $file)) {
        @unlink($temporary);
        $failures[] = "Unable to replace: {$file}";
    }
}

ksort($changedFiles);

echo "Removed magic-quotes compatibility pass\n";
echo "Mode: " . ($apply ? 'apply' : 'dry-run') . "\n";
echo "Changed files: " . count($changedFiles) . "\n";
echo "Changed calls: {$totalChanges}\n";

foreach ($changedFiles as $file => $changes) {
    echo "CHANGED ({$changes}): {$file}\n";
}

if ($failures !== []) {
    fwrite(STDERR, "\nFailures:\n");

    foreach ($failures as $failure) {
        fwrite(STDERR, $failure . "\n");
    }

    exit(1);
}

exit(0);
PHP

chmod +x "${MODERNISER}"

section "Create PHP 8.2 moderniser runner"

cat >"${RUNNER}" <<'BASH'
#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="/run/media/derek/main/chisimba-revival"
DEV="${ROOT}/dev-environment"

MODE="${1:---apply}"

case "${MODE}" in
    --apply|--dry-run)
        ;;
    *)
        echo "Usage: $0 [--apply|--dry-run]" >&2
        exit 2
        ;;
esac

ROOTS=(
    "${ROOT}/framework/app"
    "${ROOT}/modules"
    "${ROOT}/canvases"
)

php \
    "${DEV}/tools/php-moderniser/modernise-removed-magic-quotes.php" \
    "${MODE}" \
    "${ROOTS[@]}"
BASH

chmod +x "${RUNNER}"

section "Dry-run transformation"

"${RUNNER}" --dry-run

section "Apply transformation to source repositories"

"${RUNNER}" --apply

section "Verify the first-fatal source file"

INSTALLER="${ROOT}/framework/app/installer/index.php"

if [[ ! -f "${INSTALLER}" ]]; then
    fail "Installer source not found: ${INSTALLER}"
fi

grep -n \
    -E 'magic_quotes|install_gpc_stripslashes|false' \
    "${INSTALLER}" \
    | head -n 30 \
    || true

echo

php -l "${INSTALLER}"

section "Check removed calls across active source repositories"

REMAINING="$(
    grep -RInE \
        --include='*.php' \
        --include='*_class_inc.php' \
        --include='*_tpl.php' \
        --exclude='*.before-*' \
        --exclude='*.failed-*' \
        '\b(get_magic_quotes_gpc|get_magic_quotes_runtime|set_magic_quotes_runtime)[[:space:]]*\(' \
        "${ROOT}/framework/app" \
        "${ROOT}/modules" \
        "${ROOT}/canvases" \
        || true
)"

if [[ -n "${REMAINING}" ]]; then
    echo "Untransformed calls remain:"
    printf '%s\n' "${REMAINING}"
    fail "Magic-quotes modernisation is incomplete."
fi

echo "No active magic-quotes function calls remain."

section "Reassemble disposable PHP 8.2 runtime"

docker compose \
    -f "${COMPOSE}" \
    stop web \
    || true

if [[ -e "${RUNTIME}" ]]; then
    chmod -R u+rwX "${RUNTIME}" 2>/dev/null || true
    rm -rf "${RUNTIME}"
fi

mkdir -p "${RUNTIME}"

cp -a "${ROOT}/framework/app/." "${RUNTIME}/"

rm -rf "${RUNTIME}/packages" "${RUNTIME}/canvases"
mkdir -p "${RUNTIME}/packages" "${RUNTIME}/canvases"

cp -a "${ROOT}/modules/." "${RUNTIME}/packages/"
cp -a "${ROOT}/canvases/." "${RUNTIME}/canvases/"

rm -f \
    "${RUNTIME}/config/installdone.txt" \
    "${RUNTIME}/tmpinstallfile"

mkdir -p \
    "${RUNTIME}/config" \
    "${RUNTIME}/error_log" \
    "${RUNTIME}/error_logs" \
    "${RUNTIME}/usrfiles" \
    "${RUNTIME}/user_images"

chmod -R a+rwX "${RUNTIME}"

echo "Fresh PHP 8.2 runtime assembled."

section "Restart PHP 8.2 web container"

docker compose \
    -f "${COMPOSE}" \
    up -d web

docker compose \
    -f "${COMPOSE}" \
    ps -a

section "Request installer after magic-quotes modernisation"

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

section "New first fatal"

{
    docker compose \
        -f "${COMPOSE}" \
        logs --no-color --since=5m web \
        2>/dev/null

    find "${RUNTIME}" \
        -maxdepth 4 \
        -type f \
        \( -iname '*error*' -o -iname '*.log' \) \
        -exec cat {} + \
        2>/dev/null
} \
    | grep -Ei \
        'fatal error|parse error|uncaught|compile error|typeerror|valueerror' \
    | tail -n 30 \
    || echo "No fatal-pattern line was detected."

section "Relevant PHP 8.2 logs"

docker compose \
    -f "${COMPOSE}" \
    logs --no-color --tail=150 web \
    || true

section "Repository status"

echo "--- framework ---"
git -C "${ROOT}/framework" status --short

echo
echo "--- modules ---"
git -C "${ROOT}/modules" status --short

echo
echo "--- canvases ---"
git -C "${ROOT}/canvases" status --short

echo
echo "--- dev-environment ---"
git -C "${DEV}" status --short

section "Magic-quotes migration pass complete"

echo "Finished: $(date --iso-8601=seconds)"
echo
echo "PHP 8.2:"
echo "  http://localhost:8082/ch/"
echo
echo "Upload:"
echo "  ${LOG}"
