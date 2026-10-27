# 部署前检查

在花时间部署之前，先确认这台 VPS 的 IP **在国内能连上**、**名声不太差**。

## 1. 国内可达性（Globalping）

Globalping 提供免费 API，可以从国内的探针发起测试。

### 一键脚本（🖥️ 电脑，需要 curl，可选 jq）

```bash
bash scripts/check-cn.sh <VPS_IP> <SSH端口>
```

### 手动调用 API

```bash
# ICMP ping（5 个国内探针）
curl -s -X POST https://api.globalping.io/v1/measurements \
  -H 'Content-Type: application/json' \
  -d '{"type":"ping","target":"<VPS_IP>","locations":[{"country":"CN"}],"limit":5}'
# 返回 {"id":"xxxx",...}，等几秒后取结果：
curl -s https://api.globalping.io/v1/measurements/<ID>

# TCP 443（Xray 端口）
curl -s -X POST https://api.globalping.io/v1/measurements \
  -H 'Content-Type: application/json' \
  -d '{"type":"ping","target":"<VPS_IP>","locations":[{"country":"CN"}],"limit":5,"measurementOptions":{"protocol":"TCP","port":443}}'

# TCP SSH 端口（部署前一般是 22，部署后是 3649）
curl -s -X POST https://api.globalping.io/v1/measurements \
  -H 'Content-Type: application/json' \
  -d '{"type":"ping","target":"<VPS_IP>","locations":[{"country":"CN"}],"limit":5,"measurementOptions":{"protocol":"TCP","port":22}}'
```

> 部署前 443 上还没有服务，TCP 443 可能显示不通，这是正常的；此时以 ICMP 和 SSH 端口为准。部署完成后再测一次 443。

### 如何判读

| 现象 | 含义 |
|---|---|
| ICMP / TCP 都通，丢包低 | 正常 |
| ICMP 不通，TCP 通 | 机房禁 ping，通常没问题 |
| ICMP 通，TCP 443 全部 100% 丢包（服务已启动） | 疑似端口被封 → 可换端口 |
| 全部 100% 丢包 | 疑似 IP 被封 → 先排查服务器，再考虑换 IP（**可能要花钱，先确认**） |

网页版：https://globalping.io （选 China 作为 location）。

## 2. IP 纯净度 / 风险评分

浏览器打开（把 IP 填进去）：

- https://ping0.cc/ip/<VPS_IP> —— IP 类型（机房/家宽）、风控值
- https://scamalytics.com/ip/<VPS_IP> —— Fraud Score，越低越好
- https://ippure.com —— 纯净度
- https://proxycheck.io —— 是否被标记为代理/VPN

分数高只影响部分网站（如 ChatGPT、流媒体、支付）的风控，不影响能否翻墙本身。
