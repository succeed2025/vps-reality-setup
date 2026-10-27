#!/usr/bin/env bash
# =============================================================================
# vps-reality-setup / install.sh
# 一键部署：SSH 加固 + ufw 防火墙 + Xray (VLESS + XTLS-Vision + REALITY) + BBR
# 目标系统：Ubuntu 22.04 x86_64（其他系统会警告，需手动确认）
#
# 用法（在服务器上以 root 运行）：
#   bash install.sh [--ssh-port 3649] [--sni www.nvidia.com] [--skip-ssh-harden] [--yes]
# 也可用环境变量：SSH_PORT / SNI / SKIP_SSH_HARDEN=1 / ASSUME_YES=1 / SERVER_IP / FORCE_REGEN=1
#
# 安全承诺：本脚本绝不重装系统、绝不涉及任何付费操作；
#          UUID / 密钥 / shortId 全部在服务器本地自动生成，只写入 /root 下 600 权限文件。
# =============================================================================
set -euo pipefail

# ---------- 默认参数 ----------
SSH_PORT="${SSH_PORT:-3649}"
SNI="${SNI:-www.nvidia.com}"
SKIP_SSH_HARDEN="${SKIP_SSH_HARDEN:-0}"
ASSUME_YES="${ASSUME_YES:-0}"
FORCE_REGEN="${FORCE_REGEN:-0}"   # 1 = 强制重新生成 UUID/密钥（旧链接会失效）
SERVER_IP="${SERVER_IP:-}"
XRAY_PORT=443
NODE_TAG="VPS-Reality"

XRAY_CONFIG="/usr/local/etc/xray/config.json"
SSH_DROPIN_DIR="/etc/ssh/sshd_config.d"
SSH_PORT_CONF="${SSH_DROPIN_DIR}/00-vps-port.conf"
SSH_KEY_CONF="${SSH_DROPIN_DIR}/00-vps-key.conf"
AUTH_KEYS="/root/.ssh/authorized_keys"
INFO_FILE="/root/vps-client-info.txt"
LINK_FILE="/root/vps-link.txt"

# ---------- 输出工具 ----------
c_red=$'\033[31m'; c_grn=$'\033[32m'; c_ylw=$'\033[33m'; c_blu=$'\033[36m'; c_off=$'\033[0m'
info() { printf '%s[信息]%s %s\n' "$c_blu" "$c_off" "$*"; }
ok()   { printf '%s[完成]%s %s\n' "$c_grn" "$c_off" "$*"; }
warn() { printf '%s[警告]%s %s\n' "$c_ylw" "$c_off" "$*" >&2; }
die()  { printf '%s[错误]%s %s\n' "$c_red" "$c_off" "$*" >&2; exit 1; }
step() { printf '\n%s==== %s ====%s\n' "$c_grn" "$*" "$c_off"; }

confirm() {
  # confirm "问题"  -> 返回 0 表示同意
  if [[ "$ASSUME_YES" == "1" ]]; then return 0; fi
  local ans
  read -r -p "$1 [y/N]: " ans </dev/tty || return 1
  [[ "$ans" =~ ^[Yy]([Ee][Ss])?$ ]]
}

usage() {
  cat <<USAGE
用法: bash install.sh [选项]
  --ssh-port N        SSH 新端口（默认 3649）
  --sni HOST          REALITY 伪装目标站点（默认 www.nvidia.com）
  --skip-ssh-harden   跳过 SSH 加固（不改端口、不关密码登录）
  --server-ip IP      手动指定公网 IP（默认自动探测）
  --force-regen       强制重新生成 UUID/密钥/shortId（旧链接失效）
  -y, --yes           所有确认自动回答 yes（谨慎使用）
  -h, --help          显示帮助
USAGE
}

# ---------- 参数解析 ----------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ssh-port)        SSH_PORT="${2:?缺少端口}"; shift 2 ;;
    --sni)             SNI="${2:?缺少域名}"; shift 2 ;;
    --skip-ssh-harden) SKIP_SSH_HARDEN=1; shift ;;
    --server-ip)       SERVER_IP="${2:?缺少 IP}"; shift 2 ;;
    --force-regen)     FORCE_REGEN=1; shift ;;
    -y|--yes)          ASSUME_YES=1; shift ;;
    -h|--help)         usage; exit 0 ;;
    *) die "未知参数: $1（用 --help 查看帮助）" ;;
  esac
