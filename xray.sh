#!/usr/bin/env bash
set -euo pipefail
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

# ==========================================================
# RV - VLESS TCP REALITY Vision (One-click, non-interactive)
#
# Default:
#   SNI = www.tesla.com
#   Port = random (20000-60000)
#   UUID = random
#   Fingerprint = chrome
#
# Run:
#   bash xray.sh
#
# Optional env:
#   reym=www.tesla.com        # SNI/伪装域名
#   vlpt=443                  # 端口(留空随机)
#   uuid=xxxx                 # UUID(留空随机)
#   fp=chrome                 # 指纹(默认 chrome)
#   bbr=1                     # 额外开启 BBR+fq（可选）
#
# Commands:
#   bash xray.sh              # install/reinstall & print info
#   bash xray.sh info         # print info only
#   bash xray.sh status       # systemd status
#   bash xray.sh log          # last 200 logs
#   bash xray.sh uninstall    # remove xray + clean
# ==========================================================

ENV_FILE="/root/reality_vision.env"
XRAY_BIN="/usr/local/bin/xray"
XRAY_CONF="/usr/local/etc/xray/config.json"
SERVICE="xray"

REYM_DEFAULT="www.tesla.com"
FP_DEFAULT="chrome"
PORT_MIN=20000
PORT_MAX=60000

die(){ echo "ERROR: $*" >&2; exit 1; }
is_root(){ [[ "${EUID:-0}" -eq 0 ]]; }

need_cmd(){ command -v "$1" >/dev/null 2>&1 || die "缺少命令: $1"; }

install_deps() {
  echo "==> 安装依赖..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y >/dev/null
  apt-get install -y curl unzip openssl ca-certificates iproute2 coreutils >/dev/null
}

install_xray() {
  echo "==> 安装/更新官方 Xray..."
  # 官方安装脚本：安装/更新
  bash <(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh) >/dev/null
  [[ -x "$XRAY_BIN" ]] || die "Xray 安装失败：找不到 $XRAY_BIN"
}

stop_conflicts() {
  # 如果你装过 Argosbx，它可能有 xr.service / /root/agsbx/xray
  echo "==> 停止可能冲突的服务(如存在)..."
  systemctl stop xr 2>/dev/null || true
  systemctl disable xr 2>/dev/null || true
  pkill -f "/root/agsbx/xray" 2>/dev/null || true
}

is_port_free() {
  # free => 0, used => 1
  ss -lnt 2>/dev/null | awk '{print $4}' | grep -qE "[:.]$1\$" && return 1 || return 0
}

choose_port() {
  if [[ -n "${vlpt:-}" ]]; then
    PORT="$vlpt"
    is_port_free "$PORT" || die "端口 $PORT 被占用，请换：vlpt=38443 bash xray.sh"
    return
  fi
  for _ in $(seq 1 180); do
    PORT="$(shuf -i ${PORT_MIN}-${PORT_MAX} -n 1)"
    is_port_free "$PORT" && return
  done
  die "随机端口选择失败，请手动指定：vlpt=xxxxx"
}

gen_uuid() {
  if [[ -n "${uuid:-}" ]]; then
    UUID="$uuid"
  else
    UUID="$(cat /proc/sys/kernel/random/uuid)"
  fi
}

gen_reality_keys() {
  echo "==> 生成 Reality x25519 密钥对..."
  local KEYS PRIVATE_KEY PUBLIC_KEY
  KEYS="$("$XRAY_BIN" x25519 2>/dev/null || true)"

  # 兼容两种输出：
  # 新：PrivateKey: xxx  Password: yyy
  # 旧：Private key: xxx Public key: yyy
  PRIVATE_KEY="$(echo "$KEYS" | awk -F'[: ]+' '/PrivateKey|Private key/ {print $2; exit}')"
  PUBLIC_KEY="$(echo "$KEYS"  | awk -F'[: ]+' '/Password|Public key/ {print $2; exit}')"

  [[ -n "$PRIVATE_KEY" && -n "$PUBLIC_KEY" ]] || {
    echo "密钥生成/解析失败，输出如下："
    echo "$KEYS"
    die "请确认 Xray 可执行 & 版本正常"
  }

  PRIVATE_KEY_R="$PRIVATE_KEY"
  PUBLIC_KEY_R="$PUBLIC_KEY"
  SHORT_ID="$(openssl rand -hex 4)"
}

