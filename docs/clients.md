# 客户端配置

服务器部署完成后，终端里会打印一条 `vless://...#VPS-Reality` 链接（也保存在服务器 `/root/vps-link.txt`）。
以后需要时在 🌐 服务器上 `cat /root/vps-link.txt` 查看，**不要**把它发到群里或提交到仓库。

---

## Windows：v2rayN

### 下载
从 v2rayN 的 GitHub Releases 下载 **`v2rayN-windows-64`**（自带 Xray 内核的版本），解压到固定目录（如 `D:\v2rayN`）。

### 1. 导入节点
1. 复制 `vless://` 链接。
2. v2rayN 主界面 → 「配置文件」→「从剪贴板导入分享链接」（或直接 `Ctrl+V`）。
3. 选中 `VPS-Reality`，回车设为活动服务器。

### 2. 本地端口改为 7892
「设置」→「参数设置」→「Core: 基础设置」→ **本地混合监听端口 = `7892`** → 确定。
> Codex 等工具预期的代理是 `127.0.0.1:7892`（HTTP + SOCKS 混合端口）。

### 3. 系统代理与路由
- 主界面底部「系统代理」选 **自动配置系统代理**。
- 「路由」选 **`V4-绕过大陆(Whitelist)`**（国内直连，国外走代理）。

### 4. 注意事项
- **不要同时运行另一个代理客户端**（比如机场客户端、Clash 等），会抢系统代理/TUN 导致全部断网。
- 浏览器里如有 **SwitchyOmega** 等代理插件，请**删除或停用**，否则可能指向一个不存在的端口。
- 验证：浏览器打开 https://www.google.com ；打开 https://ping0.cc 显示的应该是 VPS 的 IP。

### 5. Codex 桌面版：任务面板需要 TUN 模式
Codex 的部分功能（任务面板等）不走系统代理，表现为「status unavailable」。解决：
1. **以管理员身份运行** v2rayN（右键 → 以管理员身份运行）。
2. 主界面底部打开 **「启用 Tun」**。
3. Tun 设置保持默认：**自动路由（auto route）开、严格路由（strict route）开、协议栈 gvisor**。
4. 刚开启 TUN 的几秒钟内断网一下是**正常的**，等它重连即可。

### 6. TUN 模式下必须加的两条直连规则
TUN 会接管所有流量，需要在 **`V4-绕过大陆(Whitelist)`** 规则集**最顶部**加两条直连规则：

| 别名（remarks） | outboundTag | IP 框 | 作用 |
|---|---|---|---|
| `公司内网直连` | `direct` | `192.168.0.0/16` | 不然 TUN 会把局域网（公司内网、打印机、NAS）也送去代理，导致内网打不开 |
| `VPS直连` | `direct` | `<VPS_IP>/32` | 防止「连 VPS 的流量又被 TUN 送进代理」形成回环，日志刷屏 `REALITY: received real certificate` |

操作步骤：
1. 「路由」→「路由设置」→ 双击 `V4-绕过大陆(Whitelist)` 打开规则集。
2. 「添加规则」，在弹窗里：
   - **别名**：如上表
   - **outboundTag**：选 `direct`
   - **IP**：只在 IP 框里填一行（如 `192.168.0.0/16`）
   - **其他所有框（域名、端口、协议、进程等）都留空**
3. 确定后，选中这条规则，点 **「置顶」**。第二条同样操作并置顶。（两条都要在最上面）
4. 保存 → 回主界面，**重启服务**（「重启服务」按钮或右键托盘图标）。

### 7. 日志级别
「设置」→「参数设置」→「Core: 基础设置」→ **日志等级 = `error`**。
TUN 模式下常见的 `endpoint not connected` 之类日志是**无害的**，调成 error 后就不会刷屏。

---

## 安卓：v2rayNG

### 下载
从 v2rayNG 的 GitHub Releases 下载**标准版（不是 fdroid 版）**的 **`arm64-v8a`** APK（绝大多数现代手机）。

### 导入
- 方法 A：复制 `vless://` 链接 → v2rayNG 右上角 **＋** →「从剪贴板导入」。
- 方法 B：右上角 **＋** →「扫描二维码」，扫服务器终端里 `qrencode` 打出的二维码。

选中节点 → 右下角 **V** 按钮连接，首次会请求 VPN 权限，允许即可。
验证：手机浏览器打开 https://www.google.com 。

路由建议：「设置」→「路由设置」→ 预定义规则选「绕过局域网及大陆地址」。

---

## 手动填写参数（其他客户端）

在 🌐 服务器上 `cat /root/vps-client-info.txt`，对应填写：

| 字段 | 值 |
|---|---|
| 协议 | VLESS |
| 地址 / 端口 | `<VPS_IP>` / `443` |
| UUID | 文件中的 UUID |
| 流控 flow | `xtls-rprx-vision` |
| 传输 | tcp |
| 安全 | reality |
| SNI | `www.nvidia.com`（或你指定的） |
| Fingerprint | `chrome` |
| PublicKey (pbk) | 文件中的公钥 |
| ShortId (sid) | 文件中的 shortId |
