#!/usr/bin/env bash
set -euo pipefail

WORKSPACE="/run/media/derek/main/chisimba-revival"
DEV="$WORKSPACE/dev-environment"
DEPENDENCIES="$DEV/dependencies"
BUILDER="$DEV/scripts/build-chisimba-pear-runtime.sh"

mkdir -p "$DEPENDENCIES"

cat > "$DEPENDENCIES/pear-packages.tsv" <<'EOF'
idversionsource_typesourcestatuspurpose
PEAR1.10.18pear_tgzhttps://pear.php.net/get/PEAR-1.10.18.tgzcurrentPEAR core runtime
MDB296380f6github_tarhttps://github.com/imrelaszlo/PEAR-MDB2/archive/96380f6.tar.gzpinned-forkPHP 7.4 and PHP 8 compatible Chisimba database API
MDB2_Schemae9cc352github_tarhttps://github.com/pear/MDB2_Schema/archive/e9cc352.tar.gzpinnedMDB2 schema and installer support
XML_Parser1.3.8pear_tgzhttps://pear.php.net/get/XML_Parser-1.3.8.tgzcurrentXML parser required by MDB2_Schema
XML_Util1.4.5pear_tgzhttps://pear.php.net/get/XML_Util-1.4.5.tgzcurrentXML utility API required by PEAR and Chisimba
Calendar0.5.5pear_tgzhttps://pear.php.net/get/Calendar-0.5.5.tgzlegacy-compatibleChisimba calendar API
XML_RPC1.5.5pear_tgzhttps://pear.php.net/get/XML_RPC-1.5.5.tgzlegacy-compatibleXML_RPC API required by Chisimba RPC modules
EOF

cat > "$DEPENDENCIES/PEAR_DEPENDENCIES.md" <<'EOF'
# Chisimba PEAR Dependency Register

This file is the human-readable bill of materials for the curated Chisimba
PEAR runtime.

The machine-readable source of truth is:

`pear-packages.tsv`

The dependency builder must obtain these packages from their recorded upstream
sources. Files must not be copied from an old assembled runtime.

## Current dependency set

| Package | Version or commit | Status | Purpose |
|---|---:|---|---|
| PEAR | 1.10.18 | Current | PEAR core runtime |
| MDB2 | commit `96380f6` | Pinned maintained fork | Chisimba database API with PHP 7.4/PHP 8 compatibility |
| MDB2_Schema | commit `e9cc352` | Pinned | Database schema and installer support |
| XML_Parser | 1.3.8 | Current compatible release | Required by MDB2_Schema |
| XML_Util | 1.4.5 | Current compatible release | Required by PEAR and Chisimba XML code |
| Calendar | 0.5.5 | Legacy-compatible | Preserves the Calendar API used by Chisimba |
| XML_RPC | 1.5.5 | Legacy-compatible | Preserves XML_RPC classes and file paths used throughout Chisimba |

## Required XML_RPC interface

Chisimba currently requires these files:

- `XML/RPC.php`
- `XML/RPC/Server.php`
- `XML/RPC/Dump.php`

It also uses these classes:

- `XML_RPC_Value`
- `XML_RPC_Message`
- `XML_RPC_Client`
- `XML_RPC_Response`
- `XML_RPC_Server`

XML_RPC2 is not a drop-in replacement for this API.

## Dependency policy

1. Use the latest compatible release of the same API where possible.
2. Use a maintained fork when the original package cannot support the target PHP version.
3. Record every pinned commit and downloaded package.
4. Never populate the curated tree from an old assembled runtime.
5. Run syntax and class-load checks after building.
6. Record obsolete or unmaintained dependencies in `PEAR_OLDER_LIST.md`.
7. Add newly discovered dependencies to the manifest before adding them to the runtime.

## Completeness

This register describes the dependencies currently incorporated into the
manifest-driven builder. When another required PEAR package is discovered, it
must be added to both `pear-packages.tsv` and this document before the runtime
is rebuilt.
EOF

cat > "$DEPENDENCIES/PEAR_OLDER_LIST.md" <<'EOF'
# Older PEAR Dependencies Retained by Chisimba

