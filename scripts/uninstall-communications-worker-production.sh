#!/usr/bin/env bash
set -euo pipefail

if (( EUID != 0 )); then
    echo "Run this uninstaller with sudo." >&2
    exit 77
fi

systemctl disable --now chisimba-communications-worker.timer 2>/dev/null || true
rm -f /etc/systemd/system/chisimba-communications-worker.timer
rm -f /etc/systemd/system/chisimba-communications-worker.service
rm -f /usr/local/libexec/chisimba-communications-worker
rm -f /etc/chisimba/communications-worker.conf
systemctl daemon-reload
echo "Chisimba Communications worker removed. /etc/chisimba was retained."