done

if ! [[ "$SSH_PORT" =~ ^[0-9]+$ ]] || (( SSH_PORT < 1 || SSH_PORT > 65535 )); then
  die "SSH_PORT 不合法: $SSH_PORT"
fi
(( SSH_PORT != XRAY_PORT )) || die "SSH 端口不能与 Xray 端口 ${XRAY_PORT} 相同"
[[ "$SNI" =~ ^[A-Za-z0-9.-]+$ ]] || die "SNI 不合法: $SNI"

# ---------- 0. 前置检查 ----------
step "0. 前置检查"
[[ $EUID -eq 0 ]] || die "请以 root 运行（sudo -i 后再执行）"

if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
else
  ID=unknown; VERSION_ID=unknown
fi
ARCH="$(uname -m)"
if [[ "${ID:-}" != "ubuntu" || "${VERSION_ID:-}" != "22.04" || "$ARCH" != "x86_64" ]]; then
  warn "本脚本针对 Ubuntu 22.04 x86_64 测试，当前为: ${PRETTY_NAME:-$ID $VERSION_ID} / $ARCH"
  confirm "仍要继续吗？" || die "已取消"
else
  ok "系统: ${PRETTY_NAME} / ${ARCH}"
fi

cat <<NOTE

即将执行：
  - 安装依赖（curl openssl qrencode ufw jq）
  - 停用旧的 shadowsocks-libev（如存在）
  - SSH：端口改为 ${SSH_PORT}，有公钥时才关闭密码登录 $( [[ "$SKIP_SSH_HARDEN" == "1" ]] && echo '（已选择跳过）')
  - ufw：默认拒绝入站，仅放行 ${SSH_PORT}/tcp 和 ${XRAY_PORT}/tcp
  - 安装/更新 Xray，写入 VLESS + Vision + REALITY 配置（SNI: ${SNI}）
  - 开启 BBR
本脚本不会重装系统，也不会进行任何付费操作。
建议提前在 https://globalping.io 等工具确认本 IP 在国内可达（见 docs/precheck.md）。

NOTE
confirm "确认开始部署？" || die "已取消"

# ---------- 1. 依赖 ----------
step "1. 安装依赖"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y curl ca-certificates openssl qrencode ufw jq iproute2
ok "依赖已安装"

# ---------- 2. 停用旧 shadowsocks ----------
step "2. 检查旧 shadowsocks-libev"
for svc in shadowsocks-libev shadowsocks-libev-server@config; do
  if systemctl list-unit-files 2>/dev/null | grep -q "^${svc%%@*}"; then
    if systemctl is-active --quiet "$svc" 2>/dev/null || systemctl is-enabled --quiet "$svc" 2>/dev/null; then
      if confirm "检测到 ${svc}（通常占用 8388 端口），停止并禁用？"; then
        systemctl disable --now "$svc" || true
        ok "已停用 ${svc}"
      fi
    fi
  fi
done
if ss -lntup 2>/dev/null | grep -q ':8388 '; then
  warn "8388 端口仍被占用，请手动确认：ss -lntup | grep 8388"
else
  ok "8388 端口空闲"
fi

# ---------- 3. SSH 加固 ----------
step "3. SSH 加固"
has_pubkey() {
  [[ -s "$AUTH_KEYS" ]] && grep -Eq '^(ssh-(ed25519|rsa)|ecdsa-sha2-|sk-)' "$AUTH_KEYS"
}

if [[ "$SKIP_SSH_HARDEN" == "1" ]]; then
  warn "已跳过 SSH 加固（SKIP_SSH_HARDEN=1）。ufw 将放行的 SSH 端口: ${SSH_PORT}"
