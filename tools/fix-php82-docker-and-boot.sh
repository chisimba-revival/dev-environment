#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="/run/media/derek/main/chisimba-revival"
DEV="${ROOT}/dev-environment"

COMPOSE="${DEV}/compose/php82.yml"
DOCKERFILE="${DEV}/docker/php82/Dockerfile"
RUNTIME="${DEV}/runtime/php82-ch"
LOG="${ROOT}/killme.txt"

exec > >(tee "${LOG}") 2>&1

section()
{
    echo
    echo "============================================================"
    echo "$1"
    echo "============================================================"
}

fail()
{
    echo
    echo "ERROR: $*" >&2
    exit 1
}

section "Milestone 8: Correct PHP 8.2 Docker base and continue boot"

echo "Started: $(date --iso-8601=seconds)"
echo

for required in \
    "${COMPOSE}" \
    "${DOCKERFILE}" \
    "${RUNTIME}" \
    "${DEV}/config/php/php82.ini" \
    "${DEV}/docker/php74/chisimba-runtime-errors.php" \
    "${DEV}/docker/php74/99-chisimba-runtime-errors.ini"
do
    [[ -e "${required}" ]] ||
        fail "Required path does not exist: ${required}"
done

section "Back up failed PHP 8.2 Dockerfile"

BACKUP="${DOCKERFILE}.before-bookworm-fix-$(date '+%Y%m%d-%H%M%S')"

cp -a "${DOCKERFILE}" "${BACKUP}"

echo "Backup:"
echo "  ${BACKUP}"

section "Write clean PHP 8.2 Bookworm Dockerfile"

cat >"${DOCKERFILE}" <<'DOCKERFILE'
FROM php:8.2-apache-bookworm

# PHP 8.2 is deliberately pinned to Debian Bookworm.
#
# Do not copy the archived Bullseye repository override used by the
# frozen PHP 7.4 image. The official PHP 8.2 Bookworm image already
# contains a coherent Debian package configuration.

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        libpng-dev \
        libjpeg62-turbo-dev \
        libfreetype6-dev \
        libxml2-dev \
        libzip-dev \
        libonig-dev \
        zlib1g-dev \
        unzip \
        curl \
        rsync \
        default-mysql-client \
    ; \
    docker-php-ext-configure gd \
        --with-freetype \
        --with-jpeg \
    ; \
    docker-php-ext-install -j"$(nproc)" \
        gd \
        mysqli \
        mbstring \
        xml \
        zip \
    ; \
    rm -rf /var/lib/apt/lists/*

COPY config/php/php82.ini \
    /usr/local/etc/php/conf.d/chisimba.ini

RUN a2enmod rewrite

WORKDIR /var/www/html/ch

# Retain the existing Chisimba runtime error capture policy during
# migration so PHP 7.4 and PHP 8.2 failures remain comparable.
COPY docker/php74/chisimba-runtime-errors.php \
    /usr/local/lib/php/chisimba-runtime-errors.php

COPY docker/php74/99-chisimba-runtime-errors.ini \
    /usr/local/etc/php/conf.d/99-chisimba-runtime-errors.ini
DOCKERFILE

echo "New Dockerfile:"
echo
cat "${DOCKERFILE}"

section "Validate Compose configuration"

docker compose \
    -f "${COMPOSE}" \
    config >/dev/null

echo "Compose configuration is valid."

section "Build corrected PHP 8.2 image"

docker compose \
    -f "${COMPOSE}" \
    build --no-cache web

section "Start PHP 8.2 containers"

docker compose \
    -f "${COMPOSE}" \
    up -d

section "Container status"

docker compose \
    -f "${COMPOSE}" \
    ps -a

section "Verify PHP 8.2 environment"

docker compose \
    -f "${COMPOSE}" \
    exec -T web \
    php -v

echo
echo "Debian release:"

docker compose \
    -f "${COMPOSE}" \
    exec -T web \
    cat /etc/os-release

echo
echo "Required extensions:"

docker compose \
    -f "${COMPOSE}" \
    exec -T web \
    php -m \
    | grep -E \
        '^(gd|libxml|mbstring|mysqli|xml|xmlreader|xmlwriter|zip)$' \
    | sort \
    || true

section "Check fresh runtime state"

if [[ -e "${RUNTIME}/config/installdone.txt" ]]; then
    fail "Fresh PHP 8.2 runtime unexpectedly contains installdone.txt."
fi

echo "Confirmed: installdone.txt is absent."

section "Request PHP 8.2 installer"

set +e

HTTP_OUTPUT="$(
    curl \
        --silent \
        --show-error \
        --location \
        --max-time 30 \
        --write-out '\nHTTP_STATUS:%{http_code}\n' \
        "http://localhost:8082/ch/" \
        2>&1
)"

CURL_STATUS=$?

set -e

echo "curl exit status: ${CURL_STATUS}"
echo
printf '%s\n' "${HTTP_OUTPUT}"

section "Apache and PHP logs"

docker compose \
    -f "${COMPOSE}" \
    logs --no-color --tail=300 web \
    || true

section "Runtime error files"

find "${RUNTIME}" \
    -maxdepth 4 \
    -type f \
    \( \
        -iname '*error*' -o \
        -iname '*.log' \
    \) \
    -print0 \
    2>/dev/null \
    | sort -z \
    | while IFS= read -r -d '' error_file; do
        echo
        echo "------------------------------------------------------------"
        echo "FILE: ${error_file}"
        echo "------------------------------------------------------------"
        tail -n 150 "${error_file}" 2>/dev/null || true
    done

section "First PHP 8.2 fatal extraction"

FATAL_OUTPUT="$(
    {
        docker compose \
            -f "${COMPOSE}" \
            logs --no-color web \
            2>/dev/null

        find "${RUNTIME}" \
            -maxdepth 4 \
            -type f \
            \( -iname '*error*' -o -iname '*.log' \) \
            -exec cat {} + \
            2>/dev/null
    } \
        | grep -Ei \
            'fatal error|parse error|uncaught|compile error|typeerror|valueerror' \
        | head -n 30 \
        || true
)"

if [[ -n "${FATAL_OUTPUT}" ]]; then
    printf '%s\n' "${FATAL_OUTPUT}"
else
    echo "No fatal-pattern line was detected automatically."
fi

section "PHP syntax scan summary"

SYNTAX_LOG="$(mktemp)"

set +e

docker compose \
    -f "${COMPOSE}" \
    exec -T web \
    sh -lc '
        find /var/www/html/ch \
            -type f \
            \( -name "*.php" -o -name "*_class_inc.php" \) \
            -print0 \
        | xargs -0 -n1 php -l
    ' >"${SYNTAX_LOG}" 2>&1

SYNTAX_STATUS=$?

set -e

echo "Syntax scan exit status: ${SYNTAX_STATUS}"
echo

grep -E \
    'Parse error|Fatal error|Errors parsing' \
    "${SYNTAX_LOG}" \
    | head -n 50 \
    || echo "No syntax errors were reported in the scanned files."

rm -f "${SYNTAX_LOG}"

section "PHP 7.4 reference status"

docker compose \
    -f "${DEV}/compose/php74.yml" \
    ps

section "Git status"

git -C "${DEV}" status --short

section "PHP 8.2 boot attempt complete"

echo "Finished: $(date --iso-8601=seconds)"
echo
echo "PHP 8.2 URL:"
echo "  http://localhost:8082/ch/"
echo
echo "PHP 7.4 reference URL:"
echo "  http://localhost:8081/ch/"
echo
echo "Upload:"
echo "  ${LOG}"
