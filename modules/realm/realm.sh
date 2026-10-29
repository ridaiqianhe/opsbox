#!/usr/bin/env bash
# Imported from ridaiqianhe Gist cf516fc8182035c7cabfbe80fab163db.
# Standalone Realm manager; also used by opsbox realm.

# Prefer the directory used by an existing service before considering legacy data.
realm_default_dir() {
    local modern="${1:-/root/realm}" legacy="${2:-/etc/realm}" unit="${3:-/etc/systemd/system/realm.service}"
    if [[ -f "$unit" ]]; then
        if grep -Fq "ExecStart=$legacy/realm " "$unit" && [[ -f "$legacy/config.toml" ]]; then
            printf '%s\n' "$legacy"; return
        fi
        if grep -Fq "ExecStart=$modern/realm " "$unit" && [[ -f "$modern/config.toml" ]]; then
            printf '%s\n' "$modern"; return
        fi
    fi
    if [[ -f "$modern/config.toml" ]]; then printf '%s\n' "$modern"
    elif [[ -f "$legacy/config.toml" ]]; then printf '%s\n' "$legacy"
    else printf '%s\n' "$modern"; fi
}

REALM_DIR=''
realm_refresh_status() {

# 检查Realm是否已安装
if [ -f "${REALM_DIR}/realm" ]; then
    echo "检测到Realm已安装。"
    realm_status="已安装"
    realm_status_color="\033[0;32m" # 绿色
else
    echo "Realm未安装。"
    realm_status="未安装"
    realm_status_color="\033[0;31m" # 红色
fi

}

# 检查Realm服务状态
check_realm_service_status() {
    # 检查转发规则数量
    local rule_count
    rule_count=$(grep -c '^\[\[endpoints\]\]' "${REALM_DIR}/config.toml" 2>/dev/null) || true
    rule_count=${rule_count:-0}

    if systemctl is-active --quiet realm && [ "$rule_count" -gt 0 ]; then
        echo -e "\033[0;32m启用\033[0m" # 绿色
    else
        echo -e "\033[0;31m未启用\033[0m" # 红色
    fi
}

# 获取当前安装版本；菜单只读取本机，不在每次刷新时访问网络。
get_realm_version() {
    if [ -x ${REALM_DIR}/realm ]; then
        ${REALM_DIR}/realm --version 2>/dev/null | head -n 1
    else
        printf '%s\n' '未安装'
    fi
}

# 下载仅使用 HTTPS 的官方地址，不依赖 jq 或 Python。
realm_download() {
    if command -v curl >/dev/null 2>&1; then
        curl --fail --location --silent --show-error --retry 2 \
            --connect-timeout 15 --max-time 180 --proto '=https' \
            --output "$2" "$1"
    elif command -v wget >/dev/null 2>&1; then
        wget --quiet --timeout=30 --tries=3 --output-document="$2" "$1"
    else
        echo '请先安装 curl 或 wget。' >&2
        return 1
    fi
}

# 选择官方完整构建；musl 包优先，避免旧系统的 glibc 版本限制。
realm_asset_targets() {
    case "$1" in
        x86_64|amd64)
            printf '%s\n' x86_64-unknown-linux-musl x86_64-unknown-linux-gnu ;;
        aarch64|arm64)
            printf '%s\n' aarch64-unknown-linux-musl aarch64-unknown-linux-gnu ;;
        armv7l|armv7*)
            printf '%s\n' armv7-unknown-linux-musleabihf armv7-unknown-linux-gnueabihf ;;
        armv6l|armv6*)
            printf '%s\n' arm-unknown-linux-musleabihf arm-unknown-linux-gnueabihf ;;
        armv5*)
            printf '%s\n' arm-unknown-linux-musleabi arm-unknown-linux-gnueabi ;;
        *)
            echo "暂不支持当前架构：$1，未修改已安装的 Realm。" >&2
            return 1 ;;
    esac
}

