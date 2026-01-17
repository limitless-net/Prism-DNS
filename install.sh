#!/bin/bash

# ==========================================================
#   NodePass/V2bX 专用解锁服务搭建脚本 (V3.2 GitHub版)
#   功能：双栈IP选择 + 解锁模式选择 + 审计规则集成 + 自动配置
#   Prism-DNS Unlock Service Setup Script (V3.2)
#   Features: Dual-stack IP selection + Unlock modes + Audit rules + Auto config
# ==========================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
SKY='\033[0;36m'
NC='\033[0m'
WORK_DIR="/root/dns_unlock"

# Language selection (default: Chinese)
LANG_CHOICE="zh"

# Select language / 选择语言
select_language() {
    clear
    echo "=================================================="
    echo "  Prism-DNS Unlock Service Setup / 解锁服务部署"
    echo "=================================================="
    echo ""
    echo "Please select language / 请选择语言:"
    echo "1. 简体中文 (Chinese)"
    echo "2. English"
    echo ""
    read -p "Enter your choice / 输入选项 [1-2] (default/默认: 1): " lang_input
    
    case $lang_input in
        2)
            LANG_CHOICE="en"
            ;;
        *)
            LANG_CHOICE="zh"
            ;;
    esac
}

# Multilingual text function
txt() {
    local key="$1"
    case "$key" in
        "check_root_err")
            [ "$LANG_CHOICE" = "en" ] && echo "Error: This script must be run as root" || echo "错误: 必须使用 root 权限运行此脚本"
            ;;
        "port_check_title")
            [ "$LANG_CHOICE" = "en" ] && echo "Checking Port Availability" || echo "检查端口占用情况"
            ;;
        "port_occupied")
            [ "$LANG_CHOICE" = "en" ] && echo "Port $2 is already in use by:" || echo "端口 $2 已被占用，占用进程："
            ;;
        "port_conflict_warn")
            [ "$LANG_CHOICE" = "en" ] && echo "Warning: Required ports (53, 80, 443) are in use. This may cause conflicts." || echo "警告: 必需端口 (53, 80, 443) 被占用，可能导致冲突。"
            ;;
        "port_continue")
            [ "$LANG_CHOICE" = "en" ] && echo "Do you want to continue anyway? [y/N]:" || echo "是否继续安装? [y/N]:"
            ;;
        "port_check_pass")
            [ "$LANG_CHOICE" = "en" ] && echo "✓ All required ports are available" || echo "✓ 所有必需端口可用"
            ;;
        "port_available")
            [ "$LANG_CHOICE" = "en" ] && echo "Port $2: Available" || echo "端口 $2: 可用"
            ;;
        "tip_prefix")
            [ "$LANG_CHOICE" = "en" ] && echo "Tip:" || echo "提示:"
            ;;
        "port_conflict_tip")
            [ "$LANG_CHOICE" = "en" ] && echo "You may need to stop existing services or change their ports." || echo "您可能需要停止现有服务或更改它们的端口。"
            ;;
        *)
            echo "$key"
            ;;
    esac
}

# Show spinner for background tasks
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
    printf "\r"
}

# 1. Check Root privileges / 检查 Root 权限
if [ "$(id -u)" != "0" ]; then
    echo -e "${RED}$(txt check_root_err)${NC}"
    exit 1
fi

# 2. Check port availability / 检查端口占用
check_port_availability() {
    echo -e "\n${SKY}═══════════════════════════════════════════════${NC}"
    echo -e "${SKY}  $(txt port_check_title)${NC}"
    echo -e "${SKY}═══════════════════════════════════════════════${NC}\n"
    
    local ports=(53 80 443)
    local port_conflict=false
    
    for port in "${ports[@]}"; do
        # Check if port is in use using both ss and lsof for reliability
        local port_status=""
        
        if command -v ss &> /dev/null; then
            port_status=$(ss -tuln 2>/dev/null | grep -E "(::|0\.0\.0\.0|\\*):${port}\\b")
        elif command -v netstat &> /dev/null; then
            port_status=$(netstat -tuln 2>/dev/null | grep -E "(::|0\.0\.0\.0|\\*):${port}\\b")
        fi
        
        if [ -n "$port_status" ]; then
            port_conflict=true
            echo -e "${RED}✗ $(txt port_occupied "$port")${NC}"
            
            # Try to identify the process using the port
            if command -v lsof &> /dev/null; then
                lsof -i :$port 2>/dev/null | grep LISTEN | awk '{print "  "$1" (PID: "$2")"}'
            elif command -v ss &> /dev/null; then
                # Extract process info from ss output, handling different formats
                ss -tlnp 2>/dev/null | grep ":$port" | sed 's/.*users:((\([^)]*\)).*/  \1/' | head -1
            fi
        else
            echo -e "${GREEN}✓ $(txt port_available "$port")${NC}"
        fi
    done
    
    echo ""
    
    if [ "$port_conflict" = true ]; then
        echo -e "${YELLOW}$(txt port_conflict_warn)${NC}"
        echo -e "${YELLOW}$(txt tip_prefix) $(txt port_conflict_tip)${NC}"
        echo ""
        read -p "$(txt port_continue) " continue_install
        
        if [[ ! "$continue_install" =~ ^[Yy]$ ]]; then
            echo -e "${RED}Installation cancelled / 安装已取消${NC}"
            exit 1
        fi
    else
        echo -e "${GREEN}$(txt port_check_pass)${NC}"
    fi
    
    sleep 2
}

