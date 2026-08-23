#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="$ROOT/local-https/nginx-php85.conf"

grep -Eq '^[[:space:]]*client_max_body_size[[:space:]]+64m;' "$CONFIG"
echo "OK: PHP 8.5 HTTPS proxy accepts 64 MB request bodies"
