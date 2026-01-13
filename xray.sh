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
#   openfw=1                  # 自动放行防火墙端口（可选）
#   dry=1                     # dry-run（仅打印将执行动作）
#   gh_proxy=https://xxx/     # GitHub raw 代理前缀（可选）
#
# Commands:
#   bash xray.sh              # install/reinstall & print info
#   bash xray.sh install      # same as default
#   bash xray.sh update       # update xray core only (no config change)
#   bash xray.sh info         # print saved node info
#   bash xray.sh status       # systemd status
#   bash xray.sh log          # last 200 logs
#   bash xray.sh check        # self-check
#   bash xray.sh uninstall    # remove xray + clean
#   bash xray.sh bbr          # enable BBR+fq
#
# Dry-run flag:
#   bash xray.sh --dry-run install
# ==========================================================

trap 'echo "ERROR: line=$LINENO cmd=$BASH_COMMAND" >&2' ERR

ENV_FILE="/root/reality_vision.env"
XRAY_BIN="/usr/local/bin/xray"
XRAY_CONF="/usr/local/etc/xray/config.json"
SERVICE="xray"

REYM_DEFAULT="www.tesla.com"
FP_DEFAULT="chrome"
PORT_MIN=20000
PORT_MAX=60000

DRY_RUN="${dry:-0}"

die(){ echo "ERROR: $*" >&2; exit 1; }
warn(){ echo "WARN: $*" >&2; }
is_root(){ [[ "${EUID:-0}" -eq 0 ]]; }
need_cmd(){ command -v "$1" >/dev/null 2>&1 || die "缺少命令: $1"; }

run_cmd() {
  if [[ "$DRY_RUN" == "1" ]]; then
    echo "[dry-run] $*"
    return 0
  fi
  "$@"
}

parse_dry_run_flag() {
  case "${1:-}" in
    --dry-run|dry-run|-n)
      DRY_RUN="1"
      shift || true
      ;;
  esac
  echo "${1:-}"
}

is_debian_like() {
  [[ -r /etc/os-release ]] || return 1
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ "${ID:-}" == "debian" || "${ID:-}" == "ubuntu" || "${ID_LIKE:-}" == *"debian"* ]]
}

