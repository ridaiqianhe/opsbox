#!/usr/bin/env bash
set -Eeuo pipefail

log() {
    printf '[random-ipv6-socks] %s\n' "$*"
}

fail() {
    log "ERROR: $*" >&2
    exit 1
}

is_true() {
    case "${1,,}" in
        1|true|yes|on) return 0 ;;
        *) return 1 ;;
    esac
}

validate_credential() {
    local label="$1"
    local value="$2"
    local length
    length=$(LC_ALL=C printf '%s' "$value" | wc -c)
    (( length >= 1 && length <= 255 )) || fail "$label must be 1-255 bytes"
}

SOCKS_PORT="${SOCKS_PORT:-12345}"
SOCKS_USERNAME="${SOCKS_USERNAME:-}"
SOCKS_PASSWORD="${SOCKS_PASSWORD:-}"
SOCKS_LISTEN="${SOCKS_LISTEN:-0.0.0.0}"
SOCKS_UDP="${SOCKS_UDP:-true}"
SOCKS_UDP_ADVERTISE_IP="${SOCKS_UDP_ADVERTISE_IP:-}"
IPV6_INTERFACE="${IPV6_INTERFACE:-auto}"
IPV6_POOL="${IPV6_POOL:-}"
IPV6_POOL_PREFIX_LEN="${IPV6_POOL_PREFIX_LEN:-120}"
IPV6_POOL_SEED="${IPV6_POOL_SEED:-random-ipv6-socks}"
ALLOW_LARGE_IPV6_POOL="${ALLOW_LARGE_IPV6_POOL:-false}"
XRAY_LOG_LEVEL="${XRAY_LOG_LEVEL:-warning}"

[[ "$SOCKS_PORT" =~ ^[0-9]+$ ]] || fail "SOCKS_PORT must be numeric"
(( SOCKS_PORT >= 1024 && SOCKS_PORT <= 65535 )) || fail "SOCKS_PORT must be between 1024 and 65535"
validate_credential "SOCKS_USERNAME" "$SOCKS_USERNAME"
validate_credential "SOCKS_PASSWORD" "$SOCKS_PASSWORD"

case "$XRAY_LOG_LEVEL" in
    debug|info|warning|error|none) ;;
    *) fail "XRAY_LOG_LEVEL must be debug, info, warning, error, or none" ;;
esac

if [[ "$IPV6_INTERFACE" == "auto" ]]; then
    for _ in $(seq 1 60); do
        IPV6_INTERFACE=$(ip -6 route show default | awk '$1 == "default" {for (i=1; i<=NF; i++) if ($i == "dev") {print $(i+1); exit}}')
        [[ -n "$IPV6_INTERFACE" ]] && break
        IPV6_INTERFACE="auto"
        sleep 2
    done
    [[ "$IPV6_INTERFACE" != "auto" ]] || fail "no default IPv6 interface found"
fi

ip link show dev "$IPV6_INTERFACE" >/dev/null 2>&1 || fail "interface $IPV6_INTERFACE does not exist"

pool_args=(
    --interface "$IPV6_INTERFACE"
    --pool "$IPV6_POOL"
    --prefix-len "$IPV6_POOL_PREFIX_LEN"
    --seed "$IPV6_POOL_SEED"
)
if is_true "$ALLOW_LARGE_IPV6_POOL"; then
    pool_args+=(--allow-large)
fi

pool_error=/tmp/select-pool.error
for _ in $(seq 1 60); do
    if IPV6_POOL=$(/usr/local/libexec/select_pool.py "${pool_args[@]}" 2>"$pool_error"); then
        break
    fi
    sleep 2
done
[[ -n "$IPV6_POOL" ]] || fail "$(cat "$pool_error")"

if [[ "$(sysctl -n net.ipv6.ip_nonlocal_bind 2>/dev/null || true)" != "1" ]]; then
    sysctl -w net.ipv6.ip_nonlocal_bind=1 >/dev/null 2>&1 \
        || fail "net.ipv6.ip_nonlocal_bind is disabled; run install.sh as root on the host"
fi

route_preexisting=false
if ip -6 route show table local \
    | grep -Fq "local $IPV6_POOL dev $IPV6_INTERFACE"; then
    route_preexisting=true
fi
ip -6 route replace local "$IPV6_POOL" dev "$IPV6_INTERFACE" table local

cat > /run/ndppd.conf <<EOF
route-ttl 30000

proxy $IPV6_INTERFACE {
    router no
    timeout 500
    ttl 30000

    rule $IPV6_POOL {
        static
    }
}
EOF

udp_json=false
if is_true "$SOCKS_UDP"; then
    udp_json=true
fi

jq -n \
    --arg access "/var/log/xray/access.log" \
    --arg error "/var/log/xray/error.log" \
    --arg loglevel "$XRAY_LOG_LEVEL" \
    --arg tag "socks5-in" \
    --arg listen "$SOCKS_LISTEN" \
    --argjson port "$SOCKS_PORT" \
    --arg username "$SOCKS_USERNAME" \
    --arg password "$SOCKS_PASSWORD" \
    --argjson udp "$udp_json" \
    --arg udp_ip "$SOCKS_UDP_ADVERTISE_IP" \
    --arg pool "$IPV6_POOL" \
    '{
        log: {
            access: $access,
            error: $error,
            loglevel: $loglevel
        },
        inbounds: [{
            tag: $tag,
            listen: $listen,
            port: $port,
            protocol: "socks",
            settings: ({
                auth: "password",
                accounts: [{user: $username, pass: $password}],
                udp: $udp
            } + (if $udp_ip == "" then {} else {ip: $udp_ip} end))
        }],
        outbounds: [{
            tag: "random-ipv6",
            protocol: "freedom",
            sendThrough: $pool,
            settings: {domainStrategy: "UseIP"}
        }]
    }' > /run/xray.json

touch /var/log/xray/access.log /var/log/xray/error.log
chown -R xray:xray /var/log/xray
chmod 0750 /var/log/xray
chmod 0640 /var/log/xray/access.log /var/log/xray/error.log
chown xray:xray /run/xray.json
chmod 0600 /run/xray.json

gosu xray:xray /usr/local/bin/xray run -test -config /run/xray.json

log "interface=$IPV6_INTERFACE pool=$IPV6_POOL listen=$SOCKS_LISTEN:$SOCKS_PORT"

ndppd -c /run/ndppd.conf -p /run/ndppd.pid &
ndppd_pid=$!
gosu xray:xray /usr/local/bin/xray run -config /run/xray.json &
xray_pid=$!
printf '%s\n' "$xray_pid" > /run/xray.pid

# Invoked indirectly by the signal and exit traps below.
# shellcheck disable=SC2329
cleanup() {
    trap - TERM INT EXIT
    set +e
    gosu xray:xray kill "$xray_pid" 2>/dev/null
    kill "$ndppd_pid" 2>/dev/null
    wait "$xray_pid" "$ndppd_pid" 2>/dev/null
    if [[ "$route_preexisting" == false ]]; then
        ip -6 route del local "$IPV6_POOL" dev "$IPV6_INTERFACE" table local 2>/dev/null
    fi
}

trap 'cleanup; exit 0' TERM INT
trap cleanup EXIT

set +e
wait -n "$ndppd_pid" "$xray_pid"
status=$?
set -e
log "a managed process exited with status $status"
exit "$status"
