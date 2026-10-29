#!/bin/bash

# ===================================================================
# vps-proxy — 常用代理协议一键脚本合集入口
# 仓库: https://github.com/ridaiqianhe/opsbox
#
# 用法:
#   bash <(wget -qO- https://raw.githubusercontent.com/ridaiqianhe/opsbox/main/modules/vps-proxy/vps-proxy.sh)
# ===================================================================

REPO_RAW="https://raw.githubusercontent.com/ridaiqianhe/opsbox/main/modules/vps-proxy"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

fetch() {
    if command -v curl >/dev/null 2>&1; then curl -fsSL "$1"; else wget -qO- "$1"; fi
}

run_script() {
    local name="$1"
    if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/$name" ]; then
        bash "$SCRIPT_DIR/$name"
    else
        local content
        content=$(fetch "$REPO_RAW/$name")
        if [ -z "$content" ]; then
            printf '下载 %s 失败，请检查网络。\n' "$name" >&2
            return 1
        fi
        bash <(echo "$content")
    fi
}

# shellcheck source=lib/ui.sh
if [[ -r "$SCRIPT_DIR/../../lib/ui.sh" ]]; then
    source "$SCRIPT_DIR/../../lib/ui.sh"
    ui_init
else
    # Keep the documented standalone download usable without the full checkout.
    ui_header() { printf '\nOpsBox / %s\n\n' "$1"; }
    ui_item() { printf '%s. %s\n' "$1" "$2"; }
    ui_controls() { printf '\n0 返回 · h 首页 · q 退出\n'; }
    ui_read() {
        local name="$1" value=""
        read -r -p '选择 > ' value || return 21
        case "$value" in h) return 20 ;; q) return 21 ;; b) value=0 ;; esac
        printf -v "$name" '%s' "$value"
    }
    ui_pause() { read -r -p '按回车继续…' _; }
    ui_status() { printf '操作退出码：%s\n' "$1"; }
fi

main() {
    if (( EUID != 0 )); then
        echo '代理服务管理需要 root，请使用 sudo opsbox proxy。' >&2
        return 1
    fi
    local choice result
    while true; do
        ui_header '代理协议' '选择协议进入管理；退出协议后直接返回此页'
        ui_item 1 'Snell' 'Surge · v5 / v6'
        ui_item 2 'Hysteria2' 'QUIC / UDP'
        ui_item 3 'Shadowsocks 2022' 'SS-rust'
        ui_item 4 'AnyTLS' '通用 TLS'
        ui_item 5 'TUIC v5'
        ui_item 6 'Trojan'
        ui_item 7 'VLESS Reality' 'Xray'
        ui_item 8 'Shadow-TLS v3'
        ui_item 9 'TCP / BBR 调优' '统一网络模块'
        ui_item 10 'AnyTLS + Reality' 'sing-box'
        ui_item 11 'SOCKS5 / HTTP / HTTPS'
        ui_controls
        ui_read choice || return $?
        case "$choice" in
            1) run_script snell.sh ;;
            2) run_script hysteria2.sh ;;
            3) run_script ss-2022.sh ;;
            4) run_script anytls.sh ;;
            5) run_script tuic.sh ;;
            6) run_script trojan.sh ;;
            7) run_script reality.sh ;;
            8) run_script shadow-tls.sh ;;
            9)
                if [[ -f "$SCRIPT_DIR/../system/manage.sh" ]]; then
                    bash "$SCRIPT_DIR/../system/manage.sh" tcp
                else
                    echo '请安装完整 OpsBox 后运行 opsbox tcp。'
                fi ;;
            10) run_script anytls-reality.sh ;;
            11) run_script socks-http.sh ;;
            0) return 0 ;;
            *) echo '请输入有效选项。'; continue ;;
        esac
        result=$?
        case "$result" in
            20|21) return "$result" ;;
            0|130) ;;
            *) ui_status "$result"; ui_pause || return $? ;;
        esac
    done
}

main "$@"
