# SSH 密钥：生成、添加、登录

> ⚠️ **顺序很重要：先把公钥加到服务器并测试能用密钥登录，再关闭密码登录。**
> `install.sh` 在 `/root/.ssh/authorized_keys` 里找不到公钥时，会拒绝关闭密码登录。

## Windows（🖥️ PowerShell）

```powershell
# 如果 $env:USERPROFILE\.ssh\id_ed25519 已经存在（别的用途），不要覆盖，用单独文件名：
ssh-keygen -t ed25519 -f $env:USERPROFILE\.ssh\id_ed25519_vps -C vps-key
# 提示输入 passphrase（口令）可以设置，也可以直接回车留空
# 查看公钥（这一行可以公开，私钥绝不外传）：
Get-Content $env:USERPROFILE\.ssh\id_ed25519_vps.pub
```

预期输出类似：`ssh-ed25519 AAAAC3Nza... vps-key`

## 安卓 Termux（📱）

```bash
pkg update && pkg install -y openssh
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_vps -C phone-key
cat ~/.ssh/id_ed25519_vps.pub
```

## 把公钥加到服务器（🌐 服务器，仍用密码登录时）

```bash
mkdir -p /root/.ssh && chmod 700 /root/.ssh
nano /root/.ssh/authorized_keys     # 每把公钥一行：电脑一行、手机一行，粘贴后保存
chmod 600 /root/.ssh/authorized_keys
grep -c '^ssh-' /root/.ssh/authorized_keys   # 预期: 2（两把公钥）
```

## 测试登录（🖥️ 新开一个窗口）

```powershell
# 部署前（端口 22）
ssh -i "$env:USERPROFILE\.ssh\id_ed25519_vps" -p 22 root@<VPS_IP>
# 部署后（新端口）
ssh -i "$env:USERPROFILE\.ssh\id_ed25519_vps" -p 3649 root@<VPS_IP>
```

Termux：`ssh -i ~/.ssh/id_ed25519_vps -p 3649 root@<VPS_IP>`

预期：不再询问 root 密码（如果设置了口令，会询问私钥口令）。

## Xshell / 其他图形客户端

Xshell 不会自动读取 `.ssh` 目录：在「工具 → 用户密钥管理者」里**导入私钥文件** `id_ed25519_vps`（不是 `.pub`），然后在会话属性里认证方式选「Public Key」并选中该密钥，端口改为新 SSH 端口。

## 脚本做了什么

写入 `/etc/ssh/sshd_config.d/00-vps-port.conf`（端口）和 `/etc/ssh/sshd_config.d/00-vps-key.conf`：

```
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
```

使用 drop-in 文件而不是改主配置，是因为有些服务商镜像的主配置或其他 drop-in 里写了 `PubkeyAuthentication no` 等；sshd 对同一选项**取第一次出现的值**，`00-` 前缀保证最先被读取。重载前会执行 `sshd -t` 校验。

验证：`sshd -T | grep -Ei 'port|passwordauth|pubkeyauth|permitroot'`
