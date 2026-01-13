#!/usr/bin/env bash
set -euo pipefail
export LANG=en_US.UTF-8

# ============================================================
# xray.sh — VLESS TCP REALITY Vision 一键脚本（自用向）
#
# 目标：
#   - 一条命令部署 VLESS + TCP + REALITY + Vision
#   - 输出 vless 分享链接（客户端直接导入）
#   - systemd 管理 xray.service
#
# 设计原则：
#   - 非交互：避免“菜单乱码 / 复制粘贴失效 / curl 返回 HTML 误执行”等问题
#   - 稳定优先：只做必要动作，不碰复杂防火墙规则
#
# 命令：
#   bash xray.sh              # 默认 install（安装/重装）
#   bash xray.sh install      # 安装/重装
#   bash xray.sh info         # 输出节点信息（链接/参数）
#   bash xray.sh status       # 查看服务状态
#   bash xray.sh log          # 最近 200 行日志
#   bash xray.sh update       # 仅更新 Xray 内核（不改配置，客户端不用重配）
#   bash xray.sh bbr          # 单独开启 BBR + fq
#   bash xray.sh uninstall    # 卸载 Xray 并清理配置
#
# 可选环境变量（安装时生效）：
#   reym=www.tesla.com   # Reality 伪装域名（SNI，默认特斯拉）
#   vlpt=443            # 固定端口（不填随机）
#   uuid=xxxx           # 固定 UUID（不填自动生成）
#   fp=chrome           # 指纹（默认 chrome）
#   bbr=1               # 安装时同时开启 BBR + fq
# ============================================================

# -------------------- 路径与默认值 --------------------
XRAY_BIN="/usr/local/bin/xray"                # 官方脚本默认安装位置
XRAY_CONF="/usr/local/etc/xray/config.json"   # 官方建议配置目录
ENV_FILE="/root/reality_vision.env"           # 保存生成出来的节点参数，方便 info 重复输出
SERVICE="xray"

REYM_DEFAULT="www.tesla.com"                  # 默认伪装域名（SNI）
PORT_MIN=20000                                # 默认随机端口范围（避开常见端口）
PORT_MAX=60000

# -------------------- 基础判断 --------------------
is_root() { [[ "${EUID}" -eq 0 ]]; }

# 判断端口是否被占用（TCP LISTEN）
# - free 返回 0
# - 占用返回 1
is_port_free() {
  ss -lnt 2>/dev/null | awk '{print $4}' | grep -qE "[:.]$1\$" && return 1 || return 0
}

# ============================================================
# 1) 公网 IP 获取（NAT 机器更友好）
# ------------------------------------------------------------
# 说明：
# - 有些机器是 NAT / 多网卡，直接读取本机 IP 不可靠
# - 用外部服务探测“从公网看到的出口 IP”
# - 优先 IPv4，失败再兜底其它接口
# - 若探测到 IPv6，为了符合 URL 格式，返回时加 []
# ============================================================
get_public_ip() {
  local ip=""
  ip="$(curl -4 -s --max-time 3 https://api.ipify.org 2>/dev/null || true)"
  [[ -z "$ip" ]] && ip="$(curl -s --max-time 3 https://icanhazip.com 2>/dev/null | tr -d '\n' || true)"
  [[ -z "$ip" ]] && ip="$(curl -s --max-time 3 https://ifconfig.me 2>/dev/null | tr -d '\n' || true)"

  if [[ "$ip" == *:* ]]; then
    echo "[$ip]"
  else
    echo "$ip"
  fi
}

# ============================================================
# 2) 防火墙检测与放行（只处理常见的 ufw/firewalld）
# ------------------------------------------------------------
# 说明：
# - NS 用户里 Debian/Ubuntu 常见 ufw
# - CentOS/RHEL 系常见 firewalld
# - nftables/iptables 不强行改（避免误伤已有规则）
# ============================================================
open_firewall_port() {
  local port="$1"

  # UFW
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qi "active"; then
    echo "==> ufw 已启用，放行 TCP ${port}"
    ufw allow "${port}/tcp" >/dev/null 2>&1 || true
  fi

  # firewalld
  if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    echo "==> firewalld 已启用，放行 TCP ${port}"
    firewall-cmd --permanent --add-port="${port}/tcp" >/dev/null 2>&1 || true
    firewall-cmd --reload >/dev/null 2>&1 || true
  fi
}

