#!/usr/bin/env php
<?php

declare(strict_types=1);

/**
 * Chisimba PHP Moderniser
 *
 * Reports known PHP compatibility issues by default.
 *
 * Use:
 *   php modernise.php
 *
 * To apply the narrowly scoped curated PEAR compatibility fixes:
 *   php modernise.php --apply --pear-only
 */

const EXIT_SUCCESS = 0;
const EXIT_FAILURE = 1;

$workspaceDir = dirname(__DIR__, 3);

$applyChanges = in_array('--apply', $argv, true);
$pearOnly = in_array('--pear-only', $argv, true);

$sourceRoots = [
    $workspaceDir . '/framework/app',
    $workspaceDir . '/modules',
    $workspaceDir . '/canvases',
];

$excludedDirectoryNames = [
    '.git',
    'node_modules',
    'vendor',
    'resources',
    'tests',
    'tmp',
    'wastebin',
];

$allowedExtensions = [
    'php',
    'inc',
];

$rules = [
    [
        'id' => '001-reference-new',
        'description' => 'PHP 4 object construction using =& new or = &new',
        'pattern' => '/=\s*&\s*new\b/',
    ],
    [
        'id' => '002-removed-ereg',
        'description' => 'Removed ereg() or eregi() function calls',
        'pattern' => '/\beregi?\s*\(/i',
    ],
    [
        'id' => '003-reserved-object-class',
        'description' => 'Reserved class name object or inheritance from object',
        'pattern' => '/(?:\bclass\s+object\b|\bextends\s+object\b)/i',
    ],
    [
        'id' => '004-reference-method-result',
        'description' => 'Assignment by reference from a method call',
        'pattern' => '/=\s*&\s*\$this->\w+\s*\(/',
    ],
    [
        'id' => '005-removed-magic-quotes',
        'description' => 'Calls to removed PHP Magic Quotes functions',
        'pattern' => '/\b(?:get_magic_quotes_runtime|get_magic_quotes_gpc|set_magic_quotes_runtime)\s*\(/',
    ],
    [
        'id' => '006-continue-in-switch',
        'description' => 'Bare continue inside a switch case',
        'pattern' => '/^\s*continue\s*;\s*$/',
    ],
];

$files = findSourceFiles(
    $sourceRoots,
    $allowedExtensions,
    $excludedDirectoryNames
);

if ($files === []) {
    fwrite(STDERR, "No PHP source files were found.\n");
    exit(EXIT_FAILURE);
}

$changedFiles = [];

if ($applyChanges) {
    $changedFiles = applyPearCompatibilityFixes(
        $files,
        $workspaceDir,
        $pearOnly
    );
}

echo "Chisimba PHP Moderniser\n";
echo "=======================\n\n";
echo 'Mode: ' . ($applyChanges ? 'apply changes' : 'report only') . "\n";
echo 'Files scanned: ' . count($files) . "\n\n";

$totalMatches = 0;

foreach ($rules as $rule) {
    $matches = scanRule($files, $rule['pattern']);

    echo $rule['id'] . "\n";
    echo str_repeat('-', strlen($rule['id'])) . "\n";
    echo $rule['description'] . "\n";
    echo 'Matches: ' . count($matches) . "\n";

    foreach ($matches as $match) {
        echo sprintf(
            "  %s:%d: %s\n",
            makeRelativePath($match['file'], $workspaceDir),
            $match['line'],
            trim($match['text'])
        );
    }

    echo "\n";
    $totalMatches += count($matches);
}

echo "Summary\n";
echo "-------\n";
echo 'Files scanned: ' . count($files) . "\n";
echo 'Total matches: ' . $totalMatches . "\n";

if ($applyChanges) {
    echo 'Files changed: ' . count($changedFiles) . "\n";

    foreach ($changedFiles as $changedFile) {
        echo '  ' . makeRelativePath($changedFile, $workspaceDir) . "\n";
    }
} else {
    echo "No files were changed.\n";
}

exit(EXIT_SUCCESS);

/**
 * @return string[]
 */
function findSourceFiles(
    array $roots,
    array $allowedExtensions,
    array $excludedDirectoryNames
): array {
    $files = [];

    foreach ($roots as $root) {
        if (!is_dir($root)) {
            fwrite(STDERR, "Source directory not found: {$root}\n");
            continue;
        }

        $directoryIterator = new RecursiveDirectoryIterator(
            $root,
            FilesystemIterator::SKIP_DOTS
        );

        $filterIterator = new RecursiveCallbackFilterIterator(
            $directoryIterator,
            static function (
                SplFileInfo $current,
                string $key,
                RecursiveIterator $iterator
            ) use ($excludedDirectoryNames): bool {
                if ($current->isDir()) {
                    return !in_array(
                        $current->getFilename(),
                        $excludedDirectoryNames,
                        true
                    );
                }

                return true;
            }
        );

        $iterator = new RecursiveIteratorIterator(
            $filterIterator,
            RecursiveIteratorIterator::LEAVES_ONLY
        );

        foreach ($iterator as $fileInfo) {
            if (!$fileInfo instanceof SplFileInfo || !$fileInfo->isFile()) {
                continue;
            }

            $extension = strtolower($fileInfo->getExtension());

            if (!in_array($extension, $allowedExtensions, true)) {
                continue;
            }

            $files[] = $fileInfo->getPathname();
        }
    }

    sort($files);

    return array_values(array_unique($files));
}

