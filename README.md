# Xray Reality Vision 一键脚本

这是一个用于 **快速、稳定部署 Xray Reality Vision 节点** 的一键脚本，  
目标是提供一个 **长期可用、行为可预期、不折腾** 的基础部署方案。

项目面向的是 **自用与小规模运维场景**，而不是面板化、商业化或功能堆叠。  
设计重点放在 **稳定性、可维护性以及更新安全性** 上。

---

## 项目定位

这个脚本解决的不是“怎么装”，而是：

- 如何 **装完就能长期跑**
- 如何 **更新而不影响客户端**
- 如何 **出问题时能快速定位**
- 如何 **避免不可控的一键脚本行为**

因此，本项目遵循以下原则：

- 不引入面板或 Web UI
- 不做多协议混合
- 不隐藏关键行为
- 不进行破坏性自动修改

---

## 核心特性

- **VLESS + TCP + REALITY + Vision**（主流、稳定组合）
- **非交互式运行**：无菜单、无输入，避免 SSH / 编码 / 管道异常
- **参数可控**：端口 / UUID / SNI 通过环境变量指定
- **自动生成 Reality x25519 密钥**
- **NAT / 双栈 VPS 友好**：自动探测公网 IPv4 / IPv6
- **IPv4 + IPv6 双监听**
- **节点信息持久化**（本地 env 文件）
- `update`：仅更新 Xray 内核，不修改配置、不影响客户端
- `check`：快速自检（服务 / 端口 / 配置 / 日志 / SNI / 防火墙）
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

## 安装与运行

```bash
curl -O https://raw.githubusercontent.com/li210724/xray/main/xray.sh
chmod +x xray.sh
bash xray.sh
```

---

## 默认行为说明

直接运行脚本将会：

- 使用随机端口（20000–60000）
- 生成随机 UUID
- 使用默认 SNI：`www.tesla.com`
- 使用指纹：`chrome`

安装完成后会输出：

- VLESS 分享链接
- Clash Meta 配置片段

节点信息会保存到本地文件：

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

---

## 更新（不影响客户端）

```bash
bash xray.sh update
```

仅更新 Xray 内核，不修改配置文件、不更换端口或密钥，  
客户端无需重新导入。

---

## 自检与排错

```bash
bash xray.sh check
```

用于快速检查：

- 服务是否运行
- 端口是否监听
- 配置是否可加载
- SNI 出站是否正常
- 防火墙是否拦截

---

## 其他常用命令

```bash
bash xray.sh info      # 查看节点信息
bash xray.sh bbr       # 开启 BBR + fq
bash xray.sh uninstall # 完整卸载
```

---

## Dry-Run（只查看行为）

```bash
bash xray.sh --dry-run install
```

仅打印将执行的操作，不对系统做任何修改。

---

## 设计取向

- 稳定优先于功能数量
- 行为明确、结果可预期
- 更新不破客户端
- 适合长期运行与维护

如果你需要的是一个  
**“装完之后半年都不用管，只偶尔 update 的节点”**，  
这个项目正是为此而存在。

---

## License

MIT License  

仅供学习与技术研究，请遵守当地法律法规。
