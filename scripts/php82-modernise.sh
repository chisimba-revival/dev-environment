#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="/run/media/derek/main/chisimba-revival"
DEV="${ROOT}/dev-environment"

MODE="${1:---apply}"

case "${MODE}" in
    --apply|--dry-run)
        ;;
    *)
        echo "Usage: $0 [--apply|--dry-run]" >&2
        exit 2
        ;;
esac

php \
    "${DEV}/tools/php-moderniser/modernise-removed-magic-quotes.php" \
    "${MODE}" \
    "${ROOT}/framework/app"
