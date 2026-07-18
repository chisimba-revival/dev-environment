#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="/run/media/derek/main/chisimba-revival"
OUT="$ROOT/killme.txt"

exec >"$OUT" 2>&1

echo "===== Redirects to installer ====="
grep -RIn \
    "installer/index.php" \
    "$ROOT/framework/app"

echo
echo "===== installdone references ====="
grep -RIn \
    "installdone" \
    "$ROOT/framework/app"

echo
echo "===== config.xml references ====="
grep -RIn \
    "config.xml" \
    "$ROOT/framework/app"

echo
echo "===== dbdetails references ====="
grep -RIn \
    "dbdetails" \
    "$ROOT/framework/app"