This register records dependencies that are retained because Chisimba still
uses their historical API.

These packages are not copied from a legacy runtime. They are downloaded from
their recorded upstream package source and included reproducibly by the
dependency builder.

## XML_RPC

- **Package:** `XML_RPC`
- **Version:** `1.5.5`
- **Status:** Legacy-compatible; unmaintained API
- **Why retained:** Chisimba directly requires the original XML_RPC classes and file layout.
- **Required files:**
  - `XML/RPC.php`
  - `XML/RPC/Server.php`
  - `XML/RPC/Dump.php`
- **Required classes:**
  - `XML_RPC_Value`
  - `XML_RPC_Message`
  - `XML_RPC_Client`
  - `XML_RPC_Response`
  - `XML_RPC_Server`
- **Known Chisimba users:**
  - `core_modules/packages/classes/rpcserver_class_inc.php`
  - `core_modules/api/classes/xmlrpcapi_class_inc.php`
  - XML-RPC clients and filters throughout the framework
- **Current compatibility treatment:** Syntax checking and narrowly scoped PEAR modernisation for PHP 7.4.
- **Future replacement:** Replace the Chisimba XML-RPC layer with a maintained XML-RPC implementation or a modern HTTP/JSON API while preserving required integration behaviour.
- **Removal condition:** Remove only after all Chisimba references to the original XML_RPC API have been migrated and integration-tested.

## Calendar

- **Package:** `Calendar`
- **Version:** `0.5.5`
- **Status:** Legacy-compatible
- **Why retained:** Chisimba code expects the original PEAR Calendar API.
- **Current compatibility treatment:** PHP syntax and runtime class-load testing.
- **Future replacement:** Replace with maintained date and calendar services where practical.
- **Removal condition:** Remove only after all original Calendar API consumers have been migrated and tested.

## Maintenance rule

Every package retained because of an old API must be added here when it is
added to `pear-packages.tsv`.

Each entry must record:

1. Exact package and version.
2. Why Chisimba requires it.
3. Relevant classes and file paths.
4. PHP compatibility treatment.
5. Intended replacement.
6. Conditions required before removal.
EOF

cp -a "$BUILDER" "$BUILDER.before-milestone5-manifest"

cat > "$BUILDER" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_ENV_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKSPACE_DIR="$(cd "$DEV_ENV_DIR/.." && pwd)"
FRAMEWORK_DIR="$WORKSPACE_DIR/framework"

MANIFEST="$DEV_ENV_DIR/dependencies/pear-packages.tsv"
PACK_ROOT="$DEV_ENV_DIR/dependencies/chisimba-pear-runtime"
STAGING_ROOT="$DEV_ENV_DIR/runtime/.chisimba-pear-runtime-staging"
DOWNLOAD_ROOT="$DEV_ENV_DIR/runtime/.chisimba-pear-downloads"
BACKUP_ROOT="$DEV_ENV_DIR/runtime/chisimba-pear-runtime-backup"
TARGET_ROOT="$FRAMEWORK_DIR/app/lib/pear"

if [[ ! -f "$MANIFEST" ]]; then
    echo "Missing dependency manifest: $MANIFEST" >&2
    exit 1
fi

rm -rf "$STAGING_ROOT" "$DOWNLOAD_ROOT"
mkdir -p "$STAGING_ROOT" "$DOWNLOAD_ROOT"

download_extract() {
    local id="$1"
    local version="$2"
    local url="$3"

    local archive="$DOWNLOAD_ROOT/${id}-${version}.archive"
    local extract_dir="$DOWNLOAD_ROOT/extracted/${id}"

    echo
    echo "Downloading $id $version"
    echo "  $url"

    curl -fL \
        --retry 3 \
        --connect-timeout 20 \
        --max-time 180 \
        "$url" \
        -o "$archive"

    echo "SHA-256:"
    sha256sum "$archive"

    mkdir -p "$extract_dir"
    tar -xzf "$archive" -C "$extract_dir"

    printf '%s\n' "$extract_dir"
}

