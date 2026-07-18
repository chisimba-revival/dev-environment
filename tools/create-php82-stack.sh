#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="/run/media/derek/main/chisimba-revival"
DEV_ENV="${ROOT}/dev-environment"
LOG="${ROOT}/killme.txt"

PHP74_COMPOSE="${DEV_ENV}/compose/php74.yml"
PHP82_COMPOSE="${DEV_ENV}/compose/php82.yml"

BACKUP_ROOT="${DEV_ENV}/backups/php82-stack-creation"
TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
BACKUP_DIR="${BACKUP_ROOT}/${TIMESTAMP}"

exec > >(tee "${LOG}") 2>&1

echo "============================================================"
echo "Milestone 8: Create isolated PHP 8.2 Docker configuration"
echo "Started: $(date --iso-8601=seconds)"
echo "============================================================"
echo

fail()
{
    echo
    echo "ERROR: $*" >&2
    exit 1
}

find_php74_dockerfile()
{
    local compose_dir
    local dockerfile_reference
    local candidate

    compose_dir="$(dirname "${PHP74_COMPOSE}")"

    # First try to identify an explicit Dockerfile entry in Compose.
    dockerfile_reference="$(
        awk '
            /^[[:space:]]*dockerfile:[[:space:]]*/ {
                sub(/^[[:space:]]*dockerfile:[[:space:]]*/, "")
                gsub(/["'\''"]/, "")
                print
                exit
            }
        ' "${PHP74_COMPOSE}"
    )"

    if [[ -n "${dockerfile_reference}" ]]; then
        if [[ "${dockerfile_reference}" = /* ]]; then
            candidate="${dockerfile_reference}"
        else
            candidate="${compose_dir}/${dockerfile_reference}"
        fi

        if [[ -f "${candidate}" ]]; then
            realpath "${candidate}"
            return 0
        fi
    fi

    # Fall back to likely PHP 7.4 Dockerfile names.
    while IFS= read -r candidate; do
        if [[ -f "${candidate}" ]]; then
            realpath "${candidate}"
            return 0
        fi
    done < <(
        find "${DEV_ENV}" \
            -maxdepth 4 \
            -type f \
            \( \
                -iname 'Dockerfile.php74' -o \
                -iname 'Dockerfile-php74' -o \
                -iname 'php74.Dockerfile' -o \
                -ipath '*php74*/Dockerfile' \
            \) \
            | sort
    )

    return 1
}

replace_checked()
{
    local file="$1"
    local old="$2"
    local new="$3"
    local description="$4"

    if grep -Fq "${old}" "${file}"; then
        sed -i "s|${old}|${new}|g" "${file}"
        echo "Changed ${description}:"
        echo "  ${old}"
        echo "  -> ${new}"
    else
        echo "No '${old}' reference found for ${description}; no change made."
    fi
}

[[ -d "${ROOT}" ]] ||
    fail "Project root does not exist: ${ROOT}"

[[ -d "${DEV_ENV}" ]] ||
    fail "Development environment repository does not exist: ${DEV_ENV}"

[[ -f "${PHP74_COMPOSE}" ]] ||
    fail "PHP 7.4 Compose file not found: ${PHP74_COMPOSE}"

PHP74_DOCKERFILE="$(find_php74_dockerfile)" ||
    fail "Could not identify the Dockerfile used by the PHP 7.4 stack."

PHP74_DOCKERFILE_DIR="$(dirname "${PHP74_DOCKERFILE}")"
PHP74_DOCKERFILE_NAME="$(basename "${PHP74_DOCKERFILE}")"

case "${PHP74_DOCKERFILE_NAME}" in
    *php74*)
        PHP82_DOCKERFILE_NAME="${PHP74_DOCKERFILE_NAME//php74/php82}"
        ;;
    *PHP74*)
        PHP82_DOCKERFILE_NAME="${PHP74_DOCKERFILE_NAME//PHP74/PHP82}"
        ;;
    Dockerfile)
        # Keep the new Dockerfile alongside the old one, but do not overwrite it.
        PHP82_DOCKERFILE_NAME="Dockerfile.php82"
        ;;
    *)
        PHP82_DOCKERFILE_NAME="${PHP74_DOCKERFILE_NAME}.php82"
        ;;
esac

PHP82_DOCKERFILE="${PHP74_DOCKERFILE_DIR}/${PHP82_DOCKERFILE_NAME}"

echo "PHP 7.4 Compose file:"
echo "  ${PHP74_COMPOSE}"
echo
echo "PHP 7.4 Dockerfile:"
echo "  ${PHP74_DOCKERFILE}"
echo
echo "PHP 8.2 Compose file to create:"
echo "  ${PHP82_COMPOSE}"
echo
echo "PHP 8.2 Dockerfile to create:"
echo "  ${PHP82_DOCKERFILE}"
echo

