# SSH 管理

运行 `opsbox ssh`。需要 Linux root 和已安装的 OpenSSH 服务端。

- 修改本地用户密码：调用系统 `passwd`，由系统隐藏输入并检查密码策略，不打印或保存密码。
- 修改 SSH 端口：先确认云安全组和防火墙已放行；配置备份后检查候选文件，重载失败回滚。保留当前连接，使用新端口登录成功后再断开。
- 查看全局设置：读取 `sshd -T`，不修改系统。用户级 `Match` 条件需要结合对应用户单独核查。
- 启用密码登录、允许 root 登录为两个单独选项，均需显式确认，不会因为修改密码而自动开启。

备份保存在 `/etc/ssh/sshd_config.opsbox-backup.*`。保留原有 Include 和 Match 配置；候选全局值与预期不一致时拒绝写入。使用 `ssh.socket` 的系统不通过本工具修改端口。服务重载支持 systemd 和 OpenRC。

与旧脚本相比，不再停止 WARP、解除 passwd/shadow 的文件保护、禁用 SSH Include、打印 root 密码或自动开放登录方式。