# 3. Intelligent IP detection and selection / 智能 IP 检测与选择
select_public_ip() {
    clear
    echo -e "${SKY}═══════════════════════════════════════════════${NC}"
    [ "$LANG_CHOICE" = "en" ] && echo -e "${SKY}  Detecting Public IP Addresses${NC}" || echo -e "${SKY}  正在检测本机 IP${NC}"
    echo -e "${SKY}═══════════════════════════════════════════════${NC}\n"
    
    # Detect IPs with spinner
    (curl -4s --max-time 5 ifconfig.me 2>/dev/null > /tmp/ipv4_result) &
    local pid_v4=$!
    spinner $pid_v4 "Detecting IPv4 / 检测 IPv4 地址..."
    wait $pid_v4
    IPV4=$(cat /tmp/ipv4_result 2>/dev/null)
    
    (curl -6s --max-time 5 ifconfig.co 2>/dev/null > /tmp/ipv6_result) &
    local pid_v6=$!
    spinner $pid_v6 "Detecting IPv6 / 检测 IPv6 地址..."
    wait $pid_v6
    IPV6=$(cat /tmp/ipv6_result 2>/dev/null)
    
    rm -f /tmp/ipv4_result /tmp/ipv6_result

    echo -e "\n${SKY}Detected IP addresses / 检测到以下 IP 地址：${NC}"
    if [ -n "$IPV4" ]; then 
        echo -e "1. IPv4: ${GREEN}$IPV4${NC} (${YELLOW}Recommended/推荐${NC})"
    else 
        echo -e "1. IPv4: ${RED}Not detected / 未检测到${NC}"
    fi
    
    if [ -n "$IPV6" ]; then 
        echo -e "2. IPv6: ${GREEN}$IPV6${NC}"
    else 
        echo -e "2. IPv6: ${RED}Not detected / 未检测到${NC}"
    fi
    echo "3. Manual input / 手动输入其他 IP"

    echo ""
    [ "$LANG_CHOICE" = "en" ] && \
        read -p "Select IP for unlock service [1-3]: " IP_CHOICE || \
        read -p "请选择作为解锁服务的 IP [1-3]: " IP_CHOICE

    case $IP_CHOICE in
        1)
            if [ -z "$IPV4" ]; then 
                echo -e "${RED}Invalid IPv4 / 无效的 IPv4${NC}"
                exit 1
            fi
            FINAL_IP="$IPV4"
            ;;
        2)
            if [ -z "$IPV6" ]; then 
                echo -e "${RED}Invalid IPv6 / 无效的 IPv6${NC}"
                exit 1
            fi
            FINAL_IP="$IPV6"
            ;;
        3)
            [ "$LANG_CHOICE" = "en" ] && \
                read -p "Enter IP address: " FINAL_IP || \
                read -p "请输入 IP 地址: " FINAL_IP
            ;;
        *)
            echo -e "${YELLOW}Invalid option, using auto-detected IP / 选项错误，使用自动检测到的 IP${NC}"
            FINAL_IP="${IPV4:-$IPV6}"
            ;;
    esac
    echo -e "\n${GREEN}✓ Selected service IP / 已选择服务 IP: ${FINAL_IP}${NC}"
    sleep 1
}

