#!/bin/sh
set -eu
export LANG=en_US.UTF-8

# ==========================================================
# rv.sh - Interactive Minimal VLESS TCP REALITY Vision
#
# Run:
#   sh rv.sh            # interactive menu
# Or:
#   sh rv.sh install|info|status|log|bbr|uninstall
#
# Optional env:
#   reym=www.tesla.com   vlpt=443   uuid=xxxx   fp=chrome
# ==========================================================

ENV_FILE="/root/reality_vision.env"
XRAY_BIN="/usr/local/bin/xray"
XRAY_CONF="/usr/local/etc/xray/config.json"
SERVICE="xray"

REYM_DEFAULT="www.tesla.com"
FP_DEFAULT="chrome"
PORT_MIN=10000
PORT_MAX=65535

die() { echo "ERROR: $*" >&2; exit 1; }

is_root() {
  [ "${EUID:-0}" -eq 0 ] 2>/dev/null
}

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "缺少命令: $1"; }

load_env() {
  if [ -f "$ENV_FILE" ]; then
    # shellcheck disable=SC1090
    . "$ENV_FILE"
  fi
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
PUBLIC_KEY=${PUBLIC_KEY}
SHORT_ID=${SHORT_ID}
ENV
  chmod 600 "$ENV_FILE" 2>/dev/null || true
}

get_public_ip() {
  # best-effort
  curl -s --max-time 3 https://api.ipify.org 2>/dev/null || true
}

is_port_free() {
  # return 0 free, 1 used
  ss -lnt 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]$1\$" && return 1 || return 0
}

rand_port() {
  # use shuf if exists else awk+rand
  if command -v shuf >/dev/null 2>&1; then
    shuf -i "${PORT_MIN}-${PORT_MAX}" -n 1
  else
    awk -v min="$PORT_MIN" -v max="$PORT_MAX" 'BEGIN{srand(); print int(min+rand()*(max-min+1))}'
  fi
}

rand_hex4() {
  # 4 bytes => 8 hex
  openssl rand -hex 4
}

install_deps() {
  echo "==> 安装依赖..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y >/dev/null
  apt-get install -y curl unzip openssl jq ca-certificates iproute2 coreutils >/dev/null
}

install_xray() {
  echo "==> 安装/更新官方 Xray..."
  # POSIX sh compatible (no process substitution)
  curl -Ls https://github.com/XTLS/Xray-install/raw/main/install-release.sh | sh -s -- >/dev/null
  [ -x "$XRAY_BIN" ] || die "Xray 安装失败：找不到 $XRAY_BIN"
}

stop_conflicts() {
  echo "==> 停止可能冲突的服务(如存在)..."
  # Argosbx xr service (if installed)
  systemctl stop xr 2>/dev/null || true
  systemctl disable xr 2>/dev/null || true
  pkill -f "/root/agsbx/xray" 2>/dev/null || true
}

gen_uuid() {
  if [ -n "${uuid:-}" ]; then
    UUID="$uuid"
  else
    UUID="$(cat /proc/sys/kernel/random/uuid)"
  fi
}

choose_port() {
  if [ -n "${vlpt:-}" ]; then
    PORT="$vlpt"
    is_port_free "$PORT" || die "端口 $PORT 被占用，请换一个端口（例如：vlpt=38443 sh rv.sh install）"
    return 0
  fi

  i=0
  while [ "$i" -lt 120 ]; do
    PORT="$(rand_port)"
    if is_port_free "$PORT"; then
      return 0
    fi
    i=$((i+1))
  done
  die "随机端口选择失败，请手动指定：vlpt=xxxxx"
}

gen_reality_keys() {
  echo "==> 生成 Reality 密钥对..."
  KEYS="$("$XRAY_BIN" x25519)"

  # Compatible outputs:
  # New: PrivateKey: xxx  Password: yyy
  # Old: Private key: xxx Public key: yyy
  PRIVATE_KEY="$(echo "$KEYS" | awk -F'[: ]+' '/PrivateKey|Private key/ {print $2; exit}')"
  PUBLIC_KEY="$(echo "$KEYS" | awk -F'[: ]+' '/Password|Public key/ {print $2; exit}')"

  [ -n "${PRIVATE_KEY:-}" ] || { echo "$KEYS" >&2; die "密钥解析失败（PrivateKey）"; }
  [ -n "${PUBLIC_KEY:-}" ]  || { echo "$KEYS" >&2; die "密钥解析失败（PublicKey）"; }

  SHORT_ID="$(rand_hex4)"
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
  systemctl enable "$SERVICE" >/dev/null 2>&1 || true
  systemctl restart "$SERVICE"
  systemctl --no-pager -l status "$SERVICE" | sed -n '1,14p'
}

