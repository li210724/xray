# Xray Reality Vision 一键脚本  
**自用向 · 稳定优先 · 可长期维护**

这是一个用于 **快速、稳定部署 Xray Reality Vision 节点** 的一键脚本，  
默认部署组合为 **VLESS + TCP + REALITY + Vision**。

项目目标不是“功能越多越好”，而是提供一个 **装完就能长期跑、更新不折腾、出问题好排查** 的基础部署方案，适合自用与小规模运维场景。

---

## 为什么做这个项目？

在实际使用中，很多“一键脚本”往往存在以下问题：

- 交互菜单复杂，行为不可预测  
- 自动修改系统较多，但缺乏透明度  
- 更新方式粗暴，导致端口 / 密钥变化，客户端需要重配  
- 出问题时缺乏自检手段，排错成本高  

本项目选择了一条更克制的路线：

- **非交互式**：默认一条命令完成部署  
- **显式可控**：关键参数通过环境变量指定  
- **更新安全**：更新内核不修改配置  
- **可维护**：提供自检命令，问题可快速定位  
- **可回滚**：支持完整卸载与清理  

---

## 项目定位与边界

这个项目只做一件事：  
👉 **部署一个稳定、可长期使用的 Reality Vision 节点**

### 包含的功能
- 一键安装 / 重装
- 节点信息输出与保存
- 更新 Xray 内核（不影响客户端）
- 自检与排错
- 可选防火墙端口放行
- 可选开启 BBR + fq

### 明确不包含
- 面板 / Web UI
- 订阅系统
- 多协议混合“全家桶”
- 不透明的系统级魔改

---

## 核心特性

- **VLESS + TCP + REALITY + Vision**（主流、稳定组合）
- **非交互式运行**：无菜单、无输入，减少环境差异导致的失败
- **参数可控**：端口 / UUID / SNI 通过环境变量指定
- **自动生成 Reality x25519 密钥**
- **NAT / 双栈 VPS 友好**：自动探测公网 IPv4 / IPv6
- **IPv4 + IPv6 双监听**
- **节点信息持久化**：保存到 `/root/reality_vision.env`
- `update`：仅更新 Xray Core，不修改配置、不影响客户端
- `check`：自检（服务 / 端口 / 配置 / 日志 / SNI / 防火墙）
- 可选：自动放行防火墙端口（ufw / firewalld / iptables）
- 可选：开启 BBR + fq
- 支持完整卸载与清理

---

## 适用环境

- Debian / Ubuntu（apt 系）
- x86_64 / arm64
- 需要 root 权限
- systemd

---

## 安装与运行（推荐）

```bash
curl -O https://raw.githubusercontent.com/li210724/xray/main/xray.sh
chmod +x xray.sh
bash xray.sh
```

> 如果你的网络访问 GitHub Raw 不稳定，可使用代理前缀（脚本支持）：  
> `gh_proxy=https://你的代理前缀/ bash xray.sh`

---

## 默认行为说明

直接运行脚本将会：

- 随机端口（20000–60000）
- 自动生成 UUID
- 默认 SNI：`www.tesla.com`
- 指纹：`chrome`

安装完成后会输出：

- **VLESS 分享链接**
- **Clash Meta 配置片段**

并将节点信息保存到本地文件：

```text
/root/reality_vision.env
```

---

## 自定义安装（非交互）

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
|---|---|
| `reym` | Reality SNI / 伪装域名 |
| `vlpt` | 监听端口（留空则随机） |
| `uuid` | VLESS UUID（留空则随机） |
| `fp` | 指纹（默认 `chrome`） |
| `openfw=1` | 自动尝试放行防火墙端口 |
| `bbr=1` | 安装时开启 BBR + fq |

> ⚠️ 注意：云厂商 **安全组** 仍需手动放行端口。

---

## 更新 Xray（不影响客户端）

```bash
bash xray.sh update
```

仅更新 Xray 内核，不修改配置、不更换端口或密钥，  
客户端无需重新导入。

---

## 自检与排错

```bash
bash xray.sh check
```

自检内容包括：

- 服务是否运行
- 端口是否监听
- 配置是否可加载
- SNI 出站是否正常
- 防火墙是否拦截
- 最近 200 行日志

---

## 常用命令速查

```bash
bash xray.sh info       # 查看节点信息
bash xray.sh status     # 查看服务状态
bash xray.sh log        # 查看最近 200 行日志
bash xray.sh bbr        # 开启 BBR + fq
bash xray.sh uninstall  # 完整卸载
```

---

## Dry-Run（仅查看行为）

```bash
bash xray.sh --dry-run install
```

仅打印将执行的操作，不对系统做任何修改，适合先审脚本。

---

## 常见问题（FAQ）

**Q：安装成功但连不上？**  
A：优先检查云厂商安全组是否放行端口，其次运行 `bash xray.sh check` 查看自检结果。

**Q：update 会不会导致客户端失效？**  
A：不会。`update` 仅更新 Xray Core，不修改任何节点参数。

**Q：支持 NAT VPS 吗？**  
A：支持，脚本会自动探测公网 IP（IPv4 / IPv6）。

**Q：脚本会不会乱改系统设置？**  
A：不会。除非你显式启用 `openfw=1` 或 `bbr=1`，否则不会修改防火墙或内核参数。

---

## 免责声明

本项目仅供学习与技术研究，请遵守当地法律法规。  
使用者需自行承担因配置、网络或合规问题带来的风险。

---

## License

MIT License