# 4. Install Docker / 安装 Docker
install_docker() {
    echo -e "\n${SKY}═══════════════════════════════════════════════${NC}"
    [ "$LANG_CHOICE" = "en" ] && echo -e "${SKY}  Installing Docker Environment${NC}" || echo -e "${SKY}  安装 Docker 环境${NC}"
    echo -e "${SKY}═══════════════════════════════════════════════${NC}\n"
    
    if ! command -v docker &> /dev/null; then
        echo -e "${YELLOW}Installing Docker / 正在安装 Docker...${NC}"
        (curl -fsSL https://get.docker.com | bash > /tmp/docker_install.log 2>&1) &
        local pid=$!
        spinner $pid "Downloading and installing Docker / 下载并安装 Docker..."
        wait $pid
        
        systemctl enable docker > /dev/null 2>&1
        systemctl start docker
        echo -e "${GREEN}✓ Docker installed successfully / Docker 安装成功${NC}"
    else
        echo -e "${GREEN}✓ Docker already installed / Docker 已安装${NC}"
    fi
    
    if ! command -v docker-compose &> /dev/null; then
        echo -e "${YELLOW}Installing Docker Compose / 正在安装 Docker Compose...${NC}"
        apt-get install -y docker-compose-plugin 2>/dev/null || apt-get install -y docker-compose 2>/dev/null
        echo -e "${GREEN}✓ Docker Compose installed / Docker Compose 已安装${NC}"
    else
        echo -e "${GREEN}✓ Docker Compose already installed / Docker Compose 已安装${NC}"
    fi
    
    sleep 1
}

# 5. Select unlock mode & deploy service / 选择解锁模式 & 部署服务
deploy_service() {
    echo -e "\n${SKY}═══════════════════════════════════════════════${NC}"
    [ "$LANG_CHOICE" = "en" ] && echo -e "${SKY}  Select Unlock Mode${NC}" || echo -e "${SKY}  选择解锁模式${NC}"
    echo -e "${SKY}═══════════════════════════════════════════════${NC}\n"
    
    # --- Define rules / 定义规则变量 ---
    
    # 1. ChatGPT
    CONF_GPT="address=/openai.com/$FINAL_IP
address=/chatgpt.com/$FINAL_IP
address=/oaistatic.com/$FINAL_IP
address=/oaiusercontent.com/$FINAL_IP
address=/auth0.com/$FINAL_IP
address=/sentry.io/$FINAL_IP
address=/identrust.com/$FINAL_IP
address=/challenges.cloudflare.com/$FINAL_IP
address=/ai.com/$FINAL_IP"
    JSON_GPT='"openai.com", "chatgpt.com", "oaistatic.com", "oaiusercontent.com", "auth0.com", "sentry.io", "ai.com"'

    # 2. Gemini
    CONF_GEMINI="address=/bard.google.com/$FINAL_IP
address=/gemini.google.com/$FINAL_IP
address=/ai.google.dev/$FINAL_IP
address=/generativelanguage.googleapis.com/$FINAL_IP
address=/makersuite.google.com/$FINAL_IP
address=/deepmind.com/$FINAL_IP
address=/deepmind.google/$FINAL_IP
address=/google.com/$FINAL_IP
address=/googleapis.com/$FINAL_IP
address=/gstatic.com/$FINAL_IP
address=/googleusercontent.com/$FINAL_IP
address=/googlevideo.com/$FINAL_IP
address=/youtube.com/$FINAL_IP
address=/ytimg.com/$FINAL_IP
address=/ggpht.com/$FINAL_IP"
    JSON_GEMINI='"bard.google.com", "gemini.google.com", "ai.google.dev", "generativelanguage.googleapis.com", "makersuite.google.com", "deepmind.com", "google.com", "googleapis.com", "gstatic.com", "googleusercontent.com", "googlevideo.com", "youtube.com", "ytimg.com", "ggpht.com"'

    # 3. TikTok (独立)
    CONF_TIKTOK="address=/tiktok.com/$FINAL_IP
address=/tiktokv.com/$FINAL_IP
address=/tiktokcdn.com/$FINAL_IP
address=/byteoversea.com/$FINAL_IP
address=/ibytedtos.com/$FINAL_IP
address=/ipstatp.com/$FINAL_IP
address=/muscdn.com/$FINAL_IP
address=/musical.ly/$FINAL_IP"
    JSON_TIKTOK='"tiktok.com", "tiktokv.com", "tiktokcdn.com", "byteoversea.com", "ibytedtos.com", "ipstatp.com", "muscdn.com", "musical.ly"'

    # 4. 其他流媒体 (Netflix/Disney/Spotify/HBO)
    CONF_STREAMING="address=/netflix.com/$FINAL_IP
address=/netflix.net/$FINAL_IP
address=/nflximg.net/$FINAL_IP
address=/nflxvideo.net/$FINAL_IP
address=/nflxso.net/$FINAL_IP
address=/nflxext.com/$FINAL_IP
address=/disney.com/$FINAL_IP
address=/disneyplus.com/$FINAL_IP
address=/dssott.com/$FINAL_IP
address=/spotify.com/$FINAL_IP
address=/pscdn.co/$FINAL_IP
address=/scdn.co/$FINAL_IP
address=/hbo.com/$FINAL_IP
address=/hbogo.com/$FINAL_IP"
    JSON_STREAMING='"netflix.com", "netflix.net", "nflximg.net", "nflxvideo.net", "nflxso.net", "nflxext.com", "disney.com", "disneyplus.com", "dssott.com", "spotify.com", "hbo.com", "hbogo.com"'

    # --- Menu / 菜单 ---
    if [ "$LANG_CHOICE" = "en" ]; then
        echo "Please select unlock mode:"
        echo "1. ChatGPT Only"
        echo "2. Google Gemini Only (includes Google services)"
        echo "3. TikTok Only"
        echo "4. All AI (GPT + Gemini)"
        echo "5. All Streaming (Netflix/Disney + TikTok)"
        echo "6. Super Bundle (AI + Streaming + TikTok) [Recommended]"
    else
        echo "请选择解锁模式："
        echo "1. 仅解锁 ChatGPT"
        echo "2. 仅解锁 Google Gemini (含谷歌全家桶)"
        echo "3. 仅解锁 TikTok (国际抖音)"
        echo "4. 解锁所有 AI (GPT + Gemini)"
        echo "5. 解锁所有流媒体 (Netflix/Disney + TikTok)"
        echo "6. 超级全家桶 (AI + 流媒体 + TikTok) [推荐]"
    fi
    
    read -p "$([ "$LANG_CHOICE" = "en" ] && echo "Enter option [1-6]: " || echo "请输入选项 [1-6]: ")" MODE_CHOICE

    mkdir -p "$WORK_DIR"
    cd "$WORK_DIR" || exit 1
    echo "" > dnsmasq.conf

    case $MODE_CHOICE in
        1)
            echo "$CONF_GPT" >> dnsmasq.conf
            FINAL_JSON_LIST="$JSON_GPT"
            TYPE_NAME=$([ "$LANG_CHOICE" = "en" ] && echo "ChatGPT Only" || echo "ChatGPT 专用")
            ;;
        2)
            echo "$CONF_GEMINI" >> dnsmasq.conf
            FINAL_JSON_LIST="$JSON_GEMINI"
            TYPE_NAME=$([ "$LANG_CHOICE" = "en" ] && echo "Gemini Only" || echo "Gemini 专用")
            ;;
        3)
            echo "$CONF_TIKTOK" >> dnsmasq.conf
            FINAL_JSON_LIST="$JSON_TIKTOK"
            TYPE_NAME=$([ "$LANG_CHOICE" = "en" ] && echo "TikTok Only" || echo "TikTok 专用")
            ;;
        4)
            echo "$CONF_GPT" >> dnsmasq.conf
            echo "$CONF_GEMINI" >> dnsmasq.conf
            FINAL_JSON_LIST="$JSON_GPT, $JSON_GEMINI"
            TYPE_NAME=$([ "$LANG_CHOICE" = "en" ] && echo "All AI" || echo "所有 AI")
            ;;
        5)
            echo "$CONF_STREAMING" >> dnsmasq.conf
            echo "$CONF_TIKTOK" >> dnsmasq.conf
            FINAL_JSON_LIST="$JSON_STREAMING, $JSON_TIKTOK"
            TYPE_NAME=$([ "$LANG_CHOICE" = "en" ] && echo "All Streaming" || echo "全流媒体 (含TikTok)")
            ;;
        6)
            echo "$CONF_GPT" >> dnsmasq.conf
            echo "$CONF_GEMINI" >> dnsmasq.conf
            echo "$CONF_STREAMING" >> dnsmasq.conf
            echo "$CONF_TIKTOK" >> dnsmasq.conf
            FINAL_JSON_LIST="$JSON_GPT, $JSON_GEMINI, $JSON_STREAMING, $JSON_TIKTOK"
            TYPE_NAME=$([ "$LANG_CHOICE" = "en" ] && echo "Super Bundle" || echo "超级全家桶")
            ;;
        *)
            echo -e "${YELLOW}$([ "$LANG_CHOICE" = "en" ] && echo "Invalid option, using Super Bundle" || echo "默认选择全家桶")${NC}"
            echo "$CONF_GPT" >> dnsmasq.conf
            echo "$CONF_GEMINI" >> dnsmasq.conf
            echo "$CONF_STREAMING" >> dnsmasq.conf
            echo "$CONF_TIKTOK" >> dnsmasq.conf
            FINAL_JSON_LIST="$JSON_GPT, $JSON_GEMINI, $JSON_STREAMING, $JSON_TIKTOK"
            TYPE_NAME=$([ "$LANG_CHOICE" = "en" ] && echo "Super Bundle" || echo "超级全家桶")
            ;;
    esac
    
    echo -e "\n${GREEN}✓ Selected mode / 已选择模式: ${TYPE_NAME}${NC}\n"
    sleep 1

    # Download Dockerfile / 下载 Dockerfile
    echo -e "${SKY}═══════════════════════════════════════════════${NC}"
    [ "$LANG_CHOICE" = "en" ] && echo -e "${SKY}  Building Docker Container${NC}" || echo -e "${SKY}  构建 Docker 容器${NC}"
    echo -e "${SKY}═══════════════════════════════════════════════${NC}\n"
    
    if [ ! -f "Dockerfile" ]; then
        echo -e "${YELLOW}$([ "$LANG_CHOICE" = "en" ] && echo "Downloading Dockerfile..." || echo "正在下载 Dockerfile...")${NC}"
        curl -fsSL https://raw.githubusercontent.com/limitless-net/Prism-DNS/main/Dockerfile -o Dockerfile
        if [ $? -ne 0 ]; then
            echo -e "${RED}$([ "$LANG_CHOICE" = "en" ] && echo "Failed to download Dockerfile" || echo "下载 Dockerfile 失败")${NC}"
            exit 1
        fi
        echo -e "${GREEN}✓ Dockerfile downloaded / Dockerfile 已下载${NC}"
    fi

    # Generate docker-compose / 生成 docker-compose
    cat > docker-compose.yml <<EOL
