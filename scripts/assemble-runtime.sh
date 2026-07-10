#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_ENV_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKSPACE_DIR="$(cd "$DEV_ENV_DIR/.." && pwd)"
RUNTIME_DIR="$DEV_ENV_DIR/runtime/chisimba"

required_repositories=(
    framework
    modules
    canvases
    shellscripts
)

for repository in "${required_repositories[@]}"; do
    if [[ ! -d "$WORKSPACE_DIR/$repository" ]]; then
        echo "Missing sibling repository: $WORKSPACE_DIR/$repository" >&2
        exit 1
    fi
done

echo "Assembling Chisimba runtime at:"
echo "  $RUNTIME_DIR"

rm -rf "$RUNTIME_DIR"
mkdir -p "$RUNTIME_DIR"

ln -s "$WORKSPACE_DIR/framework" "$RUNTIME_DIR/framework"
ln -s "$WORKSPACE_DIR/modules" "$RUNTIME_DIR/modules"
ln -s "$WORKSPACE_DIR/canvases" "$RUNTIME_DIR/canvases"
ln -s "$WORKSPACE_DIR/shellscripts" "$RUNTIME_DIR/shellscripts"

mkdir -p \
    "$RUNTIME_DIR/site/config" \
    "$RUNTIME_DIR/site/usrfiles" \
    "$RUNTIME_DIR/site/error_logs" \
    "$RUNTIME_DIR/site/packages"

echo
echo "Runtime assembled successfully."
find "$RUNTIME_DIR" -maxdepth 2 -mindepth 1 -printf '%P -> %l\n'
