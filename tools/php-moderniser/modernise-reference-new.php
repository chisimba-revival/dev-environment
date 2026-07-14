<?php

declare(strict_types=1);

/**
 * Modernise obsolete PHP object construction by reference.
 *
 * Converts all variants such as:
 *
 *     $object =& new SomeClass();
 *     $object = &new SomeClass();
 *     $object = & new SomeClass();
 *
 * into:
 *
 *     $object = new SomeClass();
 *
 * PHP 7 and later reject object construction using "&new".
 *
 * Usage:
 *
 *     php modernise-reference-new.php PATH [PATH ...]
 *     php modernise-reference-new.php --dry-run PATH [PATH ...]
 */

$arguments = $argv;
array_shift($arguments);

$dryRun = false;

if (($arguments[0] ?? null) === '--dry-run') {
    $dryRun = true;
    array_shift($arguments);
}

if ($arguments === []) {
    fwrite(
        STDERR,
        "Usage: php modernise-reference-new.php [--dry-run] PATH [PATH ...]\n"
    );
    exit(1);
}

$allowedExtensions = [
    'php',
    'inc',
    'php5',
];

$excludedNameParts = [
    '.before-',
    '.failed-',
    '.disabled-',
];

$filesChecked = 0;
$filesChanged = 0;
$replacements = 0;
$errors = 0;

/**
 * Determine whether a file should be processed.
 */
function shouldProcessFile(
    SplFileInfo $file,
    array $allowedExtensions,
    array $excludedNameParts
): bool {
    if (!$file->isFile() || $file->isLink()) {
        return false;
    }

    $filename = $file->getFilename();

    foreach ($excludedNameParts as $excludedPart) {
        if (strpos($filename, $excludedPart) !== false) {
            return false;
        }
    }

    $extension = strtolower($file->getExtension());

    return in_array($extension, $allowedExtensions, true);
}

/**
 * Process one PHP source file.
 */
function processFile(
    string $filename,
    bool $dryRun,
    int &$filesChecked,
    int &$filesChanged,
    int &$replacements,
    int &$errors
): void {
    $filesChecked++;

    $original = file_get_contents($filename);

    if ($original === false) {
        fwrite(STDERR, "ERROR: Could not read {$filename}\n");
        $errors++;
        return;
    }

    $changedCount = 0;

    /*
     * Match:
     *
     *     =& new
     *     = &new
     *     = & new
     *
     * The assignment operator is retained, while the obsolete reference
     * operator is removed.
     */
    $updated = preg_replace(
        '/=\s*&\s*new\b/',
        '= new',
        $original,
        -1,
        $changedCount
    );

    if ($updated === null) {
        fwrite(STDERR, "ERROR: Regular-expression failure in {$filename}\n");
        $errors++;
        return;
    }

    if ($changedCount === 0) {
        return;
    }

    $filesChanged++;
    $replacements += $changedCount;

    $mode = $dryRun ? 'WOULD CHANGE' : 'CHANGED';

    echo sprintf(
        "%s: %s (%d replacement%s)\n",
        $mode,
        $filename,
        $changedCount,
        $changedCount === 1 ? '' : 's'
    );

    if ($dryRun) {
        return;
    }

    if (file_put_contents($filename, $updated) === false) {
        fwrite(STDERR, "ERROR: Could not write {$filename}\n");
        $errors++;
    }
}

/**
 * Process a file or recursively process a directory.
 */
function processPath(
    string $path,
    bool $dryRun,
    array $allowedExtensions,
    array $excludedNameParts,
    int &$filesChecked,
    int &$filesChanged,
    int &$replacements,
    int &$errors
): void {
    if (!file_exists($path)) {
        fwrite(STDERR, "ERROR: Path does not exist: {$path}\n");
        $errors++;
        return;
    }

    if (is_file($path)) {
        $file = new SplFileInfo($path);

        if (shouldProcessFile($file, $allowedExtensions, $excludedNameParts)) {
            processFile(
                $path,
                $dryRun,
                $filesChecked,
                $filesChanged,
                $replacements,
                $errors
            );
        }

        return;
    }

    $directory = new RecursiveDirectoryIterator(
        $path,
        FilesystemIterator::SKIP_DOTS
    );

    $iterator = new RecursiveIteratorIterator(
        $directory,
        RecursiveIteratorIterator::LEAVES_ONLY
    );

    foreach ($iterator as $file) {
        if (!$file instanceof SplFileInfo) {
            continue;
        }

        if (!shouldProcessFile(
            $file,
            $allowedExtensions,
            $excludedNameParts
        )) {
            continue;
        }

        processFile(
            $file->getPathname(),
            $dryRun,
            $filesChecked,
            $filesChanged,
            $replacements,
            $errors
        );
    }
}

foreach ($arguments as $path) {
    processPath(
        $path,
        $dryRun,
        $allowedExtensions,
        $excludedNameParts,
        $filesChecked,
        $filesChanged,
        $replacements,
        $errors
    );
}

echo PHP_EOL;
echo "Files checked: {$filesChecked}\n";
echo "Files changed: {$filesChanged}\n";
echo "Replacements:  {$replacements}\n";
echo "Errors:        {$errors}\n";

exit($errors === 0 ? 0 : 1);
