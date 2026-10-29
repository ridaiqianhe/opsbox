#!/usr/bin/env bash
set -uo pipefail

OPSBOX_ROOT=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
VERSION=1.0.0

usage() {
    cat <<'EOF'
OpsBox — 常用服务器工具箱

用法: opsbox [命令] [参数]
  proxy [工具]        代理协议菜单，或直接打开某个工具
  ipv6 [操作]         随机 IPv6 SOCKS5（Docker）
  realm               Realm TCP/UDP 转发
  ssh                 SSH 密码与连接设置
  list                列出工具
  version             显示版本
  help                显示帮助

代理工具: snell hysteria2 ss-2022 anytls anytls-reality tuic trojan
          reality shadow-tls socks-http tcp-tune
IPv6 操作: setup install status logs restart stop uninstall
不带参数进入菜单；安装和管理服务需要 Linux root 权限。
EOF
}

require_root() {
    if [[ $(uname -s) != Linux ]]; then
        echo '服务管理仅支持 Linux。' >&2
        return 1
    fi
    if (( EUID != 0 )); then
        echo '请使用 sudo bash opsbox.sh 或 sudo opsbox。' >&2
        return 1
    fi
}

run_module() {
    require_root || return
    local script="$1"
    shift
    bash "$OPSBOX_ROOT/modules/$script" "$@"
}

dispatch() {
    local command="${1:-help}" tool
    (( $# == 0 )) || shift
    case "$command" in
        help|-h|--help) usage ;;
        version|--version) printf 'OpsBox %s\n' "$VERSION" ;;
        list) usage ;;
        proxy)
            tool="${1:-menu}"
            (( $# == 0 )) || shift
            case "$tool" in
                menu) run_module vps-proxy/vps-proxy.sh "$@" ;;
                snell|hysteria2|ss-2022|anytls|anytls-reality|tuic|trojan|reality|shadow-tls|socks-http|tcp-tune)
                    run_module "vps-proxy/$tool.sh" "$@" ;;
                *) printf '未知代理工具: %s\n' "$tool" >&2; return 2 ;;
            esac ;;
        ipv6) run_module random-ipv6-socks/manage.sh "$@" ;;
        realm) run_module realm/realm.sh "$@" ;;
        ssh) run_module ssh/ssh.sh "$@" ;;
        *) printf '未知命令: %s（运行 opsbox help 查看帮助）\n' "$command" >&2; return 2 ;;
    esac
}

main() {
    local choice command result
    if (( $# )); then
        dispatch "$@"
        return
    fi
    while true; do
        printf '\n  OpsBox · 常用工具箱\n\n'
        printf '  1. 代理协议\n  2. 随机 IPv6 SOCKS5\n  3. Realm 转发\n  4. SSH 管理\n  5. 帮助\n  0. 退出\n\n'
        read -r -p '请选择 [0-5]: ' choice || return 0
        case "$choice" in
            1) command=proxy ;; 2) command=ipv6 ;; 3) command=realm ;;
            4) command=ssh ;; 5) command=help ;; 0) return 0 ;;
            *) echo '请输入有效选项。'; continue ;;
        esac
        dispatch "$command"
        result=$?
        (( result == 0 )) || printf '操作未完成（退出码 %s）。\n' "$result" >&2
        read -r -p '按回车返回工具箱…' choice || return 0
    done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
