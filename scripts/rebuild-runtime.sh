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
PRESERVED_STATE_DIR=""

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
    mapfile -t compose_services < <(
        docker compose -f "${COMPOSE}" config --services
    )

    for required_service in web db
    do
        if ! printf '%s\n' "${compose_services[@]}" \
            | grep -Fxq "${required_service}"
        then
            echo "ERROR: ${COMPOSE} does not define service ${required_service}." >&2
            exit 1
        fi
    done

    echo "Validated services: web, db"
    echo "Compose-managed ${PROFILE} volumes scheduled for deletion:"
    docker compose -f "${COMPOSE}" config --volumes \
        | sed 's/^/  - /'
    echo
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

    for required_state in         "${RUNTIME}/config/installdone.txt"         "${RUNTIME}/config/dbdetails_inc.php"         "${RUNTIME}/config/config.xml"
    do
        if [[ ! -f "${required_state}" ]]; then
            echo "ERROR: Cannot preserve the installed state."
            echo "Missing: ${required_state}"
            echo "The runtime has not been removed."
            exit 1
        fi
    done

    PRESERVED_STATE_DIR="$(mktemp -d)"
    cp -a "${RUNTIME}/config" "${PRESERVED_STATE_DIR}/config"
    echo "Preserving complete installed configuration state..."
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
elif [[ -n "${PRESERVED_STATE_DIR}" ]]; then
    echo "Restoring complete installed configuration state..."
    rm -rf "${RUNTIME}/config"
    cp -a "${PRESERVED_STATE_DIR}/config" "${RUNTIME}/config"
    rm -rf "${PRESERVED_STATE_DIR}"
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

if [[ "${MODE}" == "--fresh-db" ]]; then
    echo
    echo "Fresh-database post-rebuild verification..."

    if [[ -e "${RUNTIME}/config/installdone.txt" ]]; then
        echo "ERROR: installdone.txt remains after the fresh reset." >&2
        exit 1
    fi

    if [[ -e "${RUNTIME}/tmpinstallfile" ]]; then
        echo "ERROR: tmpinstallfile remains after the fresh reset." >&2
        exit 1
    fi

    mapfile -t running_services < <(
        docker compose -f "${COMPOSE}" ps \
            --services \
            --filter status=running
    )

    for required_service in web db
    do
        if ! printf '%s\n' "${running_services[@]}" \
            | grep -Fxq "${required_service}"
        then
            echo "ERROR: ${required_service} is not running after rebuild." >&2
            exit 1
        fi
    done

    echo "Verified: web and db are running."
    echo "Verified: installer completion markers are absent."
fi

echo
echo "Runtime rebuild complete."
