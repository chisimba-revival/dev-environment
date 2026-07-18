#!/usr/bin/env bash
set -euo pipefail

ROOT="/run/media/derek/main/chisimba-revival"
TARGET="$ROOT/dev-environment/scripts/rebuild-php74-runtime.sh"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${TARGET}.before-container-permissions-${STAMP}"

if [[ ! -f "$TARGET" ]]; then
    echo "ERROR: Rebuild script not found:"
    echo "  $TARGET"
    exit 1
fi

if grep -q "BEGIN CONTAINER RUNTIME PERMISSIONS" "$TARGET"; then
    echo "Container-side runtime permissions are already installed."
    exit 0
fi

if ! grep -q "BEGIN MANAGED RUNTIME WRITABLE PERMISSIONS" "$TARGET"; then
    echo "ERROR: Existing faulty permissions block was not found."
    exit 1
fi

cp -a "$TARGET" "$BACKUP"

python3 - "$TARGET" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

old_start = "# BEGIN MANAGED RUNTIME WRITABLE PERMISSIONS"
old_end = "# END MANAGED RUNTIME WRITABLE PERMISSIONS"

start = text.find(old_start)
end = text.find(old_end)

if start == -1 or end == -1 or end < start:
    raise SystemExit("ERROR: Could not locate the existing permissions block.")

end += len(old_end)

host_preparation = r'''# BEGIN HOST RUNTIME DIRECTORY PREPARATION
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
# END HOST RUNTIME DIRECTORY PREPARATION'''

text = text[:start] + host_preparation + text[end:]

startup_marker = '''docker compose \\
    -f "$COMPOSE_FILE" \\
    up -d --force-recreate --no-deps web
'''

container_permissions = r'''

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
'''

if startup_marker not in text:
    raise SystemExit(
        "ERROR: Could not locate the web-container startup command."
    )

text = text.replace(
    startup_marker,
    startup_marker + container_permissions,
    1
)

path.write_text(text, encoding="utf-8")
PY

bash -n "$TARGET"

echo
echo "Rebuild script patched successfully."
echo
echo "Updated:"
echo "  $TARGET"
echo
echo "Backup:"
echo "  $BACKUP"

echo
echo "Installed blocks:"
grep -nE \
    'BEGIN (HOST RUNTIME DIRECTORY PREPARATION|CONTAINER RUNTIME PERMISSIONS)' \
    "$TARGET"
