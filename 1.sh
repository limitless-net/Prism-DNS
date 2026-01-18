#!/bin/bash
# ==========================================================
#   V2bX 专用解锁服务搭建脚本 (V6.0 完美整合版)
#   特性：
#   1. 零依赖：内嵌 Dockerfile/Config，不依赖 GitHub 下载
#   2. 防自锁：防火墙配置强制放行 SSH
#   3. 双模式：支持 Docker (推荐) 和 原生模式 (省内存)
#   4. 完美JSON：自动生成含审计规则的 V2bX 后端配置
# ==========================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
SKY='\033[0;36m'
NC='\033[0m'
WORK_DIR="/root/dns_unlock"

# 默认语言 (可改为 en)
LANG_CHOICE="zh"

# ==========================================================
# 基础工具函数
# ==========================================================

validate_ip() {
    local ip="$1"
    ip=$(echo "$ip" | tr -d '[:space:]')
    [ -z "$ip" ] && return 1
    case "$ip" in *[!.:0-9a-fA-F]*) return 1;; esac
    
    # IPv4
    if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        IFS='.' read -ra octets <<< "$ip"
        for octet in "${octets[@]}"; do
            if [ "$octet" -gt 255 ]; then return 1; fi
        done
        return 0
    fi
    # IPv6 (简单校验)
    if [[ "$ip" =~ ^[0-9a-fA-F:]+$ ]] && [[ "$ip" == *:* ]]; then
        return 0
    fi
    return 1
}

spinner() {
    local pid=$1
    local msg=$2
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    while kill -0 $pid 2>/dev/null; do
        i=$(( (i+1) %10 ))
        printf "\r%s%s %s%s" "${YELLOW}" "${spin:$i:1}" "${msg}" "${NC}"
        sleep 0.1
    done
    printf "\r\033[K"
}

# ==========================================================
# 核心逻辑
# ==========================================================

# 1. 检查 Root
if [ "$(id -u)" != "0" ]; then
    echo -e "${RED}错误: 必须使用 root 权限运行此脚本${NC}"
    exit 1
fi

# 2. 检查端口
check_port_availability() {
    echo -e "\n${SKY}═══════════════════════════════════════════════${NC}"
    echo -e "${SKY}  检查端口占用情况${NC}"
    echo -e "${SKY}═══════════════════════════════════════════════${NC}\n"
    
    local ports=(53 80 443)
    local port_conflict=false
    
    for port in "${ports[@]}"; do
        if command -v ss &> /dev/null; then
            if ss -tuln | grep -q ":${port} "; then port_conflict=true; fi
        else
            if netstat -tuln | grep -q ":${port} "; then port_conflict=true; fi
        fi
        
        if [ "$port_conflict" = true ] && [[ "$port" == "53" || "$port" == "80" || "$port" == "443" ]]; then
             # 重置标志，单独判断
             :
        fi
    done
    
    # 再次详细检查并输出
    local has_err=0
    for port in "${ports[@]}"; do
        if ss -tuln 2>/dev/null | grep -q ":${port} " || netstat -tuln 2>/dev/null | grep -q ":${port} "; then
            echo -e "${RED}✗ 端口 $port 已被占用${NC}"
            has_err=1
        else
            echo -e "${GREEN}✓ 端口 $port 可用${NC}"
        fi
    done

    if [ $has_err -eq 1 ]; then
        echo -e "\n${YELLOW}警告: 必需端口被占用。如果是旧的解锁服务，脚本会自动尝试停止它们。${NC}"
        echo -e "${YELLOW}如果是 Nginx/Apache/Systemd-resolved，请手动停止。${NC}"
        read -p "是否强制继续? [y/N]: " cont
        if [[ ! "$cont" =~ ^[Yy]$ ]]; then exit 1; fi
    fi
}