else
  mkdir -p "$SSH_DROPIN_DIR"
  # Ubuntu 22.04 的 sshd_config 顶部有 Include sshd_config.d/*.conf，00- 前缀保证最先生效
  if ! grep -Eq '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config.d/\*\.conf' /etc/ssh/sshd_config; then
    warn "/etc/ssh/sshd_config 没有 Include sshd_config.d，已在文件顶部补上"
    cp -a /etc/ssh/sshd_config "/etc/ssh/sshd_config.bak.$(date +%s)"
    sed -i '1i Include /etc/ssh/sshd_config.d/*.conf' /etc/ssh/sshd_config
  fi

  # Port 可以写多次（会同时监听），所以要注释掉主配置里显式的 Port 行
  if grep -Eq '^[[:space:]]*Port[[:space:]]+' /etc/ssh/sshd_config; then
    cp -a /etc/ssh/sshd_config "/etc/ssh/sshd_config.bak.$(date +%s)"
    sed -i -E 's/^([[:space:]]*Port[[:space:]]+.*)$/# \1  # 已由 vps-reality-setup 注释，端口见 00-vps-port.conf/' /etc/ssh/sshd_config
  fi
  printf '# 由 vps-reality-setup 生成\nPort %s\n' "$SSH_PORT" > "$SSH_PORT_CONF"

  if has_pubkey; then
    info "authorized_keys 中检测到 $(grep -Ec '^(ssh-|ecdsa-|sk-)' "$AUTH_KEYS") 把公钥"
    if confirm "关闭 SSH 密码登录，仅允许密钥登录？（请确认你已能用密钥登录）"; then
      cat > "$SSH_KEY_CONF" <<'SSHCONF'
# 由 vps-reality-setup 生成：仅允许密钥登录
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
SSHCONF
      ok "已写入 ${SSH_KEY_CONF}"
    else
      warn "保留密码登录"
    fi
  else
    rm -f "$SSH_KEY_CONF"
    warn "拒绝关闭密码登录：${AUTH_KEYS} 中没有任何公钥！"
    warn "请先按 docs/ssh-keys.md 添加电脑/手机公钥，再重新运行本脚本。"
  fi
  chmod 700 /root/.ssh 2>/dev/null || true
  chmod 600 "$AUTH_KEYS" 2>/dev/null || true
fi

# ---------- 4. 防火墙（先放行 SSH，再启用） ----------
step "4. 配置 ufw 防火墙"
ufw default deny incoming
ufw default allow outgoing
ufw allow "${SSH_PORT}/tcp" comment 'ssh'
ufw allow "${XRAY_PORT}/tcp" comment 'xray-reality'
CUR_SSH_PORT="$(awk '{print $4}' <<<"${SSH_CONNECTION:-}")"
if [[ -n "$CUR_SSH_PORT" && "$CUR_SSH_PORT" != "$SSH_PORT" ]]; then
  warn "当前 SSH 会话走的是 ${CUR_SSH_PORT} 端口；已建立的连接不会被断开，但新连接需使用 ${SSH_PORT}。"
fi
ufw --force enable
ufw status verbose
ok "ufw 已启用"

# 防火墙放行后再重载 sshd
if [[ "$SKIP_SSH_HARDEN" != "1" ]]; then
  sshd -t || die "sshd 配置校验失败（sshd -t），未重载。请检查 ${SSH_DROPIN_DIR}"
  # Ubuntu 22.10+ 使用 ssh.socket 监听端口，需同步端口
  if systemctl is-active --quiet ssh.socket 2>/dev/null; then
    mkdir -p /etc/systemd/system/ssh.socket.d
    printf '[Socket]\nListenStream=\nListenStream=%s\n' "$SSH_PORT" > /etc/systemd/system/ssh.socket.d/override.conf
    systemctl daemon-reload
    systemctl restart ssh.socket
  fi
  systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || systemctl restart ssh
  sleep 1
  if ss -lnt | grep -q ":${SSH_PORT} "; then
    ok "sshd 已监听 ${SSH_PORT}"
  else
    warn "未检测到 sshd 监听 ${SSH_PORT}，请勿关闭当前窗口，先排查！"
  fi
  printf '%s>>> 重要：不要关闭当前 SSH 窗口！新开一个窗口用 -p %s 测试登录成功后再关闭。%s\n' "$c_ylw" "$SSH_PORT" "$c_off"
