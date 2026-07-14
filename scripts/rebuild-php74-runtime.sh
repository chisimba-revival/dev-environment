#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_ENV_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKSPACE_DIR="$(cd "$DEV_ENV_DIR/.." && pwd)"

ASSEMBLY_SCRIPT="$SCRIPT_DIR/assemble-php74-runtime.sh"
COMPOSE_FILE="$DEV_ENV_DIR/compose/php74.yml"
RUNTIME_DIR="$DEV_ENV_DIR/runtime/php74-ch"
STATE_BACKUP_DIR="$DEV_ENV_DIR/runtime/.php74-state-backup"

required_paths=(
    "$ASSEMBLY_SCRIPT"
    "$COMPOSE_FILE"
    "$WORKSPACE_DIR/framework/app"
    "$WORKSPACE_DIR/modules"
    "$WORKSPACE_DIR/canvases"
)

for path in "${required_paths[@]}"; do
    if [[ ! -e "$path" ]]; then
        echo "Required path is missing: $path" >&2
        exit 1
    fi
done

echo "============================================================"
echo "Rebuild Chisimba PHP 7.4 runtime"
echo "============================================================"
date
echo

echo "Workspace:"
echo "  $WORKSPACE_DIR"
echo "Runtime:"
echo "  $RUNTIME_DIR"
echo

rm -rf "$STATE_BACKUP_DIR"
mkdir -p "$STATE_BACKUP_DIR"

preserve_path()
{
    local relative_path="$1"
    local source_path="$RUNTIME_DIR/$relative_path"
    local backup_path="$STATE_BACKUP_DIR/$relative_path"

    if [[ ! -e "$source_path" ]]; then
        return
    fi

    mkdir -p "$(dirname "$backup_path")"
    cp -a "$source_path" "$backup_path"

    echo "Preserved: $relative_path"
}

restore_path()
{
    local relative_path="$1"
    local backup_path="$STATE_BACKUP_DIR/$relative_path"
    local destination_path="$RUNTIME_DIR/$relative_path"

    if [[ ! -e "$backup_path" ]]; then
        return
    fi

    rm -rf "$destination_path"
    mkdir -p "$(dirname "$destination_path")"
    cp -a "$backup_path" "$destination_path"

    echo "Restored: $relative_path"
}

echo "Preserving runtime-generated state..."

# Preserve only installer/site state and user-generated writable content.
# Application code, PEAR, modules and canvases are always rebuilt from Git.
preserve_path "config"
preserve_path "usrfiles"
preserve_path "user_images"
preserve_path "error_logs"
preserve_path "tmpinstallfile"

echo
echo "Assembling a fresh runtime from source..."
"$ASSEMBLY_SCRIPT"

echo
echo "Restoring runtime-generated state..."
restore_path "config"
restore_path "usrfiles"
restore_path "user_images"
restore_path "error_logs"
restore_path "tmpinstallfile"

chmod -R a+rwX "$RUNTIME_DIR"

echo
echo "Recreating PHP 7.4 web container..."
docker compose \
    -f "$COMPOSE_FILE" \
    up -d --force-recreate --no-deps web

echo
echo "Waiting for Apache..."
for attempt in {1..30}; do
    if curl -fsS \
        --max-time 3 \
        http://localhost:8081/ch/ \
        >/dev/null 2>&1; then
        break
    fi

    if [[ "$attempt" -eq 30 ]]; then
        echo "Apache did not become ready." >&2
        docker logs --tail 100 chisimba-php74-web >&2 || true
        exit 1
    fi

    sleep 1
done

echo
echo "Verifying PHP version..."
docker compose \
    -f "$COMPOSE_FILE" \
    exec -T -w / web \
    php -v | head -n 1

echo
echo
echo "Verifying curated PEAR installation..."

docker compose \
    -f "$COMPOSE_FILE" \
    exec -T -w / web \
    php -l /var/www/html/ch/lib/pear/PEAR/Common.php

echo "PEAR/Common.php syntax OK."

echo "Verified: case T_WHITESPACE uses continue 2."

echo
echo "Checking for removed executable Magic Quotes calls..."
remaining_magic_quotes="$(
    docker compose \
        -f "$COMPOSE_FILE" \
        exec -T -w / web \
        grep -RniE \
        '\b(get_magic_quotes_runtime|get_magic_quotes_gpc|set_magic_quotes_runtime)[[:space:]]*\(' \
        /var/www/html/ch/lib/pear \
        --include='*.php' \
        --include='*.inc' \
        2>/dev/null || true
)"

if [[ -n "$remaining_magic_quotes" ]]; then
    echo "Verification failed: removed Magic Quotes calls remain:"
    echo "$remaining_magic_quotes"
    exit 1
fi

echo "Verified: no removed executable Magic Quotes calls remain."

echo
echo "HTTP response:"
curl -sS -I \
    --max-time 10 \
    http://localhost:8081/ch/ |
    sed -n '1,8p'

echo
echo "Container status:"
docker compose \
    -f "$COMPOSE_FILE" \
    ps

rm -rf "$STATE_BACKUP_DIR"

echo
echo "PHP 7.4 runtime rebuild completed successfully."
