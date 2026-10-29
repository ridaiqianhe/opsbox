#!/usr/bin/env bash
# Shared, dependency-free terminal presentation. Importing this file has no side effects.
OPSBOX_VERSION=${OPSBOX_VERSION:-1.2.0}
OPSBOX_HOME_RC=20
OPSBOX_QUIT_RC=21
UI_RESET='' UI_BOLD='' UI_ACCENT='' UI_DIM='' UI_GOOD='' UI_WARN=''
# Consumed by the imported system-module status messages.
export UI_GOOD

ui_init() {
    if [[ -z ${NO_COLOR:-} && ${TERM:-dumb} != dumb ]] && { [[ -t 1 ]] || [[ ${OPSBOX_COLOR:-auto} == always ]]; }; then
        UI_RESET=$'\033[0m'; UI_BOLD=$'\033[1m'; UI_ACCENT=$'\033[36m'
        UI_DIM=$'\033[90m'; UI_GOOD=$'\033[32m'; UI_WARN=$'\033[33m'
    fi
}
ui_columns() {
    local columns=${COLUMNS:-80}
    [[ $columns =~ ^[0-9]{2,3}$ ]] || columns=80
    (( columns >= 36 )) || columns=36
    (( columns <= 100 )) || columns=100
    printf '%s' "$columns"
}
ui_rule() {
    local count line
    count=$(ui_columns)
    printf -v line '%*s' "$((count - 4))" ''
    printf '  %s%s%s\n' "$UI_DIM" "${line// /─}" "$UI_RESET"
}
ui_header() {
    local title=${1:-首页} description=${2:-}
    if [[ -t 1 && ${TERM:-dumb} != dumb && ${OPSBOX_CLEAR:-1} != 0 ]]; then
        printf '\033[2J\033[H'
    fi
    printf '\n  %s%sOpsBox%s  %sv%s%s\n' "$UI_BOLD" "$UI_ACCENT" "$UI_RESET" "$UI_DIM" "$OPSBOX_VERSION" "$UI_RESET"
    printf '  %s%s%s\n' "$UI_BOLD" "$title" "$UI_RESET"
    [[ -z $description ]] || printf '  %s%s%s\n' "$UI_DIM" "$description" "$UI_RESET"
    ui_rule
}
ui_section() { printf '\n  %s%s%s\n' "$UI_ACCENT" "$1" "$UI_RESET"; }
ui_item() {
    printf '  %s%2s%s  %s' "$UI_ACCENT" "$1" "$UI_RESET" "$2"
    if [[ -n ${3:-} ]]; then
        if (( $(ui_columns) >= 76 )); then
            printf '  %s%s%s' "$UI_DIM" "$3" "$UI_RESET"
        fi
    fi
    printf '\n'
}
ui_controls() {
    ui_rule
    printf '  %s0/b 返回  ·  h 首页  ·  q 退出%s\n' "$UI_DIM" "$UI_RESET"
}
ui_prompt() { printf '\n  %s选择 › %s' "$UI_ACCENT" "$UI_RESET" >&2; }
ui_read() {
    local __ui_name=$1 __ui_value=''
    ui_prompt
    IFS= read -r __ui_value || return "$OPSBOX_QUIT_RC"
    case "$__ui_value" in
        h|H) return "$OPSBOX_HOME_RC" ;;
        q|Q) return "$OPSBOX_QUIT_RC" ;;
        b|B) __ui_value=0 ;;
    esac
    printf -v "$__ui_name" '%s' "$__ui_value"
}
ui_pause() {
    local __ui_reply=''
    printf '\n  %s回车继续 · h 首页 · q 退出%s ' "$UI_DIM" "$UI_RESET" >&2
    IFS= read -r __ui_reply || return "$OPSBOX_QUIT_RC"
    case "$__ui_reply" in
        h|H) return "$OPSBOX_HOME_RC" ;;
        q|Q) return "$OPSBOX_QUIT_RC" ;;
    esac
}
ui_status() {
    case "$1" in
        0|20|21|130) return 0 ;;
        *) printf '\n  %s操作未完成（退出码 %s）%s\n' "$UI_WARN" "$1" "$UI_RESET" >&2 ;;
    esac
}
ui_machine_summary() {
    local os='' memory='' disk=''
    if [[ -r /etc/os-release ]]; then
        os=$(sed -n 's/^PRETTY_NAME=//p' /etc/os-release | head -n 1)
        os=${os#\"}; os=${os%\"}
    else
        os=$(uname -s)
    fi
    if [[ -r /proc/meminfo ]]; then
        memory=$(awk '/^MemTotal:/ {t=$2} /^MemAvailable:/ {a=$2} END {if(t) printf "内存 %.0f%%", (t-a)*100/t}' /proc/meminfo)
    fi
    disk=$(df -P / 2>/dev/null | awk 'NR==2 {print "磁盘 " $5}')
    printf '%s' "$os"
    [[ -z $memory ]] || printf ' · %s' "$memory"
    [[ -z $disk ]] || printf ' · %s' "$disk"
}