# 3. IP 选择
select_public_ip() {
    clear
    echo -e "${SKY}═══════════════════════════════════════════════${NC}"
    echo -e "${SKY}  检测本机 IP${NC}"
    echo -e "${SKY}═══════════════════════════════════════════════${NC}\n"
    
    IPV4=$(curl -4s --max-time 3 api.ip.sb/ip || curl -4s --max-time 3 ifconfig.me)
    IPV6=$(curl -6s --max-time 3 api.ip.sb/ip || curl -6s --max-time 3 ifconfig.co)

    echo -e "1. IPv4: ${GREEN}${IPV4:-未检测到}${NC}"
    echo -e "2. IPv6: ${GREEN}${IPV6:-未检测到}${NC}"
    echo "3. 手动输入"
    
    read -p "请选择解锁服务使用的 IP [1-3] (默认1): " IP_CHOICE
    case $IP_CHOICE in
        2) FINAL_IP="$IPV6" ;;
        3) read -p "输入 IP: " FINAL_IP ;;
        *) FINAL_IP="$IPV4" ;;
    esac
    
    if [ -z "$FINAL_IP" ]; then
        echo -e "${RED}错误：无效的 IP${NC}"
        exit 1
    fi
    echo -e "已选择: ${YELLOW}$FINAL_IP${NC}"
}

# 4. 部署模式选择
select_deploy_mode() {
    echo -e "\n${SKY}═══════════════════════════════════════════════${NC}"
    echo -e "${SKY}  选择部署模式${NC}"
    echo -e "${SKY}═══════════════════════════════════════════════${NC}\n"
    echo "1. Docker 模式 (推荐，环境隔离，稳定)"
    echo "2. 原生模式 (直接安装，省内存，适合 < 512MB 机器)"
    read -p "输入选项 [1-2] (默认1): " mode_input
    
    if [ "$mode_input" = "2" ]; then
        DEPLOY_MODE="native"
    else
        DEPLOY_MODE="docker"
    fi
}

# 5. 安装 Docker (如果是 Docker 模式)
install_docker_env() {
    if ! command -v docker &> /dev/null; then
        echo -e "${YELLOW}正在安装 Docker...${NC}"
        curl -fsSL https://get.docker.com | bash
        systemctl enable docker --now
    fi
    # 检查 Compose
    if ! docker compose version &> /dev/null; then
        apt-get update && apt-get install -y docker-compose-plugin
    fi
}

# 6. 原生安装依赖
install_native_env() {
    echo -e "${YELLOW}正在安装 Dnsmasq 和 Sniproxy...${NC}"
    apt-get update
    apt-get install -y dnsmasq sniproxy
    systemctl stop dnsmasq sniproxy systemd-resolved 2>/dev/null || true
}

# ==========================================================
# 服务配置生成 (关键部分：内嵌文件)
# ==========================================================

