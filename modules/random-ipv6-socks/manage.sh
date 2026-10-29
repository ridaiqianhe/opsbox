#!/usr/bin/env bash
set -uo pipefail
IPV6_MODULE_DIR=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd -- "$IPV6_MODULE_DIR" || exit 1
# shellcheck source=lib/ui.sh
source "$IPV6_MODULE_DIR/../../lib/ui.sh"

setup() {
    if [[ ! -f .env ]]; then
        (umask 077; cp .env.example .env) || return
    fi
    local -a editor
    read -r -a editor <<< "${EDITOR:-vi}"
    "${editor[@]}" .env
}

compose() {
    if [[ ! -f .env ]]; then
        echo '请先运行 opsbox ipv6 setup，设置端口和账号密码。' >&2
        return 1
    fi
    docker compose "$@"
}

action() {
    case "${1:-}" in
        setup) setup ;;
        install) bash ./install.sh ;;
        status) compose ps ;;
        logs) compose logs --tail=100 -f ;;
        restart) compose restart ;;
        stop) compose stop ;;
        uninstall)
            local answer
            read -r -p '停止并移除随机 IPv6 代理容器？保留 .env 和日志 [yes/N]: ' answer || return 1
            [[ "$answer" == yes ]] || return 0
            bash ./uninstall.sh ;;
        *) echo '未知操作；可用 setup install status logs restart stop uninstall。' >&2; return 2 ;;
    esac
}

main() {
    if (( $# )); then action "$@"; return; fi
    local choice result
    ui_init
    while true; do
        ui_header '随机 IPv6 SOCKS5' '独立 Docker 容器 · Xray 随机出口'
        ui_item 1 '配置账号和端口'
        ui_item 2 '安装 / 更新'
        ui_item 3 '查看状态'
        ui_item 4 '查看日志' 'Ctrl+C 停止跟踪'
        ui_item 5 '重启'
        ui_item 6 '停止'
        ui_item 7 '卸载容器' '保留配置和日志'
        ui_controls
        ui_read choice || return $?
        case "$choice" in
            1) action setup ;; 2) action install ;; 3) action status ;;
            4) action logs ;; 5) action restart ;; 6) action stop ;;
            7) action uninstall ;; 0) return 0 ;;
            *) echo '请输入有效选项。'; continue ;;
        esac
        result=$?
        ui_status "$result"
        # Returning from an editor/log follower needs no extra acknowledgement.
        if [[ "$choice" != 1 && "$choice" != 4 ]]; then ui_pause || return $?; fi
    done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
