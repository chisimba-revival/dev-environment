#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
runner="$root/scripts/run-communications-worker.sh"
service="$root/systemd/user/chisimba-communications-worker.service"
timer="$root/systemd/user/chisimba-communications-worker.timer"

grep -Fq 'communications/scripts/run_outbox_worker.php' "$runner"
grep -Fq 'flock --nonblock' "$runner"
grep -Fq 'chisimba-php85-web' "$runner"
grep -Fq 'Type=oneshot' "$service"
grep -Fq 'OnUnitActiveSec=1min' "$timer"
grep -Fq 'Persistent=true' "$timer"
echo 'OK: communications systemd worker contract'
