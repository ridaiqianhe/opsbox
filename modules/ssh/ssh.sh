#!/usr/bin/env bash
set -uo pipefail

SSHD_CONFIG=${SSHD_CONFIG:-/etc/ssh/sshd_config}
SSHD_BIN=${SSHD_BIN:-/usr/sbin/sshd}

reload_ssh() {
    if command -v systemctl >/dev/null 2>&1; then
        if systemctl is-active --quiet ssh; then
            systemctl reload ssh
        elif systemctl is-active --quiet sshd; then
            systemctl reload sshd
        else
            echo '没有找到运行中的 ssh/sshd 服务。' >&2
            return 1
        fi
    elif command -v rc-service >/dev/null 2>&1; then
        rc-service sshd reload
    else
        echo '未识别服务管理器，配置未应用。' >&2
        return 1
    fi
}

# Preserve Match sections and Include directives.
render_config() {
    local key="$1" value="$2"
    printf '%s %s\n' "$key" "$value"
    awk -v key="$key" '
        tolower($1) == "match" { in_match = 1 }
        !in_match && tolower($1) == tolower(key) { next }
        { print }
    ' "$SSHD_CONFIG"
}

apply_setting() (
    local key="$1" value="$2" candidate backup effective
    [[ -f "$SSHD_CONFIG" && ! -L "$SSHD_CONFIG" && -x "$SSHD_BIN" ]] || {
        echo '需要已安装的 OpenSSH 服务和常规 sshd_config 文件。' >&2; return 1;
    }
    "$SSHD_BIN" -t -f "$SSHD_CONFIG" || return 1
    candidate=$(mktemp "${SSHD_CONFIG}.opsbox-candidate.XXXXXX") || return 1
    backup=$(mktemp "${SSHD_CONFIG}.opsbox-backup.XXXXXX") || { rm -f -- "$candidate"; return 1; }
    trap 'rm -f -- "$candidate"' EXIT
    cp -p -- "$SSHD_CONFIG" "$backup" || return 1
    render_config "$key" "$value" > "$candidate" || return 1
    "$SSHD_BIN" -t -f "$candidate" || return 1
    effective=$("$SSHD_BIN" -T -f "$candidate") || return 1
    if ! awk -v key="$key" -v value="$value" '
        tolower($1) == tolower(key) { count++; if ($2 != value) invalid = 1 }
        END { exit !(count == 1 && !invalid) }
    ' <<< "$effective"; then
        echo '实际配置与目标不一致（可能被 Include 或多端口配置影响），未修改。' >&2
        return 1
    fi
    if ! cat "$candidate" > "$SSHD_CONFIG"; then
        cp -p -- "$backup" "$SSHD_CONFIG"
        return 1
    fi
    if ! "$SSHD_BIN" -t -f "$SSHD_CONFIG" || ! reload_ssh; then
        cp -p -- "$backup" "$SSHD_CONFIG"
        reload_ssh || true
        echo "应用失败，已恢复配置。备份：$backup" >&2
        return 1
    fi
    printf '已应用 %s。备份：%s\n' "$key" "$backup"
)

change_password() {
    local account
    read -r -p '要修改密码的本地用户名 [root]: ' account || return 1
    account=${account:-root}
    [[ "$account" =~ ^[a-zA-Z_][a-zA-Z0-9_.-]*\$?$ ]] || { echo '用户名格式无效。' >&2; return 1; }
    id "$account" >/dev/null 2>&1 || { echo '用户不存在。' >&2; return 1; }
    passwd "$account"
}

change_port() {
    local port answer
    read -r -p '新的 SSH 端口 [1-65535，空白取消]: ' port || return 1
    [[ -n "$port" ]] || return 0
    [[ "$port" =~ ^[0-9]{1,5}$ ]] && (( 10#$port >= 1 && 10#$port <= 65535 )) || {
        echo '端口无效。' >&2; return 1;
    }
    port=$((10#$port))
    echo '请先在云安全组和防火墙放行新端口，保留当前连接直到新连接验证成功。'
    if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet ssh.socket; then
        echo '检测到 ssh.socket，请通过系统工具修改 socket 监听端口。' >&2; return 1
    fi
    read -r -p "将 SSH 端口改为 $port？[yes/N]: " answer || return 1
    [[ "$answer" == yes ]] || return 0
    apply_setting Port "$port"
}

enable_password_login() {
    local answer
    echo '此操作仅启用全局 PasswordAuthentication，保留现有用户和 root 登录限制。'
    read -r -p '确认启用密码登录？[yes/N]: ' answer || return 1
    [[ "$answer" == yes ]] || return 0
    apply_setting PasswordAuthentication yes
}

enable_root_login() {
    local answer
    echo '此操作允许 root 登录。密码登录是否可用仍由 PasswordAuthentication 和 Match 规则决定。'
    read -r -p '确认允许 root 登录？[yes/N]: ' answer || return 1
    [[ "$answer" == yes ]] || return 0
    apply_setting PermitRootLogin yes
}

show_settings() {
    "$SSHD_BIN" -T -f "$SSHD_CONFIG" | awk '$1 ~ /^(port|permitrootlogin|passwordauthentication|kbdinteractiveauthentication|pubkeyauthentication)$/ { print }'
}

main() {
    (( EUID == 0 )) || { echo '请使用 root 运行 SSH 管理。' >&2; return 1; }
    local choice result
    while true; do
        printf '\nSSH 管理\n1. 修改本地用户密码\n2. 修改 SSH 端口\n3. 查看全局 SSH 设置\n4. 启用密码登录\n5. 允许 root 登录\n0. 返回\n'
        read -r -p '请选择 [0-5]: ' choice || return 0
        case "$choice" in
            1) change_password ;; 2) change_port ;; 3) show_settings ;;
            4) enable_password_login ;; 5) enable_root_login ;;
            0) return 0 ;; *) echo '请输入有效选项。'; continue ;;
        esac
        result=$?
        (( result == 0 )) || echo '操作未完成。' >&2
    done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