# 在临时目录中下载、验证，完成后自动清理；已有规则不在此处修改。
install_latest_realm() (
    local workdir version version_number arch targets target asset url current was_active=0
    if [ "$(uname -s)" != Linux ]; then
        echo '此脚本使用 systemd，目前仅支持 Linux。' >&2
        return 1
    fi
    if [ "$(id -u)" -ne 0 ]; then
        echo '请以 root 身份运行安装或更新。' >&2
        return 1
    fi
    arch=$(uname -m)
    targets=$(realm_asset_targets "$arch") || return 1
    workdir=$(mktemp -d) || return 1
    trap 'rm -rf -- "$workdir"' EXIT

    echo '正在连接官方 GitHub，获取最新稳定版本……'
    if ! realm_download 'https://api.github.com/repos/zhboner/realm/releases/latest' "$workdir/release.json"; then
        echo '获取版本失败，保留原有程序和配置，请稍后重试。' >&2
        return 1
    fi
    version=$(grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"[^"]+"' "$workdir/release.json" |
        head -n 1 | sed 's/^[^:]*:[[:space:]]*"\([^"]*\)"$/\1/')
    if ! [[ "$version" =~ ^v([0-9]+\.[0-9]+\.[0-9]+)(-[0-9]+)?$ ]]; then
        echo '官方版本信息无效，未修改已安装的 Realm。' >&2
        return 1
    fi
    version_number=${BASH_REMATCH[1]}
    url=''
    while IFS= read -r target; do
        asset="realm-${target}.tar.gz"
        url=$(grep -oE '"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]+"' "$workdir/release.json" |
            sed 's/^[^:]*:[[:space:]]*"\([^"]*\)"$/\1/' |
            grep -Fx "https://github.com/zhboner/realm/releases/download/${version}/${asset}" | head -n 1)
        [ -n "$url" ] && break
    done <<< "$targets"
    if [ -z "$url" ]; then
        echo "官方 ${version} 没有适配 ${arch} 的完整安装包，未做修改。" >&2
        return 1
    fi
    current=$(get_realm_version)
    echo "当前版本：${current}  |  最新稳定版：${version}  |  架构：${arch}"
    if [[ "$current" =~ (^|[[:space:]])v?([0-9]+\.[0-9]+\.[0-9]+)($|[[:space:]]) ]] &&
       [ "${BASH_REMATCH[2]}" = "$version_number" ] && [ "$version" = "v$version_number" ]; then
        echo '已经是最新稳定版，无需替换程序。'
        return 0
    fi

    echo "正在下载：${asset}"
    if ! realm_download "$url" "$workdir/realm.tar.gz" ||
       ! tar -xzf "$workdir/realm.tar.gz" -C "$workdir"; then
        echo '下载或解压失败，保留原有程序。' >&2
        return 1
    fi
    if [ ! -f "$workdir/realm" ] || ! chmod +x "$workdir/realm"; then
        echo '安装包缺少可执行程序，未做修改。' >&2
        return 1
    fi
    local downloaded_version
    if ! downloaded_version=$("$workdir/realm" --version 2>/dev/null) ||
       ! [[ "$downloaded_version" =~ (^|[[:space:]])v?([0-9]+\.[0-9]+\.[0-9]+)($|[[:space:]]) ]] ||
       [ "${BASH_REMATCH[2]}" != "$version_number" ]; then
        echo '新程序无法运行或版本不符，可能与当前系统不兼容，保留原有程序。' >&2
        return 1
    fi
    mkdir -p ${REALM_DIR} || return 1
    if [ -f ${REALM_DIR}/realm ]; then
        cp -p ${REALM_DIR}/realm "$workdir/previous-realm" || return 1
    fi
    systemctl is-active --quiet realm.service && was_active=1
    # 同目录原子替换，避免直接覆盖正在运行的可执行文件。
    if ! install -m 755 "$workdir/realm" ${REALM_DIR}/.realm-new ||
       ! mv -f ${REALM_DIR}/.realm-new ${REALM_DIR}/realm; then
        rm -f ${REALM_DIR}/.realm-new
        echo '替换程序失败。' >&2
        return 1
    fi
    if [ "$was_active" -eq 1 ]; then
        if ! systemctl restart realm.service || ! systemctl is-active --quiet realm.service; then
            echo '新版启动失败，正在恢复原版本。' >&2
            if [ -f "$workdir/previous-realm" ]; then
                cp -p "$workdir/previous-realm" ${REALM_DIR}/.realm-new &&
                    mv -f ${REALM_DIR}/.realm-new ${REALM_DIR}/realm
                systemctl restart realm.service
            fi
            return 1
        fi
    fi
    echo "Realm ${version} 安装完成。"
)

# 星轨中转站：只调整菜单展示，原有编号和转发操作保持一致。
show_menu() {
    clear
    local pink='\033[1;35m' cyan='\033[1;36m' white='\033[1;37m' reset='\033[0m'
    printf '\n%b' "$pink"
    printf '%s\n' '  ╭──────────────────────────────────────────────────╮'
    printf '%s\n' '          R E A L M  ·  星 轨 中 转 站'
    printf '%b' "$cyan"
    printf '%s\n' '             /\_/\        ミ☆  连接星河'
    printf '%s\n' '            ( o.o )       每一条连接，都有归宿'
    printf '%s\n' '             > ^ <        Welcome, Commander!'
    printf '%b' "$pink"
    printf '%s\n' '  ╰──────────────────────────────────────────────────╯'
    printf '%b  当前核心：%s  ·  %s\n\n' "$white" "$(get_realm_version)" "$(uname -m)"
    printf '%b  ✦ 启航准备 ──────────────────────────────────────\n' "$cyan"
    printf '%b    [1] 安装 / 更新 Realm（官方最新稳定版）\n\n' "$white"
    printf '%b  ✦ 星轨编排 ──────────────────────────────────────\n' "$pink"
    printf '%b    [2] 添加转发规则        [3] 查看转发规则\n' "$white"
    printf '    [4] 修改转发规则        [5] 删除转发规则\n\n'
    printf '%b  ✦ 引擎控制 ──────────────────────────────────────\n' "$cyan"
    printf '%b    [6] 启动服务            [7] 停止服务\n' "$white"
    printf '    [8] 重启服务            [9] 卸载 Realm\n\n'
    printf '%b  ✦ 航行工具 ──────────────────────────────────────\n' "$pink"
    printf '%b   [10] 定时重启任务\n' "$white"
    printf '   [11] 导出转发规则       [12] 导入转发规则\n\n'
    printf '%b    [0] 返回现实世界  (｡･ω･｡)ﾉ\n' "$cyan"
    printf '%b  ──────────────────────────────────────────────────\n' "$pink"
    printf '%b  安装状态：%b%s%b  |  转发状态：' "$white" "$realm_status_color" "$realm_status" "$reset"
    check_realm_service_status
    printf '%b\n' "$reset"
}

