# vps-reality-setup

一键把一台全新的 **Ubuntu 22.04 x86_64** VPS 部署成自用代理节点。UUID、REALITY 密钥和 shortId 都在服务器上现场生成。本仓库**不包含**真实 IP、UUID、私钥、密码或 `vless://` 链接。

脚本**不会重装系统，也不会做任何付费操作**。

## 项目做什么

在你自己的服务器上完成这些事（幂等，可重复运行）：

- **SSH 加固**：把 SSH 改到自定义端口（默认 `3649`）。只有 `/root/.ssh/authorized_keys` 里已经有公钥时，才会关闭密码登录，避免把自己锁在门外。
- **防火墙**：ufw 默认拒绝入站，只放行 SSH 端口和 `443/tcp`。
- **代理**：安装 Xray，配置 **VLESS + XTLS-Vision + REALITY**。默认伪装站点是 `www.nvidia.com`。
- **拥塞控制**：开启 BBR。
- **凭据**：在服务器本地生成 UUID、x25519 密钥和 shortId，在终端打印导入链接和二维码，并写入下面两个权限为 `600` 的文件：
  - `/root/vps-link.txt`
  - `/root/vps-client-info.txt`

这两个文件、终端里的链接和二维码都是机密。不要提交到 Git，不要发到聊天或群里。

## 目录说明

| 路径 | 说明 |
|---|---|
| `install.sh` | 服务器端一键部署脚本（root 运行，可重复执行） |
| `scripts/check-cn.sh` | 在自己的电脑上，用 Globalping 从国内探针测 ping、TCP 443 和 SSH 端口 |
| `SKILL.md` | 给 AI 助手用的分步流程（面向新手，一次只做一步） |
| `docs/precheck.md` | 部署前检查：国内可达性与 IP 纯净度 |
| `docs/ssh-keys.md` | Windows 与安卓 Termux 生成 SSH 密钥并写入服务器 |
| `docs/sni.md` | REALITY 伪装站点（SNI）怎么选、怎么测 |
| `docs/clients.md` | v2rayN（Windows）与 v2rayNG（安卓）的配置入口 |
| `docs/usage.md` | 用量建议、日常检查、出问题时的处理顺序 |
| `docs/troubleshooting.md` | 实际遇到过的问题和解决方法 |

## 部署前检查

先在自己的电脑上确认这台 VPS 从国内能连上，再花时间部署。完整说明见 [docs/precheck.md](docs/precheck.md)。

```bash
# 部署前 SSH 一般还是 22；部署完成后改成实际端口（默认 3649）
bash scripts/check-cn.sh <VPS_IP> 22
```

`<VPS_IP>` 换成这台服务器的公网地址。需要 `curl`，装了 `jq` 时输出更易读。也可以用网页版 https://globalping.io ，地点选 China。

怎么看结果：

- ICMP 不通但 TCP 通：很多机房禁 ping，通常没问题。
- 部署前 443 上还没有服务，TCP 443 不通是正常的。这时以 ICMP 和当前 SSH 端口为准。部署完成后再测一次 443。
- 服务已经起来之后，ICMP 通而 TCP 443 全部丢包：可能是端口被封，可以换端口。
- 全部 100% 丢包：先排查服务器本身和云厂商安全组，再考虑换 IP。换 IP 可能要花钱，先确认再操作。

IP 类型和风险评分在浏览器里查（地址后面接你的公网 IP）：

- https://ping0.cc
- https://scamalytics.com
- https://ippure.com
- https://proxycheck.io

分数高只影响部分网站（例如部分账号、流媒体、支付）的风控，不代表节点一定连不上。

## SSH 公钥准备

**先把公钥加到服务器，并确认能用密钥登录，再运行安装脚本。** 找不到公钥时，脚本只会修改 SSH 端口，**不会**关闭密码登录。逐步说明见 [docs/ssh-keys.md](docs/ssh-keys.md)。

Windows（PowerShell）。如果 `id_ed25519` 已经存在，不要覆盖，用单独的文件名：

```powershell
ssh-keygen -t ed25519 -f $env:USERPROFILE\.ssh\id_ed25519_vps -C vps-key
Get-Content $env:USERPROFILE\.ssh\id_ed25519_vps.pub
```

安卓 Termux：

```bash
pkg update && pkg install -y openssh
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_vps -C phone-key
cat ~/.ssh/id_ed25519_vps.pub
```

口令（passphrase）可以设置，也可以直接回车留空。`.pub` 那一行是公钥，可以放到服务器上；没有 `.pub` 后缀的私钥不要外传。

在仍能用密码登录的服务器上，把电脑和手机的公钥各写一行：

```bash
mkdir -p /root/.ssh && chmod 700 /root/.ssh
nano /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
grep -c '^ssh-' /root/.ssh/authorized_keys
```

两把公钥都写上时，最后一条命令的预期结果是 `2`。

新开一个窗口测试（部署前端口一般是 22）。预期不再询问 root 密码；如果设置了私钥口令，会询问口令：

```powershell
ssh -i "$env:USERPROFILE\.ssh\id_ed25519_vps" -p 22 root@<VPS_IP>
```

Xshell 等图形客户端不会自动读取 `.ssh` 目录，需要导入私钥文件 `id_ed25519_vps`（不是 `.pub`），认证方式选 Public Key。

## 如何上传并运行 install.sh

在服务器上以 **root** 运行（`sudo -i` 后再执行）。下面命令里的 `<VPS_IP>` 换成你的服务器地址。首次部署时 SSH 端口通常仍是 `22`，部署完成后再改用新端口。

### 方式 A：从电脑上传脚本（推荐）

在本仓库目录、Windows PowerShell 中：

