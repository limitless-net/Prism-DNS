#!/bin/bash
# ==========================================================
#   V2bX 专用解锁服务总控脚本 (V5.1 修复增强版)
#   基于原版逻辑重构：
#   1. 菜单式交互 (UI)
#   2. 修复 Docker 端口不监听问题 (内嵌构建文件)
#   3. 配置持久化保存
# ==========================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
SKY='\033[0;36m'
NC='\033[0m'
WORK_DIR="/root/dns_unlock"
CONFIG_FILE="$WORK_DIR/install.env"

# 加载保存的配置
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# ==========================================================
# 基础工具
# ==========================================================

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

validate_ip() {
    local ip="$1"
    if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then return 0; fi
    if [[ "$ip" =~ ^[0-9a-fA-F:]+$ ]]; then return 0; fi
    return 1
}

save_config() {
    mkdir -p "$WORK_DIR"
    echo "FINAL_IP=\"$FINAL_IP\"" > "$CONFIG_FILE"
    echo "DEPLOY_MODE=\"$DEPLOY_MODE\"" >> "$CONFIG_FILE"
    echo "FINAL_JSON_LIST='$FINAL_JSON_LIST'" >> "$CONFIG_FILE"
}

# ==========================================================
# 核心安装逻辑 (修复 Docker 监听问题)
# ==========================================================

install_check() {
    # 检查 Root
    if [ "$(id -u)" != "0" ]; then
        echo -e "${RED}错误: 必须使用 root 权限运行此脚本${NC}"
        exit 1
    fi

    # 检查端口
    local ports=(53 80 443)
    local has_err=0
    for port in "${ports[@]}"; do
        if ss -tuln | grep -q ":${port} "; then
            echo -e "${RED}✗ 端口 $port 已被占用${NC}"
            has_err=1
        fi
    done
    if [ $has_err -eq 1 ]; then
        echo -e "${YELLOW}提示: 如果是旧的解锁服务占用，安装过程中会自动尝试停止。${NC}"
        read -p "是否继续? [y/N]: " cont
        if [[ ! "$cont" =~ ^[Yy]$ ]]; then return 1; fi
    fi
}

select_ip_logic() {
    echo -e "${SKY}正在检测本机 IP...${NC}"
    IPV4=$(curl -4s --max-time 3 api.ip.sb/ip || curl -4s --max-time 3 ifconfig.me)
    IPV6=$(curl -6s --max-time 3 api.ip.sb/ip || curl -6s --max-time 3 ifconfig.co)

    echo -e "1. IPv4: ${GREEN}${IPV4:-未检测到}${NC}"
    echo -e "2. IPv6: ${GREEN}${IPV6:-未检测到}${NC}"
    echo "3. 手动输入"
    
    read -p "请选择解锁服务使用的 IP [1-3]: " IP_CHOICE
    case $IP_CHOICE in
        2) FINAL_IP="$IPV6" ;;
        3) read -p "输入 IP: " FINAL_IP ;;
        *) FINAL_IP="$IPV4" ;;
    esac
    
    if [ -z "$FINAL_IP" ]; then
        echo -e "${RED}错误：无效的 IP${NC}"
        return 1
    fi
}

select_services_logic() {
    # 原版服务选择逻辑
    echo -e "\n${SKY}选择需要解锁的服务 (可多选，逗号分隔)${NC}"
    echo "1. ChatGPT (OpenAI)"
    echo "2. Gemini (Google)"
    echo "3. Copilot (Microsoft)"
    echo "4. Claude (Anthropic)"
    echo "5. Netflix"
    echo "6. Disney+"
    echo "7. TikTok"
    echo "8. YouTube"
    echo "9. Spotify"
    echo "10. HBO Max"
    echo "a. 全选 (1-10)"
    read -p "输入: " SERVICE_CHOICE

    if [[ "$SERVICE_CHOICE" == "a" || "$SERVICE_CHOICE" == "A" ]]; then
        SERVICE_CHOICE="1,2,3,4,5,6,7,8,9,10"
    fi

    mkdir -p "$WORK_DIR"
    echo "# Generated Config" > "$WORK_DIR/dnsmasq.conf"
    FINAL_JSON_LIST=""
    
    IFS=',' read -ra SERVICES <<< "$SERVICE_CHOICE"
    for service in "${SERVICES[@]}"; do
        local d_list=""
        local json_item=""
        case $service in
            1) d_list="openai.com chatgpt.com oaistatic.com oaiusercontent.com ai.com"; json_item='"openai.com", "chatgpt.com", "oaistatic.com", "oaiusercontent.com", "ai.com"';;
            2) d_list="gemini.google.com bard.google.com ai.google.dev deepmind.com"; json_item='"gemini.google.com", "bard.google.com"';;
            3) d_list="copilot.microsoft.com bing.com"; json_item='"copilot.microsoft.com", "bing.com"';;
            4) d_list="anthropic.com claude.ai"; json_item='"anthropic.com", "claude.ai"';;
            5) d_list="netflix.com netflix.net nflxvideo.net nflximg.net nflxext.com"; json_item='"netflix.com", "netflix.net", "nflxvideo.net", "nflximg.net"';;
            6) d_list="disney.com disneyplus.com dssott.com bamgrid.com"; json_item='"disney.com", "disneyplus.com"';;
            7) d_list="tiktok.com tiktokv.com tiktokcdn.com musical.ly"; json_item='"tiktok.com", "tiktokv.com"';;
            8) d_list="youtube.com googlevideo.com ytimg.com ggpht.com"; json_item='"youtube.com", "googlevideo.com"';;
            9) d_list="spotify.com scdn.co"; json_item='"spotify.com"';;
            10) d_list="hbomax.com max.com hbo.com"; json_item='"hbomax.com", "max.com"';;
        esac
        
        for d in $d_list; do
            echo "address=/$d/$FINAL_IP" >> "$WORK_DIR/dnsmasq.conf"
        done
        
        if [ -n "$json_item" ]; then
            if [ -n "$FINAL_JSON_LIST" ]; then FINAL_JSON_LIST="$FINAL_JSON_LIST, "; fi
            FINAL_JSON_LIST="${FINAL_JSON_LIST}${json_item}"
        fi
    done
}