print_info() {
  load_env
  [ -n "${PORT:-}" ] || die "没有找到已保存的节点信息：$ENV_FILE（先运行 install）"
  [ -n "${UUID:-}" ] || die "没有找到已保存的节点信息：$ENV_FILE（先运行 install）"
  [ -n "${PUBLIC_KEY:-}" ] || die "没有找到已保存的节点信息：$ENV_FILE（先运行 install）"
  [ -n "${SHORT_ID:-}" ] || die "没有找到已保存的节点信息：$ENV_FILE（先运行 install）"
  [ -n "${SNI:-}" ] || die "没有找到已保存的节点信息：$ENV_FILE（先运行 install）"

  NAME="RV-Tesla-Vision"
  SERVER="${SERVER_IP:-YOUR_VPS_IP}"

  echo
  echo "================= 节点信息 ================="
  echo "服务器IP      : ${SERVER}"
  echo "端口(PORT)     : ${PORT}"
  echo "UUID           : ${UUID}"
  echo "SNI(伪装域名)  : ${SNI}"
  echo "PublicKey(pbk) : ${PUBLIC_KEY}"
  echo "ShortID(sid)   : ${SHORT_ID}"
  echo "Fingerprint    : ${FP:-$FP_DEFAULT}"
  echo "==========================================="
  echo
  echo "vless 分享链接："
  echo "vless://${UUID}@${SERVER}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SNI}&fp=${FP:-$FP_DEFAULT}&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp#${NAME}"
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

cmd_status() { systemctl --no-pager -l status "$SERVICE"; }

cmd_log() { journalctl -u "$SERVICE" --no-pager -n 200; }

cmd_bbr() {
  is_root || die "请用 root 运行"

  need_cmd sysctl
  echo "==> 开启 BBR + fq ..."
  modprobe tcp_bbr 2>/dev/null || true

  mkdir -p /etc/sysctl.d
  cat > /etc/sysctl.d/99-bbr-fq.conf <<CONF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
CONF

  sysctl --system >/dev/null
  echo "==> 已写入 /etc/sysctl.d/99-bbr-fq.conf 并应用"
  echo "当前拥塞控制：$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo unknown)"
  echo "当前队列算法  ：$(sysctl -n net.core.default_qdisc 2>/dev/null || echo unknown)"
}

cmd_install() {
  is_root || die "请用 root 运行"

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

  echo
  echo "==> 安装完成，已保存到：$ENV_FILE"
  echo "==> 可运行：sh rv.sh info  查看链接"
}

cmd_uninstall() {
  is_root || die "请用 root 运行"

  systemctl stop "$SERVICE" 2>/dev/null || true
  systemctl disable "$SERVICE" 2>/dev/null || true

  rm -f "$XRAY_CONF" "$ENV_FILE"

  echo "==> 卸载 Xray..."
  curl -Ls https://github.com/XTLS/Xray-install/raw/main/install-release.sh | sh -s -- remove || true

  echo "已卸载完成（配置与保存信息已清理）"
}

# ------------------ interactive UI ------------------

prompt() {
  # prompt "text" "default"
  text="$1"
  def="${2:-}"
  if [ -n "$def" ]; then
    printf "%s [%s]: " "$text" "$def"
  else
    printf "%s: " "$text"
  fi
  IFS= read -r ans || ans=""
  if [ -z "$ans" ]; then
    echo "$def"
  else
    echo "$ans"
  fi
}

menu() {
  echo
  echo "=============================="
  echo " RV - VLESS TCP REALITY Vision"
  echo "=============================="
  echo "1) Install / Reinstall"
  echo "2) Show node info"
  echo "3) Service status"
  echo "4) Show logs (last 200)"
  echo "5) Enable BBR + fq"
  echo "6) Uninstall"
  echo "0) Exit"
  echo "------------------------------"
}

interactive_install() {
  echo
  echo "==> 交互安装：回车使用默认值"
  reym_in="$(prompt "SNI/伪装域名" "${reym:-$REYM_DEFAULT}")"
  vlpt_in="$(prompt "端口(留空随机)" "${vlpt:-}")"
  uuid_in="$(prompt "UUID(留空随机)" "${uuid:-}")"
  fp_in="$(prompt "Fingerprint" "${fp:-$FP_DEFAULT}")"

  # export to affect cmd_install
  if [ -n "$reym_in" ]; then reym="$reym_in"; export reym; fi
  if [ -n "$vlpt_in" ]; then vlpt="$vlpt_in"; export vlpt; else unset vlpt 2>/dev/null || true; fi
  if [ -n "$uuid_in" ]; then uuid="$uuid_in"; export uuid; else unset uuid 2>/dev/null || true; fi
  if [ -n "$fp_in" ]; then fp="$fp_in"; export fp; fi

  cmd_install
}

main_menu() {
  while :; do
    menu
    choice="$(prompt "选择" "1")"
    case "$choice" in
      1) interactive_install ;;
      2) print_info ;;
      3) cmd_status ;;
      4) cmd_log ;;
      5) cmd_bbr ;;
      6)
        confirm="$(prompt "确认卸载? 输入 YES 继续" "NO")"
        [ "$confirm" = "YES" ] && cmd_uninstall || echo "已取消"
        ;;
      0) exit 0 ;;
      *) echo "无效选择：$choice" ;;
    esac
  done
}

# ------------------ entry ------------------

case "${1:-}" in
  install)   cmd_install ;;
  info)      print_info ;;
  status)    cmd_status ;;
  log)       cmd_log ;;
  bbr)       cmd_bbr ;;
  uninstall) cmd_uninstall ;;
  "" )       main_menu ;;
  *)
    echo "用法："
    echo "  sh rv.sh                 # 交互菜单"
    echo "  sh rv.sh install         # 安装/更新并生成节点"
    echo "  sh rv.sh info            # 输出分享链接/Clash片段"
    echo "  sh rv.sh status          # 查看服务状态"
    echo "  sh rv.sh log             # 查看最近200行日志"
    echo "  sh rv.sh bbr             # 开启 BBR + fq"
    echo "  sh rv.sh uninstall       # 卸载"
    echo
    echo "可选变量："
    echo "  reym=www.tesla.com vlpt=443 uuid=xxx fp=chrome sh rv.sh install"
    ;;
esac
