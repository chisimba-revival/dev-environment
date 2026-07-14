#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-report}"

if [[ "$MODE" != "report" && "$MODE" != "--apply" ]]; then
    echo "Usage:"
    echo "  $0"
    echo "  $0 --apply"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_ENV_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKSPACE_DIR="$(cd "$DEV_ENV_DIR/.." && pwd)"

FRAMEWORK_DIR="$WORKSPACE_DIR/framework"
MODULES_DIR="$WORKSPACE_DIR/modules"

BASE_CLASS_FILE="$FRAMEWORK_DIR/app/classes/core/object_class_inc.php"

if [[ ! -f "$BASE_CLASS_FILE" ]]; then
    echo "Base class file not found:"
    echo "  $BASE_CLASS_FILE"
    exit 1
fi

echo "PHP 7.4 modernisation"
echo "Mode: $MODE"
echo

echo "Rule: rename reserved Chisimba base class"
echo "  class object                -> class ChisimbaObject"
echo "  extends object/Object       -> extends ChisimbaObject"
echo "  new object(...)             -> new ChisimbaObject(...)"
echo "  'object' inheritance checks -> 'ChisimbaObject'"
echo

mapfile -d '' SOURCE_FILES < <(
    find \
        "$FRAMEWORK_DIR/app/classes" \
        "$FRAMEWORK_DIR/app/core_modules" \
        "$FRAMEWORK_DIR/app/installer" \
        "$MODULES_DIR" \
        -type f \
        \( -name '*.php' -o -name '*.inc' \) \
        ! -path '*/resources/*' \
        ! -path '*/vendor/*' \
        ! -path '*/lib/*' \
        ! -path '*/pear/*' \
        ! -path '*/wastebin/*' \
        ! -path '*/tmp/*' \
        ! -path '*/tests/*' \
        ! -name '*~' \
        ! -name '.goutputstream-*' \
        -print0
)

declare -a EXTENDS_FILES=()
declare -a NEW_OBJECT_FILES=()
declare -a QUOTED_REFERENCE_FILES=()

for file in "${SOURCE_FILES[@]}"; do
    if grep -Eq \
        '(^|[[:space:]])extends[[:space:]]+[Oo]bject([[:space:]\{]|$)' \
        "$file"; then
        EXTENDS_FILES+=("$file")
    fi

    if grep -Eq \
        'new[[:space:]]+[Oo]bject[[:space:]]*\(' \
        "$file"; then
        NEW_OBJECT_FILES+=("$file")
    fi

    if grep -Eq \
        "(is_a|is_subclass_of|class_exists)[[:space:]]*\([^)]*['\"]object['\"]" \
        "$file"; then
        QUOTED_REFERENCE_FILES+=("$file")
    fi
done

BASE_DECLARATIONS="$(
    grep -Ec \
        '^[[:space:]]*class[[:space:]]+object([[:space:]\{]|$)' \
        "$BASE_CLASS_FILE" || true
)"

echo "Source files scanned: ${#SOURCE_FILES[@]}"
echo "Base-class declarations found: $BASE_DECLARATIONS"
echo "Subclass files found: ${#EXTENDS_FILES[@]}"
echo "Direct-instantiation files found: ${#NEW_OBJECT_FILES[@]}"
echo "Quoted-reference files found: ${#QUOTED_REFERENCE_FILES[@]}"
echo

if [[ "$BASE_DECLARATIONS" -ne 1 ]]; then
    echo "Expected exactly one base-class declaration."
    echo "No changes were made."
    exit 1
fi

if [[ "$MODE" == "report" ]]; then
    echo "Base class file:"
    echo "  $BASE_CLASS_FILE"
    echo

    echo "Subclass files:"
    for file in "${EXTENDS_FILES[@]}"; do
        echo "  $file"
    done
    echo

    echo "Direct-instantiation files:"
    for file in "${NEW_OBJECT_FILES[@]}"; do
        echo "  $file"
    done
    echo

    echo "Quoted-reference files:"
    for file in "${QUOTED_REFERENCE_FILES[@]}"; do
        echo "  $file"
    done
    echo

    echo "Dry run only. No files were changed."
    echo
    echo "To apply:"
    echo "  $0 --apply"
    exit 0
fi

echo "Applying changes..."

perl -pi -e \
    's/^(\s*class\s+)object(\s*(?:\{|$))/${1}ChisimbaObject${2}/' \
    "$BASE_CLASS_FILE"

for file in "${EXTENDS_FILES[@]}"; do
    perl -pi -e \
        's/\bextends\s+[Oo]bject\b/extends ChisimbaObject/g' \
        "$file"
done

for file in "${NEW_OBJECT_FILES[@]}"; do
    perl -pi -e \
        's/\bnew\s+[Oo]bject\s*\(/new ChisimbaObject(/g' \
        "$file"
done

for file in "${QUOTED_REFERENCE_FILES[@]}"; do
    perl -pi -e \
        "s/(['\"])object\1/\${1}ChisimbaObject\${1}/g" \
        "$file"
done

echo
echo "Changes applied."
echo "Base class updated: 1"
echo "Subclass files updated: ${#EXTENDS_FILES[@]}"
echo "Direct-instantiation files updated: ${#NEW_OBJECT_FILES[@]}"
echo "Quoted-reference files updated: ${#QUOTED_REFERENCE_FILES[@]}"
echo
echo "Review with:"
echo "  git -C \"$FRAMEWORK_DIR\" diff --stat"
echo "  git -C \"$MODULES_DIR\" diff --stat"

echo
echo "Modernising removed POSIX regular-expression functions..."
php "$DEV_ENV_DIR/tools/php-moderniser/modernise-ereg.php"