deploy_service() {
    # 选择服务
    echo -e "\n${SKY}═══════════════════════════════════════════════${NC}"
    echo -e "${SKY}  选择需要解锁的服务${NC}"
    echo -e "${SKY}═══════════════════════════════════════════════${NC}\n"
    echo "1. ChatGPT + AI (OpenAI/Gemini/Copilot)"
    echo "2. Netflix"
    echo "3. Disney+"
    echo "4. TikTok"
    echo "5. YouTube"
    echo "6. Spotify/HBO/Prime"
    echo "a. 全选 (推荐)"
    echo ""
    read -p "输入数字(逗号分隔) 或 a: " svc_in
    
    if [[ "$svc_in" == "a" || "$svc_in" == "A" ]]; then
        svc_in="1,2,3,4,5,6"
    fi

    # 准备工作目录
    mkdir -p "$WORK_DIR"
    cd "$WORK_DIR"
    
    # === 生成 dnsmasq 规则 ===
    echo "# Generated by Unlock Script" > dnsmasq_rules.conf
    
    FINAL_JSON_LIST=""
    TYPE_NAME=""
    
    # 辅助函数：添加规则
    add_rule() {
        local domain="$1"
        echo "address=/$domain/$FINAL_IP" >> dnsmasq_rules.conf
        if [ -n "$FINAL_JSON_LIST" ]; then FINAL_JSON_LIST="$FINAL_JSON_LIST, "; fi
        FINAL_JSON_LIST="${FINAL_JSON_LIST}\"$domain\""
    }

    # 1. AI
    if [[ $svc_in == *"1"* ]]; then
        for d in openai.com chatgpt.com oaistatic.com oaiusercontent.com ai.com gemini.google.com bard.google.com copilot.microsoft.com bing.com anthropic.com claude.ai; do add_rule $d; done
        TYPE_NAME="${TYPE_NAME}AI "
    fi
    # 2. Netflix
    if [[ $svc_in == *"2"* ]]; then
        for d in netflix.com netflix.net nflxvideo.net nflximg.net nflxext.com nflxso.net; do add_rule $d; done
        TYPE_NAME="${TYPE_NAME}Netflix "
    fi
    # 3. Disney
    if [[ $svc_in == *"3"* ]]; then
        for d in disney.com disneyplus.com dssott.com bamgrid.com; do add_rule $d; done
        TYPE_NAME="${TYPE_NAME}Disney "
    fi
    # 4. TikTok
    if [[ $svc_in == *"4"* ]]; then
        for d in tiktok.com tiktokv.com tiktokcdn.com musical.ly; do add_rule $d; done
        TYPE_NAME="${TYPE_NAME}TikTok "
    fi
    # 5. YouTube
    if [[ $svc_in == *"5"* ]]; then
        for d in youtube.com googlevideo.com ytimg.com ggpht.com; do add_rule $d; done
        TYPE_NAME="${TYPE_NAME}YouTube "
    fi
    # 6. Others
    if [[ $svc_in == *"6"* ]]; then
        for d in spotify.com hbomax.com hbo.com max.com amazonvideo.com primevideo.com; do add_rule $d; done
        TYPE_NAME="${TYPE_NAME}Others "
    fi
    
    if [ -z "$TYPE_NAME" ]; then TYPE_NAME="Custom"; fi

    # === 生成 sniproxy.conf (内嵌) ===
    cat > sniproxy.conf <<EOF
user daemon
pidfile /var/run/sniproxy.pid

error_log {
    filename /dev/stderr
    priority notice
}
access_log {
    filename /dev/stdout
}

listen 80 {
    proto http
    table http_hosts
}
listen 443 {
    proto tls
    table https_hosts
}

table http_hosts {
    .* *
}
table https_hosts {
    .* *
}
EOF

    # === 部署逻辑 ===
    if [ "$DEPLOY_MODE" = "docker" ]; then
        echo -e "${YELLOW}正在构建 Docker 环境 (零依赖模式)...${NC}"
        install_docker_env
        
        # 生成 Dockerfile (内嵌 Alpine 镜像)
        cat > Dockerfile <<EOF
FROM alpine:latest
RUN apk add --no-cache dnsmasq sniproxy
# 准备启动脚本
RUN echo '#!/bin/sh' > /entrypoint.sh && \\
    echo 'dnsmasq --no-daemon --conf-file=/etc/dnsmasq.conf &' >> /entrypoint.sh && \\
    echo 'sniproxy -c /etc/sniproxy.conf -f' >> /entrypoint.sh && \\
    chmod +x /entrypoint.sh
# 默认配置
RUN echo 'port=53' > /etc/dnsmasq.conf && \\
    echo 'no-resolv' >> /etc/dnsmasq.conf && \\
    echo 'server=8.8.8.8' >> /etc/dnsmasq.conf && \\
    echo 'conf-dir=/etc/dnsmasq.d/,*.conf' >> /etc/dnsmasq.conf && \\
    echo 'cache-size=1000' >> /etc/dnsmasq.conf
ENTRYPOINT ["/entrypoint.sh"]
EOF

        # 生成 docker-compose.yml
        cat > docker-compose.yml <<EOF
services:
  unlock:
    build: .
    container_name: dns_unlock
    restart: always
    network_mode: host
    privileged: true
    volumes:
      - ./dnsmasq_rules.conf:/etc/dnsmasq.d/unlock.conf
      - ./sniproxy.conf:/etc/sniproxy.conf
EOF
        
        # 启动
        docker compose down 2>/dev/null
        docker compose up -d --build
        
    else
        # 原生模式
        echo -e "${YELLOW}正在配置原生环境...${NC}"
        install_native_env
        
        # 配置 Dnsmasq
        cat > /etc/dnsmasq.conf <<EOF
port=53
no-resolv
server=8.8.8.8
conf-dir=/etc/dnsmasq.d/,*.conf
cache-size=1000
EOF
        cp dnsmasq_rules.conf /etc/dnsmasq.d/unlock.conf
        
        # 配置 Sniproxy
        mkdir -p /var/log/sniproxy
        sed -i 's|/dev/stderr|/var/log/sniproxy/error.log|g' sniproxy.conf
        sed -i 's|/dev/stdout|/var/log/sniproxy/access.log|g' sniproxy.conf
        cp sniproxy.conf /etc/sniproxy.conf
        
        systemctl restart dnsmasq sniproxy
        systemctl enable dnsmasq sniproxy
    fi
}

