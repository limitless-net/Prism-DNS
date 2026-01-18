# Prism-DNS (全能流媒体/AI 解锁部署工具)

> 专为 NodePass / V2bX 面板设计的 DNS 劫持与 SNI 反向代理一键部署工具。

![Language](https://img.shields.io/badge/Language-Bash-green.svg) ![Container](https://img.shields.io/badge/Container-Docker-blue.svg) ![Compatibility](https://img.shields.io/badge/SingBox-1.12%2B-orange.svg) ![License](https://img.shields.io/badge/License-MIT-yellow.svg)

## 📖 简介

**Prism-DNS** 是一个轻量级的 Shell 脚本，旨在帮助机场管理员在 **原生解锁 VPS**（如 Akile HKLite、AWS SG、原生 IP 机器）上快速搭建私有解锁服务。

通过 `Dnsmasq` + `SNIProxy` 架构，配合智能的 **防火墙白名单机制**，它可以将你的 "小鸡"（入口/中转机）流量无感分流至 "母鸡"（解锁机），实现 **Netflix、Disney+、ChatGPT、Gemini、TikTok** 等服务的解锁。

## ✨ 核心特性

- **双部署模式**：支持 Docker 模式（推荐）和原生模式（适合低配 VPS），灵活应对不同硬件环境。
- **多语言界面**：支持中文和英文，方便国际用户使用。
- **智能端口检测**：安装前自动检测端口冲突，提供清晰的错误提示和解决建议。
- **精细化服务选择**：支持单独选择每个服务（ChatGPT、Gemini、Netflix、Disney+ 等），避免不必要的域名导致断流。
- **多选支持**：可同时选择多个服务（如输入 `1,3,5` 选择 ChatGPT+Copilot+Netflix），灵活组合。
- **精简域名列表**：每个服务只保留核心必要域名，减少不相关流量被劫持导致的超时问题。
- **智能双栈检测**：自动识别 IPv4/IPv6，优先推荐最稳定的 IPv4 链路。
- **渐进式反馈**：分步骤显示安装进度，配合加载动画，提升用户体验。
- **自动审计集成**：生成的配置文件自动集成 BT、轮子、回国流量屏蔽等审计规则，保障落地机安全。
- **新版核心兼容**：完美适配 **Sing-box 1.12+** (移除已废弃的 geosite，全量使用 domain_suffix)。
- **安全白名单**：交互式配置防火墙，仅允许你指定的客户端连接，防止被白嫖或扫描。
- **一键生成配置**：脚本运行结束直接输出 V2bX/NodePass 可用的 JSON 代码，复制粘贴即用。

## 🆕 最近更新

### v5.0 - 2026年1月 精简版 - 精细化服务选择

此版本大幅精简脚本，解决用户反馈的"域名太多导致节点断流超时"问题：

**🔥 主要改进：**
- **精细化服务选择**：将原来的 6 个预设模式改为 10 个独立服务选择，用户可以精确选择需要解锁的服务
- **多选支持**：支持输入如 `1,3,5` 同时选择多个服务，或使用快捷键 `a`(所有AI)、`s`(所有流媒体)、`*`(全部)
- **精简域名列表**：每个服务只保留核心必要域名，大幅减少不必要的 DNS 劫持

**📋 可选服务列表：**
| # | 服务 | 核心域名数 | 说明 |
|---|------|-----------|------|
| 1 | ChatGPT | 5 | OpenAI 核心域名 |
| 2 | Gemini | 7 | Google AI 核心域名（不含 Google 全家桶） |
| 3 | Copilot | 4 | Microsoft Copilot |
| 4 | Claude | 2 | Anthropic Claude |
| 5 | Netflix | 5 | Netflix 核心域名 |
| 6 | Disney+ | 4 | Disney+ 核心域名 |
| 7 | TikTok | 4 | TikTok 核心域名 |
| 8 | YouTube | 4 | YouTube 核心域名 |
| 9 | Spotify | 3 | Spotify 核心域名 |
| 10 | HBO Max | 3 | HBO/Max 核心域名 |


## 🚀 快速开始

请在你的 **解锁机 (能看奈飞/GPT的机器)** 上，以 `root` 身份执行以下命令：

```bash
bash <(curl -Ls https://raw.githubusercontent.com/limitless-net/Prism-DNS/main/install.sh)
```

> **注意**：请确保机器已安装 `curl`，若未安装可先执行 `apt update && apt install -y curl`

### 独立配置模板（仅审计规则）

如果你只需要审计规则配置（屏蔽 BT/P2P、回国流量等），无需解锁功能，可以直接使用项目中的 [`v2bx_config_template.json`](./v2bx_config_template.json) 文件：

```bash
# 下载模板文件
curl -O https://raw.githubusercontent.com/limitless-net/Prism-DNS/main/v2bx_config_template.json

# 查看内容
cat v2bx_config_template.json
```

此模板仅包含审计规则（屏蔽 BT、回国流量等），**不包含解锁功能**。如需解锁 Netflix/ChatGPT 等服务，请运行安装脚本生成完整配置。

## ⚙️ 使用流程

1. **运行脚本**：执行上述一键命令。

2. **选择语言**：首次运行时可选择中文或英文界面。

3. **端口检查**：脚本会自动检查必需端口（53、80、443）是否可用，如有冲突会提示。

4. **选择 IP**：脚本会自动检测公网 IP，建议选择 IPv4 以获得最佳兼容性。

5. **选择部署模式**：
   - `1` Docker 模式 (推荐) - 容器隔离，便于管理
   - `2` 原生模式 (低资源) - 直接安装 dnsmasq + sniproxy，内存占用更低（~50MB）

6. **选择解锁服务**（v5.0 新版多选）：
   - 输入数字选择服务，用逗号分隔，例如：`1,3,5`
   - **AI 服务**：`1` ChatGPT, `2` Gemini, `3` Copilot, `4` Claude
   - **流媒体**：`5` Netflix, `6` Disney+, `7` TikTok, `8` YouTube, `9` Spotify, `10` HBO Max
   - **快捷选项**：`a` 所有AI, `s` 所有流媒体, `*` 全部服务

7. **依赖安装**：根据选择的部署模式，脚本会自动安装 Docker 或原生依赖（dnsmasq + sniproxy）。

8. **安全授权**：输入你的 **入口/中转服务器 IP**（例如阿里云深圳、腾讯云广州的公网 IP）。脚本会自动配置防火墙放行规则。

9. **服务验证**：脚本会逐步验证服务状态、端口监听情况和 DNS 解析功能。

10. **应用配置**：
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

- **端口占用**：本脚本需要占用解锁机的 `80`, `443`, `53` 端口。脚本会在安装前自动检测端口是否被占用，如发现冲突会提示处理建议。如果该机器同时运行了节点程序，请务必将节点端口改为 `8443`、`2053` 或其他非标准端口。
- **系统支持**：支持 Debian 10+, Ubuntu 20.04+, CentOS 7+。
- **防火墙**：脚本会自动配置 `ufw` 或 `iptables`。如果你使用的是 AWS、阿里云等有外部安全组的机器，请务必在云厂商控制台同步放行 `53/udp`, `53/tcp`, `80/tcp`, `443/tcp`。
- **地理位置**：解锁机和落地机【不需要】在同一地区。例如：解锁机在香港，落地机可以在日本、美国或任何其他地区。
- **低配 VPS**：如果 VPS 内存小于 512MB，建议选择**原生模式**，内存占用仅约 50MB。

## 🔍 故障排查

### Docker 安装失败

> **✨ v3.4 新增功能**：脚本现在会在 Docker 安装后进行验证，失败时会给出明确提示。

如果看到 `docker: command not found` 错误：

1. **选择原生模式**：重新运行脚本，选择"原生模式（低资源）"，无需 Docker
   ```bash
   bash <(curl -Ls https://raw.githubusercontent.com/limitless-net/Prism-DNS/main/install.sh)
   # 在部署模式选择时输入 2
   ```

2. **手动安装 Docker**（可选）：
   ```bash
   # 查看安装日志
   cat /tmp/docker_install.log
   
   # 手动安装 Docker
   curl -fsSL https://get.docker.com | bash
   
   # 启动 Docker 服务
   systemctl enable docker
   systemctl start docker
   ```

3. **检查系统资源**：
   ```bash
   # 检查可用内存
   free -m
   
   # 检查磁盘空间
   df -h
   ```

### 端口冲突问题

> **✨ v3.2 新增功能**：脚本现在会在安装前自动检测端口冲突，并提供详细的进程信息。

如果脚本提示端口被占用：

1. **查看占用端口的进程**
   ```bash
   # 检查端口 53
   lsof -i :53
   # 检查端口 80
   lsof -i :80
   # 检查端口 443
   lsof -i :443
   ```

2. **处理端口冲突**
   - 如果是节点程序占用：修改节点配置，将端口改为 8443、2053 等非标准端口
   - 如果是 systemd-resolved 占用 53 端口（Ubuntu 常见）：
     ```bash
     systemctl disable systemd-resolved
     systemctl stop systemd-resolved
     rm /etc/resolv.conf
     echo "nameserver 8.8.8.8" > /etc/resolv.conf
     ```
   - 如果是其他服务：根据实际情况停止或重新配置该服务

3. **重新运行脚本**
   ```bash
   bash <(curl -Ls https://raw.githubusercontent.com/limitless-net/Prism-DNS/main/install.sh)
   ```

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

**Q: Docker 模式和原生模式有什么区别？**
A: 
- Docker 模式：服务运行在容器中，隔离性好，便于管理，但内存占用稍高（约 150MB）
- 原生模式：服务直接运行在系统上，内存占用低（约 50MB），适合低配 VPS

**Q: 如何卸载 Prism-DNS 服务？**
A: 重新运行安装脚本，在主菜单选择 "2. 卸载解锁服务" 选项：
```bash
bash <(curl -Ls https://raw.githubusercontent.com/limitless-net/Prism-DNS/main/install.sh)
```
卸载程序会自动检测部署模式（Docker 或原生）并完全清理所有组件。

## 🔧 管理命令

### 卸载服务

```bash
# 运行安装脚本并选择卸载选项
bash <(curl -Ls https://raw.githubusercontent.com/limitless-net/Prism-DNS/main/install.sh)
# 然后选择: 2. 卸载解锁服务

# 卸载程序会自动：
# - 停止并删除 Docker 容器和镜像（Docker 模式）
# - 停止并禁用 systemd 服务（原生模式）
# - 删除所有配置文件
# - 恢复原始 dnsmasq 配置（如果存在备份）
```

### Docker 模式

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

### 原生模式

```bash
# 查看服务状态
systemctl status dnsmasq sniproxy

# 查看实时日志
journalctl -u dnsmasq -u sniproxy -f

# 重启服务
systemctl restart dnsmasq sniproxy

# 停止服务
systemctl stop dnsmasq sniproxy

# 完全重新安装
bash <(curl -Ls https://raw.githubusercontent.com/limitless-net/Prism-DNS/main/install.sh)
```

## 🤝 贡献与反馈

如果您发现任何问题，欢迎提交 Issue 或 Pull Request。

**Star ⭐ 这个项目以支持开发！**
