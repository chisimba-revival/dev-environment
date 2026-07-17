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
