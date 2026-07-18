#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="${CHISIMBA_ROOT:-/run/media/derek/main/chisimba-revival}"
CONTAINER="${CHISIMBA_WEB_CONTAINER:-chisimba-php82-web}"
OUT="$ROOT/killme.txt"

{
    echo "============================================================"
    echo "NATIVE AUTH SHADOW TRACE"
    echo "Generated: $(date --iso-8601=seconds)"
    echo "============================================================"
    echo
    echo "Container: $CONTAINER"
    echo
    echo "================ DIRECTORY ================================"
    docker exec "$CONTAINER" sh -lc \
        'ls -la /var/www/html/ch/usrfiles/auth-shadow 2>&1 || true'
    echo
    echo "================ TRACE LOG ================================"
    docker exec "$CONTAINER" sh -lc \
        'cat /var/www/html/ch/usrfiles/auth-shadow/trace.log 2>&1 || true'
    echo
    echo "================ SNAPSHOTS ================================"
    docker exec "$CONTAINER" sh -lc \
        'find /var/www/html/ch/usrfiles/auth-shadow -maxdepth 1 -type f -name "auth-shadow-*.json" -print 2>/dev/null | sort'
    echo
    echo "================ PHP ERROR LOG HINTS ======================"
    docker logs "$CONTAINER" 2>&1 \
        | grep -E \
            'Native auth shadow|Fatal error|Parse error|Warning|Exception' \
        | tail -n 200 || true
} > "$OUT"

cat "$OUT"