valid_port() { [[ "$1" =~ ^[0-9]+$ ]] && (( $1 >= 1 && $1 <= 65535 )); }
valid_uuid() { [[ "$1" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; }
valid_sni() {
  [[ -n "$1" ]] || return 1
  [[ "$1" =~ ^[A-Za-z0-9.-]+$ ]] || return 1
  [[ "$1" == *.* ]] || return 1
  return 0
}

# ---------- robust fetch helpers ----------

curl_fetch() {
  # curl_fetch <url> <out_file>
  # extra stable: retry + timeout + follow redirect
  local url="$1" out="$2"
  local ua="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125 Safari/537.36"

  if [[ "$DRY_RUN" == "1" ]]; then
    echo "[dry-run] curl -fsSL --retry 3 --retry-delay 1 --connect-timeout 5 --max-time 25 -A '$ua' '$url' -o '$out'"
    return 0
  fi

  curl -fsSL \
    --retry 3 --retry-delay 1 --retry-connrefused \
    --connect-timeout 5 --max-time 25 \
    -A "$ua" \
    "$url" -o "$out"
}

with_proxy_if_set() {
  # if gh_proxy is set, prepend it
  # gh_proxy must end with / (recommended), but we handle both
  local url="$1"
  if [[ -n "${gh_proxy:-}" ]]; then
    local p="$gh_proxy"
    [[ "$p" == */ ]] || p="${p}/"
    echo "${p}${url}"
  else
    echo "$url"
  fi
}

# ---------- deps / xray ----------

install_deps() {
  echo "==> 安装依赖..."
  is_debian_like || die "当前脚本仅内置 Debian/Ubuntu apt 依赖安装逻辑"
  export DEBIAN_FRONTEND=noninteractive
  run_cmd apt-get update -y >/dev/null
  run_cmd apt-get install -y curl unzip openssl ca-certificates iproute2 coreutils >/dev/null
}

install_xray() {
  echo "==> 安装/更新官方 Xray..."

  # ✅ 正确 raw 地址（修复 404 根因）
  local RAW_URL="https://raw.githubusercontent.com/XTLS/Xray-install/main/install-release.sh"

  # 可选：你设置 gh_proxy 后，会变成：gh_proxy + RAW_URL
  local URL="$(with_proxy_if_set "$RAW_URL")"

  local tmp="/tmp/xray-install.$RANDOM.$RANDOM.sh"
  run_cmd rm -f "$tmp" 2>/dev/null || true

  echo "==> 拉取安装脚本：$URL"
  if ! curl_fetch "$URL" "$tmp"; then
    # 给更明确的报错提示（特别是 404/网络问题）
    die "下载官方安装脚本失败（可能网络/代理/URL 问题）。可尝试：gh_proxy=https://你的代理/ bash xray.sh"
  fi

  # 简单 sanity check：避免下载到 HTML/错误页
  if [[ "$DRY_RUN" != "1" ]]; then
    grep -qE "Xray|install|remove" "$tmp" || {
      echo "==== 安装脚本内容预览(前40行) ===="
      sed -n '1,40p' "$tmp" || true
      die "安装脚本内容异常（可能被代理替换/返回了错误页）"
    }
  fi

  run_cmd bash "$tmp" >/dev/null
  run_cmd rm -f "$tmp" 2>/dev/null || true

  [[ "$DRY_RUN" == "1" ]] && return 0
  [[ -x "$XRAY_BIN" ]] || die "Xray 安装失败：找不到 $XRAY_BIN"
}

stop_conflicts() {
  echo "==> 停止可能冲突的服务(如存在)..."
  run_cmd systemctl stop xr 2>/dev/null || true
  run_cmd systemctl disable xr 2>/dev/null || true
  run_cmd pkill -f "/root/agsbx/xray" 2>/dev/null || true
}

is_port_free() {
  ss -lnt 2>/dev/null | awk '{print $4}' | grep -qE "[:.]$1\$" && return 1 || return 0
}

choose_port() {
  if [[ -n "${vlpt:-}" ]]; then
    valid_port "$vlpt" || die "vlpt 不是有效端口：$vlpt"
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
    valid_uuid "$uuid" || die "uuid 格式不对：$uuid"
    UUID="$uuid"
  else
    UUID="$(cat /proc/sys/kernel/random/uuid)"
  fi
}

gen_reality_keys() {
  echo "==> 生成 Reality x25519 密钥对..."
  if [[ "$DRY_RUN" == "1" ]]; then
    PRIVATE_KEY_R="(dry-run-redacted)"
    PUBLIC_KEY_R="(dry-run-redacted)"
    SHORT_ID="(dry-run-redacted)"
    return 0
  fi

  local KEYS PRIVATE_KEY PUBLIC_KEY
  KEYS="$("$XRAY_BIN" x25519 2>/dev/null || true)"

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
  local ip=""
  ip="$(curl -4 -s --max-time 3 https://api.ipify.org 2>/dev/null || true)"
  [[ -n "$ip" ]] || ip="$(curl -4 -s --max-time 3 https://ifconfig.me 2>/dev/null || true)"
  [[ -n "$ip" ]] || ip="$(curl -4 -s --max-time 3 https://icanhazip.com 2>/dev/null || true)"
  ip="${ip//$'\n'/}"
  if [[ -z "$ip" ]]; then
    ip="$(curl -6 -s --max-time 3 https://api64.ipify.org 2>/dev/null || true)"
    ip="${ip//$'\n'/}"
  fi
  echo "$ip"
}

write_config() {
  echo "==> 写入配置..."
  run_cmd mkdir -p "$(dirname "$XRAY_CONF")"

  if [[ "$DRY_RUN" == "1" ]]; then
    echo "[dry-run] would write $XRAY_CONF"
    return 0
  fi

  cat > "$XRAY_CONF" <<JSON
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "tag": "vless-in-4",
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
      "sniffing": { "enabled": true, "destOverride": ["http","tls","quic"] }
    },
    {
      "tag": "vless-in-6",
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
      "sniffing": { "enabled": true, "destOverride": ["http","tls","quic"] }
    }
  ],
  "outbounds": [
    { "protocol": "freedom", "tag": "direct" }
  ]
}
JSON

  echo "==> 配置自检..."
  "$XRAY_BIN" run -test -config "$XRAY_CONF" >/dev/null
}

start_service() {
  echo "==> 启动 Xray..."
  run_cmd systemctl enable "$SERVICE" >/dev/null 2>&1 || true
  run_cmd systemctl restart "$SERVICE"
  if [[ "$DRY_RUN" == "1" ]]; then
    echo "[dry-run] would show: systemctl status $SERVICE"
    return 0
  fi
  systemctl --no-pager -l status "$SERVICE" | sed -n '1,14p'
}

