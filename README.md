# Prism-DNS (全能流媒体/AI 解锁部署工具)

> 专为 NodePass / V2bX 面板设计的 DNS 劫持与 SNI 反向代理一键部署工具。

![Language](https://img.shields.io/badge/Language-Bash-green.svg) ![Container](https://img.shields.io/badge/Container-Docker-blue.svg) ![Compatibility](https://img.shields.io/badge/SingBox-1.12%2B-orange.svg) ![License](https://img.shields.io/badge/License-MIT-yellow.svg)

## 📖 简介

**Prism-DNS** 是一个轻量级的 Shell 脚本，旨在帮助机场管理员在 **原生解锁 VPS**（如 Akile HKLite、AWS SG、原生 IP 机器）上快速搭建私有解锁服务。

通过 `Dnsmasq` + `SNIProxy` 架构，配合智能的 **防火墙白名单机制**，它可以将你的 "小鸡"（入口/中转机）流量无感分流至 "母鸡"（解锁机），实现 **Netflix、Disney+、ChatGPT、Gemini、TikTok** 等服务的解锁。

## ✨ 核心特性

- **多模式选择**：支持仅解锁 AI、仅解锁流媒体、仅解锁 TikTok 或 **超级全家桶**模式。
- **智能双栈检测**：自动识别 IPv4/IPv6，优先推荐最稳定的 IPv4 链路。
- **自动审计集成**：生成的配置文件自动集成 BT、轮子、回国流量屏蔽等审计规则，保障落地机安全。
- **新版核心兼容**：完美适配 **Sing-box 1.12+** (移除已废弃的 geosite，全量使用 domain_suffix)。
- **安全白名单**：交互式配置防火墙，仅允许你指定的客户端连接，防止被白嫖或扫描。
- **一键生成配置**：脚本运行结束直接输出 V2bX/NodePass 可用的 JSON 代码，复制粘贴即用。

## 🚀 快速开始

请在你的 **解锁机 (能看奈飞/GPT的机器)** 上，以 `root` 身份执行以下命令：

```bash
bash <(curl -Ls https://raw.githubusercontent.com/limitless-net/Prism-DNS/main/install.sh)
```

> **注意**：请确保机器已安装 `curl`，若未安装可先执行 `apt update && apt install -y curl`

## ⚙️ 使用流程

1. **运行脚本**：执行上述一键命令。

2. **选择 IP**：脚本会自动检测公网 IP，建议选择 IPv4 以获得最佳兼容性。

3. **选择模式**：
   - `1` ChatGPT 专用 (仅接管 OpenAI 流量)
   - `2` Gemini 专用 (含 Google 基础服务，防止登录验证失败)
   - `3` TikTok 专用 (独立解锁国际版抖音)
   - `4` 所有 AI (GPT + Gemini)
   - `5` 全流媒体 (Netflix + Disney + TikTok + Spotify)
   - `6` 超级全家桶 (上述所有功能合集，**推荐**)

4. **安全授权**：输入你的 **入口/中转服务器 IP**（例如阿里云深圳、腾讯云广州的公网 IP）。脚本会自动配置防火墙放行规则。

5. **应用配置**：
   - 脚本运行结束后，会输出一段完整的 JSON 配置代码。
   - **全选复制** 这段黄色代码。
   - 登录 V2bX / NodePass 面板，找到对应节点的配置模版，清空原内容并粘贴。
   - **重启节点** 即可生效。

## 🛠️ 架构原理

```text
[ 用户客户端 ]
      |
      v
[ 需解锁的节点服务器 ]  <--- (V2bX / v2board / Xboard 等端点)
      |
      | (分流规则：domain_suffix)
      |
      +--- (普通流量) -----> [ 直连目标 ] (保持原线路速度，如 YouTube)
      |
      +--- (需解锁流量) ----> [ Prism-DNS 解锁机 ] -----> [ OpenAI / Netflix ]
                             (Docker SNIProxy)         (伪装为原生 IP)
```

## 📝 注意事项

- **端口占用**：本脚本需要占用解锁机的 `80`, `443`, `53` 端口。如果该机器同时运行了节点程序，请务必将节点端口改为 `8443`、`2053` 或其他非标准端口。
- **系统支持**：支持 Debian 10+, Ubuntu 20.04+, CentOS 7+。
- **防火墙**：脚本会自动配置 `ufw` 或 `iptables`。如果你使用的是 AWS、阿里云等有外部安全组的机器，请务必在云厂商控制台同步放行 `53/udp`, `53/tcp`, `80/tcp`, `443/tcp`。

## 🤝 贡献与反馈

如果您发现任何问题，欢迎提交 Issue 或 Pull Request。

**Star ⭐ 这个项目以支持开发！**
