#!/usr/bin/env php
<?php

declare(strict_types=1);

/**
 * Guard unprotected global imagecreatefrombmp() definitions.
 *
 * Usage:
 *   php modernise-imagecreatefrombmp-20260715.php [--dry-run] PATH [PATH ...]
 */

$args = $argv;
array_shift($args);
$dryRun = false;

if (($args[0] ?? null) === '--dry-run') {
    $dryRun = true;
    array_shift($args);
}

if ($args === []) {
    fwrite(STDERR, "Usage: php modernise-imagecreatefrombmp-20260715.php [--dry-run] PATH [PATH ...]\n");
    exit(1);
}

$extensions = ['php', 'inc', 'php5'];
$excluded = ['.before-', '.failed-', '.disabled-'];
$checked = 0;
$changedFiles = 0;
$guarded = 0;
$errors = 0;

function eligible(SplFileInfo $file, array $extensions, array $excluded): bool
{
    if (!$file->isFile() || $file->isLink()) {
        return false;
    }

    foreach ($excluded as $part) {
        if (strpos($file->getFilename(), $part) !== false) {
            return false;
        }
    }

    return in_array(strtolower($file->getExtension()), $extensions, true);
}

function matchingBrace(string $source, int $openingBrace): ?int
{
    $tokens = token_get_all($source);
    $offset = 0;
    $depth = 0;
    $started = false;

    foreach ($tokens as $token) {
        $text = is_array($token) ? $token[1] : $token;
        $length = strlen($text);

        for ($i = 0; $i < $length; $i++) {
            $absolute = $offset + $i;

            if (!$started) {
                if ($absolute === $openingBrace && $text[$i] === '{') {
                    $started = true;
                    $depth = 1;
                }
                continue;
            }

            if ($text[$i] === '{') {
                $depth++;
            } elseif ($text[$i] === '}') {
                $depth--;
                if ($depth === 0) {
                    return $absolute;
                }
            }
        }

        $offset += $length;
    }

    return null;
}

function alreadyGuarded(string $source, int $functionOffset): bool
{
    $start = max(0, $functionOffset - 300);
    $prefix = substr($source, $start, $functionOffset - $start);

    return preg_match(
        "/if\\s*\\(\\s*!\\s*function_exists\\s*\\(\\s*['\"]imagecreatefrombmp['\"]\\s*\\)\\s*\\)\\s*\\{\\s*$/is",
        $prefix
    ) === 1;
}

function transform(string $source, int &$count): string
{
    $count = 0;
    $pattern = '/^[ \\t]*function[ \\t]+imagecreatefrombmp[ \\t]*\\([^)]*\\)[ \\t\\r\\n]*\\{/mi';
    $offset = 0;

    while (preg_match($pattern, $source, $match, PREG_OFFSET_CAPTURE, $offset)) {
        $matched = $match[0][0];
        $functionOffset = $match[0][1];

        if (alreadyGuarded($source, $functionOffset)) {
            $offset = $functionOffset + strlen($matched);
            continue;
        }

        $relativeBrace = strrpos($matched, '{');
        if ($relativeBrace === false) {
            throw new RuntimeException('Opening brace not found.');
        }

        $openingBrace = $functionOffset + $relativeBrace;
        $closingBrace = matchingBrace($source, $openingBrace);
        if ($closingBrace === null) {
            throw new RuntimeException('Matching closing brace not found.');
        }

        $lineStart = strrpos(substr($source, 0, $functionOffset), "\n");
        $lineStart = $lineStart === false ? 0 : $lineStart + 1;
        $indent = substr($source, $lineStart, $functionOffset - $lineStart);
        $indent = preg_replace('/[^ \\t].*$/s', '', $indent) ?? '';

        $guardStart = $indent . "if (!function_exists('imagecreatefrombmp')) {\n";
        $source = substr_replace($source, $guardStart, $functionOffset, 0);
        $closingBrace += strlen($guardStart);

        $guardEnd = "\n" . $indent . "}";
        $source = substr_replace($source, $guardEnd, $closingBrace + 1, 0);

        $count++;
        $offset = $closingBrace + 1 + strlen($guardEnd);
    }

    return $source;
}

function processFile(
    string $path,
    bool $dryRun,
    int &$checked,
    int &$changedFiles,
    int &$guarded,
    int &$errors
): void {
    $checked++;
    $original = file_get_contents($path);

    if ($original === false) {
        fwrite(STDERR, "ERROR: cannot read {$path}\n");
        $errors++;
        return;
    }

    try {
        $count = 0;
        $updated = transform($original, $count);
    } catch (Throwable $error) {
        fwrite(STDERR, "ERROR: {$path}: {$error->getMessage()}\n");
        $errors++;
        return;
    }

    if ($count === 0) {
        return;
    }

    echo ($dryRun ? 'WOULD CHANGE: ' : 'CHANGED: ') . $path . " ({$count})\n";
    $changedFiles++;
    $guarded += $count;

    if ($dryRun) {
        return;
    }

    if (file_put_contents($path, $updated) === false) {
        fwrite(STDERR, "ERROR: cannot write {$path}\n");
        $errors++;
        return;
    }

    exec('php -l ' . escapeshellarg($path) . ' 2>&1', $lintOutput, $lintStatus);
    if ($lintStatus !== 0) {
        fwrite(STDERR, "ERROR: syntax check failed for {$path}\n" . implode("\n", $lintOutput) . "\n");
        $errors++;
    }
}

function processPath(
    string $path,
    bool $dryRun,
    array $extensions,
    array $excluded,
    int &$checked,
    int &$changedFiles,
    int &$guarded,
    int &$errors
): void {
    if (!file_exists($path)) {
        fwrite(STDERR, "ERROR: path does not exist: {$path}\n");
        $errors++;
        return;
    }

    if (is_file($path)) {
        $file = new SplFileInfo($path);
        if (eligible($file, $extensions, $excluded)) {
            processFile($path, $dryRun, $checked, $changedFiles, $guarded, $errors);
        }
        return;
    }

    $iterator = new RecursiveIteratorIterator(
        new RecursiveDirectoryIterator($path, FilesystemIterator::SKIP_DOTS),
        RecursiveIteratorIterator::LEAVES_ONLY
    );

    foreach ($iterator as $file) {
        if ($file instanceof SplFileInfo && eligible($file, $extensions, $excluded)) {
            processFile($file->getPathname(), $dryRun, $checked, $changedFiles, $guarded, $errors);
        }
    }
}

foreach ($args as $path) {
    processPath($path, $dryRun, $extensions, $excluded, $checked, $changedFiles, $guarded, $errors);
}

echo "\nFiles checked: {$checked}\n";
echo "Files changed: {$changedFiles}\n";
echo "Definitions guarded: {$guarded}\n";
echo "Errors: {$errors}\n";

exit($errors === 0 ? 0 : 1);
