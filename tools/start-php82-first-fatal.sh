#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="/run/media/derek/main/chisimba-revival"
DEV="${ROOT}/dev-environment"
LOG="${ROOT}/killme.txt"

FRAMEWORK="${ROOT}/framework/app"
MODULES="${ROOT}/modules"
CANVASES="${ROOT}/canvases"

PROFILE="php82"
RUNTIME="${DEV}/runtime/${PROFILE}-ch"
COMPOSE="${DEV}/compose/${PROFILE}.yml"
DOCKER_DIR="${DEV}/docker/${PROFILE}"
DOCKERFILE="${DOCKER_DIR}/Dockerfile"

SOURCE_DOCKERFILE="${DEV}/docker/php74/Dockerfile.php82"
PHP_INI_SOURCE="${DEV}/config/php/php74.ini"
PHP_INI_TARGET="${DEV}/config/php/php82.ini"

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

section "Milestone 8: Assemble and start fresh PHP 8.2 runtime"

echo "Started: $(date --iso-8601=seconds)"
echo "Profile: ${PROFILE}"
echo "Runtime: ${RUNTIME}"
echo

for required in \
    "${FRAMEWORK}" \
    "${MODULES}" \
    "${CANVASES}" \
    "${COMPOSE}" \
    "${SOURCE_DOCKERFILE}" \
    "${PHP_INI_SOURCE}"
do
    [[ -e "${required}" ]] ||
        fail "Required path does not exist: ${required}"
done

section "Stop and remove any previous PHP 8.2 containers"

docker compose \
    -f "${COMPOSE}" \
    down --remove-orphans \
    || true

echo
echo "Removing the PHP 8.2 database volume to guarantee a fresh install..."

docker volume rm chisimba-php82_php82_db 2>/dev/null || true
docker volume rm php82_db 2>/dev/null || true

section "Create clean PHP 8.2 Docker profile"

mkdir -p "${DOCKER_DIR}"

cp -a "${SOURCE_DOCKERFILE}" "${DOCKERFILE}"
cp -a "${PHP_INI_SOURCE}" "${PHP_INI_TARGET}"

python3 - \
    "${DOCKERFILE}" \
    "${COMPOSE}" <<'PY'
from pathlib import Path
import re
import sys

dockerfile_path = Path(sys.argv[1])
compose_path = Path(sys.argv[2])

dockerfile = dockerfile_path.read_text()

dockerfile = dockerfile.replace(
    "COPY config/php/php74.ini /usr/local/etc/php/conf.d/chisimba.ini",
    "COPY config/php/php82.ini /usr/local/etc/php/conf.d/chisimba.ini",
)

dockerfile = dockerfile.replace(
    "# Chisimba PHP 7.4 runtime error policy",
    "# Chisimba PHP 8.2 runtime error policy",
)

dockerfile = dockerfile.replace(
    "COPY docker/php74/chisimba-runtime-errors.php "
    "/usr/local/lib/php/chisimba-runtime-errors.php",
    "COPY docker/php74/chisimba-runtime-errors.php "
    "/usr/local/lib/php/chisimba-runtime-errors.php",
)

dockerfile = dockerfile.replace(
    "COPY docker/php74/99-chisimba-runtime-errors.ini "
    "/usr/local/etc/php/conf.d/99-chisimba-runtime-errors.ini",
    "COPY docker/php74/99-chisimba-runtime-errors.ini "
    "/usr/local/etc/php/conf.d/99-chisimba-runtime-errors.ini",
)

dockerfile_path.write_text(dockerfile)

compose = compose_path.read_text()

compose, count = re.subn(
    r'^(\s*dockerfile:\s*).*$',
    r'\1docker/php82/Dockerfile',
    compose,
    count=1,
    flags=re.MULTILINE,
)

if count != 1:
    raise SystemExit(
        "Expected exactly one dockerfile entry in compose/php82.yml"
    )

compose_path.write_text(compose)
PY

echo "PHP 8.2 Docker profile:"
echo "  ${DOCKERFILE}"
echo
echo "PHP 8.2 configuration:"
echo "  ${PHP_INI_TARGET}"
echo

docker compose -f "${COMPOSE}" config >/dev/null

echo "Compose configuration is valid."

section "Assemble fresh PHP 8.2 runtime from repositories"