```powershell
scp -P 22 -i "$env:USERPROFILE\.ssh\id_ed25519_vps" install.sh root@<VPS_IP>:/root/
ssh -i "$env:USERPROFILE\.ssh\id_ed25519_vps" -p 22 root@<VPS_IP>
```

登录服务器后：

```bash
bash /root/install.sh
```

### 方式 B：在服务器上克隆本仓库

```bash
git clone https://github.com/succeed2025/vps-reality-setup.git
cd vps-reality-setup
bash install.sh
```

### 方式 C：直接下载脚本

文件进入 `main` 分支之后可以使用：

```bash
curl -fsSL https://raw.githubusercontent.com/succeed2025/vps-reality-setup/main/install.sh -o /root/install.sh
bash /root/install.sh
```

常用运行方式：

```bash
bash install.sh                                   # 默认：SSH 端口 3649，SNI www.nvidia.com
bash install.sh --ssh-port 3649 --sni www.nvidia.com
SKIP_SSH_HARDEN=1 bash install.sh                 # 不改 SSH 端口，也不关密码登录
bash install.sh --yes                             # 跳过交互确认，请先看完脚本会改什么
```

脚本会先列出将要执行的步骤，并等待确认。结束时在终端打印导入链接和二维码。

**不要关闭当前 SSH 窗口。** 新开一个窗口，用新端口登录成功后再关旧窗口：

```powershell
ssh -i "$env:USERPROFILE\.ssh\id_ed25519_vps" -p 3649 root@<VPS_IP>
```

云厂商控制台里如果有安全组或防火墙，也要放行新的 SSH 端口和 `443/tcp`。

## 常用参数

也可以用同名环境变量，不必写命令行参数。

| 参数 | 环境变量 | 默认 | 说明 |
|---|---|---|---|
| `--ssh-port N` | `SSH_PORT` | `3649` | SSH 新端口。必须是 1–65535，且不能是 `443` |
| `--sni HOST` | `SNI` | `www.nvidia.com` | REALITY 伪装站点。需要支持 TLS 1.3 和 HTTP/2，见 [docs/sni.md](docs/sni.md) |
| `--skip-ssh-harden` | `SKIP_SSH_HARDEN=1` | 关闭 | 跳过 SSH 加固（不改端口、不关密码登录） |
| `--server-ip IP` | `SERVER_IP` | 自动探测 | 写入客户端链接里的公网地址 |
| `--force-regen` | `FORCE_REGEN=1` | 关闭 | 重新生成 UUID、密钥和 shortId。旧链接会失效 |
| `-y` / `--yes` | `ASSUME_YES=1` | 关闭 | 所有确认自动回答 yes |
| `-h` / `--help` |  |  | 显示帮助后退出 |

重复运行且不加 `--force-regen` 时，会复用已有的 UUID 和密钥。只更换 SNI 时，客户端需要重新导入链接。

以后在服务器上查看链接：`cat /root/vps-link.txt`。查看日志：`tail -f /var/log/xray/error.log`。

## 客户端配置

配置步骤写在 [docs/clients.md](docs/clients.md)。链接只从服务器读取，不要转发。

- **Windows：v2rayN**  
  从 GitHub Releases 下载带 Xray 内核的 `v2rayN-windows-64`。复制导入链接，在「配置文件 → 从剪贴板导入分享链接」导入，选中 `VPS-Reality`。本地混合监听端口设为 `7892`，系统代理选「自动配置系统代理」，路由选「V4-绕过大陆(Whitelist)」。不要同时开另一个代理客户端，浏览器里的 SwitchyOmega 一类插件也要停用。  
  Codex 任务面板不走系统代理时，用管理员身份运行 v2rayN 并开启 TUN，再按文档在规则最顶部加上局域网（`192.168.0.0/16`）和这台 VPS（`<VPS_IP>/32`）的直连规则。

- **安卓：v2rayNG**  
  下载标准版 `arm64-v8a` APK。用「从剪贴板导入」，或扫描服务器终端里的二维码。连接时允许 VPN 权限。路由建议选「绕过局域网及大陆地址」。

- **其他客户端**  
  在服务器上执行 `cat /root/vps-client-info.txt`，按其中的字段填写：协议 VLESS，端口 `443`，流控 `xtls-rprx-vision`，传输 tcp，安全 reality，指纹 `chrome`。SNI、公钥和 shortId 以该文件为准，不要使用任何示例值。

验证：浏览器打开 https://www.google.com ；https://ping0.cc 上显示的地址应是这台 VPS。

## 注意事项

- 只在你本人拥有或已获授权的服务器上使用。续费、换 IP、删除机器、重装系统都不在脚本范围内；这些操作先自己确认。
- 没有公钥时不要手动关掉密码登录。改完 SSH 端口后，先用新端口登录成功，再关闭原来的窗口。
- 服务商安全组也要放行 SSH 新端口和 `443/tcp`。SSH 连不上时，用服务商网页控制台或 VNC 修复，不要先重装系统。
- `/root/vps-link.txt`、`/root/vps-client-info.txt`、SSH 私钥、UUID、REALITY 私钥和导入链接都不要进入仓库、截图或聊天。`.gitignore` 已忽略常见密钥文件以及 `*link*.txt`、`*client-info*.txt`。
- 用量、每天两次的可达性检查，以及出问题时「先查本地、再重启、再换端口或 SNI、最后才考虑换 IP」的顺序，见 [docs/usage.md](docs/usage.md)。
- 对症排查见 [docs/troubleshooting.md](docs/troubleshooting.md)。一次只改一处，改完再验证。
- 请遵守当地法律法规与服务商条款。

## 免责声明

仅供个人学习与合法用途，请遵守当地法律法规与服务商条款。
