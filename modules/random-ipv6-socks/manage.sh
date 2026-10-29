#!/usr/bin/env bash
set -uo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")" || exit 1

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
    while true; do
        printf '\n随机 IPv6 SOCKS5\n'
        printf '1. 配置账号和端口\n2. 安装 / 更新\n3. 查看状态\n4. 查看日志\n5. 重启\n6. 停止\n7. 卸载容器\n0. 返回\n'
        read -r -p '请选择 [0-7]: ' choice || return 0
        case "$choice" in
            1) action setup ;; 2) action install ;; 3) action status ;;
            4) action logs ;; 5) action restart ;; 6) action stop ;;
            7) action uninstall ;; 0) return 0 ;;
            *) echo '请输入有效选项。'; continue ;;
        esac
        result=$?
        (( result == 0 )) || printf '操作未完成（退出码 %s）。\n' "$result" >&2
    done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
