#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_ENV_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKSPACE_DIR="$(cd "$DEV_ENV_DIR/.." && pwd)"

echo "Chisimba Revival runtime assembly"
echo
echo "Workspace: $WORKSPACE_DIR"
echo "Framework: $WORKSPACE_DIR/framework"
echo "Modules: $WORKSPACE_DIR/modules"
echo "Canvases: $WORKSPACE_DIR/canvases"
echo "Shellscripts: $WORKSPACE_DIR/shellscripts"
echo
echo "Runtime assembly is not implemented yet."
