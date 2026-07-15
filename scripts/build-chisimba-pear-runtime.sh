#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_ENV_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKSPACE_DIR="$(cd "$DEV_ENV_DIR/.." && pwd)"

MANIFEST="$DEV_ENV_DIR/dependencies/pear-packages.tsv"
PACK_ROOT="$DEV_ENV_DIR/dependencies/chisimba-pear-runtime"
STAGING_ROOT="$DEV_ENV_DIR/runtime/.chisimba-pear-runtime-staging"
DOWNLOAD_ROOT="$DEV_ENV_DIR/runtime/.chisimba-pear-downloads"
BACKUP_ROOT="$DEV_ENV_DIR/runtime/chisimba-pear-runtime-backup"
TARGET_ROOT="$WORKSPACE_DIR/framework/app/lib/pear"

if [[ ! -f "$MANIFEST" ]]; then
    echo "Missing manifest: $MANIFEST" >&2
    exit 1
fi

require_path() {
    local path="$1"

    if [[ ! -e "$path" ]]; then
        echo "Required component is missing: $path" >&2
        exit 1
    fi
}

download_and_extract() {
    local id="$1"
    local version="$2"
    local url="$3"
    local archive="$DOWNLOAD_ROOT/${id}-${version}.tgz"
    local extract_dir="$DOWNLOAD_ROOT/extracted/${id}"

    echo
    echo "Downloading $id $version"
    echo "Source: $url"

    rm -rf "$extract_dir"
    mkdir -p "$extract_dir"

    curl -fL \
        --retry 3 \
        --connect-timeout 20 \
        --max-time 180 \
        "$url" \
        -o "$archive"

    echo "Downloaded checksum:"
    sha256sum "$archive"

    tar -xzf "$archive" -C "$extract_dir"

    DOWNLOADED_ROOT="$(
        find "$extract_dir" \
            -mindepth 1 \
            -maxdepth 1 \
            -type d \
            -print \
            | head -n 1
    )"

    if [[ -z "$DOWNLOADED_ROOT" || ! -d "$DOWNLOADED_ROOT" ]]; then
        echo "Could not identify extracted package root for $id." >&2
        exit 1
    fi

    echo "Extracted root: $DOWNLOADED_ROOT"
}

echo "============================================================"
echo "Build Chisimba curated PEAR compatibility pack"
echo "============================================================"
date

rm -rf "$STAGING_ROOT" "$DOWNLOAD_ROOT"
mkdir -p "$STAGING_ROOT" "$DOWNLOAD_ROOT/extracted"

