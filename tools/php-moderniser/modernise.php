#!/usr/bin/env php
<?php

declare(strict_types=1);

/**
 * Chisimba PHP Moderniser
 *
 * Initially operates in report-only mode. Each compatibility rule reports
 * matching source locations without changing files.
 */

const EXIT_SUCCESS = 0;
const EXIT_FAILURE = 1;

$workspaceDir = dirname(__DIR__, 3);

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

echo "Chisimba PHP Moderniser\n";
echo "=======================\n\n";
echo "Mode: report only\n";
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
echo "No files were changed.\n";

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
