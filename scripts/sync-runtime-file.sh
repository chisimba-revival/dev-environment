#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage:"
    echo "  $0 PATH_RELATIVE_TO_FRAMEWORK_APP"
    echo
    echo "Example:"
    echo "  $0 installer/steps/createconfigs.inc"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_ENV_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKSPACE_DIR="$(cd "$DEV_ENV_DIR/.." && pwd)"

RELATIVE_PATH="${1#/}"

SOURCE_FILE="$WORKSPACE_DIR/framework/app/$RELATIVE_PATH"
RUNTIME_FILE="$DEV_ENV_DIR/runtime/php74-ch/$RELATIVE_PATH"

if [[ ! -f "$SOURCE_FILE" ]]; then
    echo "Source file does not exist:"
    echo "  $SOURCE_FILE" >&2
    exit 1
fi

mkdir -p "$(dirname "$RUNTIME_FILE")"

cp -a "$SOURCE_FILE" "$RUNTIME_FILE"

echo "Synchronized:"
echo "  Source:  $SOURCE_FILE"
echo "  Runtime: $RUNTIME_FILE"
