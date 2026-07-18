#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="/run/media/derek/main/chisimba-revival"
DEV_ENV="${ROOT}/dev-environment"
LOG="${ROOT}/killme.txt"

exec >"${LOG}" 2>&1

section()
{
    echo
    echo "============================================================"
    echo "$1"
    echo "============================================================"
}

section "Milestone 8: Inspect existing PHP 7.4 runtime assembly process"

echo "Started: $(date --iso-8601=seconds)"
echo
echo "Project root: ${ROOT}"
echo "Development environment: ${DEV_ENV}"

section "Top-level development environment structure"

find "${DEV_ENV}" \
    -mindepth 1 \
    -maxdepth 2 \
    \( -path "${DEV_ENV}/runtime" -o -path "${DEV_ENV}/runtime/*" \) -prune \
    -o -printf '%y %p\n' \
    | sort

section "Executable shell and PHP tools"

find "${DEV_ENV}" \
    \( \
        -path "${DEV_ENV}/runtime" -o \
        -path "${DEV_ENV}/runtime/*" -o \
        -path "${DEV_ENV}/backups" -o \
        -path "${DEV_ENV}/backups/*" -o \
        -path '*/.git' -o \
        -path '*/.git/*' \
    \) -prune \
    -o \
    -type f \
    \( -name '*.sh' -o -name '*.php' -o -name 'Makefile' \) \
    -printf '%m %p\n' \
    | sort

section "Files referring to the PHP 7.4 runtime"

grep -RInE \
    --exclude-dir='.git' \
    --exclude-dir='runtime' \
    --exclude-dir='backups' \
    --exclude='killme.txt' \
    'runtime/php74-ch|php74-ch' \
    "${DEV_ENV}" \
    || true

section "Files referring to runtime assembly or rebuilding"

grep -RInE \
    --exclude-dir='.git' \
    --exclude-dir='runtime' \
    --exclude-dir='backups' \
    --exclude='killme.txt' \
    '(assemble|assembler|rebuild|build.runtime|runtime.*build|copy.*framework|rsync.*framework|modernise)' \
    "${DEV_ENV}/scripts" \
    "${DEV_ENV}/tools" \
    "${DEV_ENV}/README_RUNTIME.md" \
    2>/dev/null \
    || true

section "Scripts that reference all or some source repositories"

grep -RIlE \
    --exclude-dir='.git' \
    --exclude-dir='runtime' \
    --exclude-dir='backups' \
    '(framework|modules|canvases)' \
    "${DEV_ENV}/scripts" \
    "${DEV_ENV}/tools" \
    2>/dev/null \
    | sort \
    || true

section "Likely assembler scripts with relevant lines"

while IFS= read -r file; do
    [[ -f "${file}" ]] || continue

    echo
    echo "------------------------------------------------------------"
    echo "FILE: ${file}"
    echo "------------------------------------------------------------"

    grep -nE \
        '(framework|modules|canvases|runtime/php74-ch|php74-ch|rsync|cp -a|modernise|docker compose|installdone|database|volume)' \
        "${file}" \
        || true
done < <(
    grep -RIlE \
        --exclude-dir='.git' \
        --exclude-dir='runtime' \
        --exclude-dir='backups' \
        '(runtime/php74-ch|php74-ch|framework.*modules|modules.*framework|assemble|rebuild)' \
        "${DEV_ENV}/scripts" \
        "${DEV_ENV}/tools" \
        2>/dev/null \
        | sort
)

section "Runtime README"

if [[ -f "${DEV_ENV}/README_RUNTIME.md" ]]; then
    cat "${DEV_ENV}/README_RUNTIME.md"
else
    echo "README_RUNTIME.md was not found."
fi

section "PHP 7.4 Compose configuration"

cat "${DEV_ENV}/compose/php74.yml"

section "PHP 8.2 Compose configuration"

cat "${DEV_ENV}/compose/php82.yml"

section "PHP 7.4 Dockerfile"

cat "${DEV_ENV}/docker/php74/Dockerfile"

section "PHP 8.2 Dockerfile"

if [[ -f "${DEV_ENV}/docker/php74/Dockerfile.php82" ]]; then
    cat "${DEV_ENV}/docker/php74/Dockerfile.php82"
else
    echo "PHP 8.2 Dockerfile was not found."
fi

section "Current runtime directories"

find "${DEV_ENV}/runtime" \
    -mindepth 1 \
    -maxdepth 2 \
    -printf '%M %u:%g %p\n' \
    2>/dev/null \
    | sort \
    || true

section "Current containers"

docker compose \
    -f "${DEV_ENV}/compose/php74.yml" \
    ps -a \
    || true

echo

docker compose \
    -f "${DEV_ENV}/compose/php82.yml" \
    ps -a \
    || true

section "Git status"

git -C "${DEV_ENV}" status --short

section "Inspection complete"

echo "Finished: $(date --iso-8601=seconds)"
echo
echo "No runtime was changed."
echo "No image was built."
echo "No container was started."
echo
echo "Output written to:"
echo "${LOG}"