package_root() {
    local extract_dir="$1"

    find "$extract_dir" \
        -mindepth 1 \
        -maxdepth 1 \
        -type d \
        | head -n 1
}

require_path() {
    local path="$1"

    if [[ ! -e "$path" ]]; then
        echo "Required package component missing: $path" >&2
        exit 1
    fi
}

echo "============================================================"
echo "Build manifest-driven Chisimba PEAR compatibility pack"
echo "============================================================"
date
echo
echo "Manifest:"
echo "  $MANIFEST"

while IFS=$'\t' read -r id version source_type source status purpose; do
    if [[ "$id" == "id" || -z "$id" ]]; then
        continue
    fi

    extract_dir="$(download_extract "$id" "$version" "$source")"
    root="$(package_root "$extract_dir")"

    if [[ -z "$root" || ! -d "$root" ]]; then
        echo "Unable to identify extracted root for $id $version." >&2
        exit 1
    fi

    echo "Installing $id $version into staging area."

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

        Calendar)
            require_path "$root/Calendar.php"
            require_path "$root/Calendar"

            cp -a "$root/Calendar.php" "$STAGING_ROOT/"
            rm -rf "$STAGING_ROOT/Calendar"
            cp -a "$root/Calendar" "$STAGING_ROOT/"
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
            echo "No installation rule exists for manifest package: $id" >&2
            exit 1
            ;;
    esac
done < "$MANIFEST"

cat > "$STAGING_ROOT/CHISIMBA_DEPENDENCY_MANIFEST.txt" <<EOF_MANIFEST
Chisimba PEAR/MDB2 compatibility pack

Generated from:
$MANIFEST

Packages:
$(tail -n +2 "$MANIFEST" | cut -f1,2,5 | tr '\t' ' ')
EOF_MANIFEST

required_files=(
    "PEAR.php"
    "System.php"
    "MDB2.php"
    "MDB2/Date.php"
    "MDB2/Schema.php"
    "MDB2/Driver/mysqli.php"
    "XML/Parser.php"
    "XML/Util.php"
    "Calendar.php"
    "XML/RPC.php"
    "XML/RPC/Server.php"
    "XML/RPC/Dump.php"
)

echo
echo "Validating staged compatibility pack..."

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
echo "Backing up the current framework PEAR tree..."
rm -rf "$BACKUP_ROOT"
mkdir -p "$BACKUP_ROOT"
cp -a "$TARGET_ROOT/." "$BACKUP_ROOT/"

echo
echo "Installing the complete curated pack into the framework PEAR tree..."

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
echo "Host syntax checks..."

for path in "${required_files[@]}"; do
    php -l "$TARGET_ROOT/$path"
done

echo
echo "Checking required XML_RPC classes..."

php -d include_path="$TARGET_ROOT" -r '
require_once "XML/RPC.php";
require_once "XML/RPC/Server.php";
require_once "XML/RPC/Dump.php";

$required = [
    "XML_RPC_Value",
    "XML_RPC_Message",
    "XML_RPC_Client",
    "XML_RPC_Response",
    "XML_RPC_Server",
];

foreach ($required as $class) {
    if (!class_exists($class)) {
        fwrite(STDERR, "Missing class: {$class}\n");
        exit(1);
    }

    echo "Loaded: {$class}\n";
}
'

echo
echo "Installed dependency manifest:"
cat "$TARGET_ROOT/CHISIMBA_DEPENDENCY_MANIFEST.txt"

echo
echo "Manifest-driven compatibility pack created successfully."
echo "Next: run the PEAR moderniser and rebuild the PHP 7.4 runtime."
EOF

chmod +x "$BUILDER"

echo "Created:"
echo "  $DEPENDENCIES/pear-packages.tsv"
echo "  $DEPENDENCIES/PEAR_DEPENDENCIES.md"
echo "  $DEPENDENCIES/PEAR_OLDER_LIST.md"
echo
echo "Replaced:"
echo "  $BUILDER"
echo
echo "Backup:"
echo "  $BUILDER.before-milestone5-manifest"
