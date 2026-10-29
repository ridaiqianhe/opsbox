# OpsBox

常用服务器工具箱：代理协议、随机 IPv6 SOCKS5、Realm 转发与 SSH 管理。

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

## 工具

| 模块 | 命令 | 功能 |
| --- | --- | --- |
| [代理协议](modules/vps-proxy/README.md) | `opsbox proxy` | Snell、Hysteria2、SS2022、AnyTLS、TUIC、Trojan、Reality、Shadow-TLS、SOCKS/HTTP 与 TCP 调优 |
| [随机 IPv6](modules/random-ipv6-socks/README.md) | `opsbox ipv6` | Xray 随机 IPv6 出口、可选 IPv4 出口、Docker 生命周期管理 |
| [Realm 转发](modules/realm/README.md) | `opsbox realm` | TCP/UDP 端口转发、规则与服务管理 |
| [SSH 管理](modules/ssh/README.md) | `opsbox ssh` | 修改用户密码、SSH 端口、查看设置及显式启用登录方式 |

支持直接进入工具或执行 IPv6 容器操作：

```bash
opsbox proxy snell
opsbox proxy reality
opsbox proxy ss-2022 -p 8388 -w 'YOUR_PASSWORD'
opsbox ipv6 setup
opsbox ipv6 install
opsbox ipv6 status
```

Linux 发行版、架构及依赖要求见各模块说明。随机 IPv6 模块需要 Docker Engine、Compose v2 和可用的全局 IPv6 前缀。Realm 模块当前保留原有 Linux x86_64 / systemd 安装器及固定的 v2.6.2 版本。

## 现有服务迁移

- 代理协议脚本和 Realm 沿用原来的系统服务名、配置路径，进入工具箱不会重新安装。
- 已部署的随机 IPv6 容器应继续从原工作目录管理。迁移时先备份，将旧目录中的 `.env`、`data/` 复制到 `modules/random-ipv6-socks/`，停用旧 Compose 项目后再启动新目录，避免同名容器及端口冲突。
- 随机 IPv6 默认继续使用原有公开镜像 `ghcr.io/ridaiqianhe/random-ipv6-socks`，保证已有部署可拉取。`LOCAL_BUILD=true` 可从合并后的源码构建。
- 本仓库保留独立的多架构镜像发布工作流。发布并确认新的 `ghcr.io/ridaiqianhe/opsbox` 包可公开拉取后，可在 `.env` 设置 `SOCKS_IMAGE=ghcr.io/ridaiqianhe/opsbox` 和对应 `IMAGE_TAG`。
- SSH 密码通过系统 `passwd` 交互输入，不回显密码。修改 SSH 配置会保留备份、执行 `sshd -t` 校验，重载失败时回滚；不自动开启 root 密码登录、不修改防火墙或云安全组。

原四个仓库保持可访问，旧安装链接仍可使用。新的维护入口为本仓库；来源及导入提交见 [SOURCES.md](SOURCES.md)。

## 开发检查

```bash
find . -name '*.sh' -not -path './.git/*' -print0 | xargs -0 -n1 bash -n
python3 -m unittest discover -s tests -v
python3 -m unittest discover -s modules/random-ipv6-socks/tests -v
```

完整 CI 还执行 ShellCheck、Compose 配置校验和 Docker 镜像构建。测试在临时目录中使用模拟服务命令，不修改宿主机 SSH、密码或代理服务。
