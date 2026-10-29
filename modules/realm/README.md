# Realm 转发

通过 `opsbox realm` 管理 TCP/UDP 转发。当前保留原有 Linux x86_64 / systemd 安装器，固定使用 Realm v2.6.2。

## 运行方式

```bash
opsbox realm
```

也可在仓库目录运行 `sudo bash modules/realm/realm.sh`。原有服务名 `realm` 和配置目录 `/etc/realm` 保持不变。卸载需要显式确认，会删除服务和转发配置，但不会删除工具箱源码。
