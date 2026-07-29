#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="/run/media/derek/main/chisimba-revival"
DEV="$ROOT/dev-environment"
REBUILD="$DEV/scripts/rebuild-runtime.sh"
REPORT="$HOME/Downloads/killme.txt"

: > "$REPORT"

fail()
{
    echo "ERROR: $*" | tee -a "$REPORT" >&2
    exit 1
}

{
    echo "CHISIMBA PHP 8.2 FRESH RUNTIME REBUILD"
    echo "Generated: $(date --iso-8601=seconds)"
    echo
    echo "WARNING"
    echo "This rebuild deletes the PHP 8.2 Docker volumes and creates a fresh database."
    echo "The framework, modules, canvases, and repository contents are not deleted."
    echo
} >> "$REPORT"

[[ -x "$REBUILD" ]] || fail "Rebuild script not found or not executable: $REBUILD"

{
    echo "=== SOURCE REPOSITORY STATUS BEFORE REBUILD ==="
    for repo in framework modules canvases dev-environment; do
        path="$ROOT/$repo"
        echo
        echo "--- $repo ---"
        if [[ -d "$path/.git" ]]; then
            git -C "$path" status --short --branch
        else
            echo "Not a Git repository."
        fi
    done
    echo
    echo "=== REBUILD OUTPUT ==="
} >> "$REPORT"

"$REBUILD" php82 --fresh-db >> "$REPORT" 2>&1

RUNTIME="$DEV/runtime/php82-ch"

{
    echo
    echo "=== POST-REBUILD CHECKS ==="
    echo "Runtime: $RUNTIME"
    test -d "$RUNTIME" && echo "PASS: runtime directory exists."
    test ! -f "$RUNTIME/config/installdone.txt" \
        && echo "PASS: installdone.txt is absent for fresh installation." \
        || echo "WARNING: installdone.txt exists unexpectedly."
    echo
    docker compose -f "$DEV/compose/php82.yml" ps -a
    echo
    echo "Fresh rebuild complete."
    echo "Open the local Chisimba URL and run the installer."
} >> "$REPORT" 2>&1

printf 'Fresh rebuild complete: %s\n' "$REPORT"
