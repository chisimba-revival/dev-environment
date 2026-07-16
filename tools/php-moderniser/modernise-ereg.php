<?php
declare(strict_types=1);

/**
 * Convert removed POSIX regex functions to PCRE equivalents.
 *
 * Only real PHP function calls are transformed. Calls mentioned inside
 * comments, documentation, or string literals are ignored because the
 * source is inspected with token_get_all().
 *
 * Safely handles calls whose first argument is a quoted literal:
 *
 *   ereg('pattern', $value)          -> preg_match('~pattern~', $value)
 *   eregi('pattern', $value)         -> preg_match('~pattern~i', $value)
 *   ereg_replace('pattern', ...)     -> preg_replace('~pattern~', ...)
 *   eregi_replace('pattern', ...)    -> preg_replace('~pattern~i', ...)
 *
 * Dynamic patterns are reported but deliberately not changed.
 */

$workspace = realpath(__DIR__ . '/../../..');

if ($workspace === false) {
    fwrite(STDERR, "Unable to resolve workspace.\n");
    exit(1);
}

$arguments = $argv;
array_shift($arguments);

$backupDir = getenv('CHISIMBA_MODERNISER_BACKUP_DIR') ?: '';

if (($arguments[0] ?? null) === '--backup-dir') {
    array_shift($arguments);
    $backupDir = (string) (array_shift($arguments) ?? '');
}

if ($arguments !== []) {
    fwrite(STDERR, "Unexpected argument: {$arguments[0]}\n");
    exit(1);
}

if ($backupDir === '') {
    fwrite(
        STDERR,
        "A backup directory is required. Use --backup-dir PATH or " .
        "CHISIMBA_MODERNISER_BACKUP_DIR.\n"
    );
    exit(1);
}

if (!is_dir($backupDir) && !mkdir($backupDir, 0775, true)) {
    fwrite(STDERR, "Unable to create backup directory: {$backupDir}\n");
    exit(1);
}

$backupDir = realpath($backupDir);

if ($backupDir === false) {
    fwrite(STDERR, "Unable to resolve backup directory.\n");
    exit(1);
}

$originalsDir = $backupDir . '/originals';
$failedDir = $backupDir . '/failed';
$manifestFile = $backupDir . '/manifest.tsv';

foreach ([$originalsDir, $failedDir] as $directory) {
    if (!is_dir($directory) && !mkdir($directory, 0775, true)) {
        fwrite(STDERR, "Unable to create directory: {$directory}\n");
        exit(1);
    }
}

$roots = [
    $workspace . '/framework/app',
    $workspace . '/modules',
    $workspace . '/canvases',
];

$changed = [];
$manual = [];
$syntaxFailures = [];

function workspaceRelativePath(string $file, string $workspace): string
{
    $prefix = rtrim($workspace, DIRECTORY_SEPARATOR) . DIRECTORY_SEPARATOR;

    if (strpos($file, $prefix) !== 0) {
        throw new RuntimeException(
            "Source path is outside the workspace: {$file}"
        );
    }

    return substr($file, strlen($prefix));
}

function backupDestination(
    string $baseDirectory,
    string $file,
    string $workspace
): string {
    return rtrim($baseDirectory, DIRECTORY_SEPARATOR)
        . DIRECTORY_SEPARATOR
        . workspaceRelativePath($file, $workspace);
}

function preserveFile(
    string $source,
    string $destination,
    string $manifestFile,
    string $kind
): void {
    if (file_exists($destination)) {
        return;
    }

    $directory = dirname($destination);

    if (!is_dir($directory) && !mkdir($directory, 0775, true)) {
        throw new RuntimeException(
            "Unable to create backup directory: {$directory}"
        );
    }

    if (!copy($source, $destination)) {
        throw new RuntimeException(
            "Unable to preserve {$kind}: {$source}"
        );
    }

    $entry = $kind . "\t" . $source . "\t" . $destination . "\n";

    if (file_put_contents($manifestFile, $entry, FILE_APPEND) === false) {
        throw new RuntimeException(
            "Unable to update manifest: {$manifestFile}"
        );
    }
}