services:
  sniproxy:
    build: .
    image: prism-dns:latest
    container_name: dns_unlock
    restart: always
    network_mode: host
    privileged: true
    volumes:
      - ./dnsmasq.conf:/etc/dnsmasq.d/custom_unlock.conf
EOL

    echo -e "${YELLOW}$([ "$LANG_CHOICE" = "en" ] && echo "Building and starting service..." || echo "正在构建并启动服务...")${NC}"
    docker compose down 2>/dev/null
    
    echo -e "${YELLOW}Step 1/2: Building Docker image / 步骤 1/2: 构建镜像${NC}"
    docker compose build 2>&1 | grep -E "(Step|Successfully|ERROR)" || docker compose build
    
    echo -e "${YELLOW}Step 2/2: Starting container / 步骤 2/2: 启动容器${NC}"
    docker compose up -d
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Service started successfully / 服务启动成功${NC}"
    else
        echo -e "${RED}✗ Failed to start service / 服务启动失败${NC}"
        exit 1
    fi
    
    sleep 2
}

# 6. Configure firewall whitelist / 配置白名单防火墙
set_firewall() {
    echo -e "\n${SKY}═══════════════════════════════════════════════${NC}"
    [ "$LANG_CHOICE" = "en" ] && echo -e "${SKY}  Security Configuration: Firewall Whitelist${NC}" || echo -e "${SKY}  安全配置：防火墙白名单${NC}"
    echo -e "${SKY}═══════════════════════════════════════════════${NC}\n"
    
    if [ "$LANG_CHOICE" = "en" ]; then
        echo "Enter [Client IPs] (your landing server's public IPs)"
        echo "Multiple IPs separated by space, press Enter to skip"
        read -p "Client IPs: " CLIENT_IPS
    else
        echo "请输入【客户端 IP】（即你的落地机公网IP）"
        echo "多个 IP 用空格隔开，回车跳过"
        read -p "客户端 IP: " CLIENT_IPS
    fi

    if [ -n "$CLIENT_IPS" ]; then
        if command -v ufw &> /dev/null; then
            ufw allow 22/tcp > /dev/null 2>&1
            for ip in $CLIENT_IPS; do
                ufw allow from $ip to any port 53 > /dev/null 2>&1
                ufw allow from $ip to any port 80 > /dev/null 2>&1
                ufw allow from $ip to any port 443 > /dev/null 2>&1
                echo -e "${GREEN}✓ Allowed (UFW) / 已放行 (UFW): $ip${NC}"
            done
        elif command -v iptables &> /dev/null; then
            for ip in $CLIENT_IPS; do
                iptables -I INPUT -s $ip -p udp --dport 53 -j ACCEPT
                iptables -I INPUT -s $ip -p tcp --dport 53 -j ACCEPT
                iptables -I INPUT -s $ip -p tcp --dport 80 -j ACCEPT
                iptables -I INPUT -s $ip -p tcp --dport 443 -j ACCEPT
                echo -e "${GREEN}✓ Allowed (iptables) / 已放行 (iptables): $ip${NC}"
            done
        fi
        echo ""
    else
        echo -e "${YELLOW}$([ "$LANG_CHOICE" = "en" ] && echo "Skipped firewall configuration" || echo "跳过防火墙配置")${NC}\n"
    fi
    
    sleep 1
}