# ==========================================================
# 安全防火墙 (关键升级：防自锁)
# ==========================================================
set_firewall() {
    echo -e "\n${SKY}═══════════════════════════════════════════════${NC}"
    echo -e "${SKY}  安全配置 (IP白名单)${NC}"
    echo -e "${SKY}═══════════════════════════════════════════════${NC}\n"
    
    echo "请输入【客户端/落地机 IP】(即需要使用此解锁机的服务器IP)"
    echo "多个IP用空格分隔，回车跳过则不限制"
    read -p "IP列表: " CLIENT_IPS
    
    if [ -n "$CLIENT_IPS" ]; then
        echo -e "${YELLOW}正在应用防火墙规则...${NC}"
        
        # === UFW 逻辑 ===
        if command -v ufw &> /dev/null; then
            # 1. 必须先放行 SSH，防止自锁！
            ufw allow ssh >/dev/null 2>&1
            ufw allow 22/tcp >/dev/null 2>&1
            
            # 2. 开启 UFW
            echo "y" | ufw enable >/dev/null 2>&1
            
            # 3. 清理旧规则
            ufw delete allow 53/tcp >/dev/null 2>&1
            ufw delete allow 53/udp >/dev/null 2>&1
            ufw delete allow 80/tcp >/dev/null 2>&1
            ufw delete allow 443/tcp >/dev/null 2>&1
            
            # 4. 添加白名单
            for ip in $CLIENT_IPS; do
                if validate_ip "$ip"; then
                    ufw allow from "$ip" to any port 53 >/dev/null 2>&1
                    ufw allow from "$ip" to any port 80 >/dev/null 2>&1
                    ufw allow from "$ip" to any port 443 >/dev/null 2>&1
                    echo -e "${GREEN}✓ 已放行: $ip${NC}"
                fi
            done
            ufw reload >/dev/null 2>&1
            
        # === IPTABLES 逻辑 ===
        else
            # 1. 确保 SSH 放行
            iptables -A INPUT -p tcp --dport 22 -j ACCEPT
            
            # 2. 创建专用链
            iptables -N UNLOCK_LIMIT 2>/dev/null || iptables -F UNLOCK_LIMIT
            iptables -D INPUT -j UNLOCK_LIMIT 2>/dev/null || true
            iptables -I INPUT -j UNLOCK_LIMIT
            
            # 3. 添加白名单
            for ip in $CLIENT_IPS; do
                if validate_ip "$ip"; then
                    iptables -A UNLOCK_LIMIT -s "$ip" -p tcp --dport 53 -j ACCEPT
                    iptables -A UNLOCK_LIMIT -s "$ip" -p udp --dport 53 -j ACCEPT
                    iptables -A UNLOCK_LIMIT -s "$ip" -p tcp --dport 80 -j ACCEPT
                    iptables -A UNLOCK_LIMIT -s "$ip" -p tcp --dport 443 -j ACCEPT
                    echo -e "${GREEN}✓ 已放行: $ip${NC}"
                fi
            done
            
            # 4. 拒绝其他 53/80/443
            iptables -A UNLOCK_LIMIT -p tcp --dport 53 -j DROP
            iptables -A UNLOCK_LIMIT -p udp --dport 53 -j DROP
            iptables -A UNLOCK_LIMIT -p tcp --dport 80 -j DROP
            iptables -A UNLOCK_LIMIT -p tcp --dport 443 -j DROP
        fi
    else
        echo -e "${RED}未输入 IP，防火墙保持默认（全开放或保持原状）。${NC}"
    fi
}

