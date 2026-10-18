#!/usr/bin/env bash
# Start the existing PHP 8.5 site with the local shared-API development overlay.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test -f "$root/../work/rest-api-review-20261018/app/core_modules/restapi/controller.php"
test -f "$root/../private-storage/php85/restapi.env"
docker compose -f "$root/compose/php85.yml" -f "$root/compose/php85-restapi.yml" up -d --no-build
# nginx resolves the web container when starting; refresh it after recreation.
docker compose -f "$root/compose/php85.yml" -f "$root/compose/php85-restapi.yml" restart nginx