mkdir -p "${BACKUP_DIR}"

if [[ -e "${PHP82_COMPOSE}" ]]; then
    cp -a "${PHP82_COMPOSE}" "${BACKUP_DIR}/"
    echo "Backed up existing PHP 8.2 Compose file."
fi

if [[ -e "${PHP82_DOCKERFILE}" ]]; then
    cp -a "${PHP82_DOCKERFILE}" "${BACKUP_DIR}/"
    echo "Backed up existing PHP 8.2 Dockerfile."
fi

cp -a "${PHP74_COMPOSE}" "${PHP82_COMPOSE}"
cp -a "${PHP74_DOCKERFILE}" "${PHP82_DOCKERFILE}"

echo
echo "Copied PHP 7.4 configuration to isolated PHP 8.2 files."
echo

# Update ordinary stack identifiers.
replace_checked "${PHP82_COMPOSE}" \
    "php74" \
    "php82" \
    "lowercase stack identifiers"

replace_checked "${PHP82_COMPOSE}" \
    "PHP74" \
    "PHP82" \
    "uppercase stack identifiers"

# Preserve the PHP 7.4 service on port 8081 and use 8082 for PHP 8.2.
replace_checked "${PHP82_COMPOSE}" \
    "8081:80" \
    "8082:80" \
    "host HTTP port"

replace_checked "${PHP82_COMPOSE}" \
    "\"8081:80\"" \
    "\"8082:80\"" \
    "quoted host HTTP port"

replace_checked "${PHP82_COMPOSE}" \
    "'8081:80'" \
    "'8082:80'" \
    "single-quoted host HTTP port"

# Point Compose to the copied PHP 8.2 Dockerfile.
if grep -Eq '^[[:space:]]*dockerfile:[[:space:]]*' "${PHP82_COMPOSE}"; then
    python3 - "${PHP82_COMPOSE}" "${PHP82_DOCKERFILE_NAME}" <<'PY'
from pathlib import Path
import re
import sys

compose_path = Path(sys.argv[1])
dockerfile_name = sys.argv[2]

text = compose_path.read_text()

updated, count = re.subn(
    r'^(\s*dockerfile:\s*).*$',
    lambda match: f'{match.group(1)}{dockerfile_name}',
    text,
    count=1,
    flags=re.MULTILINE,
)

if count != 1:
    raise SystemExit(
        "Expected exactly one dockerfile entry in the Compose file."
    )

compose_path.write_text(updated)
PY
else
    fail "The copied Compose file has no explicit dockerfile entry."
fi

# Update the PHP base image only where it is clearly identified.
python3 - "${PHP82_DOCKERFILE}" <<'PY'
from pathlib import Path
import re
import sys

dockerfile_path = Path(sys.argv[1])
text = dockerfile_path.read_text()

patterns = [
    (
        r'(?im)^FROM\s+php:7\.4(?:\.\d+)?-apache(?:\s+AS\s+\S+)?\s*$',
        'FROM php:8.2-apache',
    ),
    (
        r'(?im)^FROM\s+php:7\.4(?:\.\d+)?(?:\s+AS\s+\S+)?\s*$',
        'FROM php:8.2',
    ),
]

for pattern, replacement in patterns:
    updated, count = re.subn(pattern, replacement, text, count=1)
    if count == 1:
        dockerfile_path.write_text(updated)
        print(f"Updated PHP base image in {dockerfile_path}")
        break
else:
    raise SystemExit(
        "Could not find a recognised PHP 7.4 FROM instruction. "
        "The copied Dockerfile was left otherwise unchanged."
    )
PY

echo
echo "Checking generated Compose configuration..."
docker compose -f "${PHP82_COMPOSE}" config >/dev/null

echo "Compose syntax is valid."
echo

echo "PHP-related lines in the new Dockerfile:"
grep -nE \
    '^(FROM|RUN).*php|docker-php-ext|apt-get|pecl|libxml|libzip|libjpeg|libpng|libfreetype|libonig' \
    "${PHP82_DOCKERFILE}" \
    || true

echo
echo "Generated Compose service summary:"
docker compose -f "${PHP82_COMPOSE}" config --services

echo
echo "Generated container and port references:"
grep -nE \
    'container_name:|ports:|8082|php82|PHP82|dockerfile:' \
    "${PHP82_COMPOSE}" \
    || true

echo
echo "Git status:"
git -C "${DEV_ENV}" status --short

echo
echo "============================================================"
echo "PHP 8.2 Docker configuration created successfully."
echo
echo "Compose:"
echo "  ${PHP82_COMPOSE}"
echo
echo "Dockerfile:"
echo "  ${PHP82_DOCKERFILE}"
echo
echo "No image has been built and no container has been started."
echo "PHP 7.4 files have not been modified."
echo "Finished: $(date --iso-8601=seconds)"
echo "============================================================"
