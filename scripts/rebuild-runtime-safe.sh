#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
    echo "Usage: sudo -E $0 php82|php85 --preserve-db|--fresh-db" >&2
}

[[ $# -eq 2 ]] || { usage; exit 64; }
environment=$1
mode=$2
[[ $environment == php82 || $environment == php85 ]] || { echo "ERROR: supported runtimes are php82 and php85" >&2; exit 65; }
[[ $mode == --preserve-db || $mode == --fresh-db ]] || { usage; exit 66; }
[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo "ERROR: run with sudo" >&2; exit 67; }
[[ -n ${SUDO_USER:-} && ${SUDO_USER} != root ]] || {
    echo "ERROR: invoke with sudo from the repository owner's account" >&2
    exit 68
}

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
dev_dir=$(cd -- "$script_dir/.." && pwd)
runtime="$dev_dir/runtime/${environment}-ch"
usrfiles="$runtime/usrfiles"
compose="$dev_dir/compose/${environment}.yml"
assembler="$script_dir/rebuild-runtime.sh"
lock="$dev_dir/.rebuild-runtime-safe.lock"
archive_dir=$(mktemp -d "${TMPDIR:-/tmp}/chisimba-usrfiles.XXXXXX")
archive="$archive_dir/usrfiles.tar"
config_archive="$archive_dir/config.tar"
had_usrfiles=0
had_config=0
rebuild_ok=0

cleanup() {
    status=$?
    set +e

    # A failed rebuild must put the pre-existing application data back.
    # A successful preserve-db rebuild merges it back with numeric ownership intact.
    if [[ $had_usrfiles -eq 1 && ( $rebuild_ok -eq 0 || $mode == --preserve-db ) ]]; then
        mkdir -p "$runtime"
        rm -rf -- "$usrfiles"
        tar --numeric-owner -xpf "$archive" -C "$runtime"
        echo "PERSISTENT_DATA_RESTORED=yes"
    elif [[ $had_usrfiles -eq 1 ]]; then
        echo "PERSISTENT_DATA_DISCARDED_FOR_FRESH_DB=yes"
    fi

    if [[ $mode == --preserve-db && $had_config -eq 1 ]]; then
        rm -rf -- "$runtime/config"
        tar --numeric-owner -xpf "$config_archive" -C "$runtime"
        echo "PERSISTENT_CONFIG_RESTORED=yes"
    fi

    if [[ $rebuild_ok -eq 0 ]]; then
        docker compose -f "$compose" up -d || true
        echo "STACK_RESTART_ATTEMPTED_AFTER_FAILURE=yes"
    fi

    rm -rf -- "$archive_dir"
    exit "$status"
}
trap cleanup EXIT INT TERM

exec 9>"$lock"
flock -n 9 || { echo "ERROR: another safe rebuild is already running" >&2; exit 69; }

[[ -x "$assembler" ]] || { echo "ERROR: assembler missing: $assembler" >&2; exit 70; }
[[ -f "$compose" ]] || { echo "ERROR: compose file missing: $compose" >&2; exit 71; }

if [[ $mode == --preserve-db && -d "$runtime/config" ]]; then
    tar --numeric-owner -cpf "$config_archive" -C "$runtime" config
    chmod -R a+rX "$runtime/config"
    had_config=1
    echo "PERSISTENT_CONFIG_CAPTURED=yes"
fi

echo "Stopping ${environment} stack before moving application-owned data"
docker compose -f "$compose" down

if [[ -d "$usrfiles" ]]; then
    tar --numeric-owner -cpf "$archive" -C "$runtime" usrfiles
    rm -rf -- "$usrfiles"
    had_usrfiles=1
    echo "PERSISTENT_DATA_CAPTURED=yes"
else
    echo "PERSISTENT_DATA_CAPTURED=none"
fi

echo "Running repository assembler as $SUDO_USER: $environment $mode"
sudo -u "$SUDO_USER" -- "$assembler" "$environment" "$mode"
rebuild_ok=1

echo "SAFE_REBUILD_RESULT=PASS"
