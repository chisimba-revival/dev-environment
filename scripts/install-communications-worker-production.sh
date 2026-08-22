#!/usr/bin/env bash
set -euo pipefail

container_name="chisimba-web"
worker_path="/var/www/html/ch/core_modules/communications/scripts/run_outbox_worker.php"
batch_size="20"
interval="1min"
docker_binary="$(command -v docker || true)"

usage() {
    cat <<'EOF'
Usage: sudo ./scripts/install-communications-worker-production.sh [options]

Options:
  --container NAME       PHP web container name (default: chisimba-web)
  --worker-path PATH     Worker path inside the container
  --batch-size NUMBER    Messages per run, 1-100 (default: 20)
  --interval DURATION    systemd duration such as 30s, 1min, or 5min
  --docker PATH          Docker executable (auto-detected by default)
  --help                 Show this help
EOF
}

while (( $# > 0 )); do
    case "$1" in
        --container) container_name="${2:?Missing value for --container}"; shift 2 ;;
        --worker-path) worker_path="${2:?Missing value for --worker-path}"; shift 2 ;;
        --batch-size) batch_size="${2:?Missing value for --batch-size}"; shift 2 ;;
        --interval) interval="${2:?Missing value for --interval}"; shift 2 ;;
        --docker) docker_binary="${2:?Missing value for --docker}"; shift 2 ;;
        --help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 64 ;;
    esac
done

if (( EUID != 0 )); then
    echo "Run this installer with sudo." >&2
    exit 77
fi
if [[ ! "$batch_size" =~ ^[0-9]+$ ]] || (( batch_size < 1 || batch_size > 100 )); then
    echo "Batch size must be an integer from 1 to 100." >&2
    exit 64
fi
if [[ ! "$interval" =~ ^[1-9][0-9]*(s|min|h)$ ]]; then
    echo "Interval must be a positive systemd duration such as 30s, 1min, or 5min." >&2
    exit 64
fi
if [[ -z "$docker_binary" || ! -x "$docker_binary" ]]; then
    echo "Docker executable not found; pass --docker /absolute/path/to/docker." >&2
    exit 69
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
unit_source="$repo_root/systemd/system"

install -d -m 0755 /etc/chisimba /usr/local/libexec /etc/systemd/system
install -m 0755 "$repo_root/scripts/chisimba-communications-worker" /usr/local/libexec/
install -m 0644 "$unit_source/chisimba-communications-worker.service" /etc/systemd/system/
sed "s/OnUnitActiveSec=1min/OnUnitActiveSec=$interval/" \
    "$unit_source/chisimba-communications-worker.timer" \
    > /etc/systemd/system/chisimba-communications-worker.timer
chmod 0644 /etc/systemd/system/chisimba-communications-worker.timer

printf 'CHISIMBA_CONTAINER_NAME=%q\n' "$container_name" > /etc/chisimba/communications-worker.conf
printf 'CHISIMBA_WORKER_PATH=%q\n' "$worker_path" >> /etc/chisimba/communications-worker.conf
printf 'CHISIMBA_BATCH_SIZE=%q\n' "$batch_size" >> /etc/chisimba/communications-worker.conf
printf 'CHISIMBA_DOCKER_BINARY=%q\n' "$docker_binary" >> /etc/chisimba/communications-worker.conf
chmod 0600 /etc/chisimba/communications-worker.conf

systemctl daemon-reload
systemctl enable --now chisimba-communications-worker.timer
systemctl start chisimba-communications-worker.service
systemctl --no-pager status chisimba-communications-worker.timer

echo "Installed. Check deliveries with: journalctl -u chisimba-communications-worker.service"
