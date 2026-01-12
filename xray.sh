cat > /root/rv.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
export LANG=en_US.UTF-8

# =========================
# 自用最小脚本：VLESS TCP REALITY Vision
# 命令：
#   bash rv.sh install
#   bash rv.sh info
#   bash rv.sh status
#   bash rv.sh log
#   bash rv.sh uninstall
#
# 可用环境变量：
#   reym=www.tesla.com         # 伪装域名/SNI（默认特斯拉）
#   vlpt=443                   # 端口（留空则随机）
#   uuid=xxxx                  # UUID（留空则随机）
#   fp=chrome                  # 指纹（默认 chrome）
# =========================

ENV_FILE="/root/reality_vision.env"
XRAY_BIN="/usr/local/bin/xray"
XRAY_CONF="/usr/local/etc/xray/config.json"
SERVICE="xray"

# 默认值
REYM_DEFAULT="www.tesla.com"
PORT_MIN=10000
PORT_MAX=65535

need_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "缺少命令: $1"; exit 1; }; }
is_root() { [[ "${EUID}" -eq 0 ]]; }
is_port_free() { ss -lnt 2>/dev/null | awk '{print $4}' | grep -qE "[:.]$1\$" && return 1 || return 0; }

load_env() {
  if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
  fi
}

save_env() {
  cat > "$ENV_FILE" <<ENV
# Auto-generated. Edit if you know what you're doing.
SERVER_IP=${SERVER_IP}
PORT=${PORT}
UUID=${UUID}
SNI=${SNI}
FP=${FP}
PUBLIC_KEY=${PUBLIC_KEY}
SHORT_ID=${SHORT_ID}
ENV
  chmod 600 "$ENV_FILE"
}

get_public_ip() {
  curl -s --max-time 3 https://api.ipify.org || true
}

install_deps() {
  echo "==> 安装依赖..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y >/dev/null
  apt-get install -y curl unzip openssl jq ca-certificates iproute2 coreutils >/dev/null
}

install_xray() {
  echo "==> 安装/更新官方 Xray..."
  bash <(curl -Ls https://github.com/XTLS/Xray-install/raw/main/install-release.sh) >/dev/null
  [[ -x "$XRAY_BIN" ]] || { echo "Xray 安装失败：找不到 $XRAY_BIN"; exit 1; }
}

stop_conflicts() {
  # 如果你装过 Argosbx，它可能有 xr.service / /root/agsbx/xray
  echo "==> 停止可能冲突的 Argosbx 服务(如存在)..."
  systemctl stop xr 2>/dev/null || true
  systemctl disable xr 2>/dev/null || true
  pkill -f "/root/agsbx/xray" 2>/dev/null || true
}

gen_uuid() {
  if [[ -n "${uuid:-}" ]]; then
    UUID="${uuid}"
  else
    UUID="$(cat /proc/sys/kernel/random/uuid)"
  fi
}

choose_port() {
  if [[ -n "${vlpt:-}" ]]; then
    PORT="${vlpt}"
    is_port_free "$PORT" || { echo "端口 $PORT 被占用，请换：vlpt=38443 bash rv.sh install"; exit 1; }
  else
    for _ in $(seq 1 120); do
      PORT="$(shuf -i ${PORT_MIN}-${PORT_MAX} -n 1)"
      if is_port_free "$PORT"; then break; fi
    done
    is_port_free "$PORT" || { echo "随机端口选择失败，请手动指定：vlpt=xxxxx"; exit 1; }
  fi
}

gen_reality_keys() {
  echo "==> 生成 Reality 密钥对..."
  local KEYS
  KEYS="$("$XRAY_BIN" x25519)"

  # 兼容两种输出：
  # 新：PrivateKey: xxx  Password: yyy
  # 旧：Private key: xxx Public key: yyy
  PRIVATE_KEY="$(echo "$KEYS" | awk -F'[: ]+' '/PrivateKey|Private key/ {print $2; exit}')"
  PUBLIC_KEY="$(echo "$KEYS" | awk -F'[: ]+' '/Password|Public key/ {print $2; exit}')"

  if [[ -z "${PRIVATE_KEY}" || -z "${PUBLIC_KEY}" ]]; then
    echo "密钥解析失败，原始输出："
    echo "$KEYS"
    exit 1
  fi

  SHORT_ID="$(openssl rand -hex 4)"
}

write_config() {
  mkdir -p "$(dirname "$XRAY_CONF")"

  cat > "$XRAY_CONF" <<JSON
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": ${PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          { "id": "${UUID}", "flow": "xtls-rprx-vision" }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${SNI}:443",
          "xver": 0,
          "serverNames": ["${SNI}"],
          "privateKey": "${PRIVATE_KEY}",
          "shortIds": ["${SHORT_ID}"]
        }
      }
    },
    {
      "listen": "::",
      "port": ${PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          { "id": "${UUID}", "flow": "xtls-rprx-vision" }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${SNI}:443",
          "xver": 0,
          "serverNames": ["${SNI}"],
          "privateKey": "${PRIVATE_KEY}",
          "shortIds": ["${SHORT_ID}"]
        }
      }
    }
  ],
  "outbounds": [
    { "protocol": "freedom" }
  ]
}
JSON

  echo "==> 配置自检..."
  "$XRAY_BIN" run -test -config "$XRAY_CONF" >/dev/null
}

