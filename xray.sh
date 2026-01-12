#!/usr/bin/env bash
set -euo pipefail
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# ==========================================================
# RV - VLESS TCP REALITY Vision (Interactive, self-use)
#
# Run:
#   bash xray.sh            # interactive menu
# Or:
#   bash xray.sh install|info|status|log|bbr|uninstall
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

die(){ echo "ERROR: $*" >&2; exit 1; }
is_root(){ [[ "${EUID}" -eq 0 ]]; }

load_env() {
  [[ -f "$ENV_FILE" ]] && # shellcheck disable=SC1090
  source "$ENV_FILE"
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
  [[ -x "$XRAY_BIN" ]] || die "Xray 安装失败：找不到 $XRAY_BIN"
}

stop_conflicts() {
  echo "==> 停止可能冲突的服务(如存在)..."
  systemctl stop xr 2>/dev/null || true
  systemctl disable xr 2>/dev/null || true
  pkill -f "/root/agsbx/xray" 2>/dev/null || true
}

is_port_free() {
  # free => 0, used => 1
  ss -lnt 2>/dev/null | awk '{print $4}' | grep -qE "[:.]$1\$" && return 1 || return 0
}

gen_uuid() {
  if [[ -n "${uuid:-}" ]]; then
    UUID="$uuid"
  else
    UUID="$(cat /proc/sys/kernel/random/uuid)"
  fi
}

choose_port() {
  if [[ -n "${vlpt:-}" ]]; then
    PORT="$vlpt"
    is_port_free "$PORT" || die "端口 $PORT 被占用，请换：vlpt=38443 bash xray.sh install"
    return
  fi
  for _ in $(seq 1 120); do
    PORT="$(shuf -i ${PORT_MIN}-${PORT_MAX} -n 1)"
    is_port_free "$PORT" && return
  done
  die "随机端口选择失败，请手动指定：vlpt=xxxxx"
}

gen_reality_keys() {
  echo "==> 生成 Reality 密钥对..."
  local KEYS
  KEYS="$("$XRAY_BIN" x25519)"

  PRIVATE_KEY="$(echo "$KEYS" | awk -F'[: ]+' '/PrivateKey|Private key/ {print $2; exit}')"
  PUBLIC_KEY="$(echo "$KEYS"  | awk -F'[: ]+' '/Password|Public key/ {print $2; exit}')"

  [[ -n "${PRIVATE_KEY}" && -n "${PUBLIC_KEY}" ]] || { echo "$KEYS"; die "密钥解析失败"; }
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
  systemctl enable "$SERVICE" >/dev/null 2>&1 || true
  systemctl restart "$SERVICE"
  systemctl --no-pager -l status "$SERVICE" | sed -n '1,14p'
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
  echo "==> 安装完成：$ENV_FILE"
  echo "==> 查看信息：bash xray.sh info"
}

cmd_info() {
  load_env
  [[ -n "${PORT:-}" && -n "${UUID:-}" && -n "${PUBLIC_KEY:-}" && -n "${SHORT_ID:-}" && -n "${SNI:-}" ]] \
    || die "没有找到已保存的节点信息：$ENV_FILE（先运行 install）"

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
  echo "Fingerprint    : ${FP:-$FP_DEFAULT}"
  echo "==========================================="
  echo
  echo "vless 分享链接："
  echo "vless://${UUID}@${SERVER}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SNI}&fp=${FP:-$FP_DEFAULT}&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp#${NAME}"
  echo
}

cmd_status(){ systemctl --no-pager -l status "$SERVICE"; }
cmd_log(){ journalctl -u "$SERVICE" --no-pager -n 200; }

cmd_bbr() {
  is_root || die "请用 root 运行"
  echo "==> 开启 BBR + fq..."
  modprobe tcp_bbr 2>/dev/null || true

  mkdir -p /etc/sysctl.d
  cat > /etc/sysctl.d/99-bbr-fq.conf <<CONF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
CONF

  sysctl --system >/dev/null
  echo "==> 已应用："
  sysctl -n net.ipv4.tcp_congestion_control || true
  sysctl -n net.core.default_qdisc || true
}

