# Xray Reality Vision 一键脚本（自用向 · 稳定优先）

一个 **稳定、克制、非交互式** 的 Xray 一键部署脚本，用于快速搭建  
**VLESS + TCP + REALITY + Vision** 节点。

本项目定位为 **长期自用 / 运维友好**，而不是“功能堆砌型一键脚本”。  
所有行为尽量 **可预测、可回滚、可更新而不影响客户端**。

---

## ✨ 特性一览

- ✅ **VLESS + TCP + REALITY + Vision**（当前主流、稳定组合）
- ✅ **非交互式脚本**：无菜单、无输入，避免 SSH / 编码 / `curl | bash` 问题
- ✅ **参数可控**：端口 / UUID / SNI 均可通过环境变量指定
- ✅ **自动生成 Reality x25519 密钥**
- ✅ **NAT / 双栈 VPS 友好**：自动探测公网 IPv4 / IPv6
- ✅ **IPv4 + IPv6 双监听**
- ✅ **节点信息持久化**（本地 env 文件）
- ✅ **update 更新模式**：只更新 Xray 内核，不改配置、不影响客户端
- ✅ **check 自检模式**：快速排查端口 / 防火墙 / SNI / 日志问题
- ✅ **可选自动放行防火墙端口**
  - ufw
  - firewalld
  - iptables
- ✅ **可选开启 BBR + fq**
- ✅ **完整卸载与清理**

> 本脚本**不包含**：  
> ❌ 面板  
> ❌ Web UI  
> ❌ 订阅系统  
> ❌ 多协议混合  
> ❌ 不可控的“魔法自动化”

---

## 📦 支持环境

- **系统**：Debian / Ubuntu（apt 系）
- **架构**：x86_64 / arm64
- **需要 root 权限**
- **systemd 环境**

---

## 📥 下载脚本

### 方法一：直接下载（推荐）

```bash
curl -O https://raw.githubusercontent.com/li210724/xray/blob/main/xray.sh
chmod +x xray.sh
```

### 方法二：Git Clone

```bash
git clone https://github.com/li210724/xray/blob/.git
cd 你的仓库名
chmod +x xray.sh
```

---

## 🚀 一键安装（默认）

```bash
bash xray.sh
```

默认行为：

- 随机端口（20000–60000）
- 随机 UUID
- 默认 SNI：`www.tesla.com`
- 指纹：`chrome`

安装完成后会直接输出：

- ✅ **VLESS 分享链接**
- ✅ **Clash Meta 配置片段**

并将节点信息保存到：

```text
/root/reality_vision.env
```

---

## ⚙️ 自定义安装参数（非交互）

通过 **环境变量** 控制：

```bash
reym=www.tesla.com \
vlpt=443 \
uuid=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx \
fp=chrome \
openfw=1 \
bbr=1 \
bash xray.sh
```

参数说明：

| 参数 | 说明 |
|----|----|
| `reym` | Reality SNI / 伪装域名 |
| `vlpt` | 监听端口（留空则随机） |
| `uuid` | VLESS UUID（留空则随机） |
| `fp` | 指纹（默认 `chrome`） |
| `openfw=1` | 自动尝试放行防火墙端口 |
| `bbr=1` | 安装时开启 BBR + fq |

> ⚠️ 注意：云厂商 **安全组** 仍需手动放行端口。

---

## 🔄 更新 Xray 内核（不改配置）

```bash
bash xray.sh update
```

- 仅更新 **Xray Core**
- **不会修改** `config.json`
- **不会更换** 端口 / UUID / Reality 密钥
- 客户端 **无需任何改动**

👉 适合长期运行的 VPS 定期维护。

---

## 🔍 自检与排错

```bash
bash xray.sh check
```

自检内容包括：

1. systemd 服务状态  
2. 端口是否监听  
3. Xray 配置自检（`xray -test`）  
4. SNI 出站 TCP 连通性  
5. 防火墙状态（只读）  
6. 最近 200 行日志  

适合排查：

- 安装成功但无法连接
- NAT / 防火墙 / 端口问题
- Reality SNI 不通

---

## ℹ️ 查看节点信息

```bash
bash xray.sh info
```

会从本地读取：

```text
/root/reality_vision.env
```

可随时重新输出分享链接和 Clash Meta 配置。

---

## 📈 单独开启 BBR + fq

```bash
bash xray.sh bbr
```

仅修改内核参数，不影响 Xray 配置。

---

## 🧪 Dry-Run（只看行为，不改系统）

```bash
bash xray.sh --dry-run install
```

或：

```bash
dry=1 bash xray.sh install
```

仅打印将执行的操作，**不会修改系统**，适合先审脚本。

---

## 🗑️ 卸载

```bash
bash xray.sh uninstall
```

卸载过程包括：

- 停止并禁用 Xray 服务
- 删除配置与节点信息
- 调用官方脚本卸载 Xray Core

---

## 📌 设计理念

- **稳定优先于功能数量**
- **明确可控优先于“自动魔法”**
- **更新不破客户端**
- **脚本行为应当可读、可预期**

如果你想要的是一个：

> **今天装好，半年后 update 也不怕翻车的脚本**

那这份脚本正是为此而写。

---

## 📄 License

MIT License  

仅供学习与技术研究，请遵守当地法律法规。