start_service() {
  echo "==> 启动 Xray..."
  systemctl enable "$SERVICE" >/dev/null
  systemctl restart "$SERVICE"
  systemctl --no-pager -l status "$SERVICE" | sed -n '1,14p'
}

print_info() {
  load_env

  if [[ -z "${PORT:-}" || -z "${UUID:-}" || -z "${PUBLIC_KEY:-}" || -z "${SHORT_ID:-}" || -z "${SNI:-}" ]]; then
    echo "没有找到已保存的节点信息：$ENV_FILE"
    echo "先运行：bash rv.sh install"
    exit 1
  fi

  local NAME="RV-Tesla-Vision"
  local SERVER="${SERVER_IP:-YOUR_VPS_IP}"

  echo
  echo "================= 节点信息 ================="
  echo "服务器IP      : ${SERVER}"
  echo "端口(PORT)     : ${PORT}"
  echo "UUID           : ${UUID}"
  echo "SNI(伪装域名)  : ${SNI}"
  echo "PublicKey(pbk) : ${PUBLIC_KEY}"
  echo "ShortID(sid)   : ${SHORT_ID}"
  echo "Fingerprint    : ${FP:-chrome}"
  echo "==========================================="
  echo

  echo "vless 分享链接："
  echo "vless://${UUID}@${SERVER}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SNI}&fp=${FP:-chrome}&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp#${NAME}"
  echo
  echo "Clash Meta 片段："
  cat <<YAML
proxies:
  - name: ${NAME}
    type: vless
    server: ${SERVER}
    port: ${PORT}
    uuid: ${UUID}
    network: tcp
    tls: true
    flow: xtls-rprx-vision
    servername: ${SNI}
    reality-opts:
      public-key: ${PUBLIC_KEY}
      short-id: ${SHORT_ID}
    udp: true
YAML
  echo
  echo "注意：请确保云安全组/防火墙已放行 TCP ${PORT}"
}

cmd_install() {
  is_root || { echo "请用 root 运行"; exit 1; }

  install_deps
  install_xray
  stop_conflicts

  SNI="${reym:-$REYM_DEFAULT}"
  FP="${fp:-chrome}"

  gen_uuid
  choose_port
  gen_reality_keys

  SERVER_IP="$(get_public_ip)"
  write_config
  start_service

  save_env

  echo
  echo "==> 安装完成，已保存到：$ENV_FILE"
  echo "==> 现在可运行：bash rv.sh info  查看链接"
}

cmd_status() {
  systemctl --no-pager -l status "$SERVICE"
}

cmd_log() {
  journalctl -u "$SERVICE" --no-pager -n 200
}

cmd_uninstall() {
  is_root || { echo "请用 root 运行"; exit 1; }

  systemctl stop "$SERVICE" 2>/dev/null || true
  systemctl disable "$SERVICE" 2>/dev/null || true

  rm -f "$XRAY_CONF" "$ENV_FILE"
  bash <(curl -Ls https://github.com/XTLS/Xray-install/raw/main/install-release.sh) --remove || true

  echo "已卸载完成（配置与保存信息已清理）"
}

case "${1:-}" in
  install)   cmd_install ;;
  info)      print_info ;;
  status)    cmd_status ;;
  log)       cmd_log ;;
  uninstall) cmd_uninstall ;;
  *)
    echo "用法："
    echo "  bash rv.sh install        # 安装/更新并生成节点"
    echo "  bash rv.sh info           # 输出分享链接/Clash片段"
    echo "  bash rv.sh status         # 查看服务状态"
    echo "  bash rv.sh log            # 查看最近200行日志"
    echo "  bash rv.sh uninstall      # 卸载"
    echo
    echo "可选变量："
    echo "  reym=www.tesla.com vlpt=443 uuid=xxx fp=chrome bash rv.sh install"
    ;;
esac
EOF

chmod +x /root/rv.sh
echo "已生成：/root/rv.sh"
echo "下一步运行：bash /root/rv.sh install"
