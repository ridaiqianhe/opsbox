# Realm 独立管理脚本

`realm.sh` 使用原 Gist `cf516fc8182035c7cabfbe80fab163db` 的实现，独立放在此目录，不依赖 OpsBox 的其他脚本文件。

```bash
# 在 OpsBox 中使用
opsbox realm

# 也可以单独下载运行（Linux root）
wget -N https://raw.githubusercontent.com/ridaiqianhe/opsbox/main/modules/realm/realm.sh
chmod +x realm.sh
./realm.sh
```

## 功能

- 从 Realm 官方 GitHub 获取最新稳定版，自动匹配 x86_64、ARM64、ARMv7、ARMv6 或 ARMv5 构建；优先 musl。
- 安装、更新、启动、停止、重启和卸载；更新失败时恢复原程序。
- 添加、查看、修改、删除 TCP/UDP 转发规则，支持 IPv4、IPv6、域名和中文备注。
- 批量导入、导出转发规则，设置定时重启。

## 兼容已有安装

原 Gist 默认使用 `/root/realm`，此前 OpsBox 使用 `/etc/realm`。脚本优先识别已有 systemd 服务所使用的目录，再查找已有配置；没有已有配置时使用 `/root/realm`。已安装程序的更新保留原转发配置和服务定义。

仅下载或查看帮助不会安装服务。卸载需输入 `yes`，会移除 Realm 服务及所选数据目录，但不会删除 `realm.sh` 或整个 OpsBox。

原 Gist 的菜单、规则功能和更新机制保留；调整了数据目录兼容、无终端输入处理及卸载保护。在 OpsBox 中可用 `h` 回首页、`q` 退出。
