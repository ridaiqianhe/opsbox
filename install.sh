#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

if (( EUID != 0 )); then
    echo "Run this installer as root so it can persist the required IPv6 sysctl." >&2
    exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
    echo "Docker Engine is required." >&2
    exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
    echo "Docker Compose v2 is required." >&2
    exit 1
fi

if [[ ! -f .env ]]; then
    cp .env.example .env
    echo "Created .env. Set the port, username, and password, then run ./install.sh again." >&2
    exit 1
fi

if grep -Eq '^SOCKS_(USERNAME|PASSWORD)=change-me' .env; then
    echo "Refusing to start with placeholder credentials in .env." >&2
    exit 1
fi

chmod 0600 .env
mkdir -p data/logs
chmod 0700 data data/logs

sysctl_file=$(mktemp)
logrotate_file=$(mktemp)
trap 'rm -f "$sysctl_file" "$logrotate_file"' EXIT
printf '%s\n' 'net.ipv6.ip_nonlocal_bind = 1' > "$sysctl_file"
install -m 0644 -o root -g root "$sysctl_file" /etc/sysctl.d/99-random-ipv6-socks.conf
sysctl -w net.ipv6.ip_nonlocal_bind=1 >/dev/null

if command -v logrotate >/dev/null 2>&1; then
    printf '%s\n' \
        "\"$PWD/data/logs/*.log\" {" \
        '    daily' \
        '    rotate 14' \
        '    compress' \
        '    delaycompress' \
        '    missingok' \
        '    notifempty' \
        '    copytruncate' \
        '    su root root' \
        '}' > "$logrotate_file"
    install -m 0644 -o root -g root "$logrotate_file" /etc/logrotate.d/random-ipv6-socks
fi

docker compose config --quiet
docker compose up -d --build

for _ in $(seq 1 45); do
    status=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' random-ipv6-socks 2>/dev/null || true)
    case "$status" in
        healthy|running)
            docker compose ps
            exit 0
            ;;
        unhealthy|exited|dead)
            docker compose logs --tail=100
            exit 1
            ;;
    esac
    sleep 2
done

docker compose logs --tail=100
echo "Container did not become healthy in time." >&2
exit 1
