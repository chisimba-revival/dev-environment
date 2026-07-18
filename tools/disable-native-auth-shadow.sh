#!/usr/bin/env bash
set -Eeuo pipefail

CONTAINER="${CHISIMBA_WEB_CONTAINER:-chisimba-php82-web}"

if ! docker inspect "$CONTAINER" >/dev/null 2>&1; then
    echo "Container not found; shadow capture is effectively disabled."
    exit 0
fi

docker exec "$CONTAINER" sh -lc '
    rm -f /var/www/html/ch/usrfiles/auth-shadow/ENABLED
'

echo "Native-auth shadow capture disabled."
