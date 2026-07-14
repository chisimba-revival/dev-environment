#!/usr/bin/env bash
set -euo pipefail

PEAR_VERSION="1.10.18"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_ENV_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKSPACE_DIR="$(cd "$DEV_ENV_DIR/.." && pwd)"
FRAMEWORK_DIR="$WORKSPACE_DIR/framework"
PEAR_ROOT="$FRAMEWORK_DIR/app/lib/pear"

DOWNLOAD_DIR="$DEV_ENV_DIR/runtime/.pear-core-download"
BACKUP_DIR="$DEV_ENV_DIR/runtime/pear-core-backup-pre-${PEAR_VERSION}"
ARCHIVE="$DOWNLOAD_DIR/PEAR-${PEAR_VERSION}.tgz"
EXTRACT_DIR="$DOWNLOAD_DIR/extracted"

COMPOSE_FILE="$DEV_ENV_DIR/compose/php74.yml"

required_paths=(
    "$PEAR_ROOT"
    "$PEAR_ROOT/MDB2.php"
    "$PEAR_ROOT/MDB2"
    "$COMPOSE_FILE"
)

for path in "${required_paths[@]}"; do
    if [[ ! -e "$path" ]]; then
        echo "Required path is missing: $path" >&2
        exit 1
    fi
done

echo "============================================================"
echo "Replace hybrid PEAR core with PEAR ${PEAR_VERSION}"
echo "============================================================"
date
echo

echo "Framework PEAR root:"
echo "  $PEAR_ROOT"
echo

rm -rf "$DOWNLOAD_DIR"
mkdir -p "$EXTRACT_DIR"

echo "Downloading official PEAR ${PEAR_VERSION} package..."
curl -fL \
    --retry 3 \
    --connect-timeout 20 \
    --max-time 180 \
    "https://pear.php.net/get/PEAR-${PEAR_VERSION}.tgz" \
    -o "$ARCHIVE"

echo
echo "Archive checksum:"
sha256sum "$ARCHIVE"

echo
echo "Extracting package..."
tar -xzf "$ARCHIVE" -C "$EXTRACT_DIR"

PACKAGE_ROOT="$EXTRACT_DIR/PEAR-${PEAR_VERSION}"

if [[ ! -d "$PACKAGE_ROOT" ]]; then
    PACKAGE_ROOT="$(
        find "$EXTRACT_DIR" \
            -mindepth 1 \
            -maxdepth 1 \
            -type d \
            | head -n 1
    )"
fi

if [[ -z "${PACKAGE_ROOT:-}" || ! -d "$PACKAGE_ROOT" ]]; then
    echo "Unable to locate extracted PEAR package root." >&2
    exit 1
fi

echo "Extracted package root:"
echo "  $PACKAGE_ROOT"

required_package_files=(
    "$PACKAGE_ROOT/PEAR.php"
    "$PACKAGE_ROOT/PEAR"
    "$PACKAGE_ROOT/System.php"
)

for path in "${required_package_files[@]}"; do
    if [[ ! -e "$path" ]]; then
        echo "Official package is missing expected path: $path" >&2
        exit 1
    fi
done

echo
echo "Validating official PEAR version marker..."
if ! grep -q "Release: ${PEAR_VERSION}" "$PACKAGE_ROOT/PEAR.php"; then
    echo "Downloaded PEAR.php does not identify as ${PEAR_VERSION}." >&2
    exit 1
fi

echo "Validated PEAR.php release marker."

echo
echo "Preparing backup..."
rm -rf "$BACKUP_DIR"
mkdir -p "$BACKUP_DIR"

for relative_path in PEAR.php PEAR System.php OS; do
    source_path="$PEAR_ROOT/$relative_path"

    if [[ -e "$source_path" ]]; then
        mkdir -p "$(dirname "$BACKUP_DIR/$relative_path")"
        cp -a "$source_path" "$BACKUP_DIR/$relative_path"
        echo "Backed up: $relative_path"
    fi
done

echo
echo "Replacing PEAR core atomically..."

STAGING_DIR="$PEAR_ROOT/.pear-core-${PEAR_VERSION}-staging"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