get_public_ip() {
  curl -s --max-time 3 https://api.ipify.org || true
}

write_config() {
  echo "==> 写入配置..."
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
          "privateKey": "${PRIVATE_KEY_R}",
          "shortIds": ["${SHORT_ID}"]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http","tls","quic"]
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
          "privateKey": "${PRIVATE_KEY_R}",
          "shortIds": ["${SHORT_ID}"]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http","tls","quic"]
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
  systemctl enable "$SERVICE" >/dev/null 2>&1 || true
  systemctl restart "$SERVICE"
  systemctl --no-pager -l status "$SERVICE" | sed -n '1,14p'
}

save_env() {
  umask 077
  cat > "$ENV_FILE" <<ENV
# Auto-generated. Edit if you know what you're doing.
SERVER_IP=${SERVER_IP}
PORT=${PORT}
UUID=${UUID}
SNI=${SNI}
FP=${FP}
PUBLIC_KEY=${PUBLIC_KEY_R}
SHORT_ID=${SHORT_ID}
ENV
  chmod 600 "$ENV_FILE" 2>/dev/null || true
}

load_env() {
  [[ -f "$ENV_FILE" ]] && # shellcheck disable=SC1090
  source "$ENV_FILE"
}

print_info() {
  load_env
  [[ -n "${PORT:-}" && -n "${UUID:-}" && -n "${PUBLIC_KEY:-}" && -n "${SHORT_ID:-}" && -n "${SNI:-}" ]] \
    || die "没有找到已保存的节点信息：$ENV_FILE（先运行：bash xray.sh）"

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

enable_bbr_fq() {
  echo "==> 开启 BBR + fq..."
  modprobe tcp_bbr 2>/dev/null || true
  mkdir -p /etc/sysctl.d
  cat > /etc/sysctl.d/99-bbr-fq.conf <<CONF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
CONF
  sysctl --system >/dev/null || true
  echo "==> 当前参数："
  sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true
  sysctl -n net.core.default_qdisc 2>/dev/null || true
}

cmd_install() {
  is_root || die "请用 root 运行"
  need_cmd systemctl
  install_deps
  install_xray
  stop_conflicts

  SNI="${reym:-$REYM_DEFAULT}"
  FP="${fp:-$FP_DEFAULT}"

  gen_uuid
  choose_port
  gen_reality_keys

  SERVER_IP="$(get_public_ip)"
  write_config
  start_service
  save_env

  if [[ "${bbr:-0}" == "1" ]]; then
    enable_bbr_fq
  fi

  echo
  echo "==> 安装完成，信息已保存：$ENV_FILE"
  print_info
}

cmd_uninstall() {
  is_root || die "请用 root 运行"
  echo "==> 停止服务..."
  systemctl stop "$SERVICE" 2>/dev/null || true
  systemctl disable "$SERVICE" 2>/dev/null || true

  echo "==> 清理配置..."
  rm -f "$XRAY_CONF" "$ENV_FILE"

  echo "==> 卸载 Xray..."
  # 正确卸载方式（你之前已经验证过）：pipe + bash -s -- remove
  curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh | bash -s -- remove || true

  echo "==> 卸载完成"
}

case "${1:-}" in
  "" )        cmd_install ;;
  install)    cmd_install ;;
  info)       print_info ;;
  status)     systemctl --no-pager -l status "$SERVICE" ;;
  log)        journalctl -u "$SERVICE" --no-pager -n 200 ;;
  bbr)        is_root || die "请用 root 运行"; enable_bbr_fq ;;
  uninstall)  cmd_uninstall ;;
  *)
    echo "用法："
    echo "  bash xray.sh              # 一键安装/重装并输出信息"
    echo "  bash xray.sh info         # 仅输出节点信息"
    echo "  bash xray.sh status       # 查看服务状态"
    echo "  bash xray.sh log          # 查看最近200行日志"
    echo "  bbr=1 bash xray.sh        # 安装时顺便开启 BBR+fq"
    echo "  bash xray.sh bbr          # 单独开启 BBR+fq"
    echo "  bash xray.sh uninstall    # 卸载"
    echo
    echo "可选变量："
    echo "  reym=www.tesla.com vlpt=443 uuid=xxx fp=chrome bash xray.sh"
    ;;
esac
