#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bash -n "$repo_root/scripts/install-ai-worker-production.sh"
bash -n "$repo_root/scripts/chisimba-ai-worker"
"$repo_root/scripts/install-ai-worker-production.sh" --help | grep -q -- '--container NAME'
grep -q 'CHISIMBA_AI_WORKER_CONFIG=/etc/chisimba/ai-worker.conf' "$repo_root/systemd/system/chisimba-ai-worker.service"
grep -q 'OnUnitActiveSec=10s' "$repo_root/systemd/system/chisimba-ai-worker.timer"
grep -q 'run_chapter_quiz_worker.php' "$repo_root/scripts/chisimba-ai-worker"
echo "OK: production AI worker contract"
