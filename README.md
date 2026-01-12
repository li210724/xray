# xray.sh — VLESS TCP REALITY Vision 一键脚本

一个 **自用向、稳定优先** 的 Xray 一键脚本，用于快速部署  
**VLESS + TCP + REALITY + Vision** 节点。

脚本为 **非交互设计**，避免因终端、编码或 `curl | bash` 管道导致的异常，  
适合 VPS 初始化后一键部署并长期使用。

---

## 使用方式（所有命令都在这里）

```bash
# =========================
# 一键安装（默认配置）
# =========================
bash <(curl -fsSL https://raw.githubusercontent.com/li210724/xray/main/xray.sh)

# 默认行为：
# - SNI: www.tesla.com
# - 端口: 随机 (20000-60000)
# - UUID: 自动生成
# - Fingerprint: chrome


# =========================
# 一键安装（自定义参数）
# =========================
reym=www.tesla.com vlpt=443 uuid=xxxx fp=chrome bbr=1 \
bash <(curl -fsSL https://raw.githubusercontent.com/li210724/xray/main/xray.sh)

# 参数说明：
# reym   -> Reality 伪装域名 (SNI)
# vlpt   -> 指定端口（不填则随机）
# uuid   -> 指定 UUID（不填则自动生成）
# fp     -> 指纹（默认 chrome）
# bbr=1  -> 安装时同时开启 BBR + fq


# =========================
# 下载脚本后使用（可维护）
# =========================
curl -fsSL https://raw.githubusercontent.com/li210724/xray/main/xray.sh -o xray.sh
chmod +x xray.sh
bash xray.sh


# =========================
# 已安装后的常用命令
# =========================
bash xray.sh info        # 输出节点信息 / vless 链接 / Clash Meta 片段
bash xray.sh status      # 查看 Xray 服务状态
bash xray.sh log         # 查看最近 200 行日志
bash xray.sh bbr         # 单独开启 BBR + fq
bash xray.sh uninstall   # 卸载 Xray 并清理配置
