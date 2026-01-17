# Prism-DNS 脚本安全与性能分析报告

> 分析日期: 2026年1月17日  
> 分析版本: V3.2

---

## 📊 概述

本报告对 Prism-DNS 项目的 `install.sh` 和 `Dockerfile` 进行了全面的安全与性能分析。

---

## 🔴 发现的安全漏洞

### 1. **命令注入漏洞 (高危)**

**位置**: `install.sh` 第 461-477 行（防火墙配置部分）

**问题描述**: 用户输入的 IP 地址 (`$CLIENT_IPS`) 未经验证直接用于防火墙命令，可能导致命令注入攻击。

```bash
# 原代码 (有漏洞):
for ip in $CLIENT_IPS; do
    ufw allow from $ip to any port 53 > /dev/null 2>&1
    iptables -I INPUT -s $ip -p udp --dport 53 -j ACCEPT
done
```

**攻击示例**:
```
输入: 1.1.1.1; rm -rf /
```

**修复建议**: 添加 IP 地址格式验证

```bash
# 验证函数
validate_ip() {
    local ip=$1
    # IPv4 验证
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 0
    fi
    # IPv6 验证
    if [[ $ip =~ ^[0-9a-fA-F:]+$ ]]; then
        return 0
    fi
    return 1
}
```

---

### 2. **用户输入的 IP 地址未验证 (中危)**

**位置**: `install.sh` 第 211-214 行

**问题描述**: 手动输入的 IP 地址 (`$FINAL_IP`) 未经验证，可能包含恶意字符，被插入到配置文件和 JSON 输出中。

```bash
# 原代码:
read -p "请输入 IP 地址: " FINAL_IP
# 直接使用于配置文件生成
```

**风险**: 可能导致配置文件注入或格式错误。

**修复建议**: 添加输入验证

---

### 3. **临时文件竞态条件 (低危)**

**位置**: `install.sh` 第 163-175 行

**问题描述**: 使用固定路径的临时文件 (`/tmp/ipv4_result`, `/tmp/ipv6_result`)，可能被恶意程序利用。

```bash
# 原代码:
(curl -4s --max-time 5 ifconfig.me 2>/dev/null > /tmp/ipv4_result) &
```

**修复建议**: 使用 `mktemp` 创建安全的临时文件

```bash
local tmp_ipv4=$(mktemp)
local tmp_ipv6=$(mktemp)
```

---

### 4. **Docker 容器使用特权模式 (中危)**

**位置**: `install.sh` 第 422 行

**问题描述**: Docker 容器使用 `privileged: true` 和 `network_mode: host`，这赋予容器几乎完全的主机权限。

```yaml
privileged: true
network_mode: host
```

**风险**: 如果容器被攻破，攻击者可以完全控制主机系统。

**建议**: 评估是否真正需要特权模式，考虑使用更细粒度的权限控制。

---

### 5. **从远程下载执行脚本 (中危)**

**位置**: `install.sh` 第 233 行

**问题描述**: Docker 安装脚本通过管道直接执行，未验证完整性。

```bash
curl -fsSL https://get.docker.com | bash
```

**风险**: 如果 DNS 被污染或中间人攻击，可能执行恶意代码。

**建议**: 考虑验证脚本的 checksum 或 GPG 签名。

---

## 🟡 性能问题

### 1. **串行 IP 检测**

**位置**: `install.sh` 第 163-173 行

**问题描述**: IPv4 和 IPv6 检测是串行执行的，但实际上可以并行执行以节省时间。

**当前耗时**: 最多 10 秒 (5秒 IPv4 + 5秒 IPv6)

**优化建议**: 并行执行两个检测

```bash
# 优化后:
(curl -4s --max-time 5 ifconfig.me 2>/dev/null > "$tmp_ipv4") &
local pid_v4=$!
(curl -6s --max-time 5 ifconfig.co 2>/dev/null > "$tmp_ipv6") &
local pid_v6=$!
wait $pid_v4 $pid_v6  # 并行等待
```

