#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="/run/media/derek/main/chisimba-revival"
TARGET="$ROOT/dev-environment/scripts/rebuild-php74-runtime.sh"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${TARGET}.before-state-handoff-${STAMP}"

if [[ ! -f "$TARGET" ]]; then
    echo "ERROR: Rebuild script not found:"
    echo "  $TARGET"
    exit 1
fi

if grep -q "BEGIN RUNTIME STATE HANDOFF" "$TARGET"; then
    echo "Runtime state handoff is already installed."
    echo "No changes made."
    exit 0
fi

cp -a "$TARGET" "$BACKUP"

python3 - "$TARGET" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

marker = '''echo "Stopping the web container..."
docker compose -f "$COMPOSE_FILE" stop web
'''

block = r'''# BEGIN RUNTIME STATE HANDOFF
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

'''

if marker not in text:
    raise SystemExit(
        "ERROR: Could not find the web-container stop marker."
    )

text = text.replace(marker, block + marker, 1)
path.write_text(text, encoding="utf-8")
PY

bash -n "$TARGET"

echo
echo "Patch applied successfully."
echo
echo "Updated:"
echo "  $TARGET"
echo
echo "Backup:"
echo "  $BACKUP"

echo
echo "Installed block:"
grep -n -A38 -B3 \
    "BEGIN RUNTIME STATE HANDOFF" \
    "$TARGET"