if [[ -e "${RUNTIME}" ]]; then
    echo "Removing previous disposable PHP 8.2 runtime..."
    chmod -R u+rwX "${RUNTIME}" 2>/dev/null || true
    rm -rf "${RUNTIME}"
fi

mkdir -p "${RUNTIME}"

echo "Copying framework..."
cp -a "${FRAMEWORK}/." "${RUNTIME}/"

echo "Replacing package and canvas placeholders..."
rm -rf "${RUNTIME}/packages" "${RUNTIME}/canvases"
mkdir -p "${RUNTIME}/packages" "${RUNTIME}/canvases"

echo "Copying modules..."
cp -a "${MODULES}/." "${RUNTIME}/packages/"

echo "Copying canvases..."
cp -a "${CANVASES}/." "${RUNTIME}/canvases/"

echo "Ensuring this is a fresh installer runtime..."
rm -f \
    "${RUNTIME}/config/installdone.txt" \
    "${RUNTIME}/tmpinstallfile"

mkdir -p \
    "${RUNTIME}/config" \
    "${RUNTIME}/error_log" \
    "${RUNTIME}/error_logs" \
    "${RUNTIME}/usrfiles" \
    "${RUNTIME}/user_images"

chmod -R a+rwX "${RUNTIME}"

echo
echo "Runtime assembled from:"
echo "  ${FRAMEWORK}"
echo "  ${MODULES}"
echo "  ${CANVASES}"

section "Verify PHP 7.4 baseline remains untouched"

[[ -d "${DEV}/runtime/php74-ch" ]] ||
    fail "PHP 7.4 reference runtime is unexpectedly missing."

[[ -f "${DEV}/compose/php74.yml" ]] ||
    fail "PHP 7.4 Compose file is unexpectedly missing."

echo "PHP 7.4 runtime remains present."
echo "PHP 7.4 containers will not be stopped or modified."

section "Build PHP 8.2 image"

docker compose \
    -f "${COMPOSE}" \
    build --no-cache web

section "Start PHP 8.2 database and web containers"

docker compose \
    -f "${COMPOSE}" \
    up -d

section "Container status"

docker compose \
    -f "${COMPOSE}" \
    ps -a

section "Verify PHP version and extensions"

docker compose \
    -f "${COMPOSE}" \
    exec -T web \
    php -v

echo

docker compose \
    -f "${COMPOSE}" \
    exec -T web \
    php -m \
    | grep -E \
        '^(gd|libxml|mbstring|mysqli|xml|xmlreader|xmlwriter|zip)$' \
    | sort \
    || true

section "Request the installer entry point"

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

section "First PHP 8.2 failure evidence"

echo "--- Apache/PHP container log ---"

docker compose \
    -f "${COMPOSE}" \
    logs --no-color --tail=250 web \
    || true

echo
echo "--- Chisimba runtime error files ---"

find "${RUNTIME}" \
    -maxdepth 3 \
    -type f \
    \( \
        -iname '*error*' -o \
        -iname '*.log' \
    \) \
    -print \
    2>/dev/null \
    | sort \
    | while IFS= read -r error_file; do
        echo
        echo "FILE: ${error_file}"
        tail -n 100 "${error_file}" 2>/dev/null || true
    done

echo
echo "--- Fatal and parse-error extraction ---"

{
    docker compose \
        -f "${COMPOSE}" \
        logs --no-color web \
        2>/dev/null

    find "${RUNTIME}" \
        -maxdepth 3 \
        -type f \
        \( -iname '*error*' -o -iname '*.log' \) \
        -exec cat {} + \
        2>/dev/null
} \
    | grep -Ei \
        'fatal error|parse error|uncaught|compile error|typeerror|valueerror' \
    | head -n 20 \
    || echo "No fatal-pattern line was detected automatically."

section "Git status"

git -C "${DEV}" status --short

section "Milestone 8 first PHP 8.2 boot completed"

echo "Finished: $(date --iso-8601=seconds)"
echo
echo "PHP 8.2 URL:"
echo "  http://localhost:8082/ch/"
echo
echo "The PHP 8.2 runtime and database were created fresh."
echo "The PHP 7.4 reference runtime was not altered."
echo
echo "Upload this file:"
echo "  ${LOG}"
