#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_ENV_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKSPACE_DIR="$(cd "$DEV_ENV_DIR/.." && pwd)"

ASSEMBLY_SCRIPT="$SCRIPT_DIR/assemble-php74-runtime.sh"
COMPOSE_FILE="$DEV_ENV_DIR/compose/php74.yml"
RUNTIME_ROOT="$DEV_ENV_DIR/runtime"
RUNTIME_DIR="$RUNTIME_ROOT/php74-ch"

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
ROLLBACK_DIR="$RUNTIME_ROOT/.php74-runtime-backup-$TIMESTAMP"

WEB_STOPPED=0
OLD_RUNTIME_MOVED=0
REBUILD_COMPLETE=0

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

mkdir -p "$RUNTIME_ROOT"

rollback()
{
    local exit_code=$?

    if [[ "$REBUILD_COMPLETE" -eq 1 ]]; then
        return
    fi

    echo
    echo "============================================================"
    echo "REBUILD FAILED — RESTORING PREVIOUS RUNTIME"
    echo "============================================================"

    if [[ "$OLD_RUNTIME_MOVED" -eq 1 && -d "$ROLLBACK_DIR" ]]; then
        rm -rf "$RUNTIME_DIR" 2>/dev/null || true
        mv "$ROLLBACK_DIR" "$RUNTIME_DIR"

        echo "Previous runtime restored:"
        echo "  $RUNTIME_DIR"
    fi

    if [[ "$WEB_STOPPED" -eq 1 ]]; then
        docker compose \
            -f "$COMPOSE_FILE" \
            up -d --force-recreate --no-deps web || true
    fi

    echo
    echo "The database volume was not changed."
    exit "$exit_code"
}

trap rollback ERR INT TERM

echo "============================================================"
echo "Safe rebuild of Chisimba PHP 7.4 runtime"
echo "============================================================"
date
echo

echo "Workspace:"
echo "  $WORKSPACE_DIR"
echo
echo "Runtime:"
echo "  $RUNTIME_DIR"
echo
echo "Rollback copy:"
echo "  $ROLLBACK_DIR"
echo

# BEGIN RUNTIME STATE HANDOFF
#
# Runtime-generated files are normally owned by www-data and restricted to
# the container. Before moving the runtime to the rollback location, make
# those state directories readable and copyable by the host user.
#
# Secure www-data ownership is reapplied after the replacement container
# starts successfully.
if [[ -d "$RUNTIME_DIR" ]]; then
    echo
    echo "Preparing runtime state for host-side preservation..."

    docker compose \
        -f "$COMPOSE_FILE" \
        exec -T -u root web \
        sh -c '
            set -eu

            for path in \
                /var/www/html/ch/usrfiles \
                /var/www/html/ch/user_images \
                /var/www/html/ch/error_log \
                /var/www/html/ch/error_logs \
                /var/www/html/ch/tmp \
                /var/www/html/ch/cache
            do
                if [ ! -e "$path" ]; then
                    continue
                fi

                chmod -R a+rwX "$path"
                echo "Prepared for host copy: $path"
            done
        '
fi
# END RUNTIME STATE HANDOFF

echo "Stopping the web container..."
docker compose -f "$COMPOSE_FILE" stop web
WEB_STOPPED=1

if [[ -d "$RUNTIME_DIR" ]]; then
    echo
    echo "Moving the complete current runtime to the rollback location..."

    mv "$RUNTIME_DIR" "$ROLLBACK_DIR"
    OLD_RUNTIME_MOVED=1

    echo "Preserved complete runtime:"
    echo "  $ROLLBACK_DIR"
else
    echo
    echo "No existing runtime was found."
    echo "A new runtime will be assembled."
fi

echo
echo "Assembling a fresh runtime from source..."
"$ASSEMBLY_SCRIPT"

if [[ ! -d "$RUNTIME_DIR" ]]; then
    echo "Assembly failed to create the runtime directory:" >&2
    echo "  $RUNTIME_DIR" >&2
    exit 1
fi

restore_path()
{
    local relative_path="$1"
    local source_path="$ROLLBACK_DIR/$relative_path"
    local destination_path="$RUNTIME_DIR/$relative_path"

    if [[ ! -e "$source_path" ]]; then
        return
    fi

    rm -rf "$destination_path"
    mkdir -p "$(dirname "$destination_path")"
    cp -R "$source_path" "$destination_path"

    echo "Restored: $relative_path"
}

if [[ "$OLD_RUNTIME_MOVED" -eq 1 ]]; then
    echo
    echo "Restoring installation state and generated content..."

    restore_path "config"
    restore_path "usrfiles"
    restore_path "user_images"

    # Both spellings have existed in Chisimba runtimes.
    restore_path "error_log"
    restore_path "error_logs"

    restore_path "tmpinstallfile"
fi

echo
echo "Making the assembled runtime writable..."
chmod -R u+rwX,g+rwX,o+rX "$RUNTIME_DIR"

