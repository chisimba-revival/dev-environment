<?php
if ($argc !== 3) {
    fwrite(
        STDERR,
        "Usage: php compare-auth-snapshots.php LEGACY.json NATIVE.json\n"
    );
    exit(2);
}

function loadSnapshot($path)
{
    if (!is_file($path)) {
        throw new RuntimeException('Snapshot not found: ' . $path);
    }

    $decoded = json_decode(file_get_contents($path), true);
    if (!is_array($decoded)) {
        throw new RuntimeException('Invalid JSON snapshot: ' . $path);
    }

    return $decoded;
}

function canonicalise($value)
{
    if (!is_array($value)) {
        return $value;
    }

    $isList = array_keys($value) === range(0, count($value) - 1);
    if ($isList) {
        $normalised = array();
        foreach ($value as $item) {
            $normalised[] = canonicalise($item);
        }
        usort($normalised, function ($left, $right) {
            return strcmp(json_encode($left), json_encode($right));
        });
        return $normalised;
    }

    ksort($value);
    foreach ($value as $key => $item) {
        $value[$key] = canonicalise($item);
    }
    return $value;
}

try {
    $legacy = canonicalise(loadSnapshot($argv[1]));
    $native = canonicalise(loadSnapshot($argv[2]));
} catch (Exception $exception) {
    fwrite(STDERR, $exception->getMessage() . PHP_EOL);
    exit(2);
}

if ($legacy === $native) {
    echo "MATCH: legacy and native snapshots are equivalent." . PHP_EOL;
    exit(0);
}

echo "MISMATCH: legacy and native snapshots differ." . PHP_EOL;
echo "--- LEGACY ---" . PHP_EOL;
echo json_encode($legacy, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . PHP_EOL;
echo "--- NATIVE ---" . PHP_EOL;
echo json_encode($native, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . PHP_EOL;
exit(1);
