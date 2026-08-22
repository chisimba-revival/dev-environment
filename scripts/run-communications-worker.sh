#!/usr/bin/env bash
set -euo pipefail

container_name="chisimba-php85-web"
worker_path="/var/www/html/ch/core_modules/communications/scripts/run_outbox_worker.php"
batch_size="${1:-20}"

if [[ ! "$batch_size" =~ ^[0-9]+$ ]] || (( batch_size < 1 || batch_size > 100 )); then
    echo "Batch size must be an integer from 1 to 100." >&2
    exit 64
fi

if [[ "$(docker inspect --format '{{.State.Running}}' "$container_name" 2>/dev/null || true)" != "true" ]]; then
    echo "Communications worker skipped: $container_name is not running."
    exit 0
fi

exec flock --nonblock /tmp/chisimba-communications-worker.lock \
    docker exec "$container_name" php "$worker_path" "$batch_size"
