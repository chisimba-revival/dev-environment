#!/usr/bin/env bash
set -euo pipefail

MDB2_COMMIT="96380f6"
MDB2_REPO="https://github.com/imrelaszlo/PEAR-MDB2"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_ENV_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKSPACE_DIR="$(cd "$DEV_ENV_DIR/.." && pwd)"
FRAMEWORK_DIR="$WORKSPACE_DIR/framework"
PEAR_ROOT="$FRAMEWORK_DIR/app/lib/pear"

DOWNLOAD_DIR="$DEV_ENV_DIR/runtime/.mdb2-download"
ARCHIVE="$DOWNLOAD_DIR/mdb2-${MDB2_COMMIT}.tar.gz"
EXTRACT_DIR="$DOWNLOAD_DIR/extracted"
BACKUP_DIR="$DEV_ENV_DIR/runtime/mdb2-backup-pre-${MDB2_COMMIT}"

for path in \
    "$PEAR_ROOT" \
    "$PEAR_ROOT/PEAR.php"
do
    if [[ ! -e "$path" ]]; then
        echo "Required path is missing: $path" >&2
        exit 1
    fi
done

echo "============================================================"
echo "Install coherent PHP 7.4/8-compatible MDB2 stack"
echo "============================================================"
date
echo

rm -rf "$DOWNLOAD_DIR"
mkdir -p "$EXTRACT_DIR"

echo "Downloading pinned MDB2 commit: $MDB2_COMMIT"
curl -fL \
    --retry 3 \
    --connect-timeout 20 \
    --max-time 180 \
    "$MDB2_REPO/archive/$MDB2_COMMIT.tar.gz" \
    -o "$ARCHIVE"

echo
echo "Archive checksum:"
sha256sum "$ARCHIVE"

echo
echo "Extracting..."
tar -xzf "$ARCHIVE" -C "$EXTRACT_DIR"

PACKAGE_ROOT="$(
    find "$EXTRACT_DIR" \
        -mindepth 1 \
        -maxdepth 1 \
        -type d \
        | head -n 1
)"

if [[ -z "${PACKAGE_ROOT:-}" || ! -d "$PACKAGE_ROOT" ]]; then
    echo "Unable to locate extracted MDB2 package root." >&2
    exit 1
fi

echo "Package root:"
echo "  $PACKAGE_ROOT"

for path in \
    "$PACKAGE_ROOT/MDB2.php" \
    "$PACKAGE_ROOT/MDB2" \
    "$PACKAGE_ROOT/MDB2/Driver/mysqli.php"
do
    if [[ ! -e "$path" ]]; then
        echo "Downloaded MDB2 fork is missing: $path" >&2
        exit 1
    fi
done

echo
echo "Fork metadata:"
if [[ -f "$PACKAGE_ROOT/composer.json" ]]; then
    sed -n '1,160p' "$PACKAGE_ROOT/composer.json"
fi

echo
echo "Backing up current MDB2..."
rm -rf "$BACKUP_DIR"
mkdir -p "$BACKUP_DIR"

if [[ -e "$PEAR_ROOT/MDB2.php" ]]; then
    cp -a "$PEAR_ROOT/MDB2.php" "$BACKUP_DIR/MDB2.php"
fi

if [[ -e "$PEAR_ROOT/MDB2" ]]; then
    cp -a "$PEAR_ROOT/MDB2" "$BACKUP_DIR/MDB2"
fi

echo "Backup retained at:"
echo "  $BACKUP_DIR"

echo
echo "Replacing MDB2 atomically..."

STAGING="$PEAR_ROOT/.mdb2-${MDB2_COMMIT}-staging"
rm -rf "$STAGING"
mkdir -p "$STAGING"

cp -a "$PACKAGE_ROOT/MDB2.php" "$STAGING/MDB2.php"
cp -a "$PACKAGE_ROOT/MDB2" "$STAGING/MDB2"

rm -rf "$PEAR_ROOT/MDB2.php" "$PEAR_ROOT/MDB2"

mv "$STAGING/MDB2.php" "$PEAR_ROOT/MDB2.php"
mv "$STAGING/MDB2" "$PEAR_ROOT/MDB2"
rmdir "$STAGING"

echo "MDB2 replacement completed."

echo
echo "Verifying required classes and driver files..."
for path in \
    "$PEAR_ROOT/MDB2.php" \
    "$PEAR_ROOT/MDB2/Driver/mysqli.php" \
    "$PEAR_ROOT/MDB2/Driver/Manager/mysqli.php" \
    "$PEAR_ROOT/MDB2/Driver/Datatype/mysqli.php" \
    "$PEAR_ROOT/MDB2/Driver/Function/mysqli.php" \
    "$PEAR_ROOT/MDB2/Driver/Native/mysqli.php" \
    "$PEAR_ROOT/MDB2/Driver/Reverse/mysqli.php"
do
    if [[ ! -f "$path" ]]; then
        echo "Required MDB2 file is missing: $path" >&2
        exit 1
    fi

    echo "Present: ${path#$WORKSPACE_DIR/}"
done

echo
echo "Checking for PHP 8 compatibility attributes..."
grep -Rni \
    'AllowDynamicProperties' \
    "$PEAR_ROOT/MDB2.php" \
    "$PEAR_ROOT/MDB2/Driver/mysqli.php" \
    2>/dev/null || true

echo
echo "Host syntax checks..."
php -l "$PEAR_ROOT/MDB2.php"
php -l "$PEAR_ROOT/MDB2/Driver/mysqli.php"

echo
echo "Framework Git status:"
git -C "$FRAMEWORK_DIR" status --short -- \
    app/lib/pear/PEAR.php \
    app/lib/pear/PEAR \
    app/lib/pear/System.php \
    app/lib/pear/OS \
    app/lib/pear/MDB2.php \
    app/lib/pear/MDB2

echo
echo "Pinned source:"
echo "  $MDB2_REPO"
echo "  commit $MDB2_COMMIT"

echo
echo "MDB2 replacement completed successfully."
echo "The runtime must now be rebuilt before browser testing."