cp -a "$PACKAGE_ROOT/PEAR.php" "$STAGING_DIR/PEAR.php"
cp -a "$PACKAGE_ROOT/PEAR" "$STAGING_DIR/PEAR"
cp -a "$PACKAGE_ROOT/System.php" "$STAGING_DIR/System.php"

if [[ -d "$PACKAGE_ROOT/OS" ]]; then
    cp -a "$PACKAGE_ROOT/OS" "$STAGING_DIR/OS"
fi

rm -rf \
    "$PEAR_ROOT/PEAR.php" \
    "$PEAR_ROOT/PEAR" \
    "$PEAR_ROOT/System.php" \
    "$PEAR_ROOT/OS"

mv "$STAGING_DIR/PEAR.php" "$PEAR_ROOT/PEAR.php"
mv "$STAGING_DIR/PEAR" "$PEAR_ROOT/PEAR"
mv "$STAGING_DIR/System.php" "$PEAR_ROOT/System.php"

if [[ -d "$STAGING_DIR/OS" ]]; then
    mv "$STAGING_DIR/OS" "$PEAR_ROOT/OS"
fi

rmdir "$STAGING_DIR"

echo "PEAR core replacement completed."

echo
echo "Confirming MDB2 was preserved..."
for path in \
    "$PEAR_ROOT/MDB2.php" \
    "$PEAR_ROOT/MDB2/Driver/mysqli.php"
do
    if [[ ! -f "$path" ]]; then
        echo "MDB2 preservation check failed: $path" >&2
        exit 1
    fi
    echo "Preserved: ${path#$WORKSPACE_DIR/}"
done

echo
echo "Checking PEAR public compatibility API..."
php_api_check="$(
    grep -nE \
        'function[[:space:]]+setErrorHandling[[:space:]]*\(' \
        "$PEAR_ROOT/PEAR.php" \
        || true
)"

if [[ -z "$php_api_check" ]]; then
    echo "Official PEAR.php does not expose setErrorHandling()." >&2
    exit 1
fi

echo "$php_api_check"

echo
echo "PHP 7.4 syntax checks in container..."
docker compose \
    -f "$COMPOSE_FILE" \
    up -d --no-deps web >/dev/null

for relative_path in \
    PEAR.php \
    System.php \
    MDB2.php \
    MDB2/Driver/mysqli.php
do
    docker compose \
        -f "$COMPOSE_FILE" \
        exec -T -w / web \
        php -l "/var/www/html/ch/lib/pear/$relative_path"
done

echo
echo "Direct PEAR/MDB2 compatibility test..."
docker compose \
    -f "$COMPOSE_FILE" \
    exec -T -w / web \
    php -d display_errors=1 -r '
        set_include_path(
            "/var/www/html/ch/lib/pear"
            . PATH_SEPARATOR
            . get_include_path()
        );

        require_once "PEAR.php";
        require_once "MDB2.php";
        require_once "MDB2/Driver/mysqli.php";

        $checks = array(
            "PEAR" => class_exists("PEAR"),
            "PEAR::setErrorHandling" => method_exists("PEAR", "setErrorHandling"),
            "MDB2" => class_exists("MDB2"),
            "MDB2_Driver_Common" => class_exists("MDB2_Driver_Common"),
            "MDB2_Driver_mysqli" => class_exists("MDB2_Driver_mysqli"),
            "mysqli inherited setErrorHandling" =>
                method_exists("MDB2_Driver_mysqli", "setErrorHandling"),
        );

        foreach ($checks as $label => $result) {
            echo $label . ": " . ($result ? "OK" : "FAILED") . PHP_EOL;

            if (!$result) {
                exit(1);
            }
        }

        $db = new MDB2_Driver_mysqli();

        echo "MDB2_Driver_mysqli instantiation: "
            . (is_object($db) ? "OK" : "FAILED")
            . PHP_EOL;
    '

echo
echo "Git status after replacement:"
git -C "$FRAMEWORK_DIR" status --short -- app/lib/pear

echo
echo "Backup retained at:"
echo "  $BACKUP_DIR"

echo
echo "PEAR ${PEAR_VERSION} replacement and compatibility checks completed."