run_install() {
    install_check || return
    select_ip_logic || return
    
    echo -e "\n${SKY}选择部署模式${NC}"
    echo "1. Docker 模式 (推荐)"
    echo "2. 原生模式 (低资源)"
    read -p "选择 [1-2]: " mode_input
    if [ "$mode_input" == "2" ]; then DEPLOY_MODE="native"; else DEPLOY_MODE="docker"; fi
    
    select_services_logic

    # === 原生模式部署 ===
    if [ "$DEPLOY_MODE" == "native" ]; then
        echo -e "${YELLOW}正在安装原生依赖...${NC}"
        apt-get update && apt-get install -y dnsmasq sniproxy
        systemctl stop dnsmasq sniproxy 2>/dev/null
        
        # 配置 Dnsmasq
        cat > /etc/dnsmasq.conf <<EOF
port=53
no-resolv
server=8.8.8.8
conf-dir=/etc/dnsmasq.d/,*.conf
cache-size=1000
EOF
        mkdir -p /etc/dnsmasq.d
        cp "$WORK_DIR/dnsmasq.conf" /etc/dnsmasq.d/unlock.conf
        
        # 配置 Sniproxy
        mkdir -p /var/log/sniproxy
        cat > /etc/sniproxy.conf <<EOF
user daemon
pidfile /var/run/sniproxy.pid
error_log { filename /var/log/sniproxy/error.log; priority notice; }
access_log { filename /var/log/sniproxy/access.log; }
listen 80 { proto http; table http_hosts; }
listen 443 { proto tls; table https_hosts; }
table http_hosts { .* *:80; }
table https_hosts { .* *:443; }
EOF
        systemctl restart dnsmasq sniproxy
        systemctl enable dnsmasq sniproxy
        
    # === Docker 模式部署 (修复 BUG 版) ===
    else
        echo -e "${YELLOW}正在安装 Docker...${NC}"
        if ! command -v docker &> /dev/null; then curl -fsSL https://get.docker.com | bash; fi
        
        cd "$WORK_DIR"
        
        # 【BUG修复】直接生成 Dockerfile，不依赖下载
        cat > Dockerfile <<EOF
FROM alpine:latest
RUN apk add --no-cache dnsmasq sniproxy
# 启动脚本：确保进程前台运行
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

        # 生成 Sniproxy 配置
        cat > sniproxy.conf <<EOF
user daemon
pidfile /var/run/sniproxy.pid
error_log { filename /dev/stderr; priority notice; }
access_log { filename /dev/stdout; }
listen 80 { proto http; table http_hosts; }
listen 443 { proto tls; table https_hosts; }
table http_hosts { .* *; }
table https_hosts { .* *; }
EOF

        # 生成 Compose (Host 模式)
        cat > docker-compose.yml <<EOF
services:
  unlock:
    build: .
    container_name: dns_unlock
    restart: always
    network_mode: host
    privileged: true
    volumes:
      - ./dnsmasq.conf:/etc/dnsmasq.d/unlock.conf
      - ./sniproxy.conf:/etc/sniproxy.conf
EOF
        
        echo -e "${YELLOW}正在构建并启动容器...${NC}"
        docker compose down 2>/dev/null
        docker compose up -d --build
    fi

    save_config
    echo -e "${GREEN}安装完成！${NC}"
    read -p "按回车返回菜单..." _
}

# ==========================================================
# 菜单功能函数
# ==========================================================