cmd_uninstall() {
  is_root || die "请用 root 运行"
  systemctl stop "$SERVICE" 2>/dev/null || true
  systemctl disable "$SERVICE" 2>/dev/null || true
  rm -f "$XRAY_CONF" "$ENV_FILE"
  # 官方卸载脚本对 bash 参数解析不同，这里兼容两种
  curl -Ls https://github.com/XTLS/Xray-install/raw/main/install-release.sh | bash -s -- remove || true
  echo "已卸载完成（配置与保存信息已清理）"
}

# ---------------- Interactive ----------------

prompt() {
  local msg="$1" def="${2:-}"
  if [[ -n "$def" ]]; then
    printf "%s [%s]: " "$msg" "$def"
  else
    printf "%s: " "$msg"
  fi
  local ans=""
  IFS= read -r ans || ans=""
  if [[ -z "$ans" ]]; then
    echo "$def"
  else
    echo "$ans"
  fi
}

clean_choice() {
  # keep only digits
  echo "$1" | tr -cd '0-9'
}

menu() {
  clear || true
  cat <<'EOF'
==============================
 RV - VLESS TCP REALITY Vision
==============================
1) Install / Reinstall
2) Show node info
3) Service status
4) Show logs (last 200)
5) Enable BBR + fq
6) Uninstall
0) Exit
------------------------------
EOF
}

interactive_install() {
  echo
  echo "==> 交互安装（回车使用默认值）"
  local reym_in vlpt_in uuid_in fp_in

  reym_in="$(prompt "SNI/伪装域名" "${reym:-$REYM_DEFAULT}")"
  vlpt_in="$(prompt "端口(留空随机)" "${vlpt:-}")"
  uuid_in="$(prompt "UUID(留空随机)" "${uuid:-}")"
  fp_in="$(prompt "Fingerprint" "${fp:-$FP_DEFAULT}")"

  export reym="$reym_in"
  if [[ -n "$vlpt_in" ]]; then export vlpt="$vlpt_in"; else unset vlpt || true; fi
  if [[ -n "$uuid_in" ]]; then export uuid="$uuid_in"; else unset uuid || true; fi
  export fp="$fp_in"

  cmd_install
  prompt "回车返回菜单" ""
}

main_menu() {
  while true; do
    menu
    local raw choice
    raw="$(prompt "Select" "1")"
    choice="$(clean_choice "$raw")"

    case "$choice" in
      1) interactive_install ;;
      2) cmd_info; prompt "回车返回菜单" "" ;;
      3) cmd_status; prompt "回车返回菜单" "" ;;
      4) cmd_log; prompt "回车返回菜单" "" ;;
      5) cmd_bbr; prompt "回车返回菜单" "" ;;
      6)
        local c
        c="$(prompt "确认卸载? 输入 YES 继续" "NO")"
        [[ "$c" == "YES" ]] && cmd_uninstall || echo "已取消"
        prompt "回车返回菜单" ""
        ;;
      0) exit 0 ;;
      *)
        echo "Invalid choice: $raw"
        sleep 1
        ;;
    esac
  done
}

# ---------------- entry ----------------

case "${1:-}" in
  install)   cmd_install ;;
  info)      cmd_info ;;
  status)    cmd_status ;;
  log)       cmd_log ;;
  bbr)       cmd_bbr ;;
  uninstall) cmd_uninstall ;;
  "" )       main_menu ;;
  *)
    echo "用法："
    echo "  bash xray.sh                 # 交互菜单"
    echo "  bash xray.sh install          # 安装/更新并生成节点"
    echo "  bash xray.sh info             # 输出分享链接"
    echo "  bash xray.sh status           # 查看服务状态"
    echo "  bash xray.sh log              # 查看最近200行日志"
    echo "  bash xray.sh bbr              # 开启 BBR + fq"
    echo "  bash xray.sh uninstall         # 卸载"
    echo
    echo "可选变量："
    echo "  reym=www.tesla.com vlpt=443 uuid=xxx fp=chrome bash xray.sh install"
    ;;
esac
    