/**
 * @return array<int, array{file: string, line: int, text: string}>
 */
function scanRule(array $files, string $pattern): array
{
    $matches = [];

    foreach ($files as $file) {
        $handle = fopen($file, 'rb');

        if ($handle === false) {
            fwrite(STDERR, "Unable to read: {$file}\n");
            continue;
        }

        $lineNumber = 0;

        while (($line = fgets($handle)) !== false) {
            $lineNumber++;

            if (preg_match($pattern, $line) === 1) {
                $matches[] = [
                    'file' => $file,
                    'line' => $lineNumber,
                    'text' => $line,
                ];
            }
        }

        fclose($handle);
    }

    return $matches;
}

function makeRelativePath(string $path, string $workspaceDir): string
{
    $prefix = rtrim($workspaceDir, DIRECTORY_SEPARATOR)
        . DIRECTORY_SEPARATOR;

    if (strpos($path, $prefix) === 0) {
        return substr($path, strlen($prefix));
    }

    return $path;
}

/**
 * Apply narrowly scoped PHP 7.4 compatibility fixes to the curated PEAR tree.
 *
 * @return string[] Files that were changed.
 */
function applyPearCompatibilityFixes(
    array $files,
    string $workspaceDir,
    bool $pearOnly
): array {
    $changedFiles = [];

    $pearRoot = realpath(
        $workspaceDir . '/framework/app/lib/pear'
    );

    if ($pearRoot === false) {
        fwrite(STDERR, "Curated PEAR directory was not found.\n");
        return [];
    }

    $pearPrefix = rtrim($pearRoot, DIRECTORY_SEPARATOR)
        . DIRECTORY_SEPARATOR;

    foreach ($files as $file) {
        $realFile = realpath($file);

        if ($realFile === false) {
            continue;
        }

        if ($pearOnly && strpos($realFile, $pearPrefix) !== 0) {
            continue;
        }

        /*
         * These automated changes are intentionally restricted to the
         * curated PEAR tree. Application and module code is report-only.
         */
        if (strpos($realFile, $pearPrefix) !== 0) {
            continue;
        }

        $original = file_get_contents($realFile);

        if ($original === false) {
            fwrite(STDERR, "Unable to read: {$realFile}\n");
            continue;
        }

        $updated = $original;

        /*
         * Magic Quotes was deprecated in PHP 5.3 and removed in PHP 7.
         *
         * Runtime setting reads become ini_get() calls. Attempts to alter
         * the obsolete directive become suppressed ini_set() calls, which
         * preserve the surrounding control flow without fatal errors.
         */
        $updated = preg_replace(
            '/\bget_magic_quotes_runtime\s*\(\s*\)/',
            "(bool) ini_get('magic_quotes_runtime')",
            $updated
        );

        $updated = preg_replace(
            '/\bget_magic_quotes_gpc\s*\(\s*\)/',
            'false',
            $updated
        );

        $updated = preg_replace(
            '/\bset_magic_quotes_runtime\s*\(\s*([^;\r\n]+?)\s*\)/',
            "@ini_set('magic_quotes_runtime', (string) ($1))",
            $updated
        );

        /*
         * PEAR_Common::_analyzeSourceCode() iterates over PHP tokens.
         * Its switch is inside a for loop. Bare continue historically
         * continued the token loop, so PHP 7.4 requires continue 2.
         *
         * Keep this exact and narrow rather than changing every switch.
         */
        if (
            substr($realFile, -strlen('/PEAR/Common.php'))
            === '/PEAR/Common.php'
        ) {
            $updated = preg_replace(
                '/(case\s+T_WHITESPACE\s*:\s*\R)(\s*)continue\s*;/',
                '$1$2continue 2;',
                $updated
            );
        }

        if ($updated === null) {
            fwrite(STDERR, "A replacement failed for: {$realFile}\n");
            continue;
        }

        if ($updated === $original) {
            continue;
        }

        if (file_put_contents($realFile, $updated) === false) {
            fwrite(STDERR, "Unable to write: {$realFile}\n");
            continue;
        }

        $changedFiles[] = $realFile;
    }

    sort($changedFiles);

    return $changedFiles;
}