function phpFiles(array $roots): Generator
{
    foreach ($roots as $root) {
        if (!is_dir($root)) {
            continue;
        }

        $iterator = new RecursiveIteratorIterator(
            new RecursiveDirectoryIterator(
                $root,
                FilesystemIterator::SKIP_DOTS
            )
        );

        foreach ($iterator as $file) {
            if (!$file->isFile()) {
                continue;
            }

            $name = $file->getFilename();

            if (
                substr($name, -4) === '.php'
                || substr($name, -8) === '.php.inc'
                || substr($name, -14) === '_class_inc.php'
                || $name === 'controller.php'
            ) {
                yield $file->getPathname();
            }
        }
    }
}

function delimiterFor(string $pattern): string
{
    foreach (['~', '#', '%', '!'] as $candidate) {
        if (strpos($pattern, $candidate) === false) {
            return $candidate;
        }
    }

    return '~';
}

function tokenText($token): string
{
    return is_array($token) ? $token[1] : $token;
}

function isIgnorableToken($token): bool
{
    return is_array($token)
        && in_array(
            $token[0],
            [T_WHITESPACE, T_COMMENT, T_DOC_COMMENT],
            true
        );
}

function nextMeaningfulTokenIndex(array $tokens, int $start): ?int
{
    $count = count($tokens);

    for ($index = $start; $index < $count; $index++) {
        if (!isIgnorableToken($tokens[$index])) {
            return $index;
        }
    }

    return null;
}

function lineForToken(array $tokens, int $targetIndex): int
{
    $line = 1;

    for ($index = 0; $index < $targetIndex; $index++) {
        $line += substr_count(tokenText($tokens[$index]), "\n");
    }

    return $line;
}

/**
 * Transform genuine function calls found by PHP's tokenizer.
 *
 * @return array{0:string,1:int,2:array<int,string>}
 */
function transformLiteralCalls(string $text, string $file): array
{
    $tokens = token_get_all($text);
    $changedCount = 0;
    $manualEntries = [];

    $supported = [
        'ereg' => ['preg_match', ''],
        'eregi' => ['preg_match', 'i'],
        'ereg_replace' => ['preg_replace', ''],
        'eregi_replace' => ['preg_replace', 'i'],
    ];

    $count = count($tokens);

    for ($index = 0; $index < $count; $index++) {
        $token = $tokens[$index];

        if (!is_array($token) || $token[0] !== T_STRING) {
            continue;
        }

        $function = strtolower($token[1]);

        if (!isset($supported[$function])) {
            continue;
        }

        /*
         * Do not treat object/static method calls as global functions.
         */
        $previousIndex = $index - 1;

        while (
            $previousIndex >= 0
            && isIgnorableToken($tokens[$previousIndex])
        ) {
            $previousIndex--;
        }

        if ($previousIndex >= 0) {
            $previous = $tokens[$previousIndex];

            if (
                $previous === '->'
                || $previous === '::'
                || (
                    is_array($previous)
                    && in_array(
                        $previous[0],
                        [T_OBJECT_OPERATOR, T_DOUBLE_COLON],
                        true
                    )
                )
            ) {
                continue;
            }
        }

        $openIndex = nextMeaningfulTokenIndex($tokens, $index + 1);

        if ($openIndex === null || tokenText($tokens[$openIndex]) !== '(') {
            continue;
        }

        $patternIndex = nextMeaningfulTokenIndex($tokens, $openIndex + 1);

        if (
            $patternIndex === null
            || !is_array($tokens[$patternIndex])
            || $tokens[$patternIndex][0] !== T_CONSTANT_ENCAPSED_STRING
        ) {
            $line = lineForToken($tokens, $index);
            $manualEntries[] = "{$file}:{$line}: {$token[1]}(";
            continue;
        }

        $commaIndex = nextMeaningfulTokenIndex($tokens, $patternIndex + 1);

        if ($commaIndex === null || tokenText($tokens[$commaIndex]) !== ',') {
            $line = lineForToken($tokens, $index);
            $manualEntries[] = "{$file}:{$line}: {$token[1]}(";
            continue;
        }

        $literal = $tokens[$patternIndex][1];
        $quote = $literal[0];

        if (
            ($quote !== "'" && $quote !== '"')
            || substr($literal, -1) !== $quote
        ) {
            $line = lineForToken($tokens, $index);
            $manualEntries[] = "{$file}:{$line}: {$token[1]}(";
            continue;
        }

        $pattern = substr($literal, 1, -1);
        $delimiter = delimiterFor($pattern);

        /*
         * delimiterFor() normally selects a delimiter not present in the
         * pattern. If every preferred delimiter is present, escape "~".
         */
        if (strpos($pattern, $delimiter) !== false) {
            $pattern = str_replace(
                $delimiter,
                '\\' . $delimiter,
                $pattern
            );
        }

        [$replacementFunction, $modifier] = $supported[$function];

        $tokens[$index][1] = $replacementFunction;
        $tokens[$patternIndex][1] = $quote
            . $delimiter
            . $pattern
            . $delimiter
            . $modifier
            . $quote;

        $changedCount++;
    }

    $updated = '';

    foreach ($tokens as $token) {
        $updated .= tokenText($token);
    }

    return [$updated, $changedCount, $manualEntries];
}

