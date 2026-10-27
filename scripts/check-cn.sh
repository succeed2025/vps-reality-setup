#!/usr/bin/env bash
# =============================================================================
# scripts/check-cn.sh —— 用 Globalping 免费 API 从中国大陆探针检测 VPS 可达性
# 在任意能上网的电脑上运行（不需要在 VPS 上运行），需要 curl，jq 可选。
# 用法: bash scripts/check-cn.sh <VPS_IP> [SSH_PORT]
# =============================================================================
set -euo pipefail
IP="${1:?用法: bash check-cn.sh <VPS_IP> [SSH_PORT]}"
SSH_PORT="${2:-3649}"
API="https://api.globalping.io/v1/measurements"

run() {
  # $1 = 说明, $2 = JSON 请求体
  local desc="$1" body="$2" id
  echo "=== ${desc} ==="
  id="$(curl -fsS -X POST "$API" -H 'Content-Type: application/json' -d "$body" \
        | tr -d '\n' | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  [[ -n "$id" ]] || { echo "创建测量失败（可能触发频率限制，稍后再试）"; return 0; }
  # 轮询直到测量完成（最多约 40 秒）
  local res="" i
  for i in $(seq 1 20); do
    sleep 2
    res="$(curl -fsS "${API}/${id}")"
    grep -q '"status"[[:space:]]*:[[:space:]]*"in-progress"' <<<"$res" || break
  done
  : "$i"
  if command -v jq >/dev/null; then
    printf '%s' "$res" | jq -r '.results[] |
      "\(.probe.city // "?")/\(.probe.network // "?"): \(.result.status) 丢包=\(.result.stats.loss // "-")% 平均=\(.result.stats.avg // "-")ms"'
  else
    printf '%s\n' "$res"
  fi
}

run "ICMP ping"          "{\"type\":\"ping\",\"target\":\"${IP}\",\"locations\":[{\"country\":\"CN\"}],\"limit\":5}"
run "TCP 443 (Xray)"     "{\"type\":\"ping\",\"target\":\"${IP}\",\"locations\":[{\"country\":\"CN\"}],\"limit\":5,\"measurementOptions\":{\"protocol\":\"TCP\",\"port\":443}}"
run "TCP ${SSH_PORT} (SSH)" "{\"type\":\"ping\",\"target\":\"${IP}\",\"locations\":[{\"country\":\"CN\"}],\"limit\":5,\"measurementOptions\":{\"protocol\":\"TCP\",\"port\":${SSH_PORT}}}"

cat <<TIP

判读：
  - ICMP 不通但 TCP 443 通：通常没问题（很多机房禁 ping）
  - ICMP 通、TCP 443 全部 100% 丢包：疑似端口被封，可换端口
  - 全部 100% 丢包：疑似 IP 被封，先排查服务器本身，再考虑换 IP（换 IP 可能要花钱，先确认）
TIP
