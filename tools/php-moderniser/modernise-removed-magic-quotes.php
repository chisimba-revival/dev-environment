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

    $lintOutput = [];
    $lintStatus = 0;

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