fi

# ---------- 5. SNI 检查 ----------
step "5. 检查 SNI 目标站点 ${SNI}"
if curl -sS -o /dev/null --max-time 10 --tlsv1.3 --http2 -w '%{http_version}' "https://${SNI}/" 2>/dev/null | grep -q '^2'; then
  ok "${SNI} 支持 TLS1.3 + HTTP/2"
else
  warn "${SNI} 未通过 TLS1.3/H2 检查（可能网络波动或站点不合适）"
  confirm "仍使用 ${SNI} 作为 SNI？" || die "请用 --sni 换一个站点后重试"
fi

# ---------- 6. 安装 Xray ----------
step "6. 安装 / 更新 Xray（官方脚本）"
bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
command -v xray >/dev/null || die "xray 未安装成功"
xray version | head -1

# ---------- 7. 生成 / 复用凭据 ----------
step "7. 生成凭据"
UUID=""; PRIV=""; PUB=""; SID=""
if [[ "$FORCE_REGEN" != "1" && -s "$XRAY_CONFIG" ]] && jq -e '.inbounds[0].streamSettings.realitySettings.privateKey' "$XRAY_CONFIG" >/dev/null 2>&1; then
  UUID="$(jq -r '.inbounds[0].settings.clients[0].id' "$XRAY_CONFIG")"
  PRIV="$(jq -r '.inbounds[0].streamSettings.realitySettings.privateKey' "$XRAY_CONFIG")"
  SID="$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0]' "$XRAY_CONFIG")"
  info "检测到已有 REALITY 配置，复用原 UUID/密钥（客户端链接不变）。如需更换请加 --force-regen"
fi

parse_pub() { awk -F': *' 'tolower($1) ~ /public|password/ {print $2; exit}'; }
parse_priv() { awk -F': *' 'tolower($1) ~ /private/ {print $2; exit}'; }

if [[ -z "$UUID" || "$UUID" == "null" || -z "$PRIV" || "$PRIV" == "null" ]]; then
  UUID="$(xray uuid)"
  KEYS="$(xray x25519)"
  PRIV="$(parse_priv <<<"$KEYS")"
  PUB="$(parse_pub <<<"$KEYS")"
  SID="$(openssl rand -hex 8)"
  ok "已生成新的 UUID / x25519 密钥 / shortId"
else
  PUB="$(xray x25519 -i "$PRIV" | parse_pub)"
fi
[[ -n "$UUID" && -n "$PRIV" && -n "$PUB" && -n "$SID" ]] || die "凭据生成/解析失败（xray x25519 输出格式可能变化）"

# ---------- 8. 写入 Xray 配置 ----------
step "8. 写入 ${XRAY_CONFIG}"
mkdir -p /usr/local/etc/xray /var/log/xray
[[ -s "$XRAY_CONFIG" ]] && cp -a "$XRAY_CONFIG" "${XRAY_CONFIG}.bak.$(date +%s)"
TMP_CFG="$(mktemp)"
jq -n --arg uuid "$UUID" --arg priv "$PRIV" --arg sid "$SID" --arg sni "$SNI" --argjson port "$XRAY_PORT" '{
  log: { loglevel: "warning", access: "/var/log/xray/access.log", error: "/var/log/xray/error.log" },
  inbounds: [{
    tag: "vless-reality", listen: "0.0.0.0", port: $port, protocol: "vless",
    settings: { clients: [{ id: $uuid, flow: "xtls-rprx-vision" }], decryption: "none" },
    streamSettings: {
      network: "tcp", security: "reality",
      realitySettings: { show: false, dest: ($sni + ":443"), xver: 0,
        serverNames: [$sni], privateKey: $priv, shortIds: [$sid] }
    },
    sniffing: { enabled: true, destOverride: ["http","tls","quic"], routeOnly: true }
  }],
  outbounds: [ { tag: "direct", protocol: "freedom" }, { tag: "block", protocol: "blackhole" } ],
  routing: { domainStrategy: "IPIfNonMatch", rules: [
    { type: "field", protocol: ["bittorrent"], outboundTag: "block" },
    { type: "field", ip: ["geoip:cn", "geoip:private"], outboundTag: "block" }
  ] }
}' > "$TMP_CFG"
install -m 644 "$TMP_CFG" "$XRAY_CONFIG"
rm -f "$TMP_CFG"
# xray 服务默认以 nobody 运行，确保日志目录可写
chown -R nobody:nogroup /var/log/xray 2>/dev/null || true