# 7. Verify service status / 验证服务状态
verify_services() {
    echo -e "\n${SKY}═══════════════════════════════════════════════${NC}"
    [ "$LANG_CHOICE" = "en" ] && echo -e "${SKY}  Verifying Service Status${NC}" || echo -e "${SKY}  验证服务状态${NC}"
    echo -e "${SKY}═══════════════════════════════════════════════${NC}\n"
    
    echo -e "${YELLOW}$([ "$LANG_CHOICE" = "en" ] && echo "Waiting for services to initialize..." || echo "等待服务初始化...")${NC}"
    sleep 3
    
    # Check necessary variables / 检查必要的变量是否已设置
    if [ -z "$FINAL_IP" ]; then
        echo -e "${RED}$([ "$LANG_CHOICE" = "en" ] && echo "Error: Unlock IP not detected" || echo "错误: 未检测到解锁 IP 地址")${NC}"
        return 1
    fi
    
    # Check container status / 检查容器状态
    echo -e "${YELLOW}[1/3] Checking Docker container / 检查 Docker 容器...${NC}"
    if docker ps | grep -q "dns_unlock"; then
        echo -e "${GREEN}✓ Docker container running / Docker 容器运行正常${NC}"
    else
        echo -e "${RED}✗ Docker container not running / Docker 容器未运行${NC}"
        echo -e "${RED}$([ "$LANG_CHOICE" = "en" ] && echo "Check logs: docker logs dns_unlock" || echo "请检查日志: docker logs dns_unlock")${NC}"
        return 1
    fi
    
    # Check port listening / 检查端口监听
    echo -e "\n${YELLOW}[2/3] Checking port listening status / 检查端口监听状态...${NC}"
    
    local dns_ok=false
    local http_ok=false
    local https_ok=false
    
    if netstat -tuln 2>/dev/null | grep -E ':53([[:space:]]|$)' > /dev/null || ss -tuln 2>/dev/null | grep -E ':53([[:space:]]|$)' > /dev/null; then
        echo -e "${GREEN}✓ DNS port (53) listening / DNS 端口 (53) 正常监听${NC}"
        dns_ok=true
    else
        echo -e "${RED}✗ DNS port (53) not listening / DNS 端口 (53) 未监听${NC}"
    fi
    
    if netstat -tuln 2>/dev/null | grep -E ':80([[:space:]]|$)' > /dev/null || ss -tuln 2>/dev/null | grep -E ':80([[:space:]]|$)' > /dev/null; then
        echo -e "${GREEN}✓ HTTP port (80) listening / HTTP 端口 (80) 正常监听${NC}"
        http_ok=true
    else
        echo -e "${RED}✗ HTTP port (80) not listening / HTTP 端口 (80) 未监听${NC}"
    fi
    
    if netstat -tuln 2>/dev/null | grep -E ':443([[:space:]]|$)' > /dev/null || ss -tuln 2>/dev/null | grep -E ':443([[:space:]]|$)' > /dev/null; then
        echo -e "${GREEN}✓ HTTPS port (443) listening / HTTPS 端口 (443) 正常监听${NC}"
        https_ok=true
    else
        echo -e "${RED}✗ HTTPS port (443) not listening / HTTPS 端口 (443) 未监听${NC}"
    fi
    
    # DNS resolution test / DNS 解析测试
    echo -e "\n${YELLOW}[3/3] Testing DNS resolution / 测试 DNS 解析功能...${NC}"
    
    # Select test domain based on mode / 根据选择的模式智能选择测试域名
    TEST_DOMAIN=""
    if [ -n "$FINAL_JSON_LIST" ]; then
        if echo "$FINAL_JSON_LIST" | grep -q "openai.com"; then
            TEST_DOMAIN="openai.com"
        elif echo "$FINAL_JSON_LIST" | grep -q "netflix.com"; then
            TEST_DOMAIN="netflix.com"
        elif echo "$FINAL_JSON_LIST" | grep -q "google.com"; then
            TEST_DOMAIN="google.com"
        elif echo "$FINAL_JSON_LIST" | grep -q "tiktok.com"; then
            TEST_DOMAIN="tiktok.com"
        fi
    fi
    
    # Skip test if no suitable domain / 如果没有找到合适的测试域名，跳过测试
    if [ -z "$TEST_DOMAIN" ]; then
        echo -e "${YELLOW}⚠ $([ "$LANG_CHOICE" = "en" ] && echo "Cannot determine test domain, skipping DNS test" || echo "无法确定测试域名，跳过 DNS 解析测试")${NC}"
        return 0
    fi
    
    # Try using dig first (more reliable) / 优先使用 dig (更可靠)
    if command -v dig &> /dev/null; then
        DNS_RESULT=$(dig +short @$FINAL_IP $TEST_DOMAIN 2>/dev/null | tail -1)
        
        if [ "$DNS_RESULT" == "$FINAL_IP" ]; then
            echo -e "${GREEN}✓ DNS hijack configured correctly / DNS 劫持配置正确${NC}"
            echo -e "${GREEN}  $TEST_DOMAIN → $FINAL_IP${NC}"
        else
            echo -e "${YELLOW}⚠ DNS test result / DNS 测试结果: $TEST_DOMAIN → ${DNS_RESULT:-no response}${NC}"
            [ "$LANG_CHOICE" = "en" ] && \
                echo -e "${YELLOW}  Tip: Wait for Docker to fully start, then test manually: dig +short @$FINAL_IP $TEST_DOMAIN${NC}" || \
                echo -e "${YELLOW}  提示: 等待 Docker 服务完全启动后，可手动测试: dig +short @$FINAL_IP $TEST_DOMAIN${NC}"
        fi
    # Fall back to nslookup / 降级使用 nslookup
    elif command -v nslookup &> /dev/null; then
        DNS_OUTPUT=$(nslookup $TEST_DOMAIN $FINAL_IP 2>/dev/null)
        DNS_RESULT=$(echo "$DNS_OUTPUT" | grep -v "^Server:" | grep "Address:" | tail -1 | awk '{print $2}' | tr -d '#')
        
        if [ -z "$DNS_RESULT" ]; then
            echo -e "${YELLOW}⚠ $([ "$LANG_CHOICE" = "en" ] && echo "DNS test: No result" || echo "DNS 测试未能获取解析结果")${NC}"
            [ "$LANG_CHOICE" = "en" ] && \
                echo -e "${YELLOW}  Tip: Wait for Docker to fully start, then test manually: nslookup $TEST_DOMAIN $FINAL_IP${NC}" || \
                echo -e "${YELLOW}  提示: 等待 Docker 服务完全启动后，可手动测试: nslookup $TEST_DOMAIN $FINAL_IP${NC}"
        elif [ "$DNS_RESULT" == "$FINAL_IP" ]; then
            echo -e "${GREEN}✓ DNS hijack configured correctly / DNS 劫持配置正确${NC}"
            echo -e "${GREEN}  $TEST_DOMAIN → $FINAL_IP${NC}"
        else
            echo -e "${YELLOW}⚠ DNS test result / DNS 测试结果: $TEST_DOMAIN → $DNS_RESULT${NC}"
            [ "$LANG_CHOICE" = "en" ] && \
                echo -e "${YELLOW}  Tip: Wait for Docker to fully start, then test manually: nslookup $TEST_DOMAIN $FINAL_IP${NC}" || \
                echo -e "${YELLOW}  提示: 等待 Docker 服务完全启动后，可手动测试: nslookup $TEST_DOMAIN $FINAL_IP${NC}"
        fi
    else
        echo -e "${YELLOW}⚠ $([ "$LANG_CHOICE" = "en" ] && echo "dig/nslookup not installed, skipping DNS test" || echo "dig/nslookup 未安装，跳过 DNS 解析测试")${NC}"
        [ "$LANG_CHOICE" = "en" ] && \
            echo -e "${YELLOW}  Install and test: apt install -y dnsutils && dig +short @$FINAL_IP $TEST_DOMAIN${NC}" || \
            echo -e "${YELLOW}  可手动安装后测试: apt install -y dnsutils && dig +short @$FINAL_IP $TEST_DOMAIN${NC}"
    fi
    
    echo ""
    return 0
}

