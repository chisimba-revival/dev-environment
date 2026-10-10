#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
dockerfile="$root/docker/php85/Dockerfile"
security_ini="$root/docker/php85/99-chisimba-security.ini"
errors_ini="$root/docker/php74/99-chisimba-runtime-errors.ini"
error_shim="$root/docker/php74/chisimba-runtime-errors.php"
nginx_config="$root/local-https/nginx-php85.conf"

require_line() {
    local file="$1"
    local expected="$2"
    grep -Fqx "$expected" "$file" \
        || { printf 'FAIL: %s lacks %s\n' "$file" "$expected" >&2; exit 1; }
}

require_contains() {
    local file="$1"
    local expected="$2"
    grep -Fq "$expected" "$file" \
        || { printf 'FAIL: %s lacks %s\n' "$file" "$expected" >&2; exit 1; }
}

require_line "$dockerfile" 'FROM php:8.5.11-apache-bookworm'
require_contains "$dockerfile" 'COPY docker/php85/99-chisimba-security.ini'
require_contains "$dockerfile" '/usr/local/etc/php/conf.d/zz-chisimba-security.ini'
for setting in \
    'session.use_only_cookies = On' \
    'session.use_strict_mode = On' \
    'session.cookie_secure = On' \
    'session.cookie_httponly = On' \
    'session.cookie_samesite = Lax' \
    'expose_php = Off' \
    'display_errors = Off' \
    'display_startup_errors = Off'
do
    require_line "$security_ini" "$setting"
done
require_line "$errors_ini" 'display_errors = Off'
require_line "$errors_ini" 'display_startup_errors = Off'
require_line "$error_shim" "ini_set('display_errors', '0');"
require_line "$error_shim" "ini_set('display_startup_errors', '0');"
for header in \
    'add_header X-Content-Type-Options "nosniff" always;' \
    'add_header X-Frame-Options "SAMEORIGIN" always;' \
    'add_header Referrer-Policy "strict-origin-when-cross-origin" always;' \
    'add_header Permissions-Policy "camera=(self), geolocation=(), microphone=()" always;'
do
    require_contains "$nginx_config" "$header"
done

printf 'PASS: PHP 8.5 production security baseline contract verified.\n'