---

### 2. **重复的字符串定义**

**位置**: `install.sh` 第 265-320 行

**问题描述**: 配置规则 (`CONF_*`) 和 JSON 列表 (`JSON_*`) 中的域名有大量重复定义，增加维护成本。

**建议**: 使用数组统一管理域名列表

```bash
GPT_DOMAINS=("openai.com" "chatgpt.com" "oaistatic.com")
```

---

### 3. **多次调用 Docker Compose**

**位置**: `install.sh` 第 427-433 行

**问题描述**: 先调用 `docker compose down`，再调用 `docker compose build`，再调用 `docker compose up -d`。

**优化建议**: 可以合并为单个命令

```bash
docker compose up -d --build --force-recreate
```

---

### 4. **Dockerfile 层优化**

**位置**: `Dockerfile`

**问题描述**: 可以进一步优化 Docker 镜像层，减少镜像大小。

**当前问题**:
- 多个 `RUN` 命令可以合并
- 可以使用 `--no-install-recommends` 减少依赖

---

## 🟢 已有的良好实践

1. ✅ **Root 权限检查**: 脚本开头验证 root 权限
2. ✅ **端口冲突检测**: 安装前检查必需端口
3. ✅ **错误处理**: 使用 `set -e` 在 Docker 启动脚本中
4. ✅ **信号处理**: Dockerfile 中的启动脚本正确处理 SIGTERM
5. ✅ **多语言支持**: 支持中英文界面
6. ✅ **用户确认**: 重要操作前要求用户确认

---

## 📋 修复清单

| 优先级 | 问题 | 状态 |
|--------|------|------|
| 🔴 高 | 命令注入漏洞 - IP 验证 | ✅ 已修复 |
| 🔴 高 | 用户输入 IP 验证 | ✅ 已修复 |
| 🟡 中 | 临时文件安全 | ✅ 已修复 |
| 🟡 中 | Docker 特权模式警告 | ⚠️ 功能需要 |
| 🟢 低 | 性能优化 - 并行 IP 检测 | ⬜ 可选优化 |

---

## 🛠️ 修复实施

以下安全问题已在代码中修复：

### 已修复的问题:

1. ✅ **添加 IP 地址验证函数 `validate_ip()`** 
   - 位置: 第 18-58 行
   - 功能: 验证 IPv4 和 IPv6 地址格式，防止命令注入攻击
   - 检查危险字符: `;`, `|`, `&`, `$`, `` ` ``, `(`, `)` 等

2. ✅ **使用安全的临时文件**
   - 位置: 第 203-204 行
   - 使用 `mktemp` 创建随机文件名，防止竞态条件攻击
   - 回退方案: 使用进程ID作为文件名后缀

3. ✅ **验证用户手动输入的 IP**
   - 位置: 第 262-266 行
   - 在用户选择手动输入 IP 后，调用 `validate_ip()` 验证

4. ✅ **验证防火墙白名单 IP**
   - 位置: 第 519-553 行
   - 验证每个客户端 IP，跳过无效输入
   - 使用数组存储有效 IP，使用引号包裹变量

### 安全改进详情:

```bash
# 新增的 IP 验证函数
validate_ip() {
    local ip="$1"
    
    # 检查空输入
    if [ -z "$ip" ]; then
        return 1
    fi
    
    # 只允许 IP 地址中的合法字符（数字、点、冒号、十六进制字母）
    case "$ip" in
        *[!.:0-9a-fA-F]*)
            return 1  # 包含非法字符
            ;;
    esac
    
    # IPv4 验证（包括八位字节范围检查，使用10#前缀避免八进制解析）
    if [[ "$ip" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]]; then
        for octet in "${BASH_REMATCH[@]:1}"; do
            if [ "$((10#$octet))" -gt 255 ]; then
                return 1
            fi
        done
        return 0
    fi
    
    # IPv6 验证（检查基本格式和双冒号规则）
    ...
}
```

---

*报告生成者: Prism-DNS 安全分析工具*
