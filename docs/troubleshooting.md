# 常见问题与解决（实际踩过的坑）

一次只改一处，改完验证，再看下一个。

## 1. 公钥加了，还是要求输入密码 / 密钥被拒绝
**现象：** `authorized_keys` 已写入公钥，但仍提示输入密码。
**原因：** 服务商镜像里某个配置写了 `PubkeyAuthentication no`。sshd 同一选项**以第一次出现的为准**。
**检查：** `sshd -T | grep -i pubkeyauthentication`，以及 `grep -ri pubkey /etc/ssh/sshd_config /etc/ssh/sshd_config.d/`
**解决：** 用 drop-in `/etc/ssh/sshd_config.d/00-vps-key.conf`（`00-` 保证最先读取）写入：
```
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
```
然后 `sshd -t && systemctl reload ssh`。`install.sh` 已自动处理。

## 2. ssh-keygen 提示文件已存在
**现象：** `~/.ssh/id_ed25519 already exists. Overwrite (y/n)?`
**解决：** 选 `n`，**不要覆盖**（可能是 GitHub 等其他用途的密钥）。改用单独文件：
`ssh-keygen -t ed25519 -f $env:USERPROFILE\.ssh\id_ed25519_vps -C vps-key`，登录时用 `-i` 指定。

## 3. 连上节点后完全没网
**常见原因：**
- 同时开着**另一个代理客户端**（机场 App、Clash 等）→ 关掉，只留 v2rayN。
- 浏览器里有 **SwitchyOmega** 等插件指向旧端口 → 删除/停用插件。
- v2rayN 没选中活动节点，或系统代理没设成「自动配置」。
**验证：** 关掉插件后浏览器访问 https://www.google.com 。

## 4. Codex 连不上 / 提示代理错误
**原因：** Codex 预期代理在 `127.0.0.1:7892`。
**解决：** v2rayN「参数设置」→ 本地混合监听端口改为 `7892`，重启服务。

## 5. Codex 任务面板显示「status unavailable」
**原因：** 这部分流量不走系统代理。
**解决：** 以管理员身份运行 v2rayN，开启 **TUN**（默认设置：auto route、strict route、gvisor）。见 [clients.md](clients.md#5-codex-桌面版任务面板需要-tun-模式)。

## 6. 开了 TUN 后公司内网 / 局域网打不开
**原因：** TUN 把局域网流量也送进了代理。
**解决：** 在 `V4-绕过大陆(Whitelist)` 最顶部加规则：IP `192.168.0.0/16` → `direct`，置顶、保存、重启服务。
（公司内网如果是 `10.x` 或 `172.16-31.x`，相应加 `10.0.0.0/8`、`172.16.0.0/12`。）

## 7. 日志刷屏 `REALITY: received real certificate`
**原因：** TUN 模式下，v2rayN 连接 VPS 的流量又被 TUN 捕获、再次送进代理，形成回环，最终连到了伪装站点的真实证书。
**解决：** 在规则集最顶部加 IP `<VPS_IP>/32` → `direct`，置顶、保存、重启服务。

## 8. 日志里很多 `endpoint not connected`
**无害**，TUN 模式下连接关闭时的正常日志。把 v2rayN「Core 日志等级」设为 `error` 即可隐藏。

## 9. 刚开 TUN 断网几秒
**正常**，TUN 网卡初始化和路由切换需要几秒。超过 30 秒还不通再排查。

## 10. 改了 SSH 端口后连不上
- 当前窗口**先别关**。在服务器上检查：`ss -lntp | grep sshd`、`ufw status`。
- 确认防火墙放行：`ufw allow <端口>/tcp`。
- 服务商控制台如果有「安全组 / 防火墙」，也要放行该端口和 443。
- 实在连不上，用服务商网页上的 VNC/控制台登录修复（**不要重装系统**）。

## 11. Xray 启动失败
```bash
xray run -test -config /usr/local/etc/xray/config.json
journalctl -u xray -n 50 --no-pager
ss -lntp | grep ':443'     # 是否有别的程序（nginx 等）占用 443
```

## 12. 节点突然不能用了
按 [usage.md](usage.md#出问题时的处理顺序从便宜到贵) 的顺序处理：先查本地 → 重启 xray → 换端口/SNI → 换协议 → 换 IP（要花钱，先确认）。
