#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="${CHISIMBA_ROOT:-/run/media/derek/main/chisimba-revival}"
CONTAINER="${CHISIMBA_WEB_CONTAINER:-chisimba-php82-web}"
OUT="$ROOT/killme.txt"
HOST_DIR="$ROOT/dev-environment/reports/nativeauth-shadow"

mkdir -p "$HOST_DIR"

if ! docker inspect "$CONTAINER" >/dev/null 2>&1; then
    echo "ERROR: Container not found: $CONTAINER" >&2
    exit 1
fi

mapfile -t FILES < <(
    docker exec "$CONTAINER" sh -lc \
        'find /var/www/html/ch/usrfiles/auth-shadow -maxdepth 1 -type f -name "auth-shadow-*.json" -print 2>/dev/null | sort'
)

{
    echo "============================================================"
    echo "NATIVE AUTH SHADOW CAPTURE"
    echo "Generated: $(date --iso-8601=seconds)"
    echo "============================================================"
    echo
    echo "Container: $CONTAINER"
    echo "Snapshots found: ${#FILES[@]}"
    echo
} > "$OUT"

if [[ ${#FILES[@]} -eq 0 ]]; then
    {
        echo "No snapshot was found."
        echo
        echo "Confirm that:"
        echo "1. enable-native-auth-shadow.sh was run after rebuilding runtime;"
        echo "2. normal local database login succeeded;"
        echo "3. the login used the PHP 8.2 container."
        echo
        echo "Runtime checks:"
        docker exec "$CONTAINER" sh -lc '
            ls -la /var/www/html/ch/usrfiles/auth-shadow 2>&1 || true
            test -f /var/www/html/ch/usrfiles/auth-shadow/ENABLED \
                && echo ENABLED \
                || echo DISABLED
        '
    } >> "$OUT"
    cat "$OUT"
    exit 1
fi

for remote in "${FILES[@]}"; do
    name="$(basename "$remote")"
    docker cp "$CONTAINER:$remote" "$HOST_DIR/$name" >/dev/null
done

LATEST="$(ls -1 "$HOST_DIR"/auth-shadow-*.json | sort | tail -n 1)"

{
    echo "Copied snapshots to:"
    echo "$HOST_DIR"
    echo
    echo "Latest snapshot:"
    echo "$LATEST"
    echo
    echo "================ SUMMARY ==================================="
    php -r '
        $file = $argv[1];
        $data = json_decode(file_get_contents($file), true);
        if (!is_array($data)) {
            fwrite(STDERR, "Invalid JSON\n");
            exit(1);
        }
        $auth = isset($data["authentication"])
            ? $data["authentication"] : array();
        $session = isset($data["session"])
            ? $data["session"] : array();
        $mismatches = isset($session["mismatches"])
            && is_array($session["mismatches"])
            ? $session["mismatches"] : array();

        echo "Authenticated: "
            . (!empty($auth["authenticated"]) ? "YES" : "NO")
            . PHP_EOL;
        echo "Provider: "
            . (isset($auth["provider"]) ? $auth["provider"] : "unknown")
            . PHP_EOL;
        echo "Shadow match: "
            . (!empty($auth["shadow_match"]) ? "YES" : "NO")
            . PHP_EOL;
        echo "Mismatch count: " . count($mismatches) . PHP_EOL;

        foreach ($mismatches as $field => $values) {
            echo "- " . $field
                . ": expected="
                . json_encode(isset($values["expected"])
                    ? $values["expected"] : null)
                . " actual="
                . json_encode(isset($values["actual"])
                    ? $values["actual"] : null)
                . PHP_EOL;
        }
    ' "$LATEST"
    echo
    echo "================ REDACTION CHECK ==========================="
    if grep -Eiq \
        '"(password|passwd|pass|password_hash|token|nonce|session_id|cookie)"[[:space:]]*:[[:space:]]*"(?!\[REDACTED\])' \
        "$LATEST" 2>/dev/null; then
        echo "WARNING: A potentially sensitive unredacted key was detected."
    else
        echo "No obvious unredacted credential keys detected."
    fi
    echo
    echo "Shadow remains enabled until this is run:"
    echo "  $ROOT/dev-environment/tools/disable-native-auth-shadow.sh"
} >> "$OUT"

cat "$OUT"