foreach (phpFiles($roots) as $file) {
    $original = file_get_contents($file);

    if ($original === false) {
        fwrite(STDERR, "Unable to read: {$file}\n");
        continue;
    }

    if (!preg_match('/\beregi?(?:_replace)?\s*\(/i', $original)) {
        continue;
    }

    [$updated, $count, $fileManual] = transformLiteralCalls(
        $original,
        $file
    );

    foreach ($fileManual as $entry) {
        $manual[] = $entry;
    }

    if ($count === 0 || $updated === $original) {
        continue;
    }

    try {
        $backup = backupDestination($originalsDir, $file, $workspace);
        preserveFile(
            $file,
            $backup,
            $manifestFile,
            'ORIGINAL'
        );
    } catch (Throwable $error) {
        fwrite(STDERR, "Backup failure: {$error->getMessage()}\n");
        exit(1);
    }

    if (file_put_contents($file, $updated) === false) {
        fwrite(STDERR, "Unable to write: {$file}\n");
        exit(1);
    }

    $changed[] = $file;
}

foreach ($changed as $file) {
    /*
     * exec() appends to an existing output array, so reset it for every
     * file. Without this, every later failure repeats all earlier results.
     */
    $output = [];
    $status = 0;

    $command = 'php -l ' . escapeshellarg($file) . ' 2>&1';
    exec($command, $output, $status);

    if ($status !== 0) {
        $syntaxFailures[$file] = implode("\n", $output);
    }
}

if ($syntaxFailures !== []) {
    fwrite(STDERR, "Syntax failures after transformation:\n");

    foreach ($syntaxFailures as $file => $message) {
        fwrite(STDERR, "\n{$file}\n{$message}\n");

        $failedCopy = backupDestination(
            $failedDir,
            $file,
            $workspace
        );
        $backup = backupDestination(
            $originalsDir,
            $file,
            $workspace
        );

        /*
         * Preserve the rejected transformed file externally before
         * restoring the known-good source.
         */
        try {
            preserveFile(
                $file,
                $failedCopy,
                $manifestFile,
                'FAILED'
            );
            fwrite(
                STDERR,
                "Preserved failed output: {$failedCopy}\n"
            );
        } catch (Throwable $error) {
            fwrite(
                STDERR,
                "Unable to preserve failed output: " .
                $error->getMessage() . "\n"
            );
        }

        if (!file_exists($backup)) {
            fwrite(
                STDERR,
                "Original backup is missing; cannot restore: {$backup}\n"
            );
            continue;
        }

        if (!copy($backup, $file)) {
            fwrite(STDERR, "Unable to restore backup: {$file}\n");
        } else {
            fwrite(STDERR, "Restored backup for {$file}\n");
        }
    }

    exit(1);
}

sort($changed);
sort($manual);

echo "POSIX regular-expression modernisation\n";
echo "Changed files: " . count($changed) . "\n";

foreach ($changed as $file) {
    echo "CHANGED: {$file}\n";
}

echo "\nCalls requiring manual review: " . count($manual) . "\n";

foreach ($manual as $entry) {
    echo "MANUAL: {$entry}\n";
}

exit(0);
