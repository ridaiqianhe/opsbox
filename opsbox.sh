#!/usr/bin/env bash
set -uo pipefail

OPSBOX_ROOT=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
VERSION=1.1.0

usage() {
    cat <<'HELP'
OpsBox — 服务器工具箱

用法: opsbox [命令] [参数]       不带参数进入分类菜单

代理与转发:
  proxy [工具]                  代理协议安装与管理
  ipv6 [操作]                   随机 IPv6 SOCKS5（Docker）
  realm                         Realm TCP/UDP 转发
网络与调优:
  network                       连通性检查、修复与协议优先级
  ipv6-system / nat66            宿主机 IPv6 / 地址池与 NAT66 随机出口
  tcp [legacy]                  TCP/BBR 统一调优 / 旧版参数管理
  dns / mtu                     DNS 切换 / MTU 探测与持久化
系统与安全:
  system / swap / cleanup        系统、进程与端口 / Swap / 清理
  updates / timezone            更新与时间同步 / 中国时区
  ssh / ssh-advanced             SSH 快捷操作 / 密钥、用户与安全审计
  firewall / fail2ban            防火墙 / SSH 防爆破
网站、诊断与恢复:
  site / reverse-proxy           静态导航站 / HTTPS 反向代理
  test / cloud                   性能与网络测试 / cloud-init、QGA
  recovery / snapshot            备份、恢复与旧站点迁移 / 保存快照
  dd                            DD 重装（会清空系统盘，需二次确认）
  list / version / help          命令列表 / 版本 / 帮助

代理工具: snell hysteria2 ss-2022 anytls anytls-reality tuic trojan
          reality shadow-tls socks-http
IPv6 SOCKS5 操作: setup install status logs restart stop uninstall
系统操作需要 Linux root。安装和打开菜单不会更改系统配置。
HELP
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

# Each entry is a fixed label|command|description. No command strings are evaluated.
section_menu() {
    local title="$1" entry label target detail choice result index
    shift
    local -a entries=("$@")
    while true; do
        printf '\n  OpsBox %s / %s\n' "$VERSION" "$title"
        printf '  ─────────────────────────────────────────\n'
        index=1
        for entry in "${entries[@]}"; do
            IFS='|' read -r label target detail <<< "$entry"
            printf '  %2s. %s' "$index" "$label"
            [[ -z "$detail" ]] || printf ' — %s' "$detail"
            printf '\n'
            index=$((index + 1))
        done
        printf '\n   0. 返回\n\n'
        read -r -p '请选择: ' choice || return 0
        case "$choice" in 0|q|Q) return 0 ;; esac
        if [[ ! "$choice" =~ ^[1-9][0-9]?$ ]] || (( choice > ${#entries[@]} )); then
            echo '请输入有效选项。'
            continue
        fi
        entry=${entries[choice - 1]}
        IFS='|' read -r label target detail <<< "$entry"
        dispatch "$target"
        result=$?
        (( result == 0 )) || printf '操作未完成（退出码 %s）。\n' "$result" >&2
        read -r -p '按回车返回分类菜单…' choice || return 0
    done
}

connections_menu() {
    section_menu '代理与转发' \
        '代理协议|proxy|Snell、Reality、Hysteria2、SS2022 等' \
        '随机 IPv6 SOCKS5|ipv6|独立 Docker 代理，带账号密码' \
        'Realm 转发|realm|TCP / UDP 端口转发'
}
network_tools_menu() {
    section_menu '网络与调优' \
        '网络诊断与修复|network|连通性、路由与 IPv4/IPv6 优先级' \
        '宿主机 IPv6|ipv6-system|开关、修复及地址状态' \
        'IPv6 地址池与 NAT66|nat66|系统级随机出口，会影响匹配的本机连接' \
        'TCP / BBR 调优|tcp|固定配置、动态实测及回滚' \
        'DNS 设置|dns|切换解析服务器与恢复' \
        'MTU 管理|mtu|探测、临时设置与持久化'
}
maintenance_menu() {
    section_menu '系统维护' \
        '系统、进程与端口|system|资源、监听、进程及服务健康' \
        'Swap 管理|swap|创建、调整、删除及 swappiness' \
        '磁盘与日志清理|cleanup|先预览再清理' \
        '更新与时间同步|updates|软件更新、服务健康和 NTP' \
        '设置中国时区|timezone|将系统时区设为 Asia/Shanghai'
}
protection_menu() {
    section_menu 'SSH 与安全' \
        'SSH 快捷操作|ssh|修改密码、端口及全局登录设置' \
        'SSH 密钥与安全审计|ssh-advanced|用户、公钥、登录记录及加固' \
        '防火墙|firewall|端口、来源规则及安全启用' \
        'Fail2Ban|fail2ban|SSH 防爆破、白名单及解封'
}
web_menu() {
    section_menu '网站与反代' \
        '静态导航站|site|Nginx、TLS 证书及本机回源锁定' \
        'HTTPS 反向代理|reverse-proxy|本机服务或远程站点，支持 WebSocket'
}
diagnostics_menu() {
    section_menu '测试与云主机' \
        '性能与网络测试|test|CPU、回程、TCP 质量及流媒体解锁' \
        '换 IP 与云初始化|cloud|cloud-init、QGA 和网络回滚保护'
}
danger_menu() {
    section_menu '高影响操作' \
        'DD 重装系统|dd|清空系统盘；需要控制台和二次确认'
}

dispatch() {
    local command="${1:-help}" tool
    (( $# == 0 )) || shift
    case "$command" in
        help|-h|--help|list) usage ;;
        version|--version) printf 'OpsBox %s\n' "$VERSION" ;;
        menu) main ;;
        connections) connections_menu ;;
        network-tools) network_tools_menu ;;
        maintenance) maintenance_menu ;;
        protection|security) protection_menu ;;
        web) web_menu ;;
        diagnostics) diagnostics_menu ;;
        danger) danger_menu ;;
        proxy)
            tool="${1:-menu}"
            (( $# == 0 )) || shift
            case "$tool" in
                menu) run_module vps-proxy/vps-proxy.sh "$@" ;;
                tcp-tune) run_module system/manage.sh tcp "$@" ;;
                snell|hysteria2|ss-2022|anytls|anytls-reality|tuic|trojan|reality|shadow-tls|socks-http)
                    run_module "vps-proxy/$tool.sh" "$@" ;;
                *) printf '未知代理工具: %s\n' "$tool" >&2; return 2 ;;
            esac ;;
        ipv6) run_module random-ipv6-socks/manage.sh "$@" ;;
        realm) run_module realm/realm.sh "$@" ;;
        ssh) run_module ssh/ssh.sh "$@" ;;
        network|ipv6-system|nat66|tcp|dns|mtu|system|swap|cleanup|updates|timezone|ssh-advanced|firewall|fail2ban|site|reverse-proxy|test|cloud|recovery|snapshot|dd)
            run_module system/manage.sh "$command" "$@" ;;
        *) printf '未知命令: %s（运行 opsbox help 查看帮助）\n' "$command" >&2; return 2 ;;
    esac
}

main() {
    if (( $# )); then dispatch "$@"; return; fi
    section_menu '主菜单' \
        '代理与转发|connections|代理协议、IPv6 SOCKS5、Realm' \
        '网络与调优|network-tools|诊断、IPv6、NAT66、TCP、DNS、MTU' \
        '系统维护|maintenance|资源、进程、Swap、清理、更新' \
        'SSH 与安全|protection|SSH、密钥、防火墙、Fail2Ban' \
        '网站与反代|web|静态站点与 HTTPS 反向代理' \
        '测试与云主机|diagnostics|性能、线路测试及换 IP 支持' \
        '备份与恢复|recovery|配置快照、回滚、旧站点迁移' \
        '高影响操作|danger|DD 重装系统'
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