if [[ "$OLD_RUNTIME_MOVED" -eq 1 ]]; then
    old_installed=0

    if [[ -f "$ROLLBACK_DIR/config/installdone.txt" ]]; then
        old_installed=1
    fi

    if [[ "$old_installed" -eq 1 ]]; then
        echo
        echo "Verifying preservation of installed state..."

        required_state_files=(
            "config/installdone.txt"
            "config/dbdetails_inc.php"
            "config/config.xml"
        )

        for relative_path in "${required_state_files[@]}"; do
            if [[ ! -f "$RUNTIME_DIR/$relative_path" ]]; then
                echo "Installed-state verification failed." >&2
                echo "Missing restored file: $relative_path" >&2
                exit 1
            fi

            echo "Verified: $relative_path"
        done
    else
        echo
        echo "The previous runtime was not marked as installed."
        echo "No installed-state assertion will be made."
    fi
fi


# BEGIN HOST RUNTIME DIRECTORY PREPARATION
echo
echo "Preparing runtime-writable directories..."

runtime_writable_paths=(
    "usrfiles"
    "user_images"
    "error_log"
    "error_logs"
    "tmp"
    "cache"
)

mkdir -p "$RUNTIME_DIR/usrfiles/searchindexes"

for relative_path in "${runtime_writable_paths[@]}"; do
    writable_path="$RUNTIME_DIR/$relative_path"

    if [[ ! -e "$writable_path" ]]; then
        continue
    fi

    chmod -R u+rwX,g+rwX,o+rX "$writable_path"
    echo "Prepared: $relative_path"
done
# END HOST RUNTIME DIRECTORY PREPARATION

echo
echo "Checking for obsolete '&new' syntax in the assembled runtime..."

remaining_reference_new="$(
    grep -RInE \
        '=[[:space:]]*&[[:space:]]*new\b' \
        "$RUNTIME_DIR" \
        --include='*.php' \
        --include='*.inc' \
        --include='*.php5' \
        2>/dev/null || true
)"

if [[ -n "$remaining_reference_new" ]]; then
    echo "Verification failed: obsolete '&new' syntax remains:" >&2
    echo "$remaining_reference_new" >&2
    exit 1
fi

echo "Verified: no active '&new' syntax remains."

echo
echo "Checking key PHP files..."

php -l \
    "$RUNTIME_DIR/core_modules/prelogin/templates/content/admin_tpl.php"

php -l \
    "$RUNTIME_DIR/core_modules/modulecatalogue/templates/content/updates_tpl.php"

echo
echo "Recreating the PHP 7.4 web container..."

docker compose \
    -f "$COMPOSE_FILE" \
    up -d --force-recreate --no-deps web


# BEGIN CONTAINER RUNTIME PERMISSIONS
echo
echo "Applying runtime ownership inside the web container..."

docker compose \
    -f "$COMPOSE_FILE" \
    exec -T -u root web \
    sh -c '
        set -eu

        for path in \
            /var/www/html/ch/usrfiles \
            /var/www/html/ch/user_images \
            /var/www/html/ch/error_log \
            /var/www/html/ch/error_logs \
            /var/www/html/ch/tmp \
            /var/www/html/ch/cache
        do
            if [ ! -e "$path" ]; then
                continue
            fi

            chown -R www-data:www-data "$path"
            chmod -R u+rwX,g+rwX,o-rwx "$path"

            echo "Writable for www-data: $path"
        done

        mkdir -p /var/www/html/ch/usrfiles/searchindexes

        chown -R www-data:www-data \
            /var/www/html/ch/usrfiles/searchindexes

        chmod -R u+rwX,g+rwX,o-rwx \
            /var/www/html/ch/usrfiles/searchindexes

        runuser -u www-data -- \
            test -w /var/www/html/ch/usrfiles

        runuser -u www-data -- \
            test -w /var/www/html/ch/usrfiles/searchindexes
    '

echo "Verified: runtime paths are writable by www-data."
# END CONTAINER RUNTIME PERMISSIONS

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

        docker compose \
            -f "$COMPOSE_FILE" \
            logs --no-color --tail=100 web >&2 || true

        exit 1
    fi

    sleep 1
done

echo
echo "Verifying the running PHP version..."

docker compose \
    -f "$COMPOSE_FILE" \
    exec -T -w / web \
    php -v |
    head -n 1

echo
echo "Verifying the running Module Catalogue template..."

docker compose \
    -f "$COMPOSE_FILE" \
    exec -T -w / web \
    php -l \
    /var/www/html/ch/core_modules/modulecatalogue/templates/content/updates_tpl.php

echo
echo "HTTP response..."

curl -sS -I \
    --max-time 10 \
    http://localhost:8081/ch/ |
    sed -n '1,8p'

echo
echo "Container status..."

docker compose \
    -f "$COMPOSE_FILE" \
    ps

REBUILD_COMPLETE=1
trap - ERR INT TERM

echo
echo "============================================================"
echo "PHP 7.4 runtime rebuild completed successfully"
echo "============================================================"
echo
echo "The previous complete runtime has been retained at:"
echo "  $ROLLBACK_DIR"
echo
echo "Keep it until browser testing confirms that login and"
echo "administration still work. It can then be removed manually."
