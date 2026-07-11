#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_ENV_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKSPACE_DIR="$(cd "$DEV_ENV_DIR/.." && pwd)"
RUNTIME_DIR="$DEV_ENV_DIR/runtime/ch"

required_paths=(
    "$WORKSPACE_DIR/framework/app"
    "$WORKSPACE_DIR/modules"
    "$WORKSPACE_DIR/canvases"
    "$WORKSPACE_DIR/shellscripts"
)

for path in "${required_paths[@]}"; do
    if [[ ! -e "$path" ]]; then
        echo "Required source path is missing: $path" >&2
        exit 1
    fi
done

echo "Creating disposable Chisimba runtime:"
echo "  $RUNTIME_DIR"

rm -rf "$RUNTIME_DIR"
mkdir -p "$RUNTIME_DIR"

# Copy the framework application into a disposable writable runtime.
cp -a "$WORKSPACE_DIR/framework/app/." "$RUNTIME_DIR/"

# Replace any framework placeholders with copies of the historical repositories.
rm -rf "$RUNTIME_DIR/packages" "$RUNTIME_DIR/canvases"

mkdir -p "$RUNTIME_DIR/packages" "$RUNTIME_DIR/canvases"

cp -a "$WORKSPACE_DIR/modules/." "$RUNTIME_DIR/packages/"
cp -a "$WORKSPACE_DIR/canvases/." "$RUNTIME_DIR/canvases/"

# Ensure runtime-writable directories exist.
mkdir -p \
    "$RUNTIME_DIR/config" \
    "$RUNTIME_DIR/usrfiles" \
    "$RUNTIME_DIR/usrfiles/users" \
    "$RUNTIME_DIR/user_images" \
    "$RUNTIME_DIR/error_logs"

# The historical installer expects the application root to be writable.
chmod -R a+rwX "$RUNTIME_DIR"

echo
echo "Runtime assembled successfully."

echo
echo "Runtime contents:"
find "$RUNTIME_DIR" -maxdepth 2 -mindepth 1 | sort | head -80
