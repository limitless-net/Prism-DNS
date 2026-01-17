# Prism-DNS (全能流媒体/AI 解锁部署工具)

> 专为 NodePass / V2bX 面板设计的 DNS 劫持与 SNI 反向代理一键部署工具。

![Language](https://img.shields.io/badge/Language-Bash-green.svg)
![Container](https://img.shields.io/badge/Container-Docker-blue.svg)
![Compatibility](https://img.shields.io/badge/SingBox-1.12%2B-orange.svg)
![License](https://img.shields.io/badge/License-MIT-yellow.svg)

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
bash <(curl -Ls https://raw.githubusercontent.com/[YOUR_GITHUB_USERNAME]/[YOUR_REPO_NAME]/main/install.sh)