# ============================================================
# 3) BBR + fq（可选）
# ------------------------------------------------------------
# 说明：
# - fq 作为 default_qdisc
# - bbr 作为拥塞控制算法
# - 写入 /etc/sysctl.d/99-bbr.conf，重启也有效
# ============================================================
enable_bbr() {
  echo "==> 开启 BBR + fq..."
  modprobe tcp_bbr >/dev/null 2>&1 || true

  cat > /etc/sysctl.d/99-bbr.conf <<EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF

  sysctl --system >/dev/null
  echo "==> 当前内核参数："
  sysctl net.ipv4.tcp_congestion_control net.core.default_qdisc
}

# ============================================================
# 4) 安装依赖 & 安装 Xray
# ------------------------------------------------------------
# 说明：
# - 使用 XTLS 官方 install-release.sh
# - 你的 config.json 是脚本写入的，不会被 update 覆盖
# ============================================================
install_deps() {
  echo "==> 安装依赖..."
  apt-get update -y >/dev/null
  apt-get install -y curl unzip openssl ca-certificates iproute2 >/dev/null
}

install_xray() {
  echo "==> 安装/更新 Xray（官方脚本）..."
  bash <(curl -Ls https://github.com/XTLS/Xray-install/raw/main/install-release.sh) >/dev/null
  [[ -x "$XRAY_BIN" ]] || { echo "Xray 安装失败：未找到 $XRAY_BIN"; exit 1; }
}

# ============================================================
# 5) 生成 UUID / 选择端口 / 生成 Reality 密钥
# ============================================================
gen_uuid() {
  # uuid=xxx 可自定义；否则随机生成
  UUID="${uuid:-$(cat /proc/sys/kernel/random/uuid)}"
}

choose_port() {
  if [[ -n "${vlpt:-}" ]]; then
    PORT="$vlpt"
    is_port_free "$PORT" || { echo "端口被占用：$PORT"; exit 1; }
  else
    # 随机端口，最多尝试 100 次
    for _ in $(seq 1 100); do
      PORT="$(shuf -i ${PORT_MIN}-${PORT_MAX} -n 1)"
      is_port_free "$PORT" && break
    done
    is_port_free "$PORT" || { echo "随机端口选择失败，请手动指定 vlpt=xxxxx"; exit 1; }
  fi
}

gen_reality_keys() {
  echo "==> 生成 Reality 密钥对..."
  local out
  out="$("$XRAY_BIN" x25519)"

  # Xray 输出格式可能随版本略变，这里做兼容
  PRIVATE_KEY="$(echo "$out" | awk -F'[: ]+' '/PrivateKey|Private key/ {print $2; exit}')"
  PUBLIC_KEY="$(echo "$out" | awk -F'[: ]+' '/Password|Public key/ {print $2; exit}')"

  [[ -n "$PRIVATE_KEY" && -n "$PUBLIC_KEY" ]] || { echo "密钥解析失败：$out"; exit 1; }

  # ShortID 规则：一般用 8位 hex（4 bytes）
  SHORT_ID="$(openssl rand -hex 4)"
}

# ============================================================
# 6) 写入 Xray 配置（VLESS TCP REALITY Vision）
# ------------------------------------------------------------
# 说明：
# - 监听 ::（双栈），多数情况下同时覆盖 v4/v6
# - flow: xtls-rprx-vision
# - security: reality
# - dest: SNI:443
# ============================================================
write_config() {
  mkdir -p "$(dirname "$XRAY_CONF")"

  cat > "$XRAY_CONF" <<JSON
{
  "log": { "loglevel": "warning" },
  "inbounds": [{
    "listen": "::",
    "port": $PORT,
    "protocol": "vless",
    "settings": {
      "clients": [
        { "id": "$UUID", "flow": "xtls-rprx-vision" }
      ],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "tcp",
      "security": "reality",
      "realitySettings": {
        "dest": "$SNI:443",
        "serverNames": ["$SNI"],
        "privateKey": "$PRIVATE_KEY",
        "shortIds": ["$SHORT_ID"]
      }
    }
  }],
  "outbounds": [
    { "protocol": "freedom" }
  ]
}
JSON

  echo "==> 配置自检..."
  "$XRAY_BIN" run -test -config "$XRAY_CONF" >/dev/null
}

# 保存生成信息，方便 `info` 重复输出
save_env() {
  cat > "$ENV_FILE" <<EOF
SERVER_IP=$SERVER_IP
PORT=$PORT
UUID=$UUID
SNI=$SNI
FP=$FP
PUBLIC_KEY=$PUBLIC_KEY
SHORT_ID=$SHORT_ID
EOF
  chmod 600 "$ENV_FILE" >/dev/null 2>&1 || true
}

# 输出分享链接（最常用）
print_info() {
  # shellcheck disable=SC1090
  source "$ENV_FILE" 2>/dev/null || { echo "未找到节点信息：$ENV_FILE（先 install）"; exit 1; }

  echo
  echo "================= 节点信息 ================="
  echo "服务器IP  : $SERVER_IP"
  echo "端口      : $PORT"
  echo "UUID      : $UUID"
  echo "SNI       : $SNI"
  echo "PublicKey : $PUBLIC_KEY"
  echo "ShortID   : $SHORT_ID"
  echo "Fingerprint: $FP"
  echo "==========================================="
  echo

  echo "vless 分享链接："
  echo "vless://${UUID}@${SERVER_IP}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SNI}&fp=${FP}&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp#RV-Tesla-Vision"
  echo
}

# ============================================================
# 7) 主命令实现
# ============================================================
cmd_install() {
  is_root || { echo "请用 root 运行"; exit 1; }

  install_deps
  install_xray

  # 安装参数（可通过环境变量覆盖）
  SNI="${reym:-$REYM_DEFAULT}"
  FP="${fp:-chrome}"

  gen_uuid
  choose_port
  gen_reality_keys

  SERVER_IP="$(get_public_ip)"

  # 如果 NAT 或探测失败，提示用户自行改
  if [[ -z "$SERVER_IP" ]]; then
    SERVER_IP="YOUR_PUBLIC_IP_OR_DOMAIN"
    echo "==> 提示：未自动获取公网 IP（可能是 NAT），请在输出链接里替换为你的入口 IP/域名"
  fi

  write_config

  echo "==> 启动 Xray..."
  systemctl enable "$SERVICE" >/dev/null
  systemctl restart "$SERVICE"

  # 自动放行端口（仅处理 ufw / firewalld）
  open_firewall_port "$PORT"

  # 安装时可选开启 bbr
  [[ "${bbr:-0}" == "1" ]] && enable_bbr

  save_env
  print_info
}

cmd_update() {
  is_root || { echo "请用 root 运行"; exit 1; }

  echo "==> 更新 Xray 内核（不改配置）..."
  bash <(curl -Ls https://github.com/XTLS/Xray-install/raw/main/install-release.sh) >/dev/null

  echo "==> 重启服务..."
  systemctl restart "$SERVICE" >/dev/null 2>&1 || true

  echo "==> 当前版本："
  "$XRAY_BIN" version | head -n 1 || true

  echo "==> 完成（配置未变，客户端无需重配）"
}

cmd_uninstall() {
  is_root || { echo "请用 root 运行"; exit 1; }

  echo "==> 停止并禁用服务..."
  systemctl stop "$SERVICE" 2>/dev/null || true
  systemctl disable "$SERVICE" 2>/dev/null || true

  echo "==> 清理配置与环境信息..."
  rm -f "$XRAY_CONF" "$ENV_FILE"

  echo "==> 卸载 Xray..."
  bash <(curl -Ls https://github.com/XTLS/Xray-install/raw/main/install-release.sh) --remove || true

  echo "已卸载完成"
}

# 默认不传参就 install，符合“一键生成”使用习惯
case "${1:-install}" in
  install)   cmd_install ;;
  info)      print_info ;;
  status)    systemctl --no-pager -l status "$SERVICE" ;;
  log)       journalctl -u "$SERVICE" --no-pager -n 200 ;;
  update)    cmd_update ;;
  bbr)       enable_bbr ;;
  uninstall) cmd_uninstall ;;
  *)
    echo "用法："
    echo "  bash xray.sh install      # 一键安装/重装"
    echo "  bash xray.sh info         # 输出节点信息"
    echo "  bash xray.sh status       # 查看状态"
    echo "  bash xray.sh log          # 查看日志"
    echo "  bash xray.sh update       # 更新内核（不改配置）"
    echo "  bash xray.sh bbr          # 开启 BBR + fq"
    echo "  bash xray.sh uninstall    # 卸载"
    echo
    echo "可选变量："
    echo "  reym=www.tesla.com vlpt=443 uuid=xxx fp=chrome bbr=1 bash xray.sh install"
    ;;
esac
