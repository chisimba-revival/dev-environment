#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="${CHISIMBA_ROOT:-/run/media/derek/main/chisimba-revival}"
CONTAINER="${CHISIMBA_WEB_CONTAINER:-chisimba-php82-web}"
OUT="$ROOT/killme.txt"

if ! docker inspect "$CONTAINER" >/dev/null 2>&1; then
    echo "ERROR: Container not found: $CONTAINER" >&2
    echo "Rebuild/start the PHP 8.2 runtime first." >&2
    exit 1
fi

docker exec "$CONTAINER" sh -lc '
    set -eu
    base=/var/www/html/ch/usrfiles/auth-shadow
    mkdir -p "$base"
    chmod 700 "$base"
    : > "$base/ENABLED"
    chmod 600 "$base/ENABLED"
    test -f /var/www/html/ch/core_modules/security/classes/nativeauth/nativeauthshadowcomparator.php
'

{
    echo "============================================================"
    echo "NATIVE AUTH SHADOW ENABLED"
    echo "Generated: $(date --iso-8601=seconds)"
    echo "============================================================"
    echo
    echo "Container: $CONTAINER"
    docker exec "$CONTAINER" sh -lc '
        ls -ld /var/www/html/ch/usrfiles/auth-shadow
        ls -l /var/www/html/ch/usrfiles/auth-shadow/ENABLED
        php -l /var/www/html/ch/core_modules/security/classes/nativeauth/nativeauthshadowcomparator.php
        php -l /var/www/html/ch/core_modules/security/classes/user_class_inc.php
    '
    echo
    echo "Log in once using the normal local database login."
    echo "Then run:"
    echo "  $ROOT/dev-environment/tools/collect-native-auth-shadow.sh"
} > "$OUT"

cat "$OUT"