save_env() {
  echo "==> 保存节点信息..."
  if [[ "$DRY_RUN" == "1" ]]; then
    echo "[dry-run] would write $ENV_FILE (600)"
    return 0
  fi
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
  run_cmd modprobe tcp_bbr 2>/dev/null || true
  run_cmd mkdir -p /etc/sysctl.d
  if [[ "$DRY_RUN" == "1" ]]; then
    echo "[dry-run] would write /etc/sysctl.d/99-bbr-fq.conf and run sysctl --system"
    return 0
  fi
  cat > /etc/sysctl.d/99-bbr-fq.conf <<CONF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
CONF
  sysctl --system >/dev/null || true
  echo "==> 当前参数："
  sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true
  sysctl -n net.core.default_qdisc 2>/dev/null || true
}

open_firewall_port() {
  [[ "${openfw:-0}" == "1" ]] || return 0
  echo "==> 尝试自动放行防火墙端口 TCP ${PORT}..."

  if command -v ufw >/dev/null 2>&1; then
    run_cmd ufw allow "${PORT}/tcp" >/dev/null 2>&1 || true
  fi

  if command -v firewall-cmd >/dev/null 2>&1; then
    if run_cmd firewall-cmd --state >/dev/null 2>&1; then
      run_cmd firewall-cmd --add-port="${PORT}/tcp" >/dev/null 2>&1 || true
      run_cmd firewall-cmd --permanent --add-port="${PORT}/tcp" >/dev/null 2>&1 || true
    fi
  fi

  if command -v iptables >/dev/null 2>&1; then
    if [[ "$DRY_RUN" == "1" ]]; then
      echo "[dry-run] iptables allow tcp dport ${PORT}"
    else
      iptables -C INPUT -p tcp --dport "${PORT}" -j ACCEPT 2>/dev/null \
        || iptables -I INPUT -p tcp --dport "${PORT}" -j ACCEPT 2>/dev/null || true
    fi
  fi

  echo "==> 完成（如使用云厂商安全组，还需在控制台放行）"
}

cmd_install() {
  is_root || die "请用 root 运行"
  need_cmd systemctl
  need_cmd ss

  install_deps
  install_xray
  stop_conflicts

  SNI="${reym:-$REYM_DEFAULT}"
  valid_sni "$SNI" || die "reym/SNI 看起来不合法：$SNI"
  FP="${fp:-$FP_DEFAULT}"

  gen_uuid
  choose_port
  gen_reality_keys

  SERVER_IP="$(get_public_ip)"
  write_config
  start_service
  open_firewall_port
  save_env

  if [[ "${bbr:-0}" == "1" ]]; then
    enable_bbr_fq
  fi

  echo
  echo "==> 安装完成，信息已保存：$ENV_FILE"
  [[ "$DRY_RUN" == "1" ]] || print_info
}

cmd_update() {
  is_root || die "请用 root 运行"
  need_cmd systemctl
  [[ -x "$XRAY_BIN" || "$DRY_RUN" == "1" ]] || die "未检测到已安装的 Xray，请先 install"

  echo "==> 更新 Xray 内核（不修改任何配置）..."
  install_xray

  echo "==> 重启 Xray 服务..."
  run_cmd systemctl restart "$SERVICE"

  echo
  echo "==> 更新完成（配置未变，客户端无需修改）"
  [[ "$DRY_RUN" == "1" ]] || systemctl --no-pager -l status "$SERVICE" | sed -n '1,12p'
}

cmd_check() {
  is_root || die "请用 root 运行"
  need_cmd systemctl
  need_cmd ss

  load_env

  echo "==> [1/6] systemd 状态"
  systemctl --no-pager -l status "$SERVICE" | sed -n '1,14p' || true
  echo

  echo "==> [2/6] 端口监听检查"
  if [[ -n "${PORT:-}" ]]; then
    ss -lntp 2>/dev/null | grep -E "[:.]${PORT}\b" || warn "未检测到 ${PORT} 监听（可能服务未起来或端口不一致）"
  else
    warn "ENV 中没有 PORT，无法检查监听。先运行：bash xray.sh"
  fi
  echo

  echo "==> [3/6] 配置自检（xray -test）"
  if [[ -x "$XRAY_BIN" && -f "$XRAY_CONF" ]]; then
    "$XRAY_BIN" run -test -config "$XRAY_CONF" >/dev/null && echo "OK: config test passed" || warn "config test failed"
  else
    warn "缺少 $XRAY_BIN 或 $XRAY_CONF，跳过"
  fi
  echo

  echo "==> [4/6] SNI 出站连通性（仅检查 TCP connect SNI:443）"
  if [[ -n "${SNI:-}" ]]; then
    timeout 4 bash -c "cat < /dev/null > /dev/tcp/${SNI}/443" 2>/dev/null \
      && echo "OK: TCP connect ${SNI}:443" || warn "FAIL: 无法 TCP connect ${SNI}:443（DNS/出站限制/被墙/代理问题）"
  else
    warn "ENV 中没有 SNI，跳过"
  fi
  echo

  echo "==> [5/6] 防火墙状态（只读）"
  if command -v ufw >/dev/null 2>&1; then
    echo "-- ufw --"
    ufw status 2>/dev/null || true
  else
    echo "-- ufw: not installed --"
  fi
  echo
  if command -v firewall-cmd >/dev/null 2>&1; then
    echo "-- firewalld --"
    firewall-cmd --state 2>/dev/null || true
    firewall-cmd --list-ports 2>/dev/null || true
  else
    echo "-- firewalld: not installed --"
  fi
  echo
  if command -v iptables >/dev/null 2>&1; then
    echo "-- iptables (filter INPUT excerpt) --"
    iptables -S INPUT 2>/dev/null | sed -n '1,60p' || true
  else
    echo "-- iptables: not installed --"
  fi
  echo

  echo "==> [6/6] 最近日志（200 行）"
  journalctl -u "$SERVICE" --no-pager -n 200 || true
  echo

  echo "==> 自检完成"
}

