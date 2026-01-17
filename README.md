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
- **多模式选择**：支持仅解锁 AI、仅解锁流媒体、仅解锁 TikTok 或 **超级全家桶**模式。
- **智能双栈检测**：自动识别 IPv4/IPv6，优先推荐最稳定的 IPv4 链路。
- **渐进式反馈**：分步骤显示安装进度，配合加载动画，提升用户体验。
- **自动审计集成**：生成的配置文件自动集成 BT、轮子、回国流量屏蔽等审计规则，保障落地机安全。
- **新版核心兼容**：完美适配 **Sing-box 1.12+** (移除已废弃的 geosite，全量使用 domain_suffix)。
- **安全白名单**：交互式配置防火墙，仅允许你指定的客户端连接，防止被白嫖或扫描。
- **一键生成配置**：脚本运行结束直接输出 V2bX/NodePass 可用的 JSON 代码，复制粘贴即用。

## 🆕 最近更新

### v4.1 - 2026年1月 连接稳定性优化

此版本基于用户反馈优化了配置，显著改善了连接稳定性：

- **简化路由逻辑**：将解锁域名的路由目标从 `unlock` 改回 `direct`，移除了可能导致循环解析的 `unlock` 出站配置
- **启用全局 DNS 缓存禁用**：设置 `dns.disable_cache: true`，确保始终获取最新的 DNS 响应，避免缓存导致的连接问题
- **优化日志级别**：将日志级别从 `warning` 改为 `info`，便于调试和问题排查
- **保留 DNS 劫持机制**：继续使用 DNS 劫持将解锁域名指向解锁机，但流量直接通过 `direct` 出站，避免双重域名解析

> **工作原理**：DNS 查询被劫持到解锁机（返回解锁机 IP）→ 流量通过 `direct` 出站直接到达解锁机 IP → SNI 代理转发到实际目的地
>
> **对现有用户的影响**：如果你在 v4.0 遇到连接不稳定或断流问题，请重新运行脚本并更新配置。新配置更简单、更稳定。

### v4.0 - 2026年1月 修复连接断流问题

此版本修复了 v3.9 引入的连接不稳定问题，恢复了正确的解锁流量路由：

- **恢复 unlock 出站**：重新添加 `unlock` 出站配置，使用 `domain_resolver` 指向 `unlock_dns`，确保解锁域名的流量通过解锁机 DNS 解析
- **修复路由规则**：将解锁域名的路由目标从 `direct` 改回 `unlock`，确保解锁流量正确路由到解锁机
- **保持 v3.9 优化**：保留了 `log`、`inbounds`、`protocol: bittorrent` 屏蔽、`domain_suffix` 审计规则等改进

> **对现有用户的影响**：如果你在 v3.9 版本遇到连接断流问题（连接时间不到几十秒），请重新运行脚本并更新配置。
>
> **技术说明**：v3.9 移除了 `unlock` 出站并将解锁域名路由到 `direct`，导致解锁流量无法正确通过解锁机 DNS 进行域名解析。v4.0 恢复了正确的流量路由：解锁域名 → `unlock` 出站 → 使用 `unlock_dns` 解析 → 解锁机 IP。

### v3.9 - 2026年1月 完美配置集成（稳定性+解锁功能优化）

此版本集成了经过优化的"完美"配置，既不断流还能解锁。主要改进包括：

- **新增日志配置**：添加 `log` 部分，使用 warning 级别和时间戳，方便调试
- **新增 inbounds 配置**：添加 `type: direct` 入站，确保流量正确进入
- **替换 domain_regex 为 domain_suffix**：复杂的正则表达式匹配会导致连接不稳定和性能问题，现在使用更高效的 `domain_suffix` 规则
- **增强审计规则**：添加中国大陆域名屏蔽列表，阻止回国流量
- **协议屏蔽增强**：新增 `protocol: bittorrent` 屏蔽规则，更精确地阻止 BT 流量
- **简化配置结构**：移除 `experimental` 部分和未使用的 outbound，减少潜在的兼容性问题
- **性能提升**：`domain_suffix` 匹配速度比正则表达式快 10-100 倍

> **对机场用户的影响**：此更新**不会影响**用户流量限制、设备数量限制和到期时间。这些限制由 V2bX/NodePass 面板数据库控制，不受节点配置文件影响。
>
> **为什么不影响限制功能**：用户流量、设备数量和到期时间是由面板后端管理的，与此配置文件是分离的两个层面。配置文件只控制流量的路由规则，不涉及用户认证和限制逻辑。

### v3.8 - 2026年1月 Sing-box 1.12+ 配置兼容性修复

修复了使用 V2bX + Sing-box 1.12+ 后端时节点连接超时的问题。主要改进包括：

- **DNS 服务器配置完善**：为 `unlock_dns` 添加 `address_resolver` 和 `detour` 配置，确保 Sing-box 能正确解析解锁机 DNS 地址
- **本地 DNS 解析器**：新增 `local_dns` 服务器作为地址解析器，解决 DNS 服务器地址解析的循环依赖问题
- **DNS 缓存控制**：为解锁域名的 DNS 规则添加 `disable_cache: true`，确保获取最新的 DNS 响应
- **协议路由规则**：添加 `protocol: dns` 和 `protocol: quic` 路由规则，确保 DNS 流量正确转发、QUIC 协议被阻断
- **解锁机 IP 直连**：添加解锁机 IP 的 CIDR 规则，确保到解锁机的流量走直连
- **接口自动检测**：添加 `auto_detect_interface: false` 配置，提高配置兼容性
- **简化出站配置**：移除冗余的 `domain_resolver` 配置，使配置更简洁可靠

