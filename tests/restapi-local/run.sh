#!/usr/bin/env bash
# Explicit local-only installed-site check. Never target a production container.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
for script in prepare permissions cleanup blog-inspect; do
    docker cp "$here/$script.php" "chisimba-php85-web:/tmp/restapi-$script.php"
done
docker exec -u www-data chisimba-php85-web php /tmp/restapi-prepare.php
cleanup() {
    docker exec -u www-data chisimba-php85-web php /tmp/restapi-permissions.php deactivate
    docker exec -u www-data chisimba-php85-web php /tmp/restapi-cleanup.php
}
trap cleanup EXIT
if [[ "${1:-auth}" == "blog" ]]; then
    python3 "$here/blog-check.py"
else
    python3 "$here/http-check.py"
fi
