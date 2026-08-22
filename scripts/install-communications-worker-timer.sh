#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
unit_source="$repo_root/systemd/user"
unit_target="$HOME/.config/systemd/user"

install -d "$unit_target"
install -m 0644 "$unit_source/chisimba-communications-worker.service" "$unit_target/"
install -m 0644 "$unit_source/chisimba-communications-worker.timer" "$unit_target/"
systemctl --user daemon-reload
systemctl --user enable --now chisimba-communications-worker.timer
systemctl --user --no-pager status chisimba-communications-worker.timer
