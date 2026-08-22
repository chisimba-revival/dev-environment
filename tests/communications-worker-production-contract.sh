#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
installer="$repo_root/scripts/install-communications-worker-production.sh"
runner="$repo_root/scripts/chisimba-communications-worker"
service="$repo_root/systemd/system/chisimba-communications-worker.service"
timer="$repo_root/systemd/system/chisimba-communications-worker.timer"

bash -n "$installer"
bash -n "$runner"
bash -n "$repo_root/scripts/uninstall-communications-worker-production.sh"
"$installer" --help | grep -q -- '--container NAME'
grep -q 'Environment=CHISIMBA_COMMUNICATIONS_CONFIG=/etc/chisimba/communications-worker.conf' "$service"
grep -q 'ExecStart=/usr/local/libexec/chisimba-communications-worker' "$service"
grep -q 'OnUnitActiveSec=1min' "$timer"
grep -q 'CHISIMBA_CONTAINER_NAME' "$runner"
grep -q 'docker.service' "$service"

echo "OK: production communications worker contract"