# 8. Generate final JSON configuration / 生成最终 JSON
generate_json() {
    echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
    if [ "$LANG_CHOICE" = "en" ]; then
        echo -e "${GREEN}   🎉 Setup Complete! Copy JSON Below   ${NC}"
    else
        echo -e "${GREEN}   🎉 搭建完成！请复制下方 JSON 覆盖 V2bX 模版   ${NC}"
    fi
    echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
    
    echo -e "$([ "$LANG_CHOICE" = "en" ] && echo "Unlock IP:" || echo "解锁 IP:") ${YELLOW}$FINAL_IP${NC}"
    echo -e "$([ "$LANG_CHOICE" = "en" ] && echo "Current Mode:" || echo "当前模式:") ${SKY}$TYPE_NAME${NC}"
    
    if [ "$LANG_CHOICE" = "en" ]; then
        echo -e "Features: Audit blocking + Selected unlock rules + New core compatible"
    else
        echo -e "功能: 审计屏蔽 + 选定解锁规则 + 兼容新版核心"
    fi
    
    echo -e "${YELLOW}"

    # Route rules description / 路由规则说明:
    # 1. DNS traffic sent to dns-out / DNS 流量发送到 dns-out
    # 2. Private IP traffic blocked / 私有 IP 流量被屏蔽
    # 3. Audit rule matched traffic blocked (BT, return to China traffic, etc.) / 审计规则匹配的流量被屏蔽 (BT、回国流量等)
    # 4. Unlock domain traffic goes direct (DNS already hijacked to unlock server, route allows here) / 解锁域名流量走 direct (DNS 已劫持解析到解锁服务器，此处路由放行)
    # 5. All other traffic goes direct (default fallback rule, ensures normal traffic not dropped) / 其他所有流量走 direct (默认兜底规则，确保正常流量不被遗漏)

    cat <<EOF
{
  "log": {
    "level": "warn",
    "timestamp": true
  },
  "dns": {
    "servers": [
      {
        "tag": "google",
        "address": "8.8.8.8",
        "detour": "direct"
      },
      {
        "tag": "my_private_unlock",
        "address": "${FINAL_IP}",
        "detour": "direct"
      }
    ],
    "rules": [
      {
        "domain_suffix": [
          ${FINAL_JSON_LIST}
        ],
        "server": "my_private_unlock"
      }
    ],
    "strategy": "prefer_ipv4"
  },
  "inbounds": [],
  "outbounds": [
    {
      "tag": "direct",
      "type": "direct",
      "domain_strategy": "prefer_ipv4"
    },
    { "tag": "block", "type": "block" },
    { "tag": "dns-out", "type": "dns" }
  ],
  "route": {
    "rules": [
      { "protocol": "dns", "outbound": "dns-out" },
      { "ip_is_private": true, "outbound": "block" },
      {
        "domain_regex": [
            "(api|ps|sv|offnavi|newvector|ulog.imap|newloc)(.map|).(baidu|n.shifen).com",
            "(.+.|^)(360|so).(cn|com)",
            "(Subject|HELO|SMTP)",
            "(torrent|.torrent|peer_id=|info_hash|get_peers|find_node|BitTorrent|announce_peer|announce.php?passkey=)",
            "(^.@)(guerrillamail|guerrillamailblock|sharklasers|grr|pokemail|spam4|bccto|chacuo|027168).(info|biz|com|de|net|org|me|la)",
            "(.?)(xunlei|sandai|Thunder|XLLiveUD)(.)",
            "(..||)(dafahao|mingjinglive|botanwang|minghui|dongtaiwang|falunaz|epochtimes|ntdtv|falundafa|falungong|wujieliulan|zhengjian).(org|com|net)",
            "(ed2k|.torrent|peer_id=|announce|info_hash|get_peers|find_node|BitTorrent|announce_peer|announce.php?passkey=|magnet:|xunlei|sandai|Thunder|XLLiveUD|bt_key)",
            "(.+.|^)(360).(cn|com|net)",
            "(.*.||)(guanjia.qq.com|qqpcmgr|QQPCMGR)",
            "(.*.||)(rising|kingsoft|duba|xindubawukong|jinshanduba).(com|net|org)",
            "(.*.||)(netvigator|torproject).(com|cn|net|org)",
            "(..||)(visa|mycard|gash|beanfun|bank).",
            "(.*.||)(gov|12377|12315|talk.news.pts.org|creaders|zhuichaguoji|efcc.org|cyberpolice|aboluowang|tuidang|epochtimes|zhengjian|110.qq|mingjingnews|inmediahk|xinsheng|breakgfw|chengmingmag|jinpianwang|qi-gong|mhradio|edoors|renminbao|soundofhope|xizang-zhiye|bannedbook|ntdtv|12321|secretchina|dajiyuan|boxun|chinadigitaltimes|dwnews|huaglad|oneplusnews|epochweekly|cn.rfi).(cn|com|org|net|club|net|fr|tw|hk|eu|info|me)",
            "(.*.||)(miaozhen|cnzz|talkingdata|umeng).(cn|com)",
            "(.*.||)(mycard).(com|tw)",
            "(.*.||)(gash).(com|tw)",
            "(.bank.)",
            "(.*.||)(pincong).(rocks)",
            "(.*.||)(taobao).(com)",
            "(.*.||)(laomoe|jiyou|ssss|lolicp|vv1234|0z|4321q|868123|ksweb|mm126).(com|cloud|fun|cn|gs|xyz|cc)",
            "(flows|miaoko).(pages).(dev)"
        ],
        "outbound": "block"
      },
      {
        "domain_suffix": [
          ${FINAL_JSON_LIST}
        ],
        "outbound": "direct"
      },
      {
        "outbound": "direct"
      }
    ],
    "auto_detect_interface": true
  },
  "experimental": {
    "cache_file": {
      "enabled": true
    }
  }
}
EOF
    echo -e "${NC}"
    
    # Print usage instructions and verification steps / 打印使用说明和验证步骤
    print_instructions
}