# 部署环境的函数
deploy_realm() {
    local existing_install=0
    if [ -f ${REALM_DIR}/realm ] && [ -f ${REALM_DIR}/config.toml ]; then
        existing_install=1
    fi
    install_latest_realm || return 1
    if [ "$existing_install" -eq 1 ]; then
        realm_status="已安装"
        realm_status_color="\033[0;32m"
        echo "更新检查完成，原有转发配置和服务定义已保留。"
        return 0
    fi
    cd ${REALM_DIR} || return 1
    # 创建服务文件
    echo "[Unit]
Description=realm
After=network.target

[Service]
Type=simple
User=root
Restart=on-failure
RestartSec=5s
WorkingDirectory=${REALM_DIR}
ExecStart=${REALM_DIR}/realm -c ${REALM_DIR}/config.toml

[Install]
WantedBy=multi-user.target" > /etc/systemd/system/realm.service
    systemctl daemon-reload

    # 服务启动后，检查config.toml是否存在，如果不存在则创建
    if [ ! -f ${REALM_DIR}/config.toml ]; then
        touch ${REALM_DIR}/config.toml
    fi

    # 检查 config.toml 中是否已经包含 [network] 配置块
    network_count=$(grep -c '^\[network\]' ${REALM_DIR}/config.toml)

    if [ "$network_count" -eq 0 ]; then
        # 如果没有找到 [network]，将其添加到文件顶部
        echo "[network]
no_tcp = false
use_udp = true
" | cat - ${REALM_DIR}/config.toml > temp && mv temp ${REALM_DIR}/config.toml
        echo "[network] 配置已添加到 config.toml 文件。"

    elif [ "$network_count" -gt 1 ]; then
        # 如果找到多个 [network]，删除多余的配置块，只保留第一个
        sed -i '0,/^\[\[endpoints\]\]/{//!d}' ${REALM_DIR}/config.toml
        echo "[network]
no_tcp = false
use_udp = true
" | cat - ${REALM_DIR}/config.toml > temp && mv temp ${REALM_DIR}/config.toml
        echo "多余的 [network] 配置已删除。"
    else
        echo "[network] 配置已存在，跳过添加。"
    fi

    # 更新realm状态变量
    realm_status="已安装"
    realm_status_color="\033[0;32m" # 绿色
    echo "部署完成。"
}

# 卸载realm
uninstall_realm() {
    local confirm
    read -r -p "将删除 Realm 服务和 $REALM_DIR 中的配置，确认请输入 yes: " confirm || return 1
    [[ "$confirm" == yes ]] || { echo '已取消卸载。'; return 0; }

    systemctl stop realm
    systemctl disable realm
    rm -rf /etc/systemd/system/realm.service
    systemctl daemon-reload
    rm -rf ${REALM_DIR}
    sed -i '/realm/d' /etc/crontab
    echo "Realm已被卸载。"
    # 更新realm状态变量
    realm_status="未安装"
    realm_status_color="\033[0;31m" # 红色
}

