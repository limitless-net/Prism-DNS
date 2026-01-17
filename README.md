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

## 🆕 最近更新

### v3.1 - 2026年1月 连接超时问题修复

修复了部分用户在应用脚本生成的配置后出现的连接超时问题。主要改进包括：

- **DNS 策略优化**：将 DNS 策略从 `ipv4_only` 改为 `prefer_ipv4`，提高兼容性
- **域名解析增强**：为 `direct` 出站添加 `domain_strategy` 配置，确保正常的域名解析
- **路由规则完善**：添加了最终的兜底路由规则，确保所有非屏蔽流量都能正常通过

> **对现有用户的影响**：如果你之前遇到过连接超时问题，请重新运行脚本并更新配置。新配置与原有配置完全兼容，可以直接覆盖使用。

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
- **地理位置**：解锁机和落地机【不需要】在同一地区。例如：解锁机在香港，落地机可以在日本、美国或任何其他地区。

## 🔍 故障排查

### 配置后无法上网

如果应用配置后发现无法访问任何网站，请按以下步骤排查：

> **✨ 最新版本已修复**：v3.1 版本已经修复了主要的连接超时问题。如果你使用的是旧版本，建议重新运行脚本获取最新配置。

1. **检查配置替换方式**
   - 确保你是【完全替换】了原有的 JSON 配置，而不是追加
   - V2bX/NodePass 配置框应该只包含脚本输出的 JSON，不要保留旧配置

2. **检查防火墙设置**
   - 在解锁机上确认已添加落地机 IP 到白名单
   - 检查云厂商安全组规则，确保以下端口对落地机 IP 开放：
     - `53/udp` - DNS 查询
     - `53/tcp` - DNS 查询 (TCP)
     - `80/tcp` - HTTP 代理
     - `443/tcp` - HTTPS 代理

3. **验证服务状态**
   ```bash
   # 在解锁机上执行
   docker ps                    # 确认容器正在运行
   docker logs dns_unlock       # 查看服务日志
   netstat -tuln | grep -E '(:53|:80|:443)'  # 确认端口监听
   ```

4. **测试 DNS 解析**
   ```bash
   # 从落地机测试（将 <解锁机IP> 替换为你的解锁机 IP 地址）
   nslookup openai.com <解锁机IP>
   # 应该返回解锁机的 IP 地址
   ```

5. **检查节点重启**
   - 修改配置后必须重启节点才能生效
   - 在 V2bX/NodePass 后台找到对应节点，点击重启

### 解锁不生效

如果可以上网但解锁不生效（如无法访问 Netflix、ChatGPT 等）：

1. **确认解锁机 IP 质量**
   - 在解锁机上直接测试目标服务
   - 例如：`curl -I https://www.netflix.com`
   - 确保解锁机本身能够访问这些服务

2. **检查 DNS 劫持**
   ```bash
   # 在落地机上测试（将 <解锁机IP> 替换为你的解锁机 IP 地址）
   nslookup netflix.com <解锁机IP>
   # 应该返回解锁机 IP，而不是 Netflix 真实 IP
   ```

3. **查看代理日志**
   ```bash
   # 在解锁机上查看实时流量
   docker logs -f dns_unlock
   # 访问目标服务时应该能看到连接日志
   ```

4. **验证选择的模式**
   - 确认你在脚本中选择的模式包含你想解锁的服务
   - 例如：只选择了 "ChatGPT 专用" 模式无法解锁 Netflix
   - 建议使用 "超级全家桶" 模式进行全面解锁

### 常见问题

**Q: 解锁机和落地机需要在同一地区吗？**
A: 不需要。解锁机需要在有原生 IP 的地区（如美国、香港等），落地机可以在任何地区。

**Q: 可以用多个落地机连接同一个解锁机吗？**
A: 可以。在配置防火墙白名单时，输入多个落地机 IP（空格分隔）即可。

**Q: 如何验证解锁是否正常工作？**
A: 
- 查看日志：`docker logs -f dns_unlock`
- DNS 测试：`nslookup openai.com <解锁机IP>`（替换为实际IP地址）
- 实际访问：连接落地节点后访问 Netflix、ChatGPT 等服务

**Q: 修改了解锁模式如何更新？**
A: 重新运行安装脚本，选择新的模式，然后更新落地机的配置并重启节点。

**Q: 可以在已有节点的机器上部署解锁服务吗？**
A: 可以，但需要将节点端口改为非标准端口（如 8443），因为解锁服务需要占用 80 和 443 端口。

## 🔧 管理命令

```bash
# 查看服务状态
docker ps

# 查看实时日志
docker logs -f dns_unlock

# 重启服务
cd /root/dns_unlock && docker compose restart

# 停止服务
cd /root/dns_unlock && docker compose down

# 重新部署（会保留现有配置）
cd /root/dns_unlock && docker compose up -d --build

# 完全重新安装
bash <(curl -Ls https://raw.githubusercontent.com/limitless-net/Prism-DNS/main/install.sh)
```

## 🤝 贡献与反馈

如果您发现任何问题，欢迎提交 Issue 或 Pull Request。

**Star ⭐ 这个项目以支持开发！**
