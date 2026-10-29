#!/usr/bin/env bash
# id|label|fixed command|search terms|kind (menu, view, action, danger)
# No user input is evaluated as shell code.
opsbox_catalog() {
    cat <<'CATALOG'
overview|系统概览|overview|系统 资源 CPU 内存 磁盘 负载 主机 状态|view
check|网络体检|check|网络 连通 IPv4 IPv6 DNS 检查|view
ports|监听端口|ports|端口 监听 TCP UDP 进程 PID|view
port-check|按端口诊断|port-check|占用 连接 查看|view
cpu|CPU 进程排行|cpu|进程 性能 排序|view
memory|内存进程排行|memory|进程 占用 排序|view
services|服务健康|services|systemd 失败 时间 同步 重启|view
proxy|代理协议|proxy|节点 Snell Reality Hysteria2 AnyTLS SS2022|menu
snell|Snell|proxy snell|代理 Surge v5 v6|menu
reality|VLESS Reality|proxy reality|代理 Xray Vision|menu
hysteria2|Hysteria2|proxy hysteria2|代理 UDP QUIC|menu
ss-2022|Shadowsocks 2022|proxy ss-2022|代理 SS shadowsocks|menu
anytls|AnyTLS|proxy anytls|代理 sing-box TLS|menu
anytls-reality|AnyTLS Reality|proxy anytls-reality|代理 sing-box|menu
tuic|TUIC v5|proxy tuic|代理 UDP QUIC|menu
trojan|Trojan|proxy trojan|代理 TLS|menu
shadow-tls|Shadow-TLS|proxy shadow-tls|代理 Snell SS|menu
socks-http|SOCKS5 / HTTP 代理|proxy socks-http|代理 mixed HTTPS|menu
ipv6|随机 IPv6 SOCKS5|ipv6|Docker 代理 出口 地址池|menu
ipv6-status|IPv6 SOCKS5 状态|ipv6 status|Docker 容器 健康|view
ipv6-logs|IPv6 SOCKS5 日志|ipv6 logs|Docker 日志|view
ipv6-setup|配置 IPv6 SOCKS5|ipv6 setup|Docker 账号 密码 端口|action
realm|Realm 转发|realm|端口转发 TCP UDP 中转|menu
network|网络诊断与修复|network|优先级 IPv4 IPv6 连通|menu
ipv6-system|宿主机 IPv6|ipv6-system|开关 路由 SLAAC 修复|menu
nat66|IPv6 地址池 / NAT66|nat66|系统 随机出口 /64 /128|menu
tcp|TCP / BBR 调优|tcp|网络 优化 tcpfit 缓冲|menu
dns|DNS 设置|dns|解析 Cloudflare Google Quad9|menu
mtu|MTU 管理|mtu|网络 探测 包大小|menu
system|系统工具|system|进程 端口 服务 管理|menu
swap|Swap 管理|swap|内存 交换 swappiness|menu
cleanup|磁盘与日志清理|cleanup|磁盘 journal 缓存|menu
updates|更新与时间同步|updates|软件 包 NTP chrony 健康|menu
timezone|设置中国时区|timezone|时间 Asia Shanghai|action
ssh|SSH 快捷管理|ssh|密码 端口 root 登录|menu
ssh-advanced|SSH 密钥与安全审计|ssh-advanced|用户 公钥 加固 登录 记录|menu
firewall|防火墙|firewall|UFW firewalld 端口 放行 封禁|menu
fail2ban|Fail2Ban|fail2ban|SSH 防爆破 白名单 解封|menu
site|静态导航站|site|网站 Nginx HTTPS 证书 续期|menu
reverse-proxy|HTTPS 反向代理|reverse-proxy|网站 Nginx 证书 WebSocket|menu
test|性能与网络测试|test|测速 跑分 Geekbench 回程 解锁|menu
cloud|换 IP 与云初始化|cloud|cloud-init QGA DMIT PVE|menu
recovery|备份与恢复|recovery|快照 回滚 迁移|menu
snapshot|保存配置快照|snapshot|备份 网络 SSH 防火墙|action
dd|DD 重装系统|dd|高风险 清空 磁盘 重装|danger
CATALOG
}
