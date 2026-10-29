# Random IPv6 SOCKS5

[![CI](https://github.com/ridaiqianhe/random-ipv6-socks/actions/workflows/ci.yml/badge.svg)](https://github.com/ridaiqianhe/random-ipv6-socks/actions/workflows/ci.yml)
[![Publish GHCR](https://github.com/ridaiqianhe/random-ipv6-socks/actions/workflows/publish.yml/badge.svg)](https://github.com/ridaiqianhe/random-ipv6-socks/actions/workflows/publish.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

使用 Xray 提供带账号密码认证的 SOCKS5，并为每个新连接从 IPv6 CIDR 中随机选择出口地址。还可启用独立端口，强制使用服务器 IPv4 出口。容器启动时自动恢复 `ip_nonlocal_bind`、本地路由和 NDP 代理。

Authenticated Xray SOCKS5 with a random IPv6 source address per connection and an optional IPv4 egress listener.

## 特性

- 自动检测默认 IPv6 网卡和全局前缀。
- 自动生成稳定的 `/120` 随机出口池，也支持手动指定 CIDR。
- 使用 `ndppd` 处理 NDP 回程，每次启动自动恢复 local route。
- 可选第二个 SOCKS5 端口，固定使用服务器 IPv4 出口。
- 支持 SOCKS5 用户名/密码、TCP 和可选 UDP。
- 非特权容器，根文件系统只读，仅授予必要 capabilities。
- Xray 与 `ndppd` 双进程健康检查，支持异常和重启恢复。
- 支持 `amd64` 和 `arm64`。
- 默认从 GHCR 拉取预构建多架构镜像，也支持完全本地构建。

## 前提

- Linux 服务器拥有可用的全局 IPv6 前缀，常见为 `/64`。
- 上游通过 NDP 访问该前缀中的地址。
- 已安装 Docker Engine 和 Docker Compose v2。
- 公网防火墙已放行所选 TCP/UDP 端口。

## 部署

```bash
git clone https://github.com/ridaiqianhe/random-ipv6-socks.git
cd random-ipv6-socks
cp .env.example .env
nano .env
sudo ./install.sh
```

默认拉取：

```text
ghcr.io/ridaiqianhe/random-ipv6-socks:latest
```

必须修改：

```dotenv
SOCKS_PORT=12345
SOCKS_USERNAME=your-user
SOCKS_PASSWORD=your-strong-password
```

凭据包含 `#`、`$` 或空格时，请使用 Compose `.env` 支持的单引号格式。修改参数后再次运行 `sudo ./install.sh` 即可重建容器。
监听端口必须在 `1024-65535` 范围内。

如需同时启用 IPv4 出口端口：

```dotenv
IPV4_PROXY_ENABLED=true
IPV4_SOCKS_PORT=12346
```

IPv4 端口复用 `SOCKS_USERNAME` 和 `SOCKS_PASSWORD`。`IPV4_SOCKS_PORT` 必须与 `SOCKS_PORT` 不同；也可通过 `IPV4_SOCKS_LISTEN`、`IPV4_SOCKS_UDP` 和 `IPV4_SOCKS_UDP_ADVERTISE_IP` 单独调整监听和 UDP 设置。

如需从 Dockerfile 本地构建，在 `.env` 中设置：

```dotenv
LOCAL_BUILD=true
XRAY_VERSION=26.3.27
```

也可以通过 `IMAGE_TAG=1.0.0` 固定预构建镜像版本，避免自动跟随 `latest`。

`IPV6_INTERFACE=auto` 会选择默认 IPv6 路由所在网卡。`IPV6_POOL` 留空时，项目会从网卡前缀稳定生成一个 `/120` 地址池；也可手动指定：

```dotenv
IPV6_INTERFACE=eth0
IPV6_POOL=2001:db8:1234:5678:2026:2026:2026:2000/120
```

## 使用

```bash
curl --proxy 'socks5h://USER:PASSWORD@SERVER_IP:PORT' https://api.ip.sb/ip
```

多次执行会看到地址在配置的 IPv6 池中随机变化。随机选择允许重复，不保证连续两次一定不同。

启用 IPv4 端口后，可用相同凭据访问 `IPV4_SOCKS_PORT`：

```bash
curl --proxy 'socks5h://USER:PASSWORD@SERVER_IP:12346' https://api4.ipify.org
```

IPv4 入口使用独立的 Xray 路由和 Freedom 出口，并强制使用 IPv4；IPv6-only 目标会连接失败。原 `SOCKS_PORT` 仍保持随机 IPv6 出口。

## 运维

```bash
docker compose ps
docker compose logs -f
docker compose restart
docker compose up -d --build
docker compose down
```

也可以使用 `sudo ./uninstall.sh` 停止并删除容器；加上 `--purge` 会同时删除日志和本项目写入的宿主机配置。

访问日志位于 `data/logs/access.log`，错误日志位于 `data/logs/error.log`。

## 持久化机制

- Compose 使用 `restart: unless-stopped`。
- 每次启动等待默认 IPv6 路由和全局地址就绪。
- 安装脚本通过 `/etc/sysctl.d/99-random-ipv6-socks.conf` 持久化 `net.ipv6.ip_nonlocal_bind`，容器启动时进行校验。
- 每次启动重新写入 IPv6 local route。
- `ndppd` 和 Xray 任意一个退出时容器都会退出，由 Docker 自动重启。
- `/120` 最多提供 256 个地址，并限制上游邻居缓存压力。

## 安全说明

SOCKS5 认证和协议本身不加密，不应在不可信网络中传输敏感凭据。建议使用强密码、源 IP 防火墙，或在 WireGuard、SSH 隧道等加密通道内使用。

项目需要 host network、`NET_ADMIN` 和 `NET_RAW` 来管理 IPv6 路由及 NDP，但不会使用 Docker `privileged` 模式。`.env` 不会被 Git 跟踪，安装脚本会将其权限设为 `0600`；凭据仍可被拥有 Docker 管理权限的用户查看。

第三方组件及许可证见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)，安全问题报告方式见 [SECURITY.md](SECURITY.md)。