xray run -test -config "$XRAY_CONFIG" || die "Xray 配置校验失败"
systemctl enable xray >/dev/null 2>&1
systemctl restart xray
sleep 2
systemctl is-active --quiet xray || { journalctl -u xray -n 30 --no-pager; die "xray 未能启动"; }
ok "xray.service 运行中，监听 ${XRAY_PORT}"

# ---------- 9. BBR ----------
step "9. 开启 BBR"
sed -i -E '/^[[:space:]]*net\.core\.default_qdisc[[:space:]]*=/d; /^[[:space:]]*net\.ipv4\.tcp_congestion_control[[:space:]]*=/d' /etc/sysctl.conf
printf 'net.core.default_qdisc=fq\nnet.ipv4.tcp_congestion_control=bbr\n' >> /etc/sysctl.conf
sysctl -p >/dev/null
if [[ "$(sysctl -n net.ipv4.tcp_congestion_control)" == "bbr" ]]; then
  ok "BBR 已生效（无需重启系统或 xray）"
else
  warn "BBR 未生效，当前: $(sysctl -n net.ipv4.tcp_congestion_control)"
fi

# ---------- 10. 输出客户端信息 ----------
step "10. 客户端信息"
if [[ -z "$SERVER_IP" ]]; then
  SERVER_IP="$(curl -4 -fsS --max-time 8 https://api.ipify.org 2>/dev/null || true)"
  [[ -n "$SERVER_IP" ]] || SERVER_IP="$(curl -4 -fsS --max-time 8 https://ifconfig.me 2>/dev/null || true)"
  [[ -n "$SERVER_IP" ]] || SERVER_IP="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}')"
fi
[[ -n "$SERVER_IP" ]] || { SERVER_IP="<VPS_IP>"; warn "无法探测公网 IP，请手动把链接中的 <VPS_IP> 替换掉"; }

LINK="vless://${UUID}@${SERVER_IP}:${XRAY_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SNI}&fp=chrome&pbk=${PUB}&sid=${SID}&type=tcp&headerType=none#${NODE_TAG}"

umask 077
cat > "$INFO_FILE" <<INFO
# vps-reality-setup 客户端信息（机密！不要截图外传、不要提交到 Git）
地址 (address):   ${SERVER_IP}
端口 (port):      ${XRAY_PORT}
协议:             VLESS
UUID (id):        ${UUID}
流控 (flow):      xtls-rprx-vision
传输 (network):   tcp
安全 (security):  reality
SNI:              ${SNI}
指纹 (fp):        chrome
公钥 (pbk):       ${PUB}
shortId (sid):    ${SID}
SSH 端口:         ${SSH_PORT}
生成时间:         $(date '+%F %T %Z')
INFO
printf '%s\n' "$LINK" > "$LINK_FILE"
chmod 600 "$INFO_FILE" "$LINK_FILE"

echo
echo "================ 导入链接（仅显示在终端，切勿公开） ================"
echo "$LINK"
echo "==================================================================="
qrencode -t ansiutf8 "$LINK" || true
echo
ok "已保存：${INFO_FILE}、${LINK_FILE}（权限 600）"
cat <<DONE

下一步：
  1. 复制上面的 vless:// 链接，在 v2rayN / v2rayNG 中"从剪贴板导入"（见 docs/clients.md）
  2. 新开窗口测试 SSH：ssh -i <私钥> -p ${SSH_PORT} root@${SERVER_IP}
  3. 以后查看链接：cat ${LINK_FILE}
  4. 查看日志：tail -f /var/log/xray/error.log
DONE