# 显示当前所有规则的辅助函数
show_current_rules() {
    # 接收一个参数作为提示消息
    local message=${1:-"操作完成"}

    clear
    echo -e "                      当前 Realm 转发规则                      "
    echo -e "---------------------------------------------------------------------"
    local IFS=$'\n'
    local lines=($(grep -n 'listen =' ${REALM_DIR}/config.toml 2>/dev/null || echo ""))

    if [ ${#lines[@]} -eq 0 ] || [ -z "$lines" ]; then
        echo -e "没有发现任何转发规则。"
    else
        local index=1
        for line in "${lines[@]}"; do
            local line_number=$(echo $line | cut -d ':' -f 1)
            local listen_info=$(sed -n "${line_number}p" ${REALM_DIR}/config.toml | cut -d '"' -f 2)
            local remote_info=$(sed -n "$((line_number + 1))p" ${REALM_DIR}/config.toml | cut -d '"' -f 2)
            local remark=$(sed -n "$((line_number-1))p" ${REALM_DIR}/config.toml | grep "^# 备注:" | cut -d ':' -f 2- | sed 's/^ //')

            printf " %-3s | %-12s | %-45s | %-20s\n" "$index" "$listen_info" "$remote_info" "$remark"
            echo -e "---------------------------------------------------------------------"
            let index+=1
        done
    fi

    echo -e "\n$message，按回车键返回主菜单..."
    read  # 等待用户按回车键
}

# 修改转发规则的函数
modify_forward() {
    clear  # 清屏
    echo -e "                      当前 Realm 转发规则                      "
    echo -e "---------------------------------------------------------------------"
    local IFS=$'\n' # 设置IFS仅以换行符作为分隔符
    # 搜索所有包含 [[endpoints]] 的行，表示转发规则的起始行
    local lines=($(grep -n '^\[\[endpoints\]\]' ${REALM_DIR}/config.toml 2>/dev/null || echo ""))

    if [ ${#lines[@]} -eq 0 ] || [ -z "$lines" ]; then
        echo "没有发现任何转发规则。"
        return
    fi

    local index=1
    for line in "${lines[@]}"; do
        local line_number=$(echo $line | cut -d ':' -f 1)
        local remark_line=$((line_number + 1))
        local listen_line=$((line_number + 2))
        local remote_line=$((line_number + 3))

        local remark=$(sed -n "${remark_line}p" ${REALM_DIR}/config.toml | grep "^# 备注:" | cut -d ':' -f 2- | sed 's/^ //')
        local listen_info=$(sed -n "${listen_line}p" ${REALM_DIR}/config.toml | cut -d '"' -f 2)
        local remote_info=$(sed -n "${remote_line}p" ${REALM_DIR}/config.toml | cut -d '"' -f 2)

        printf " %-3s | %-12s | %-45s | %-20s\n" "$index" "$listen_info" "$remote_info" "$remark"
        echo -e "---------------------------------------------------------------------"
        let index+=1
    done

    echo "请输入要修改的转发规则序号，取消直接按回车键返回主菜单。"
    read -e -p "选择: " choice
    if [ -z "$choice" ]; then
        echo "返回主菜单。"
        return
    fi

    if ! [[ $choice =~ ^[0-9]+$ ]]; then
        echo "无效输入，请输入数字。"
        return
    fi

    if [ $choice -lt 1 ] || [ $choice -gt ${#lines[@]} ]; then
        echo "选择超出范围，请输入有效序号。"
        return
    fi

    local chosen_line=${lines[$((choice-1))]}
    local start_line=$(echo $chosen_line | cut -d ':' -f 1)
    local remark_line=$((start_line + 1))
    local listen_line=$((start_line + 2))
    local remote_line=$((start_line + 3))

    # 获取当前值
    local current_remark=$(sed -n "${remark_line}p" ${REALM_DIR}/config.toml | grep "^# 备注:" | cut -d ':' -f 2- | sed 's/^ //')
    local current_listen=$(sed -n "${listen_line}p" ${REALM_DIR}/config.toml | cut -d '"' -f 2)
    local current_remote=$(sed -n "${remote_line}p" ${REALM_DIR}/config.toml | cut -d '"' -f 2)

    # 提取当前的本地端口
    local current_local_port=$(echo "$current_listen" | grep -o '[0-9]\+$')

    # 修复IPv6地址解析问题
    # 判断是否是IPv6地址（检查是否包含方括号）
    if [[ "$current_remote" == \[*\]* ]]; then
        # IPv6地址格式：[IPv6地址]:端口
        local current_remote_ip=$(echo "$current_remote" | sed -E 's/\[(.*)\]:.*/\1/')
        local current_remote_port=$(echo "$current_remote" | sed -E 's/.*\]:(.*)/\1/')
    else
        # IPv4地址格式：IPv4地址:端口
        local current_remote_ip=$(echo "$current_remote" | cut -d ':' -f 1)
        local current_remote_port=$(echo "$current_remote" | cut -d ':' -f 2)
    fi

    echo -e "\n---------------------------------------------------------------------"
    echo -e "                           当前配置信息                           "
    echo -e "---------------------------------------------------------------------"
    echo -e " 本地端口: $current_local_port"
    echo -e " 远程地址: $current_remote_ip"
    echo -e " 远程端口: $current_remote_port"
    echo -e " 转发备注: $current_remark"
    echo -e "---------------------------------------------------------------------"
    echo -e "                 请输入新的值（直接回车保持不变）                 "
    echo -e "---------------------------------------------------------------------"

    read -e -p " 新的本地端口 [$current_local_port]: " new_local_port
    read -e -p " 新的远程地址 [$current_remote_ip]: " new_remote_ip
    read -e -p " 新的远程端口 [$current_remote_port]: " new_remote_port
    read -e -p " 新的转发备注 [$current_remark]: " new_remark

    # 如果用户没有输入新值，则使用当前值
    new_local_port=${new_local_port:-$current_local_port}
    new_remote_ip=${new_remote_ip:-$current_remote_ip}
    new_remote_port=${new_remote_port:-$current_remote_port}
    new_remark=${new_remark:-$current_remark}

    # 处理IPv6地址的特殊格式
    if [[ "$new_remote_ip" == \[*\]* ]]; then
        # 已经包含方括号的 IPv6 地址，直接添加端口
        remote_format="$new_remote_ip:$new_remote_port"
    elif [[ "$new_remote_ip" == *:*:* ]]; then
        # 不包含方括号的 IPv6 地址，需要添加方括号
        remote_format="[$new_remote_ip]:$new_remote_port"
    else
        # IPv4 地址或主机名
        remote_format="$new_remote_ip:$new_remote_port"
    fi

    # 更新配置文件
    sed -i "${remark_line}s/^# 备注:.*$/# 备注: $new_remark/" ${REALM_DIR}/config.toml
    sed -i "${listen_line}s/listen = \".*\"/listen = \"[::]:$new_local_port\"/" ${REALM_DIR}/config.toml
    sed -i "${remote_line}s/remote = \".*\"/remote = \"$remote_format\"/" ${REALM_DIR}/config.toml

    echo -e "\n---------------------------------------------------------------------"
    echo -e "                          转发规则已更新                          "
    echo -e "---------------------------------------------------------------------"

    # 重启服务
    systemctl restart realm.service
    echo "Realm服务已重新启动。"

    # 显示当前规则
    show_current_rules "规则修改完成"

    # 使用全局变量避免重复按键
    key=1  # 设置一个非空值，使主循环中的read跳过
}



# 删除转发规则的函数
delete_forward() {
    # 标记是否进行了删除操作
    local has_deleted=false

    while true; do
        clear  # 清屏，确保每次只显示一个规则列表
        echo -e "                      当前 Realm 转发规则                      "
        echo -e "---------------------------------------------------------------------"
        local IFS=$'\n' # 设置IFS仅以换行符作为分隔符
        # 搜索所有包含 [[endpoints]] 的行，表示转发规则的起始行
        local lines=($(grep -n '^\[\[endpoints\]\]' ${REALM_DIR}/config.toml 2>/dev/null || echo ""))

        if [ ${#lines[@]} -eq 0 ] || [ -z "$lines" ]; then
            echo "没有发现任何转发规则。"
            if [ "$has_deleted" = true ]; then
                echo "所有规则已删除，正在重启 Realm 服务以应用更改..."
                systemctl restart realm.service
                echo "Realm服务已重新启动。"
                # 设置标记，避免主循环中重复按键，但不需要显示规则列表
                key=1
            fi
            echo "按回车键返回主菜单..."
            read -e  # 用户只需要按一次回车
            return
        fi

        local index=1
        for line in "${lines[@]}"; do
            local line_number=$(echo $line | cut -d ':' -f 1)
            local remark_line=$((line_number + 1))
            local listen_line=$((line_number + 2))
            local remote_line=$((line_number + 3))

            local remark=$(sed -n "${remark_line}p" ${REALM_DIR}/config.toml | grep "^# 备注:" | cut -d ':' -f 2- | sed 's/^ //')
            local listen_info=$(sed -n "${listen_line}p" ${REALM_DIR}/config.toml | cut -d '"' -f 2)
            local remote_info=$(sed -n "${remote_line}p" ${REALM_DIR}/config.toml | cut -d '"' -f 2)

            printf " %-3s | %-12s | %-45s | %-20s\n" "$index" "$listen_info" "$remote_info" "$remark"
            echo -e "---------------------------------------------------------------------"
            let index+=1
        done

        echo "请输入要删除的转发规则序号，取消直接按回车键返回主菜单。"
        read -e -p "选择: " choice
        if [ -z "$choice" ]; then
            # 如果有删除操作，则在返回主菜单前重启服务
            if [ "$has_deleted" = true ]; then
                echo "正在重启 Realm 服务以应用更改..."
                systemctl restart realm.service
                echo "Realm服务已重新启动。"
                # 设置标记，避免主循环中重复按键，但不需要显示规则列表
                key=1
            else
                echo "未进行任何删除操作。"
            fi
            return
        fi

        if ! [[ $choice =~ ^[0-9]+$ ]]; then
            echo "无效输入，请输入数字。"
            continue
        fi

        if [ $choice -lt 1 ] || [ $choice -gt ${#lines[@]} ]; then
            echo "选择超出范围，请输入有效序号。"
            continue
        fi

        local chosen_line=${lines[$((choice-1))]}
        local start_line=$(echo $chosen_line | cut -d ':' -f 1)

        # 找到下一个 [[endpoints]] 行，确定删除范围的结束行
        local next_endpoints_line=$(grep -n '^\[\[endpoints\]\]' ${REALM_DIR}/config.toml | grep -A 1 "^$start_line:" | tail -n 1 | cut -d ':' -f 1)

        if [ -z "$next_endpoints_line" ] || [ "$next_endpoints_line" -le "$start_line" ]; then
            # 如果没有找到下一个 [[endpoints]]，则删除到文件末尾
            end_line=$(wc -l < ${REALM_DIR}/config.toml)
        else
            # 如果找到了下一个 [[endpoints]]，则删除到它的前一行
            end_line=$((next_endpoints_line - 1))
        fi

        # 使用 sed 删除指定行范围的内容
        sed -i "${start_line},${end_line}d" ${REALM_DIR}/config.toml

        # 检查并删除可能多余的空行
        sed -i '/^\s*$/d' ${REALM_DIR}/config.toml

        echo "转发规则及其备注已删除。"

        # 标记已进行删除操作
        has_deleted=true
    done
}

# 查看转发规则
show_all_conf() {
    clear  # 清屏
    echo -e "                      当前 Realm 转发规则                      "
    echo -e "---------------------------------------------------------------------"
    local IFS=$'\n' # 设置IFS仅以换行符作为分隔符
    # 搜索所有包含 listen 的行，表示转发规则的起始行
    local lines=($(grep -n 'listen =' ${REALM_DIR}/config.toml 2>/dev/null || echo ""))

    if [ ${#lines[@]} -eq 0 ] || [ -z "$lines" ]; then
        echo -e "没有发现任何转发规则。"
        return
    fi

    local index=1
    for line in "${lines[@]}"; do
        local line_number=$(echo $line | cut -d ':' -f 1)
        local listen_info=$(sed -n "${line_number}p" ${REALM_DIR}/config.toml | cut -d '"' -f 2)
        local remote_info=$(sed -n "$((line_number + 1))p" ${REALM_DIR}/config.toml | cut -d '"' -f 2)
        local remark=$(sed -n "$((line_number-1))p" ${REALM_DIR}/config.toml | grep "^# 备注:" | cut -d ':' -f 2- | sed 's/^ //')

        printf " %-3s | %-12s | %-45s | %-20s\n" "$index" "$listen_info" "$remote_info" "$remark"
        echo -e "---------------------------------------------------------------------"
        let index+=1
    done
}

# 添加转发规则
add_forward() {
    clear  # 清屏
    # 先显示当前已经添加的规则列表
    echo -e "                      当前 Realm 转发规则                      "
    echo -e "---------------------------------------------------------------------"
    local IFS=$'\n'
    local lines=($(grep -n 'listen =' ${REALM_DIR}/config.toml 2>/dev/null || echo ""))

    if [ ${#lines[@]} -eq 0 ] || [ -z "$lines" ]; then
        echo -e "目前没有任何转发规则。"
    else
        local index=1
        for line in "${lines[@]}"; do
            local line_number=$(echo $line | cut -d ':' -f 1)
            local listen_info=$(sed -n "${line_number}p" ${REALM_DIR}/config.toml | cut -d '"' -f 2)
            local remote_info=$(sed -n "$((line_number + 1))p" ${REALM_DIR}/config.toml | cut -d '"' -f 2)
            local remark=$(sed -n "$((line_number-1))p" ${REALM_DIR}/config.toml | grep "^# 备注:" | cut -d ':' -f 2- | sed 's/^ //')

            printf " %-3s | %-12s | %-45s | %-20s\n" "$index" "$listen_info" "$remote_info" "$remark"
            echo -e "---------------------------------------------------------------------"
            let index+=1
        done
    fi

    echo -e "\n现在添加新的转发规则: (取消按回车键返回主菜单)"

    local has_added=false  # 标记是否添加了规则

    while true; do
        read -e -p "请输入本地监听端口: " local_port
        # 如果用户没有输入内容直接按回车，返回主菜单
        if [ -z "$local_port" ]; then
            echo "未输入端口，返回主菜单。"
            # 如果已经添加了规则，需要重启服务
            if [ "$has_added" = true ]; then
                systemctl restart realm.service
                echo "Realm服务已重新启动，转发规则已应用。"
                # 显示当前规则
                show_current_rules "规则添加完成"
                # 使用全局变量避免重复按键
                key=1
            fi
            return
        fi

        read -e -p "请输入需要转发的IP: " ip
        # 如果用户没有输入内容直接按回车，返回主菜单
        if [ -z "$ip" ]; then
            echo "未输入IP，返回主菜单。"
            # 如果已经添加了规则，需要重启服务
            if [ "$has_added" = true ]; then
                systemctl restart realm.service
                echo "Realm服务已重新启动，转发规则已应用。"
                # 显示当前规则
                show_current_rules "规则添加完成"
                # 使用全局变量避免重复按键
                key=1
            fi
            return
        fi

        read -e -p "请输入需要转发端口: " port
        # 如果用户没有输入内容直接按回车，返回主菜单
        if [ -z "$port" ]; then
            echo "未输入转发端口，返回主菜单。"
            # 如果已经添加了规则，需要重启服务
            if [ "$has_added" = true ]; then
                systemctl restart realm.service
                echo "Realm服务已重新启动，转发规则已应用。"
                # 显示当前规则
                show_current_rules "规则添加完成"
                # 使用全局变量避免重复按键
                key=1
            fi
            return
        fi

        # 备注可以为空，不做检查
        read -e -p "请输入备注(支持中文，可为空): " remark

        # 处理IPv6地址的特殊格式
        if [[ "$ip" == \[*\]* ]]; then
            # 已经包含方括号的 IPv6 地址，直接添加端口
            remote_format="$ip:$port"
        elif [[ "$ip" == *:*:* ]]; then
            # 不包含方括号的 IPv6 地址，需要添加方括号
            remote_format="[$ip]:$port"
        else
            # IPv4 地址或主机名
            remote_format="$ip:$port"
        fi

        # 追加到config.toml文件
        echo "[[endpoints]]
# 备注: $remark
listen = \"[::]:$local_port\"
remote = \"$remote_format\"" >> ${REALM_DIR}/config.toml

        # 标记已添加规则
        has_added=true

        read -e -p "是否继续添加(Y/N)? " answer
        if [[ $answer != "Y" && $answer != "y" ]]; then
            break
        fi

        # 如果用户选择继续添加，清屏并显示更新后的规则列表
        clear
        echo -e "                      当前 Realm 转发规则                      "
        echo -e "---------------------------------------------------------------------"
        local lines=($(grep -n 'listen =' ${REALM_DIR}/config.toml 2>/dev/null || echo ""))
        local index=1
        for line in "${lines[@]}"; do
            local line_number=$(echo $line | cut -d ':' -f 1)
            local listen_info=$(sed -n "${line_number}p" ${REALM_DIR}/config.toml | cut -d '"' -f 2)
            local remote_info=$(sed -n "$((line_number + 1))p" ${REALM_DIR}/config.toml | cut -d '"' -f 2)
            local remark=$(sed -n "$((line_number-1))p" ${REALM_DIR}/config.toml | grep "^# 备注:" | cut -d ':' -f 2- | sed 's/^ //')

            printf " %-3s | %-12s | %-45s | %-20s\n" "$index" "$listen_info" "$remote_info" "$remark"
            echo -e "---------------------------------------------------------------------"
            let index+=1
        done
        echo -e "\n继续添加新的转发规则: (取消按回车键返回主菜单)"
    done

    # 只有在添加了规则才重启服务
    if [ "$has_added" = true ]; then
        systemctl restart realm.service
        echo "Realm服务已重新启动，转发规则已应用。"

        # 显示当前所有规则
        show_current_rules "规则添加完成"

        # 使用全局变量避免重复按键
        key=1  # 设置一个非空值，使主循环中的read跳过
    fi
}



# 导出转发规则
export_rules() {
    clear
    echo -e "                      Realm转发规则导出                      "
    echo -e "---------------------------------------------------------------------"

    local IFS=$'\n' # 设置IFS仅以换行符作为分隔符

    # 搜索所有包含 [[endpoints]] 的行
    local lines=($(grep -n '^\[\[endpoints\]\]' ${REALM_DIR}/config.toml 2>/dev/null || echo ""))

    if [ ${#lines[@]} -eq 0 ] || [ -z "$lines" ]; then
        echo "没有发现任何转发规则。"
        return
    fi

    local index=1
    for line in "${lines[@]}"; do
        local line_number=$(echo $line | cut -d ':' -f 1)
        local remark_line=$((line_number + 1))
        local listen_line=$((line_number + 2))
        local remote_line=$((line_number + 3))

        local remark=$(sed -n "${remark_line}p" ${REALM_DIR}/config.toml | grep "^# 备注:" | cut -d ':' -f 2- | sed 's/^ //')
        local listen_info=$(sed -n "${listen_line}p" ${REALM_DIR}/config.toml | cut -d '"' -f 2)
        local remote_info=$(sed -n "${remote_line}p" ${REALM_DIR}/config.toml | cut -d '"' -f 2)

        # 提取本地端口
        local local_port=$(echo "$listen_info" | grep -o '[0-9]\+$')

        # 输出格式化的数据行
        echo "$index|$local_port|$remote_info|$remark"

        let index+=1
    done
    # 在函数结尾处：
    echo -e "---------------------------------------------------------------------"
    echo -e "已导出 $((index-1)) 条转发规则，请复制保存。"
}

# 导入转发规则
import_rules() {
    clear
    echo -e "                      Realm转发规则导入                      "
    echo -e "---------------------------------------------------------------------"
    echo -e "请按照以下格式粘贴转发规则："
    echo -e "序号|本地端口|远程IP:端口|备注"
    echo " "
    echo -e "例如："
    echo -e "1|8080|192.168.1.1:8000|一号服务器"
    echo -e "2|8443|192.168.1.2:9000|二号服务器"
    echo -e "3|9000|[2001:db8::1]:8080|IPv6服务器"
    echo " "
    echo -e "---------------------------------------------------------------------"
    echo -e "请在下方粘贴规则（粘贴完成后按Ctrl+D结束输入）："

    # 创建临时文件存储用户输入
    local temp_file=$(mktemp)

    # 读取用户输入到临时文件
    cat > "$temp_file"

    # 获取输入行数
    local line_count=$(wc -l < "$temp_file")

    if [ "$line_count" -eq 0 ]; then
        echo "未输入任何规则。"
        rm "$temp_file"
        return
    fi

    # 添加换行，确保与用户输入分开显示
    echo -e "\n检测到 $line_count 条规则，准备导入..."
    read -e -p "是否确认导入？这将添加新的规则，不会覆盖现有规则 (Y/N): " confirm

    if [[ $confirm != "Y" && $confirm != "y" ]]; then
        echo "已取消导入。"
        rm "$temp_file"
        return
    fi

    local success_count=0

    # 逐行处理导入的数据
    while IFS='|' read -r index local_port remote_addr remark || [ -n "$index" ]; do
        # 跳过空行或格式不正确的行
        if [ -z "$index" ] || [ -z "$local_port" ] || [ -z "$remote_addr" ]; then
            continue
        fi

        # 跳过不以数字开头的行（可能是表头）
        if ! [[ $index =~ ^[0-9]+$ ]]; then
            continue
        fi

        # 处理IPv6地址的格式
        if [[ "$remote_addr" != \[*\]* ]] && [[ "$remote_addr" == *:*:* ]]; then
            # 检测到未格式化的IPv6地址（包含多个冒号但不是以[开头）
            # 尝试提取最后一个冒号后的内容作为端口号
            local remote_port="${remote_addr##*:}"
            # 去除最后一部分（端口号）
            local remote_ip="${remote_addr%:$remote_port}"
            # 重新组装为正确的IPv6格式
            remote_addr="[$remote_ip]:$remote_port"
        fi

        # 添加到config.toml
        echo "[[endpoints]]
# 备注: $remark
listen = \"[::]:$local_port\"
remote = \"$remote_addr\"" >> ${REALM_DIR}/config.toml

        let success_count+=1
    done < "$temp_file"

    rm "$temp_file"

    if [ $success_count -gt 0 ]; then
        echo "成功导入 $success_count 条转发规则。"
        # 重启服务
        systemctl restart realm.service
        echo "Realm服务已重新启动。"
        # 显示当前规则
        show_current_rules "规则导入完成"
        # 使用全局变量避免重复按键
        key=1
    else
        echo "没有导入任何规则，请检查输入格式是否正确。"
    fi
}

# 自定义显示服务状态的函数
show_service_status() {
    # 检查服务是否活动
    if systemctl is-active --quiet realm; then
        # 服务活动时显示绿色圆点
        echo -e "\033[0;32m●\033[0m realm.service - realm"
    else
        # 服务不活动时显示红色圆点
        echo -e "\033[0;31m●\033[0m realm.service - realm"
    fi

    # 显示其他状态信息
    systemctl status realm.service --no-pager | tail -n +2 | head -n 4
}

# 启动服务
start_service() {
    systemctl unmask realm.service
    systemctl daemon-reload
    systemctl restart realm.service
    systemctl enable realm.service

    # 检查服务是否成功启动
    if systemctl is-active --quiet realm; then
        echo -e "\033[0;32mRealm服务已成功启动并设置为开机自启。\033[0m"  # 绿色
    else
        echo -e "\033[0;31mRealm服务启动失败！\033[0m"  # 红色
    fi

    echo "Realm 服务状态："
    show_service_status
}

# 停止服务
stop_service() {
    systemctl stop realm

    # 检查服务是否成功停止
    if ! systemctl is-active --quiet realm; then
        echo -e "\033[0;32mRealm服务已成功停止。\033[0m"  # 绿色
    else
        echo -e "\033[0;31mRealm服务停止失败！\033[0m"  # 红色
    fi

    echo "Realm 服务状态："
    show_service_status
}

# 重启服务
restart_service() {
    systemctl stop realm
    systemctl unmask realm.service
    systemctl daemon-reload
    systemctl restart realm.service
    systemctl enable realm.service

    # 检查服务是否成功重启
    if systemctl is-active --quiet realm; then
        echo -e "\033[0;32mRealm服务已成功重启。\033[0m"  # 绿色
    else
        echo -e "\033[0;31mRealm服务重启失败！\033[0m"  # 红色
    fi

    echo "Realm 服务状态："
    show_service_status
}

# 定时任务
cron_restart() {
    clear
    echo -e "---------------------------------------------------------------------"
    echo -e "                        Realm定时重启任务                        "
    echo -e "---------------------------------------------------------------------"
    echo -e "[1] 配置Realm定时重启任务"
    echo -e "[2] 删除Realm定时重启任务"
    echo -e "---------------------------------------------------------------------"
    read -e -p "请选择: " numcron
    if [ "$numcron" == "1" ]; then
        echo -e "---------------------------------------------------------------------"
        echo -e "                      Realm定时重启任务类型                      "
        echo -e "---------------------------------------------------------------------"
        echo -e "[1] 每？小时重启"
        echo -e "[2] 每日？点重启"
        echo -e "---------------------------------------------------------------------"
        read -e -p "请选择: " numcrontype
        if [ "$numcrontype" == "1" ]; then
            echo -e "---------------------------------------------------------------------"
            read -e -p "每？小时重启: " cronhr
            echo "0 */$cronhr * * * root /usr/bin/systemctl restart realm" >>/etc/crontab
            echo -e "定时重启设置成功！"
        elif [ "$numcrontype" == "2" ]; then
            echo -e "---------------------------------------------------------------------"
            read -e -p "每日？点重启: " cronhr
            echo "0 $cronhr * * * root /usr/bin/systemctl restart realm" >>/etc/crontab
            echo -e "定时重启设置成功！"
        else
            echo "输入错误，请重试"
            return
        fi
    elif [ "$numcron" == "2" ]; then
        sed -i "/realm/d" /etc/crontab
        echo -e "定时重启任务删除完成！"
    else
        echo "输入错误，请重试"
        return
    fi
}

# 主循环
main() {
    if [[ "${1:-}" == --help || "${1:-}" == -h ]]; then
        printf 'Realm 独立管理脚本：bash realm.sh，或 opsbox realm。\n'
        return 0
    fi
    if [[ $(uname -s) != Linux || $EUID -ne 0 ]]; then
        echo 'Realm 管理需要 Linux root 权限。' >&2
        return 1
    fi
    [[ ! -t 0 ]] || stty erase "^?" 2>/dev/null || true
    REALM_DIR=$(realm_default_dir)
    realm_refresh_status
    local choice key=''
    while true; do
    show_menu
    read -e -r -p "✧ 指挥官，请选择行动 [0-12]（h 首页 / q 退出）: " choice || return 0
    # 去掉输入中的空格
    choice=$(echo $choice | tr -d '[:space:]')

    case "$choice" in
        h|H) [[ -z "${OPSBOX_VERSION:-}" ]] && return 0; return 20 ;;
        q|Q) [[ -z "${OPSBOX_VERSION:-}" ]] && return 0; return 21 ;;
        b|B) return 0 ;;
    esac
    # 检查输入是否为数字，并在有效范围内
    if ! [[ "$choice" =~ ^([0-9]|1[0-2])$ ]]; then
        echo "无效选项: $choice"
        continue
    fi

    case $choice in
        1)
            deploy_realm
            ;;
        2)
            add_forward
            # 如果key变量有值，说明刚从添加完成界面返回，无需再次等待按键
            if [ -n "$key" ]; then
                key=""  # 清空key变量
                continue
            fi
            ;;
        3)
            show_all_conf
            ;;
        4)
            modify_forward
            # 如果key变量有值，说明刚从修改完成界面返回，无需再次等待按键
            if [ -n "$key" ]; then
                key=""  # 清空key变量
                continue
            fi
            ;;
        5)
            delete_forward
            # 如果key变量有值，说明刚从删除完成界面返回，无需再次等待按键
            if [ -n "$key" ]; then
                key=""  # 清空key变量
                continue
            fi
            ;;
        6)
            start_service
            ;;
        7)
            stop_service
            ;;
        8)
            restart_service
            ;;
        9)
            uninstall_realm
            ;;
        10)
            cron_restart
            ;;
        11)
            export_rules
            ;;
        12)
            import_rules
            # 如果key变量有值，说明刚从导入完成界面返回，无需再次等待按键
            if [ -n "$key" ]; then
                key=""  # 清空key变量
                continue
            fi
            ;;
        0)
            echo "退出脚本。"  # 显示退出消息
            return 0          # 返回调用方
            ;;
        *)
            echo "无效选项: $choice"
            ;;
    esac

    # 如果key变量有值，说明刚从某个操作完成界面返回，无需再次等待按键
    if [ -n "$key" ]; then
        key=""  # 清空key变量
        continue
    fi

    read -e -r -p "按回车返回主菜单..." key || return 0
done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