while IFS='|' read -r id version source_type source status purpose; do
    id="${id//$'\r'/}"
    version="${version//$'\r'/}"
    source="${source//$'\r'/}"

    if [[ -z "$id" || "$id" == "id" ]]; then
        continue
    fi

    if [[ -z "$version" || -z "$source" ]]; then
        echo "Invalid manifest row for package: $id" >&2
        exit 1
    fi

    download_and_extract "$id" "$version" "$source"
    root="$DOWNLOADED_ROOT"

    echo "Installing $id $version into staging."

    case "$id" in
        PEAR)
            require_path "$root/PEAR.php"
            require_path "$root/PEAR"
            require_path "$root/System.php"

            cp -a "$root/PEAR.php" "$STAGING_ROOT/"
            cp -a "$root/PEAR" "$STAGING_ROOT/"
            cp -a "$root/System.php" "$STAGING_ROOT/"

            if [[ -d "$root/OS" ]]; then
                cp -a "$root/OS" "$STAGING_ROOT/"
            fi
            ;;

        MDB2)
            require_path "$root/MDB2.php"
            require_path "$root/MDB2"
            require_path "$root/MDB2/Date.php"
            require_path "$root/MDB2/Driver/mysqli.php"

            cp -a "$root/MDB2.php" "$STAGING_ROOT/"
            cp -a "$root/MDB2" "$STAGING_ROOT/"
            ;;

        MDB2_Schema)
            require_path "$root/MDB2/Schema.php"
            require_path "$root/MDB2/Schema"

            mkdir -p "$STAGING_ROOT/MDB2"
            cp -a "$root/MDB2/Schema.php" "$STAGING_ROOT/MDB2/"
            rm -rf "$STAGING_ROOT/MDB2/Schema"
            cp -a "$root/MDB2/Schema" "$STAGING_ROOT/MDB2/"
            ;;

        XML_Parser)
            require_path "$root/XML/Parser.php"

            mkdir -p "$STAGING_ROOT/XML"
            cp -a "$root/XML/Parser.php" "$STAGING_ROOT/XML/"

            if [[ -d "$root/XML/Parser" ]]; then
                rm -rf "$STAGING_ROOT/XML/Parser"
                cp -a "$root/XML/Parser" "$STAGING_ROOT/XML/"
            fi
            ;;

        XML_Util)
            require_path "$root/XML/Util.php"

            mkdir -p "$STAGING_ROOT/XML"
            cp -a "$root/XML/Util.php" "$STAGING_ROOT/XML/"
            ;;

        XML_Serializer)
            require_path "$root/XML/Serializer.php"
            require_path "$root/XML/Unserializer.php"

            mkdir -p "$STAGING_ROOT/XML"
            cp -a "$root/XML/Serializer.php" "$STAGING_ROOT/XML/"
            cp -a "$root/XML/Unserializer.php" "$STAGING_ROOT/XML/"
            ;;

        Calendar)
            require_path "$root/Calendar.php"
            require_path "$root/Day.php"
            require_path "$root/Decorator"
            require_path "$root/Engine"
            require_path "$root/Month"
            require_path "$root/Table"
            require_path "$root/Util"

            cp -a "$root/Calendar.php" "$STAGING_ROOT/"

            rm -rf "$STAGING_ROOT/Calendar"
            mkdir -p "$STAGING_ROOT/Calendar"

            find "$root"                 -mindepth 1                 -maxdepth 1                 \( -type f -o -type d \)                 ! -name 'Calendar.php'                 ! -name 'docs'                 ! -name 'tests'                 ! -name 'package.xml'                 -exec cp -a {} "$STAGING_ROOT/Calendar/" \;
            ;;

        XML_RPC)
            require_path "$root/XML/RPC.php"
            require_path "$root/XML/RPC/Server.php"
            require_path "$root/XML/RPC/Dump.php"

            mkdir -p "$STAGING_ROOT/XML"
            cp -a "$root/XML/RPC.php" "$STAGING_ROOT/XML/"
            rm -rf "$STAGING_ROOT/XML/RPC"
            cp -a "$root/XML/RPC" "$STAGING_ROOT/XML/"
            ;;

        *)
            echo "No installation rule exists for package: $id" >&2
            exit 1
            ;;
    esac

done < "$MANIFEST"

cat > "$STAGING_ROOT/CHISIMBA_DEPENDENCY_MANIFEST.txt" <<EOF
Chisimba curated PEAR compatibility pack

Generated from:
$MANIFEST

Packages:
$(tail -n +2 "$MANIFEST" | cut -d '|' -f1,2,5 | tr '|' ' ')
EOF

required_files=(
    "PEAR.php"
    "System.php"
    "MDB2.php"
    "MDB2/Date.php"
    "MDB2/Schema.php"
    "MDB2/Driver/mysqli.php"
    "XML/Parser.php"
    "XML/Util.php"
    "XML/Serializer.php"
    "XML/Unserializer.php"
    "Calendar.php"
    "XML/RPC.php"
    "XML/RPC/Server.php"
    "XML/RPC/Dump.php"
)

echo
echo "Validating staged files..."

for path in "${required_files[@]}"; do
    require_path "$STAGING_ROOT/$path"
    echo "Present: $path"
done

echo
echo "Replacing canonical compatibility pack..."

rm -rf "$PACK_ROOT"
mkdir -p "$(dirname "$PACK_ROOT")"
mv "$STAGING_ROOT" "$PACK_ROOT"

echo
echo "Backing up current framework PEAR tree..."

rm -rf "$BACKUP_ROOT"
mkdir -p "$BACKUP_ROOT"
cp -a "$TARGET_ROOT/." "$BACKUP_ROOT/"

echo
echo "Installing curated pack into framework source..."

rm -rf \
    "$TARGET_ROOT/PEAR.php" \
    "$TARGET_ROOT/PEAR" \
    "$TARGET_ROOT/System.php" \
    "$TARGET_ROOT/OS" \
    "$TARGET_ROOT/MDB2.php" \
    "$TARGET_ROOT/MDB2" \
    "$TARGET_ROOT/Calendar.php" \
    "$TARGET_ROOT/Calendar" \
    "$TARGET_ROOT/XML"

cp -a "$PACK_ROOT/." "$TARGET_ROOT/"

echo
echo "Framework dependency files installed."

for path in "${required_files[@]}"; do
    require_path "$TARGET_ROOT/$path"
    echo "Installed: $path"
done

echo
echo "Dependency manifest:"
cat "$TARGET_ROOT/CHISIMBA_DEPENDENCY_MANIFEST.txt"

echo
echo "Curated PEAR pack built and installed successfully."
