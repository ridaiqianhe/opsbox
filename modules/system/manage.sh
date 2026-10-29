#!/usr/bin/env bash
set -uo pipefail

MODULE_DIR=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# The imported file only declares functions. Do not call its former startup path.
# shellcheck source=/dev/null
source "$MODULE_DIR/core.sh"
set +e
set -uo pipefail
export RUN_MODE=menu
# shellcheck source=lib/ui.sh
source "$MODULE_DIR/../../lib/ui.sh"
ui_init
c_reset=$UI_RESET; c_dim=$UI_DIM; c_bold=$UI_BOLD; c_cyan=$UI_ACCENT; c_green=$UI_GOOD; c_yellow=$UI_WARN; c_white=$UI_BOLD

# Shared presentation; business functions remain in core.sh.
menu_header() { ui_header "$@"; }
menu_section() { ui_section "$@"; }
menu_item() { ui_item "$@"; }
menu_rule() { ui_rule; }
menu_back_item() { ui_controls; }
print_kv() { printf '  %s：%s\n' "$1" "$2"; }

# Abort on closed input, including in nested prompts, instead of choosing defaults.
read_tty() {
    local __opsbox_name="$1" __opsbox_prompt="$2" __opsbox_fallback="${3:-}" __opsbox_value=""
    case "$__opsbox_prompt" in
        '请输入编号 > '|'请选择 ['*': ')
            ui_read "$__opsbox_name" || exit $?
            return 0 ;;
    esac
    if has_tty; then
        IFS= read -r -p "$__opsbox_prompt" __opsbox_value </dev/tty || exit 0
    else
        IFS= read -r -p "$__opsbox_prompt" __opsbox_value || exit 0
    fi
    printf -v "$__opsbox_name" '%s' "${__opsbox_value:-$__opsbox_fallback}"
}
read_tty_secret() {
    local __opsbox_name="$1" __opsbox_prompt="$2" __opsbox_value=""
    if has_tty; then
        IFS= read -r -s -p "$__opsbox_prompt" __opsbox_value </dev/tty || exit 0
    else
        IFS= read -r -s -p "$__opsbox_prompt" __opsbox_value || exit 0
    fi
    printf '\n' >&2
    printf -v "$__opsbox_name" '%s' "$__opsbox_value"
}

pause_for_return() { ui_pause || exit $?; }

restore_menu() {
    local choice=""
    while true; do
        menu_header '备份与恢复' '按模块恢复；进入菜单不会修改系统'
        menu_item 1 '保存配置快照' '网络、SSH、防火墙和运行状态'
        menu_item 2 '还原网络 / TCP / SSH' '只使用导入模块保存的备份'
        menu_item 3 '回滚动态 TCP 调优' '使用 tcpfit 原始快照'
        menu_item 4 '迁移旧版 DMITBox 网站' '显式清理旧站点规则并迁移回源配置'
        menu_back_item
        read_tty choice '请选择 [0-4]: ' ''
        case "$choice" in
            1) env_snapshot; pause_for_return ;;
            2)
                if confirm_word RESTORE '将还原网络、TCP 和 SSH，确认请输入 RESTORE: '; then
                    restore_all
                fi
                pause_for_return ;;
            3) tcpfit_rollback_all; pause_for_return ;;
            4)
                if confirm_word MIGRATE '迁移会修改旧网站配置和本脚本旧规则，确认请输入 MIGRATE: '; then
                    secure_site_cleanup_legacy_firewall_on_start
                    secure_site_select_nginx_paths
                    secure_site_migrate_legacy_site
                fi
                pause_for_return ;;
            0|q|Q) return 0 ;;
            *) echo '请输入有效选项。' ;;
        esac
    done
}

tcp_legacy() { bash "$MODULE_DIR/../vps-proxy/tcp-tune.sh"; }

system_dispatch() {
    case "${1:-help}" in
        overview) system_overview ;;
        check) health_check_only ;;
        ports) listening_ports ;;
        port-check) port_lookup ;;
        cpu) processes_top_cpu ;;
        memory) processes_top_memory ;;
        services) failed_services_status ;;
        network) network_menu ;;
        ipv6-system) ipv6_menu ;;
        nat66) ipv6_tools_menu ;;
        tcp)
            if [[ "${2:-}" == legacy ]]; then tcp_legacy; else tcp_menu; fi ;;
        dns) dns_switch_menu ;;
        mtu) mtu_menu ;;
        system) system_status_menu ;;
        swap) swap_menu ;;
        cleanup) cleanup_menu ;;
        updates) system_update_menu ;;
        timezone) set_timezone_china ;;
        security) security_menu ;;
        ssh-advanced) ssh_menu ;;
        firewall) common_firewall_menu ;;
        fail2ban) fail2ban_menu ;;
        site) secure_site_menu ;;
        reverse-proxy) reverse_proxy_menu ;;
        test) tests_menu ;;
        cloud) cloudinit_qga_menu ;;
        recovery) restore_menu ;;
        snapshot) env_snapshot ;;
        dd) dd_reinstall ;;
        help|--help|-h)
            printf 'OpsBox 系统模块：network ipv6-system nat66 tcp dns mtu system swap cleanup updates\n'
            printf '                 ssh-advanced firewall fail2ban site reverse-proxy test cloud recovery snapshot dd\n' ;;
        *) echo '未知系统工具。' >&2; return 2 ;;
    esac
}

main() {
    case "${1:-help}" in help|--help|-h) system_dispatch "$@"; return ;; esac
    [[ $(uname -s) == Linux && $EUID -eq 0 ]] || {
        echo '系统管理需要 Linux root 权限。' >&2; return 1;
    }
    if (( BASH_VERSINFO[0] < 4 )); then
        echo '此系统模块需要 Bash 4 或更新版本。' >&2
        return 1
    fi
    system_dispatch "$@"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