# 设置白名单
fw_settings() {
    echo -e "${SKY}输入允许连接的落地机 IP (多个用空格分隔)${NC}"
    read -p "IP: " ips
    
    if [ -n "$ips" ]; then
        if command -v ufw &> /dev/null; then
            ufw allow 22/tcp >/dev/null 2>&1 # 防自锁
            echo "y" | ufw enable >/dev/null 2>&1
            for ip in $ips; do ufw allow from "$ip" to any; done
            ufw reload
        else
            # iptables
            iptables -A INPUT -p tcp --dport 22 -j ACCEPT
            for ip in $ips; do
                iptables -I INPUT -s "$ip" -p tcp --dport 53 -j ACCEPT
                iptables -I INPUT -s "$ip" -p udp --dport 53 -j ACCEPT
                iptables -I INPUT -s "$ip" -p tcp --dport 80 -j ACCEPT
                iptables -I INPUT -s "$ip" -p tcp --dport 443 -j ACCEPT
            done
            # 拒绝其他
            iptables -A INPUT -p tcp --dport 53 -j DROP
            iptables -A INPUT -p udp --dport 53 -j DROP
            iptables -A INPUT -p tcp --dport 80 -j DROP
            iptables -A INPUT -p tcp --dport 443 -j DROP
        fi
        echo -e "${GREEN}防火墙规则已更新${NC}"
    fi
    read -p "按回车返回..." _
}

# 生成 JSON (带审计)
gen_json() {
    if [ -z "$FINAL_IP" ]; then echo -e "${RED}请先安装服务!${NC}"; read -p "" _; return; fi
    
    # 构造 CIDR
    if [[ "$FINAL_IP" == *":"* ]]; then CIDR="${FINAL_IP}/128"; else CIDR="${FINAL_IP}/32"; fi

    clear
    echo -e "${SKY}>>> V2bX / Sing-box 节点配置 (含审计规则)${NC}"
    echo -e "${YELLOW}注意：address 指向本机 IP: ${FINAL_IP}${NC}\n"
    
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
      { "ip_cidr": ["${CIDR}"], "outbound": "direct" },
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
    echo ""
    read -p "按回车返回菜单..." _
}

# 状态检查
check_status() {
    clear
    echo -e "${SKY}>>> 系统状态检查${NC}"
    echo -e "本机 IP: ${GREEN}${FINAL_IP:-未知}${NC}"
    echo -e "模式: ${YELLOW}${DEPLOY_MODE:-未知}${NC}"
    
    echo -e "\n端口监听状态:"
    for p in 53 80 443; do
        if ss -tuln | grep -q ":$p "; then
            echo -e "端口 $p: ${GREEN}正常 (监听中)${NC}"
        else
            echo -e "端口 $p: ${RED}异常 (未监听)${NC}"
        fi
    done
    
    echo -e "\n服务状态:"
    if [ "$DEPLOY_MODE" == "docker" ]; then
        if docker ps | grep -q "dns_unlock"; then echo -e "Docker: ${GREEN}运行中${NC}"; else echo -e "Docker: ${RED}停止${NC}"; fi
    else
        systemctl is-active dnsmasq >/dev/null && echo -e "Dnsmasq: ${GREEN}运行中${NC}"
        systemctl is-active sniproxy >/dev/null && echo -e "Sniproxy: ${GREEN}运行中${NC}"
    fi
    
    read -p "按回车返回..." _
}

# 连通性测试
test_connect() {
    if [ -z "$FINAL_IP" ]; then echo -e "请先安装"; read -p "" _; return; fi
    clear
    echo -e "${SKY}>>> 连通性测试 (自测)${NC}"
    echo "1. 本地 Ping"
    ping -c 3 $FINAL_IP
    echo ""
    echo "2. 本地 443 连接测试"
    curl -I -k https://$FINAL_IP
    echo ""
    read -p "按回车返回..." _
}

uninstall_all() {
    echo -e "${RED}正在卸载...${NC}"
    if command -v docker &> /dev/null; then docker rm -f dns_unlock 2>/dev/null; fi
    systemctl stop dnsmasq sniproxy 2>/dev/null
    rm -rf "$WORK_DIR"
    echo -e "${GREEN}卸载完成，防火墙建议手动清理。${NC}"
    read -p "按回车返回..." _
}

# ==========================================================
# 主菜单
# ==========================================================

main_menu() {
    while true; do
        clear
        echo -e "${SKY}==================================================${NC}"
        echo -e "${SKY}  V2bX 专用解锁服务总控 (V5.1 修复版)${NC}"
        echo -e "${SKY}==================================================${NC}\n"
        echo -e "${GREEN}当前 IP: ${FINAL_IP:-未安装}${NC}"
        echo -e "${GREEN}当前模式: ${DEPLOY_MODE:-未安装}${NC}\n"

        echo -e "${YELLOW}1) 安装 / 重装解锁服务 (Docker/原生)${NC}"
        echo -e "${YELLOW}2) 设置白名单 IP (防火墙)${NC}"
        echo -e "${YELLOW}3) 生成 V2bX/Sing-box JSON 配置${NC}"
        echo -e "${YELLOW}4) 查看运行状态${NC}"
        echo -e "${YELLOW}5) 测试连通性${NC}"
        echo -e "${RED}6) 卸载服务${NC}"
        echo -e "${RED}0) 退出${NC}"
        echo ""
        read -p ">> " choice

        case "$choice" in
            1) run_install ;;
            2) fw_settings ;;
            3) gen_json ;;
            4) check_status ;;
            5) test_connect ;;
            6) uninstall_all ;;
            0) exit 0 ;;
            *) ;;
        esac
    done
}

main_menu
