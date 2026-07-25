#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="/run/media/derek/main/chisimba-revival"
DEV="${ROOT}/dev-environment"

PROFILE="${1:-}"
MODE="${2:---preserve-db}"

usage()
{
    echo "Usage:"
    echo "  $0 php74 [--preserve-db|--fresh-db]"
    echo "  $0 php82 [--preserve-db|--fresh-db]"
}

case "${PROFILE}" in
    php74|php82)
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac

case "${MODE}" in
    --preserve-db|--fresh-db)
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac

COMPOSE="${DEV}/compose/${PROFILE}.yml"
RUNTIME="${DEV}/runtime/${PROFILE}-ch"
PRESERVED_INSTALLDONE=""

FRAMEWORK="${ROOT}/framework/app"
MODULES="${ROOT}/modules"
CANVASES="${ROOT}/canvases"

for required in \
    "${COMPOSE}" \
    "${FRAMEWORK}" \
    "${MODULES}" \
    "${CANVASES}"
do
    if [[ ! -e "${required}" ]]; then
        echo "ERROR: Missing required path: ${required}" >&2
        exit 1
    fi
done

echo "============================================================"
echo "Rebuild Chisimba runtime"
echo "Profile: ${PROFILE}"
echo "Mode: ${MODE}"
echo "Runtime: ${RUNTIME}"
echo "============================================================"

if [[ "${MODE}" == "--fresh-db" ]]; then
    echo "Stopping stack and deleting only the ${PROFILE} volumes..."

    docker compose \
        -f "${COMPOSE}" \
        down -v --remove-orphans
else
    echo "Stopping ${PROFILE} web container..."

    docker compose \
        -f "${COMPOSE}" \
        stop web \
        || true

    if [[ -f "${RUNTIME}/config/installdone.txt" ]]; then
        PRESERVED_INSTALLDONE="$(mktemp)"
        cp -a "${RUNTIME}/config/installdone.txt" "${PRESERVED_INSTALLDONE}"
        echo "Preserving installer completion state..."
    else
        echo "WARNING: No existing installdone.txt was found to preserve."
    fi
fi

echo "Removing disposable runtime..."

if [[ -e "${RUNTIME}" ]]; then
    chmod -R u+rwX "${RUNTIME}" 2>/dev/null || true
    rm -rf "${RUNTIME}"
fi

mkdir -p "${RUNTIME}"

echo "Copying framework..."
cp -a "${FRAMEWORK}/." "${RUNTIME}/"

echo "Copying modules..."
rm -rf "${RUNTIME}/packages"
mkdir -p "${RUNTIME}/packages"
cp -a "${MODULES}/." "${RUNTIME}/packages/"

echo "Copying canvases..."
rm -rf "${RUNTIME}/canvases"
mkdir -p "${RUNTIME}/canvases"
cp -a "${CANVASES}/." "${RUNTIME}/canvases/"

if [[ "${MODE}" == "--fresh-db" ]]; then
    echo "Removing installer completion state for fresh database..."
    rm -f \
        "${RUNTIME}/config/installdone.txt" \
        "${RUNTIME}/tmpinstallfile"
elif [[ -n "${PRESERVED_INSTALLDONE}" ]]; then
    echo "Restoring installer completion state..."
    mkdir -p "${RUNTIME}/config"
    cp -a "${PRESERVED_INSTALLDONE}" "${RUNTIME}/config/installdone.txt"
    rm -f "${PRESERVED_INSTALLDONE}"
fi

mkdir -p \
    "${RUNTIME}/config" \
    "${RUNTIME}/error_log" \
    "${RUNTIME}/error_logs" \
    "${RUNTIME}/usrfiles" \
    "${RUNTIME}/user_images"

chmod -R a+rwX "${RUNTIME}"

echo "Starting ${PROFILE} stack..."

docker compose \
    -f "${COMPOSE}" \
    up -d

echo
docker compose \
    -f "${COMPOSE}" \
    ps -a

echo
echo "Runtime rebuild complete."