> **对现有用户的影响**：如果你之前遇到配置后节点连接超时的问题，请重新运行脚本并更新配置。新配置与 V2bX + Sing-box 1.12+ 完全兼容。

### v3.7 - 2026年1月 新增卸载功能

新增一键卸载功能，方便用户在配置错误或不再需要时快速清理服务：

- **卸载选项**：脚本启动时可选择安装或卸载服务
- **智能检测**：自动识别部署模式（Docker 或原生），执行对应的卸载流程
- **完整清理**：自动停止服务、删除容器/镜像（Docker模式）、移除配置文件
- **安全恢复**：原生模式下会恢复原始 dnsmasq 配置（如果存在备份）
- **保留系统包**：卸载后保留 dnsmasq/sniproxy 包，避免影响其他服务

> **使用方法**：重新运行安装脚本，在主菜单选择 "2. 卸载解锁服务" 选项。

### v3.6 - 2026年1月 完整域名列表 & 路由规则修复

修复了解锁无法生效的问题。确保 DNS 配置和路由规则中的域名列表完全一致：

- **补全域名列表**：修复了 DNS 配置 (dnsmasq) 和 JSON 配置中域名列表不匹配的问题
  - ChatGPT：新增 `identrust.com`, `challenges.cloudflare.com`, `intercom.io`, `intercomcdn.com`, `featuregates.org`, `statsigapi.net`, `stripe.com`
  - 流媒体：新增 `hbomax.com`, `onetrust.com`, `bamgrid.com`, `go.com`, `pscdn.co`, `scdn.co`
- **添加路由规则**：在 route rules 中添加 `domain_suffix` 规则，确保解锁域名的流量正确路由到 direct 出口
- **完整解锁链路**：DNS 规则 → 解锁机 DNS → 返回解锁机 IP → 路由规则匹配 → 直连到解锁机 → SNI 代理转发

> **对现有用户的影响**：如果你之前遇到解锁无法生效的问题，请重新运行脚本并更新配置。

### v3.5 - 2026年1月 DNS 路由配置修复

修复了流量显示落地机地区而非解锁机地区的问题。当解锁机在香港、落地机在日本时，流媒体/AI 服务会正确显示香港地区：

- **DNS 规则配置**：生成的 JSON 配置现在包含 DNS 规则，将目标域名的 DNS 查询路由到解锁机
- **解锁机 DNS 服务器**：新增 `unlock_dns` 服务器配置，指向解锁机 IP
- **域名分流**：选定的解锁域名通过解锁机 DNS 解析，其他域名使用 Cloudflare DNS
- **完整解锁链路**：DNS 查询 → 解锁机 dnsmasq → 返回解锁机 IP → SNI 代理转发

> **对现有用户的影响**：如果你之前遇到解锁后显示落地机地区而非解锁机地区的问题，请重新运行脚本并更新配置。

### v3.4 - 2026年1月 原生模式 & Docker 安装优化

针对低配 VPS 用户的重大改进，解决 Docker 安装失败问题：

- **新增原生模式**：直接在系统上安装 dnsmasq 和 sniproxy，无需 Docker，内存占用降低约 60%（~50MB vs ~150MB）
- **部署模式选择**：安装时可选择 Docker 模式（推荐）或原生模式（低资源）
- **Docker 安装验证**：安装 Docker 后会验证是否成功，失败时提供清晰的错误信息和解决建议
- **Docker Compose 兼容性**：同时支持 docker compose（v2）和 docker-compose（v1）

> **适用场景**：如果你的 VPS 内存较小（< 512MB）或 Docker 安装失败，建议选择原生模式。

### v3.3 - 2026年1月 Sing-box 1.12+ 兼容性修复

修复了使用 V2bX 后端节点时出现的连接超时问题。主要改进包括：

- **出站配置更新**：将 `domain_strategy` 改为 `domain_resolver`，适配 Sing-box 1.12+ 的新配置格式
- **DNS 配置简化**：简化 DNS 服务器配置，使用 Cloudflare DNS (1.1.1.1) 作为默认解析器
- **路由规则优化**：移除 `dns-out` 相关配置，使用更简洁的路由规则结构
- **网络协议明确**：在兜底路由规则中明确指定 `network: ["udp","tcp"]`，确保所有流量正确路由

> **对现有用户的影响**：如果你之前配置后节点能 ping 通但连接超时，请重新运行脚本并更新配置。

### v3.2 - 2026年1月 用户体验优化

在v3.1的基础上进行了重大的用户体验改进：

- **多语言支持**：脚本启动时可选择中文或英文界面，提升国际用户体验
- **端口冲突检测**：安装前自动检查端口 53、80、443 是否被占用，避免安装后服务无法启动
- **渐进式输出**：改进输出方式，使用分步骤的进度显示 [1/3]、[2/3]，而非一次性输出
- **视觉增强**：添加加载动画、清晰的分隔线和彩色进度提示，提升视觉体验
- **智能提示**：如发现端口冲突，会提示具体占用进程，帮助用户快速定位问题

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

6. **选择解锁模式**：
   - `1` ChatGPT 专用 (仅接管 OpenAI 流量)
   - `2` Gemini 专用 (含 Google 基础服务，防止登录验证失败)
   - `3` TikTok 专用 (独立解锁国际版抖音)
   - `4` 所有 AI (GPT + Gemini)
   - `5` 全流媒体 (Netflix + Disney + TikTok + Spotify)
   - `6` 超级全家桶 (上述所有功能合集，**推荐**)

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