cmd_uninstall() {
  is_root || die "请用 root 运行"

  echo "==> 停止服务..."
  run_cmd systemctl stop "$SERVICE" 2>/dev/null || true
  run_cmd systemctl disable "$SERVICE" 2>/dev/null || true

  echo "==> 清理配置..."
  run_cmd rm -f "$XRAY_CONF" "$ENV_FILE"

  echo "==> 卸载 Xray..."
  # 同样走正确 raw 地址 + 可选 gh_proxy
  local RAW_URL="https://raw.githubusercontent.com/XTLS/Xray-install/main/install-release.sh"
  local URL="$(with_proxy_if_set "$RAW_URL")"
  local tmp="/tmp/xray-remove.$RANDOM.$RANDOM.sh"
  run_cmd rm -f "$tmp" 2>/dev/null || true

  echo "==> 拉取卸载脚本：$URL"
  if ! curl_fetch "$URL" "$tmp"; then
    warn "下载卸载脚本失败（可忽略）。你也可以手动删除：$XRAY_BIN 等文件"
    return 0
  fi

  if [[ "$DRY_RUN" == "1" ]]; then
    echo "[dry-run] bash '$tmp' remove"
    return 0
  fi

  bash "$tmp" remove >/dev/null 2>&1 || bash "$tmp" -s -- remove >/dev/null 2>&1 || true
  rm -f "$tmp" 2>/dev/null || true

  echo "==> 卸载完成"
}

usage() {
  echo "用法："
  echo "  bash xray.sh              # 一键安装/重装并输出信息"
  echo "  bash xray.sh install      # 同上"
  echo "  bash xray.sh update       # 仅更新 Xray 内核，不改配置"
  echo "  bash xray.sh info         # 输出节点信息"
  echo "  bash xray.sh status       # 查看服务状态"
  echo "  bash xray.sh log          # 查看最近200行日志"
  echo "  bash xray.sh check        # 自检（服务/端口/配置/日志/SNI/防火墙）"
  echo "  bbr=1 bash xray.sh        # 安装时顺便开启 BBR+fq"
  echo "  bash xray.sh bbr          # 单独开启 BBR+fq"
  echo "  bash xray.sh uninstall    # 卸载"
  echo
  echo "可选变量："
  echo "  reym=xxx vlpt=443 uuid=xxx fp=chrome openfw=1 bbr=1 bash xray.sh"
  echo "  gh_proxy=https://xxx/ bash xray.sh   # 可选：raw 加速/代理前缀"
  echo
  echo "Dry-run："
  echo "  bash xray.sh --dry-run install"
  echo "  dry=1 bash xray.sh install"
}

# -------- main --------

first="$(parse_dry_run_flag "${1:-}")"
if [[ "${1:-}" =~ ^(--dry-run|dry-run|-n)$ ]]; then
  shift || true
fi

case "${1:-}" in
  "" )        cmd_install ;;
  install)    cmd_install ;;
  update)     cmd_update ;;
  info)       print_info ;;
  status)     systemctl --no-pager -l status "$SERVICE" ;;
  log)        journalctl -u "$SERVICE" --no-pager -n 200 ;;
  check)      cmd_check ;;
  bbr)        is_root || die "请用 root 运行"; enable_bbr_fq ;;
  uninstall)  cmd_uninstall ;;
  *)
    usage
    ;;
esac
