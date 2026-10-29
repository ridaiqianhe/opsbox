# OpsBox

常用服务器工具箱：代理与转发、网络调优、系统维护、SSH 与防护、建站反代、云主机诊断及备份恢复。

[![CI](https://github.com/ridaiqianhe/opsbox/actions/workflows/ci.yml/badge.svg)](https://github.com/ridaiqianhe/opsbox/actions/workflows/ci.yml)

## 安装

在 Linux 服务器上运行，安装过程只下载工具箱，不安装或修改任何服务：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ridaiqianhe/opsbox/main/install.sh)
```

root 安装后运行 `opsbox`；普通用户安装后运行 `~/.local/bin/opsbox`。实际管理服务时需要 root。默认源码位于 `~/.local/share/opsbox`，可用 `OPSBOX_DIR=/opt/opsbox` 指定绝对路径。`OPSBOX_BIN_DIR` 可指定命令安装目录。

也可以直接运行 Git 工作副本：

```bash
git clone https://github.com/ridaiqianhe/opsbox.git
cd opsbox
sudo bash opsbox.sh
```

重新运行安装命令可更新工具箱，保留模块下的 `.env` 和 `data/`；更新源码不会重启服务。Git 工作副本使用 `git pull --ff-only` 更新。

## 分类菜单

```text
OpsBox
├─ 1. 代理与转发       代理协议 / 随机 IPv6 SOCKS5 / Realm
├─ 2. 网络与调优       网络诊断 / IPv6 / NAT66 / TCP / DNS / MTU
├─ 3. 系统维护         系统与进程 / 端口 / Swap / 清理 / 更新
├─ 4. SSH 与安全       快捷操作 / 密钥与审计 / 防火墙 / Fail2Ban
├─ 5. 网站与反代       静态导航站 / HTTPS 反向代理
├─ 6. 测试与云主机     性能与线路测试 / cloud-init / QGA
├─ 7. 备份与恢复       配置快照 / 回滚 / 旧网站迁移
└─ 8. 高影响操作       DD 重装系统
```

按用途归类，进入菜单不会自动安装服务、调整网络或迁移网站。`opsbox help` 可查看全部快捷命令，`opsbox version` 查看版本。

```bash
opsbox proxy snell          # 代理协议
opsbox ipv6 status         # 独立 Docker SOCKS5 状态
opsbox network             # 网络诊断与修复菜单
opsbox tcp                 # 统一 TCP / BBR 调优
opsbox ssh                 # 原有 SSH 快捷管理
opsbox ssh-advanced        # 密钥、用户及安全审计
opsbox firewall            # UFW/firewalld
opsbox reverse-proxy       # HTTPS 反代
opsbox recovery            # 快照、恢复、迁移
```

模块文档：[代理协议](modules/vps-proxy/README.md)、[随机 IPv6 SOCKS5](modules/random-ipv6-socks/README.md)、[Realm](modules/realm/README.md)、[SSH 快捷管理](modules/ssh/README.md)、[系统与网络模块](modules/system/README.md)。

系统与网络模块需要 Linux、Bash 4+ 和 root。随机 IPv6 SOCKS5 需要 Docker Engine、Compose v2 和全局 IPv6 前缀。Realm 保留原有 Linux x86_64 / systemd 安装器及固定的 v2.6.2 版本。各模块的发行版和架构支持并不完全相同。

## 现有服务迁移

- 代理协议脚本和 Realm 沿用原来的系统服务名、配置路径，进入工具箱不会重新安装。
- 已部署的随机 IPv6 容器应继续从原工作目录管理。迁移时先备份，将旧目录中的 `.env`、`data/` 复制到 `modules/random-ipv6-socks/`，停用旧 Compose 项目后再启动新目录，避免同名容器及端口冲突。
- 随机 IPv6 默认继续使用原有公开镜像 `ghcr.io/ridaiqianhe/random-ipv6-socks`，保证已有部署可拉取。`LOCAL_BUILD=true` 可从合并后的源码构建。
- 本仓库保留独立的多架构镜像发布工作流。发布并确认新的 `ghcr.io/ridaiqianhe/opsbox` 包可公开拉取后，可在 `.env` 设置 `SOCKS_IMAGE=ghcr.io/ridaiqianhe/opsbox` 和对应 `IMAGE_TAG`。
- `opsbox ssh` 中修改密码通过系统 `passwd` 交互输入，不回显密码。修改 SSH 配置会保留备份、执行 `sshd -t` 校验，重载失败时回滚；不自动开启 root 密码登录、不修改防火墙或云安全组。

- DMITBox 配置路径和受管标记保留；不会在启动时清理防火墙或自动迁移网站。旧网站迁移位于 `opsbox recovery`，需要显式确认。
- 宿主机 NAT66 与独立随机 IPv6 SOCKS5 分开管理，并检查相互冲突；旧 VPS-Proxy TCP 参数也须恢复后再启用统一调优。

原四个仓库保持可访问，旧安装链接仍可使用。新的维护入口为本仓库；来源及导入提交见 [SOURCES.md](SOURCES.md)。

## 开发检查

```bash
find . -name '*.sh' -not -path './.git/*' -print0 | xargs -0 -n1 bash -n
python3 -m unittest discover -s tests -v
python3 -m unittest discover -s modules/random-ipv6-socks/tests -v
```

完整 CI 还执行 ShellCheck、Compose 配置校验和 Docker 镜像构建。测试在临时目录中使用模拟服务命令，不修改宿主机 SSH、密码或代理服务。
