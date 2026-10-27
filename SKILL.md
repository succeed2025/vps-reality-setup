---
name: vps-reality-setup
description: 帮新手把一台 Ubuntu 22.04 VPS 一步步部署成自用的 VLESS + Vision + REALITY 节点（SSH 密钥加固、ufw、Xray、BBR），并配置 Windows v2rayN / 安卓 v2rayNG 客户端、排查常见问题。当用户想搭建、迁移、检查或修复自己的 VPS 代理节点时使用。
---

# VPS REALITY 节点部署（面向新手的分步流程）

## 基本原则（必须遵守）

1. **一次只给一步。** 每一步都说清楚「在哪里运行」：
   - 🖥️ **电脑**（Windows PowerShell）
   - 🌐 **服务器**（SSH 登录后的 root 终端）
   - 📱 **手机**（安卓 Termux / v2rayNG）
2. 给出可**直接复制粘贴**的命令，并写明**预期输出**。让用户把结果贴回来，**确认无误再进入下一步**；不对就先排查，不要跳步。
3. **边界：**
   - 涉及**付费、续费、重装系统、删除服务器、换 IP** 的操作，一律先停下来问用户，得到明确同意才继续。
   - 只操作用户**本人拥有/已授权**的服务器。
   - **绝不**让用户在聊天里发送密码、私钥、UUID、REALITY 私钥、token。需要时只让用户在自己的终端里操作。用户误发了，提醒他尽快更换。
   - 不要把 `vless://` 链接、`/root/vps-*.txt` 内容写进任何仓库或公开位置。
4. 用户贴出的输出里如含敏感信息，回复时不要原样复述。

## 流程

### 第 1 步：确认服务器信息
问用户：服务商、系统版本、IP 是否已拿到、当前 SSH 端口（通常 22）、能否用密码登录。
目标系统 Ubuntu 22.04 x86_64；不是的话说明风险，让用户决定（**不要**主动建议重装，重装要先问）。

### 第 2 步：部署前检查（🖥️ 电脑）
按 `docs/precheck.md`：
- `bash scripts/check-cn.sh <VPS_IP> 22`（或页面版 globalping.io）
- 预期：国内探针 TCP 443 / 22 有响应（丢包 0% 左右）。ICMP 不通但 TCP 通也可以。
- 再查 IP 纯净度：ping0.cc、scamalytics.com、ippure.com、proxycheck.io。
- 全部不通 → 停下，告诉用户可能是 IP 被封或机房问题，换 IP 可能要花钱，**先问**。

### 第 3 步：生成 SSH 密钥（🖥️ 电脑 / 📱 手机）
按 `docs/ssh-keys.md`。要点：
- Windows：`ssh-keygen -t ed25519 -f $env:USERPROFILE\.ssh\id_ed25519_vps -C vps-key`
  - 如果默认 `id_ed25519` 已存在，**用单独文件名**，不要覆盖。
- Termux：`ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_vps -C phone-key`
- 把**两把公钥**（`.pub`）都追加到服务器 `/root/.ssh/authorized_keys`，**在关闭密码登录之前**。
- 让用户新开窗口用密钥登录测试：`ssh -i "$env:USERPROFILE\.ssh\id_ed25519_vps" -p 22 root@<VPS_IP>`，预期不再询问密码（可能询问私钥口令）。

### 第 4 步：上传并运行脚本（🖥️ → 🌐）
- 仓库为私有：用 `scp -P 22 -i ... install.sh root@<VPS_IP>:/root/` 上传，或在服务器上用 token 克隆（见 README）。
- 🌐 `bash /root/install.sh --ssh-port 3649`
- 脚本会逐步确认；预期最后输出 `vless://...#VPS-Reality` 和二维码。
- 提醒：**不要关闭当前 SSH 窗口**，新开窗口用 `-p 3649` 测试登录成功后再关。
- 失败时让用户贴出报错的最后 30 行（提醒把 UUID/密钥打码）。

### 第 5 步：验证服务器（🌐）
```bash
systemctl is-active xray            # 预期: active
ss -lntp | grep -E ':443|:3649'     # 预期: xray 监听 443, sshd 监听 3649
ufw status                          # 预期: 只有 3649/tcp 和 443/tcp ALLOW
sysctl net.ipv4.tcp_congestion_control   # 预期: = bbr
sshd -T | grep -E 'passwordauthentication|pubkeyauthentication'  # 预期: no / yes
```
再从 🖥️ 跑一次 `bash scripts/check-cn.sh <VPS_IP> 3649`。

### 第 6 步：配置客户端（🖥️ / 📱）
按 `docs/clients.md`：v2rayN 导入链接、本地端口 7892、系统代理自动、路由「V4-绕过大陆(Whitelist)」；需要 Codex 任务面板时开 TUN 并加两条直连规则。v2rayNG 从剪贴板或扫码导入。
验证：浏览器打开 https://www.google.com ，以及 ping0.cc 显示的是 VPS IP。

### 第 7 步：交代使用与维护
简述 `docs/usage.md` 的用量建议和出问题时的处理顺序（便宜 → 贵；**花钱前先问**）。

## 排错
遇到问题先查 `docs/troubleshooting.md`，按症状对照；一次只改一处，改完验证。
