#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

if [[ "${1:-}" == "--purge" ]] && (( EUID != 0 )); then
    echo "Run with sudo when using --purge." >&2
    exit 1
fi

docker compose down --remove-orphans

if [[ "${1:-}" == "--purge" ]]; then
    rm -rf data
    rm -f /etc/sysctl.d/99-random-ipv6-socks.conf
    rm -f /etc/logrotate.d/random-ipv6-socks
fi
