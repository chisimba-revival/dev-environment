#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="${CHISIMBA_ROOT:-/run/media/derek/main/chisimba-revival}"
FRAMEWORK="$ROOT/framework"
OUT="$ROOT/killme.txt"

{
    echo "============================================================"
    echo "LIVEUSER RECORDER HOOK-POINT AUDIT"
    echo "Generated: $(date --iso-8601=seconds)"
    echo "============================================================"
    echo
    echo "This is a read-only audit. No files are modified."
    echo
    echo "================ LOGIN SUCCESS / SESSION CALLS ============="
    grep -RInE \
        --include='*.php' --include='*.inc' \
        'isLoggedIn|loginUser|authId|setSession|set_session|LiveUser|login[[:space:]]*\(' \
        "$FRAMEWORK/app/core_modules/login" \
        "$FRAMEWORK/app/core_modules/security" 2>/dev/null \
        | head -n 500 || true
    echo
    echo "================ USER ID / USERNAME ACCESSORS ==============="
    grep -RInE \
        --include='*.php' --include='*.inc' \
        'userId|userName|getUser|getUsername|getUserId|authUserId' \
        "$FRAMEWORK/app/core_modules/security/classes" 2>/dev/null \
        | head -n 500 || true
    echo
    echo "================ GROUP / PERMISSION ACCESSORS ==============="
    grep -RInE \
        --include='*.php' --include='*.inc' \
        'getGroups|groupId|isGroupMember|permission|acl|role' \
        "$FRAMEWORK/app/core_modules/groupadmin" \
        "$FRAMEWORK/app/core_modules/permissions" \
        "$FRAMEWORK/app/core_modules/security" 2>/dev/null \
        | head -n 700 || true
    echo
    echo "================ SESSION KEYS ================================"
    grep -RInE \
        --include='*.php' --include='*.inc' \
        '\$_SESSION|setSession|getSession' \
        "$FRAMEWORK/app/core_modules/login" \
        "$FRAMEWORK/app/core_modules/security" 2>/dev/null \
        | head -n 700 || true
} > "$OUT"

echo "Audit complete. Upload:"
echo "  $OUT"
