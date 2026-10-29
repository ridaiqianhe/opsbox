#!/usr/bin/env bash
set -uo pipefail

OPSBOX_ROOT=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
VERSION=1.3.0
export OPSBOX_VERSION=$VERSION
# shellcheck source=lib/ui.sh
source "$OPSBOX_ROOT/lib/ui.sh"
# shellcheck source=lib/catalog.sh
source "$OPSBOX_ROOT/lib/catalog.sh"
ui_init
OPSBOX_RECENT=()

usage() {
    cat <<'HELP'
OpsBox — 服务器工具箱

用法: opsbox [命令] [参数]       不带参数进入常用工具首页
菜单: /关键词 搜索 · . 最近使用 · h 首页 · 0/b 返回 · q 退出
直达: overview / check / ports / cpu / memory / services
      snell / reality 等协议名可直接使用；opsbox find 关键词搜索

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

# Menus carry fixed commands, never arbitrary shell expressions.
catalog_lookup() {
    local wanted="$1" row id label command _terms kind
    REPLY_LABEL='' REPLY_KIND=menu
    while IFS= read -r row; do
        IFS='|' read -r id label command _terms kind <<< "$row"
        if [[ "$wanted" == "$id" || "$wanted" == "$command" ]]; then
            REPLY_LABEL=$label; REPLY_KIND=$kind; REPLY_COMMAND=$command
            return 0
        fi
    done < <(opsbox_catalog)
    return 1
}
record_recent() {
    local command="$1" old
    local -a next=("$command")
    for old in "${OPSBOX_RECENT[@]-}"; do
        [[ -n "$old" ]] || continue
        [[ "$old" == "$command" ]] || next+=("$old")
        (( ${#next[@]} < 5 )) || break
    done
    OPSBOX_RECENT=("${next[@]}")
}
perform_command() {
    local command="$1" kind=menu result
    local -a argv
    if catalog_lookup "$command"; then
        kind=$REPLY_KIND
        [[ "$kind" != action && "$kind" != danger ]] && record_recent "$command"
    fi
    IFS=' ' read -r -a argv <<< "$command"
    dispatch "${argv[@]}"
    result=$?
    case "$result" in 20|21) return "$result" ;; esac
    ui_status "$result"
    (( result != 130 )) || return 0
    if [[ "$kind" != menu || ( "$result" != 0 && "$result" != 130 ) ]]; then
        ui_pause || return $?
    fi
    return 0
}
resolve_shortcut() {
    REPLY_COMMAND=''
    case "$1" in
        p) REPLY_COMMAND=connections ;; n) REPLY_COMMAND=network-tools ;;
        s) REPLY_COMMAND=maintenance ;; a) REPLY_COMMAND=protection ;;
        w) REPLY_COMMAND=web ;; t) REPLY_COMMAND=diagnostics ;;
        r) REPLY_COMMAND=recovery ;; '!') REPLY_COMMAND=danger ;;
        *) catalog_lookup "$1" || return 1 ;;
    esac
}
recent_menu() {
    local command label
    local -a entries=()
    for command in "${OPSBOX_RECENT[@]-}"; do
        [[ -n "$command" ]] || continue
        catalog_lookup "$command" || continue
        label=$REPLY_LABEL
        entries+=("$label|$command|")
    done
    if (( ${#entries[@]} == 0 )); then
        printf '\n  本次会话还没有使用记录。\n'
        ui_pause
    else
        section_menu '最近使用' "${entries[@]}"
    fi
}
search_menu() {
    local query="${1:-}" needle row id label command _terms kind searchable choice index start end total page=0 result
    local -a matches=() exact=() related=()
    if [[ -z "$query" ]]; then
        printf '\n  搜索工具（名称 / 关键词，留空返回）：' >&2
        IFS= read -r query || return "$OPSBOX_QUIT_RC"
        [[ -n "$query" ]] || return 0
    fi
    needle=$(printf '%s' "$query" | tr '[:upper:]' '[:lower:]')
    while IFS= read -r row; do
        searchable=$(printf '%s' "$row" | tr '[:upper:]' '[:lower:]')
        [[ "$searchable" == *"$needle"* ]] || continue
        IFS='|' read -r id label command _terms kind <<< "$row"
        if [[ "$needle" == "$(printf '%s' "$id" | tr '[:upper:]' '[:lower:]')" ||
              "$needle" == "$(printf '%s' "$label" | tr '[:upper:]' '[:lower:]')" ||
              "$needle" == "$command" ]]; then
            exact+=("$row")
        else
            related+=("$row")
        fi
    done < <(opsbox_catalog)
    (( ${#exact[@]} == 0 )) || matches+=("${exact[@]}")
    (( ${#related[@]} == 0 )) || matches+=("${related[@]}")
    total=${#matches[@]}
    if (( total == 0 )); then
        printf '\n  没有找到“%s”。试试：端口、证书、SSH、IPv6。\n' "$query"
        ui_pause
        return $?
    fi
    while true; do
        ui_header '搜索工具' "关键词：$query · 共 $total 项"
        start=$((page * 10)); end=$((start + 10))
        (( end <= total )) || end=$total
        for ((index=start; index<end; index++)); do
            IFS='|' read -r id label command _terms kind <<< "${matches[index]}"
            [[ "$kind" != danger ]] || label+=" [高风险]"
            ui_item "$((index - start + 1))" "$label" "$command"
        done
        (( total <= 10 )) || printf '\n  第 %s / %s 页 · n 下一页 · p 上一页\n' "$((page + 1))" "$(((total + 9) / 10))"
        ui_controls
        ui_read choice || return $?
        case "$choice" in
            0) return 0 ;;
            n) (( end >= total )) || page=$((page + 1)); continue ;;
            p) (( page == 0 )) || page=$((page - 1)); continue ;;
        esac
        if [[ "$choice" =~ ^([1-9]|10)$ ]] && (( choice <= end - start )); then
            IFS='|' read -r id label command _terms kind <<< "${matches[start + choice - 1]}"
            perform_command "$command" || return $?
        fi
    done
}
section_menu() {
    local title="$1" entry label target detail choice index result
    shift
    local -a entries=("$@")
    while true; do
        ui_header "$title" '输入编号直达 · /关键词 搜索 · . 最近使用'
        index=1
        for entry in "${entries[@]}"; do
            IFS='|' read -r label target detail <<< "$entry"
            ui_item "$index" "$label" "$detail"
            index=$((index + 1))
        done
        ui_controls
        ui_read choice || return $?
        case "$choice" in
            '') continue ;;
            0) return 0 ;;
            /*) search_menu "${choice#/}"; result=$? ;;
            .) recent_menu; result=$? ;;
            *)
                if [[ "$choice" =~ ^[1-9][0-9]?$ ]] && (( choice <= ${#entries[@]} )); then
                    entry=${entries[choice - 1]}
                    IFS='|' read -r label target detail <<< "$entry"
                    perform_command "$target"; result=$?
                elif resolve_shortcut "$choice"; then
                    perform_command "$REPLY_COMMAND"; result=$?
                else
                    search_menu "$choice"; result=$?
                fi ;;
        esac
        case "$result" in 20|21) return "$result" ;; esac
    done
}

connections_menu() {
    section_menu '代理与转发' \
        'Snell|proxy snell|Surge · v5 / v6' \
        'VLESS Reality|proxy reality|Xray · Vision' \
        'Hysteria2|proxy hysteria2|QUIC / UDP' \
        'Shadowsocks 2022|proxy ss-2022|SS-rust' \
        '其他代理协议|proxy|AnyTLS / TUIC / Trojan / Shadow-TLS' \
        '随机 IPv6 SOCKS5|ipv6|独立 Docker 代理，带账号密码' \
        'Realm 转发|realm|TCP / UDP 端口转发'
}
network_tools_menu() {
    section_menu '网络与调优' \
        '网络体检|check|直接检查连通性与 DNS' \
        '网络诊断与修复|network|连通性、路由与 IPv4/IPv6 优先级' \
        '宿主机 IPv6|ipv6-system|开关、修复及地址状态' \
        'IPv6 地址池与 NAT66|nat66|系统级随机出口，会影响匹配的本机连接' \
        'TCP / BBR 调优|tcp|固定配置、动态实测及回滚' \
        'DNS 设置|dns|切换解析服务器与恢复' \
        'MTU 管理|mtu|探测、临时设置与持久化'
}
maintenance_menu() {
    section_menu '系统维护' \
        '系统概览|overview|CPU / 内存 / 磁盘 / 网络' \
        '监听端口|ports|直接查看 TCP / UDP 与所属进程' \
        'CPU 进程排行|cpu|按占用排序' \
        '内存进程排行|memory|按占用排序' \
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
        'DD 重装系统 [高风险]|dd|清空系统盘；需要控制台和二次确认'
}

dispatch() {
    local command="${1:-help}" tool
    (( $# == 0 )) || shift
    case "$command" in
        help|-h|--help) usage ;;
        list) printf 'OpsBox 工具目录\n\n'; opsbox_catalog | while IFS='|' read -r id label _; do printf '%-16s %s\n' "$id" "$label"; done ;;
        find|search) search_menu "${*:-}" ;;
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
        ipv6-status) dispatch ipv6 status ;;
        ipv6-logs) dispatch ipv6 logs ;;
        ipv6-setup) dispatch ipv6 setup ;;
        realm) run_module realm/realm.sh "$@" ;;
        ssh) run_module ssh/ssh.sh "$@" ;;
        overview|check|ports|port-check|cpu|memory|services|network|ipv6-system|nat66|tcp|dns|mtu|system|swap|cleanup|updates|timezone|ssh-advanced|firewall|fail2ban|site|reverse-proxy|test|cloud|recovery|snapshot|dd)
            run_module system/manage.sh "$command" "$@" ;;
        snell|reality|hysteria2|ss-2022|anytls|anytls-reality|tuic|trojan|shadow-tls|socks-http)
            dispatch proxy "$command" "$@" ;;
        *) printf '未知命令: %s（运行 opsbox help 查看帮助）\n' "$command" >&2; return 2 ;;
    esac
}

main() {
    local choice target result summary
    local -a quick=(overview check ports connections tcp ssh firewall reverse-proxy dd)
    if (( $# )); then
        dispatch "$@"; result=$?
        case "$result" in 20) main ;; 21) return 0 ;; *) return "$result" ;; esac
        return
    fi
    summary=$(ui_machine_summary)
    while true; do
        ui_header '常用工具' "$summary"
        ui_section '快速开始'
        ui_item 1 '系统概览' 'CPU / 内存 / 磁盘'
        ui_item 2 '网络体检' '连通性 / DNS / IPv6'
        ui_item 3 '监听端口' '端口与进程'
        ui_item 4 '代理与转发' 'Snell / Reality / SOCKS5'
        ui_item 5 'TCP / BBR 调优'
        ui_item 6 'SSH 快捷管理'
        ui_item 7 '防火墙'
        ui_item 8 'HTTPS 反向代理'
        ui_item 9 'DD 重装系统 [高风险]' '清空系统盘 · 需输入 DD 确认' danger
        ui_section '全部分类'
        if (( $(ui_columns) >= 76 )); then
            ui_category_pair p '代理与转发' n '网络与调优'
            ui_category_pair s '系统维护  ' a 'SSH 与安全'
            ui_category_pair w '网站与反代' t '测试与云主机'
            ui_category_pair r '备份与恢复' '!' '高影响操作'
        else
            ui_item p '代理与转发'; ui_item n '网络与调优'; ui_item s '系统维护'; ui_item a 'SSH 与安全'
            ui_item w '网站与反代'; ui_item t '测试与云主机'; ui_item r '备份与恢复'; ui_item '!' '高影响操作'
        fi
        ui_section '快捷操作'
        if (( $(ui_columns) >= 60 )); then
            printf '  直接输入 snell / tcp / dns 等命令 · /关键词 搜索\n'
        else
            printf '  输入工具名直达 · /关键词 搜索\n'
        fi
        printf '  . 最近使用 · ? 帮助 · 0/q 退出\n'
        ui_rule
        ui_read choice; result=$?
        case "$result" in 20) continue ;; 21) return 0 ;; esac
        case "$choice" in
            0) return 0 ;;
            '') continue ;;
            '?') usage; ui_pause; result=$? ;;
            /*) search_menu "${choice#/}"; result=$? ;;
            .) recent_menu; result=$? ;;
            *)
                if [[ "$choice" =~ ^[1-9]$ ]]; then
                    target=${quick[choice - 1]}
                    perform_command "$target"; result=$?
                elif resolve_shortcut "$choice"; then
                    perform_command "$REPLY_COMMAND"; result=$?
                else
                    search_menu "$choice"; result=$?
                fi ;;
        esac
        [[ "$result" != "$OPSBOX_QUIT_RC" ]] || return 0
    done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