# Print bilingual instructions / 打印双语说明
print_instructions() {
    echo -e "\n${SKY}═══════════════════════════════════════════════${NC}"
    if [ "$LANG_CHOICE" = "en" ]; then
        echo -e "${SKY}     📋 Important Notes & Verification Steps     ${NC}"
    else
        echo -e "${SKY}              📋 重要说明与验证步骤              ${NC}"
    fi
    echo -e "${SKY}═══════════════════════════════════════════════${NC}"
    
    if [ "$LANG_CHOICE" = "en" ]; then
        cat <<'EOF'

1. Geographic Location Requirements:
   ✓ Unlock server and landing server [DO NOT NEED] to be in the same region
   - Unlock server: Needs native IP for target services (HK/SG/US etc.)
   - Landing server: Can be in any region (CN/HK/JP etc.)
   - How it works: Landing server forwards specific traffic to unlock server via DNS and SNI proxy

2. Configuration Application Steps:
   Step 1: Copy the yellow JSON configuration above
   Step 2: Login to V2bX/NodePass admin panel
   Step 3: Find your [Landing Node] configuration template
   Step 4: [COMPLETELY REPLACE] original JSON config (not append!)
   Step 5: Save and [RESTART NODE]

3. Network Connection Troubleshooting:
   If unable to access internet after configuration:
   a) Confirm firewall on unlock server has allowed landing server IP (see whitelist config above)
   b) Check cloud provider security group has opened ports 53/80/443
   c) Confirm JSON config was [COMPLETELY REPLACED], not appended
   d) Check if landing server node restarted successfully
   e) Confirm DNS address is correct:
EOF
        echo -e "      ${YELLOW}${FINAL_IP}${NC}"
        cat <<'EOF'

4. Verify Unlock is Working:
   Method 1 - Check unlock server logs:
EOF
        echo -e "     ${SKY}docker logs -f dns_unlock${NC}"
        cat <<'EOF'
   Method 2 - Access test from client:
     - ChatGPT: https://chat.openai.com
     - Netflix: https://www.netflix.com
     - TikTok: Open TikTok APP and check content
   Method 3 - Check DNS resolution:
EOF
        echo -e "     ${SKY}nslookup openai.com ${FINAL_IP}${NC}"
        echo -e "     (Should return: ${YELLOW}${FINAL_IP}${NC})"
        cat <<'EOF'

5. Common Management Commands:
EOF
        echo -e "   View service status: ${SKY}docker ps${NC}"
        echo -e "   View live logs: ${SKY}docker logs -f dns_unlock${NC}"
        echo -e "   Restart service: ${SKY}cd $WORK_DIR && docker compose restart${NC}"
        echo -e "   Stop service: ${SKY}cd $WORK_DIR && docker compose down${NC}"
        echo -e "   Redeploy: ${SKY}bash <(curl -Ls https://raw.githubusercontent.com/limitless-net/Prism-DNS/main/install.sh)${NC}"
    else
        cat <<'EOF'

1. 地理位置要求：
   ✓ 解锁机和落地机【不需要】在同一地区
   - 解锁机: 需要有对应服务的原生 IP (如香港/新加坡/美国等)
   - 落地机: 可以在任何地区 (如国内/香港/日本等)
   - 工作原理: 落地机通过 DNS 和 SNI 代理将特定流量转发到解锁机

2. 配置应用步骤：
   步骤1: 复制上方黄色 JSON 配置
   步骤2: 登录 V2bX/NodePass 后台
   步骤3: 找到你的【落地节点】配置模版
   步骤4: 【完全替换】原有 JSON 配置 (不是追加!)
   步骤5: 保存并【重启节点】

3. 网络连接问题排查：
   如果配置后无法上网，请检查：
   a) 确认解锁机防火墙已放行落地机 IP (见上方白名单配置)
   b) 检查解锁机的云厂商安全组是否放行 53/80/443 端口
   c) 确认 JSON 配置已【完全替换】，而不是追加到原配置
   d) 检查落地机节点是否成功重启
   e) 确认 DNS 地址设置正确:
EOF
        echo -e "      ${YELLOW}${FINAL_IP}${NC}"
        cat <<'EOF'

4. 验证解锁是否生效：
   方法1 - 查看解锁机日志:
EOF
        echo -e "     ${SKY}docker logs -f dns_unlock${NC}"
        cat <<'EOF'
   方法2 - 在客户端访问测试:
     - ChatGPT: https://chat.openai.com
     - Netflix: https://www.netflix.com
     - TikTok: 打开 TikTok APP 查看内容
   方法3 - 检查 DNS 解析:
EOF
        echo -e "     ${SKY}nslookup openai.com ${FINAL_IP}${NC}"
        echo -e "     (应该返回: ${YELLOW}${FINAL_IP}${NC})"
        cat <<'EOF'

5. 常用管理命令：
EOF
        echo -e "   查看服务状态: ${SKY}docker ps${NC}"
        echo -e "   查看实时日志: ${SKY}docker logs -f dns_unlock${NC}"
        echo -e "   重启服务: ${SKY}cd $WORK_DIR && docker compose restart${NC}"
        echo -e "   停止服务: ${SKY}cd $WORK_DIR && docker compose down${NC}"
        echo -e "   重新部署: ${SKY}bash <(curl -Ls https://raw.githubusercontent.com/limitless-net/Prism-DNS/main/install.sh)${NC}"
    fi
    
    echo -e "\n${GREEN}═══════════════════════════════════════════════${NC}"
    if [ "$LANG_CHOICE" = "en" ]; then
        echo -e "${GREEN}  For issues, check GitHub Issues or submit feedback  ${NC}"
    else
        echo -e "${GREEN}  如有问题，请查看项目 GitHub Issues 或提交反馈  ${NC}"
    fi
    echo -e "${GREEN}═══════════════════════════════════════════════${NC}\n"
}

# Main execution flow / 主流程
main() {
    # Create working directory with secure permissions
    mkdir -p "$WORK_DIR"
    chmod 755 "$WORK_DIR" 2>/dev/null
    
    select_language
    check_port_availability
    select_public_ip
    install_docker
    deploy_service
    set_firewall
    verify_services
    generate_json
}

# Run main function / 运行主函数
main
