# 系统与网络工具

由用户提供的 DMITBox 脚本整合而来。原发布入口：<https://box.dmitstock.com/>；原脚本版本标记为 `2026.08.14`。保留原作者来源和现有系统配置路径，工具箱界面统一为 OpsBox。

## 分类入口

| 功能 | 命令 |
| --- | --- |
| 直接查看系统 / 网络 / 端口 | `opsbox overview`、`opsbox check`、`opsbox ports` |
| CPU / 内存排行 / 服务健康 | `opsbox cpu`、`opsbox memory`、`opsbox services` |
| 网络诊断、修复、IPv4/IPv6 优先级 | `opsbox network` |
| IPv6 开关与修复 | `opsbox ipv6-system` |
| 地址池、宿主机 NAT66 随机出网 | `opsbox nat66` |
| BBR、固定 TCP 参数、tcpfit 实测调优 | `opsbox tcp` |
| DNS 与 MTU | `opsbox dns`、`opsbox mtu` |
| 系统、进程、监听端口和服务健康 | `opsbox system` |
| 中国时区 | `opsbox timezone` |
| Swap、清理、更新和时间同步 | `opsbox swap`、`opsbox cleanup`、`opsbox updates` |
| 用户、SSH 密钥、认证检查、登录记录 | `opsbox ssh-advanced` |
| UFW/firewalld、Fail2Ban | `opsbox firewall`、`opsbox fail2ban` |
| Nginx 导航站与 HTTPS 反代 | `opsbox site`、`opsbox reverse-proxy` |
| 外部性能和网络测试 | `opsbox test` |
| cloud-init、QGA、换 IP 配套设置 | `opsbox cloud` |
| 快照、恢复、旧网站迁移 | `opsbox recovery` |
| DD 重装系统 | `opsbox dd` |

需要 Linux、Bash 4+ 和 root。具体操作按需安装相应依赖；并非所有功能都适用于全部发行版。cloud-init 的 DMIT/PVE 配套配置仅用于相符的云主机环境；路由器固件及 macOS 不在此模块的运行范围内。

菜单支持 `0/b` 返回、`h` 回 OpsBox 首页、`q` 退出；普通配置字段中的 h/q 仍按输入值处理。结果页只停顿一次，CLI 直接查看命令不额外等待按键。

## 导航站主题

新建或重新生成导航站默认使用“简约白”：白色独立卡片、灰黑配色、细边框与轻悬停反馈。桌面三列，手机两列；超窄屏会切换单列。分类可直接跳转，搜索使用 Bing，不引入前端脚本或第三方字体。原有蓝、绿、橙点缀色与随机配色选项仍可选择。

## 整合行为

- `core.sh` 只提供函数，`manage.sh` 通过固定命令白名单调用。加载、查看主菜单和返回子菜单不会运行旧版启动清理或迁移。
- 网站状态查看不再自动迁移；旧 DMITBox 网站迁移位于“备份与恢复”，需输入 `MIGRATE`。网络/TCP/SSH 综合恢复需输入 `RESTORE`。
- 退出输入或关闭输入流会退出，不会将空输入自动当成操作确认。
- 保留 `/etc/dmit-*.conf`、`/etc/dmitbox-*`、`/root/dmit-backup` 等原路径和受管标记，以识别已有配置和备份。整合不是自动迁移部署。
- 宿主机 NAT66 和独立随机 IPv6 SOCKS5 容器使用不同机制，互相检查冲突后再启动；不要同时用它们修改同一出口。
- 存在 `/etc/sysctl.d/99-vps-proxy-tcp.conf` 时，新的 TCP 调优拒绝叠加。先运行 `opsbox tcp legacy` 在旧工具中恢复参数，再选择统一调优。
- 保留 tcpfit 的固定版本和 SHA-256 校验。外部测速及 DD 重装仍在明确选择后运行第三方程序；DD 会清空系统盘。

## 来源恢复与验证

用户提供的附件发生过 UTF-8/GB18030 混淆，部分中文字符及 Shell 符号丢失。导入时恢复了可还原的编码，并按上下文重写缺失的显示文字；移除了已经不再调用的旧版网站自动停复实现。原发布入口在本次取证时返回 Cloudflare 验证页，未把该验证页作为脚本，也未自动采用未经核对的远端内容。

测试覆盖无副作用加载、菜单退出、确认取消、端口校验、远程反代 URL/IP 校验、导航页与 Nginx 配置生成、嵌入 Python 语法，以及既有 OpsBox 功能。真实 SSH 切换、防火墙变更、内核调优、证书申请和系统重装未在用户现有服务器执行；这些操作仍需在适合的 Linux 主机上逐项使用。