# ==========================================================
# 结果生成 (V2bX JSON)
# ==========================================================
generate_json() {
    clear
    echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
    echo -e "${GREEN}   🎉 搭建完成！请复制下方 JSON 覆盖 V2bX 模版   ${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
    
    # 构造 IP CIDR
    if [[ "$FINAL_IP" == *":"* ]]; then
        IP_CIDR="${FINAL_IP}/128"
    else
        IP_CIDR="${FINAL_IP}/32"
    fi

    # 包含审计规则 (Block BT/回国/挖矿)
    cat <<EOF
{
  "dns": {
    "servers": [
      {
        "tag": "unlock_dns",
        "address": "${FINAL_IP}",
        "address_resolver": "local_dns",
        "detour": "direct"
      },
      {
        "tag": "local_dns",
        "address": "1.1.1.1",
        "detour": "direct"
      }
    ],
    "rules": [
      {
        "domain_suffix": [${FINAL_JSON_LIST}],
        "server": "unlock_dns",
        "disable_cache": true
      }
    ],
    "final": "local_dns",
    "strategy": "prefer_ipv4"
  },
  "outbounds": [
    { "tag": "direct", "type": "direct" },
    { "tag": "block", "type": "block" }
  ],
  "route": {
    "rules": [
      { "protocol": "dns", "outbound": "direct" },
      { "ip_cidr": ["${IP_CIDR}"], "outbound": "direct" },
      { "domain_suffix": [${FINAL_JSON_LIST}], "outbound": "direct" },
      { "ip_is_private": true, "outbound": "block" },
      { "protocol": "quic", "outbound": "block" },
      {
        "domain_regex": [
          "(api|ps|sv|offnavi|newvector|ulog.imap|newloc)(.map|).(baidu|n.shifen).com",
          "(.+.|^)(360|so).(cn|com)",
          "(Subject|HELO|SMTP)",
          "(torrent|.torrent|peer_id=|info_hash|get_peers|find_node|BitTorrent|announce_peer|announce.php?passkey=)",
          "(^.@)(guerrillamail|guerrillamailblock|sharklasers|grr|pokemail|spam4|bccto|chacuo|027168).(info|biz|com|de|net|org|me|la)",
          "(.?)(xunlei|sandai|Thunder|XLLiveUD)(.)",
          "(..||)(dafahao|mingjinglive|botanwang|minghui|dongtaiwang|falunaz|epochtimes|ntdtv|falundafa|falungong|wujieliulan|zhengjian).(org|com|net)",
          "(ed2k|.torrent|peer_id=|announce|info_hash|get_peers|find_node|BitTorrent|announce_peer|announce.php?passkey=|magnet:|xunlei|sandai|Thunder|XLLiveUD|bt_key)"
        ],
        "outbound": "block"
      },
      { "outbound": "direct", "network": ["udp","tcp"] }
    ],
    "auto_detect_interface": false
  }
}
EOF
    echo -e "${NC}"
    echo -e "${YELLOW}解锁IP: ${FINAL_IP}${NC}"
    echo -e "${YELLOW}模式: ${DEPLOY_MODE}${NC}"
    echo -e "${SKY}验证方法:${NC}"
    echo -e "1. 在落地机执行: ${GREEN}nslookup netflix.com ${FINAL_IP}${NC} (应返回 ${FINAL_IP})"
    echo -e "2. 在落地机执行: ${GREEN}curl -I https://www.netflix.com --resolve www.netflix.com:443:${FINAL_IP}${NC} (应返回 200/301/302)"
}

# ==========================================================
# 卸载功能
# ==========================================================
uninstall() {
    echo -e "${RED}正在卸载...${NC}"
    if command -v docker &> /dev/null; then
        docker rm -f dns_unlock 2>/dev/null
    fi
    systemctl stop dnsmasq sniproxy 2>/dev/null
    systemctl disable dnsmasq sniproxy 2>/dev/null
    rm -rf "$WORK_DIR"
    rm -f /etc/dnsmasq.d/unlock.conf
    echo -e "${GREEN}卸载完成，防火墙规则请按需手动清理。${NC}"
}

# ==========================================================
# 主入口
# ==========================================================
clear
echo -e "${SKY}V2bX 专用解锁服务搭建脚本 (V6.0 完美整合版)${NC}"
echo "1. 安装/重装解锁服务"
echo "2. 卸载解锁服务"
read -p "选择: " act
if [ "$act" = "2" ]; then uninstall; exit 0; fi

check_port_availability
select_public_ip
select_deploy_mode
deploy_service
set_firewall
generate_json
