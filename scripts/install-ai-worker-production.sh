#!/usr/bin/env bash
set -euo pipefail

container_name="chisimba-web"
worker_path="/var/www/html/ch/modules/mcqtests/scripts/run_chapter_quiz_worker.php"
interval="10s"
docker_binary="$(command -v docker || true)"

usage() {
    cat <<'EOF'
Usage: sudo ./scripts/install-ai-worker-production.sh [options]

Options:
  --container NAME       PHP web container name (default: chisimba-web)
  --worker-path PATH     Worker path inside the container
  --interval DURATION    systemd duration such as 10s, 30s, or 1min
  --docker PATH          Docker executable (auto-detected by default)
  --help                 Show this help
EOF
}

while (( $# > 0 )); do
    case "$1" in
        --container) container_name="${2:?Missing value for --container}"; shift 2 ;;
        --worker-path) worker_path="${2:?Missing value for --worker-path}"; shift 2 ;;
        --interval) interval="${2:?Missing value for --interval}"; shift 2 ;;
        --docker) docker_binary="${2:?Missing value for --docker}"; shift 2 ;;
        --help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 64 ;;
    esac
done

if (( EUID != 0 )); then echo "Run this installer with sudo." >&2; exit 77; fi
if [[ ! "$interval" =~ ^[1-9][0-9]*(s|min|h)$ ]]; then
    echo "Interval must be a positive systemd duration such as 10s, 30s, or 1min." >&2; exit 64
fi
if [[ -z "$docker_binary" || ! -x "$docker_binary" ]]; then
    echo "Docker executable not found; pass --docker /absolute/path/to/docker." >&2; exit 69
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
unit_source="$repo_root/systemd/system"
install -d -m 0755 /etc/chisimba /usr/local/libexec /etc/systemd/system
install -m 0755 "$repo_root/scripts/chisimba-ai-worker" /usr/local/libexec/
install -m 0644 "$unit_source/chisimba-ai-worker.service" /etc/systemd/system/
sed "s/OnUnitActiveSec=10s/OnUnitActiveSec=$interval/" "$unit_source/chisimba-ai-worker.timer" > /etc/systemd/system/chisimba-ai-worker.timer
chmod 0644 /etc/systemd/system/chisimba-ai-worker.timer
printf 'CHISIMBA_CONTAINER_NAME=%q\n' "$container_name" > /etc/chisimba/ai-worker.conf
printf 'CHISIMBA_WORKER_PATH=%q\n' "$worker_path" >> /etc/chisimba/ai-worker.conf
printf 'CHISIMBA_DOCKER_BINARY=%q\n' "$docker_binary" >> /etc/chisimba/ai-worker.conf
chmod 0600 /etc/chisimba/ai-worker.conf
systemctl daemon-reload
systemctl enable --now chisimba-ai-worker.timer
systemctl start chisimba-ai-worker.service
systemctl --no-pager status chisimba-ai-worker.timer
