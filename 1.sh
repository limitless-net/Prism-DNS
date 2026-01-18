#!/bin/bash
# ==========================================================
#   V2bX 专用解锁服务总控脚本 (V10.0 终极排错版)
#   
#   更新日志：
#   1. 新增【查看错误日志】菜单，方便排查
#   2. 安装前暴力清理端口占用 (Fix systemd-resolved)
#   3. 修复 Docker Entrypoint 逻辑
#   4. 完美保留 V2bX JSON 生成与审计规则
# ==========================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
SKY='\033[0;36m'
NC='\033[0m'

WORK_DIR="/root/dns_unlock"
CONFIG_FILE="$WORK_DIR/install.env"

# 加载配置
if [ -f "$CONFIG_FILE" ]; then source "$CONFIG_FILE"; fi

# ==========================================================
# 基础工具
# ==========================================================

check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo -e "${RED}错误: 必须使用 root 权限运行此脚本${NC}"
        exit 1
    fi
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
    echo "TYPE_NAME='$TYPE_NAME'" >> "$CONFIG_FILE"
}

# 暴力释放端口
force_release_ports() {
    echo -e "${YELLOW}>>> 正在清理端口占用...${NC}"
    # 停止常见的占用服务
    systemctl stop systemd-resolved 2>/dev/null
    systemctl disable systemd-resolved 2>/dev/null
    systemctl stop dnsmasq 2>/dev/null
    systemctl stop sniproxy 2>/dev/null
    systemctl stop nginx 2>/dev/null
    systemctl stop apache2 2>/dev/null
    
    # 杀掉进程
    fuser -k 53/tcp 2>/dev/null
    fuser -k 53/udp 2>/dev/null
    fuser -k 80/tcp 2>/dev/null
    fuser -k 443/tcp 2>/dev/null
    
    # 临时修改 resolv.conf 防止构建失败
    echo "nameserver 8.8.8.8" > /etc/resolv.conf
    echo -e "${GREEN}端口清理完毕${NC}"
}

# ==========================================================
# 核心逻辑
# ==========================================================

define_rules() {
    # 1. ChatGPT
    CONF_GPT="address=/openai.com/$FINAL_IP
address=/chatgpt.com/$FINAL_IP
address=/oaistatic.com/$FINAL_IP
address=/oaiusercontent.com/$FINAL_IP
address=/ai.com/$FINAL_IP"
    JSON_GPT='"openai.com", "chatgpt.com", "oaistatic.com", "oaiusercontent.com", "ai.com"'

    # 2. Gemini
    CONF_GEMINI="address=/gemini.google.com/$FINAL_IP
address=/bard.google.com/$FINAL_IP
address=/ai.google.dev/$FINAL_IP
address=/generativelanguage.googleapis.com/$FINAL_IP
address=/makersuite.google.com/$FINAL_IP
address=/deepmind.com/$FINAL_IP
address=/deepmind.google/$FINAL_IP"
    JSON_GEMINI='"gemini.google.com", "bard.google.com", "ai.google.dev", "generativelanguage.googleapis.com", "makersuite.google.com", "deepmind.com", "deepmind.google"'

    # 3. Copilot
    CONF_COPILOT="address=/copilot.microsoft.com/$FINAL_IP
address=/copilot.cloud.microsoft/$FINAL_IP
address=/bing.com/$FINAL_IP
address=/bingapis.com/$FINAL_IP"
    JSON_COPILOT='"copilot.microsoft.com", "copilot.cloud.microsoft", "bing.com", "bingapis.com"'

    # 4. Claude
    CONF_CLAUDE="address=/anthropic.com/$FINAL_IP
address=/claude.ai/$FINAL_IP"
    JSON_CLAUDE='"anthropic.com", "claude.ai"'

    # 5. Netflix
    CONF_NETFLIX="address=/netflix.com/$FINAL_IP
address=/netflix.net/$FINAL_IP
address=/nflxvideo.net/$FINAL_IP
address=/nflximg.net/$FINAL_IP
address=/nflxext.com/$FINAL_IP"
    JSON_NETFLIX='"netflix.com", "netflix.net", "nflxvideo.net", "nflximg.net", "nflxext.com"'

    # 6. Disney+
    CONF_DISNEY="address=/disney.com/$FINAL_IP
address=/disneyplus.com/$FINAL_IP
address=/dssott.com/$FINAL_IP
address=/bamgrid.com/$FINAL_IP"
    JSON_DISNEY='"disney.com", "disneyplus.com", "dssott.com", "bamgrid.com"'

    # 7. TikTok
    CONF_TIKTOK="address=/tiktok.com/$FINAL_IP
address=/tiktokv.com/$FINAL_IP
address=/tiktokcdn.com/$FINAL_IP
address=/musical.ly/$FINAL_IP"
    JSON_TIKTOK='"tiktok.com", "tiktokv.com", "tiktokcdn.com", "musical.ly"'

    # 8. YouTube
    CONF_YOUTUBE="address=/youtube.com/$FINAL_IP
address=/googlevideo.com/$FINAL_IP
address=/ytimg.com/$FINAL_IP
address=/ggpht.com/$FINAL_IP"
    JSON_YOUTUBE='"youtube.com", "googlevideo.com", "ytimg.com", "ggpht.com"'

    # 9. Spotify
    CONF_SPOTIFY="address=/spotify.com/$FINAL_IP
address=/scdn.co/$FINAL_IP
address=/spotifycdn.com/$FINAL_IP"
    JSON_SPOTIFY='"spotify.com", "scdn.co", "spotifycdn.com"'

    # 10. HBO Max
    CONF_HBO="address=/hbomax.com/$FINAL_IP
address=/max.com/$FINAL_IP
address=/hbo.com/$FINAL_IP"
    JSON_HBO='"hbomax.com", "max.com", "hbo.com"'
}

select_services_logic() {
    define_rules
    echo -e "\n${SKY}可用服务 (输入数字，用逗号分隔，例如 1,3,5):${NC}"
    echo ""
    echo -e "${SKY}=== AI 服务 ===${NC}"
    echo "1. ChatGPT (OpenAI)"
    echo "2. Gemini (Google AI)"
    echo "3. Copilot (Microsoft)"
    echo "4. Claude (Anthropic)"
    echo ""
    echo -e "${SKY}=== 流媒体服务 ===${NC}"
    echo "5. Netflix"
    echo "6. Disney+"
    echo "7. TikTok"
    echo "8. YouTube"
    echo "9. Spotify"
    echo "10. HBO Max"
    echo ""
    echo "快捷选项:"
    echo "  a = 所有 AI (1-4)"
    echo "  s = 所有流媒体 (5-10)"
    echo "  * = 全部服务"
    echo ""
    read -p "请输入选择: " SERVICE_CHOICE

    case "$SERVICE_CHOICE" in
        a|A) SERVICE_CHOICE="1,2,3,4" ;;
        s|S) SERVICE_CHOICE="5,6,7,8,9,10" ;;
        \*|all|ALL) SERVICE_CHOICE="1,2,3,4,5,6,7,8,9,10" ;;
    esac

    mkdir -p "$WORK_DIR"
    echo "# Config Generated by Script" > "$WORK_DIR/dnsmasq.conf"
    
    FINAL_JSON_LIST=""
    TYPE_NAME=""
    local selected_count=0
    
    IFS=',' read -ra SERVICES <<< "$SERVICE_CHOICE"
    for service in "${SERVICES[@]}"; do
        service=$(echo "$service" | tr -d '[:space:]')
        case $service in
            1) echo "$CONF_GPT" >> "$WORK_DIR/dnsmasq.conf"; ITEM="$JSON_GPT"; NAME="ChatGPT";;
            2) echo "$CONF_GEMINI" >> "$WORK_DIR/dnsmasq.conf"; ITEM="$JSON_GEMINI"; NAME="Gemini";;
            3) echo "$CONF_COPILOT" >> "$WORK_DIR/dnsmasq.conf"; ITEM="$JSON_COPILOT"; NAME="Copilot";;
            4) echo "$CONF_CLAUDE" >> "$WORK_DIR/dnsmasq.conf"; ITEM="$JSON_CLAUDE"; NAME="Claude";;
            5) echo "$CONF_NETFLIX" >> "$WORK_DIR/dnsmasq.conf"; ITEM="$JSON_NETFLIX"; NAME="Netflix";;
            6) echo "$CONF_DISNEY" >> "$WORK_DIR/dnsmasq.conf"; ITEM="$JSON_DISNEY"; NAME="Disney+";;
            7) echo "$CONF_TIKTOK" >> "$WORK_DIR/dnsmasq.conf"; ITEM="$JSON_TIKTOK"; NAME="TikTok";;
            8) echo "$CONF_YOUTUBE" >> "$WORK_DIR/dnsmasq.conf"; ITEM="$JSON_YOUTUBE"; NAME="YouTube";;
            9) echo "$CONF_SPOTIFY" >> "$WORK_DIR/dnsmasq.conf"; ITEM="$JSON_SPOTIFY"; NAME="Spotify";;
            10) echo "$CONF_HBO" >> "$WORK_DIR/dnsmasq.conf"; ITEM="$JSON_HBO"; NAME="HBO";;
            *) continue ;;
        esac
        
        [ -n "$FINAL_JSON_LIST" ] && FINAL_JSON_LIST="$FINAL_JSON_LIST, "
        FINAL_JSON_LIST="${FINAL_JSON_LIST}${ITEM}"
        [ -n "$TYPE_NAME" ] && TYPE_NAME="$TYPE_NAME+"
        TYPE_NAME="${TYPE_NAME}${NAME}"
        ((selected_count++))
    done

    if [ $selected_count -eq 0 ]; then
        echo -e "${YELLOW}未选择有效服务，默认选择 ChatGPT${NC}"
        echo "$CONF_GPT" >> "$WORK_DIR/dnsmasq.conf"
        FINAL_JSON_LIST="$JSON_GPT"
        TYPE_NAME="ChatGPT"
    fi
    
    if [ $selected_count -ge 5 ]; then
        TYPE_NAME="自定义 ($selected_count 个服务)"
    fi
}

# ==========================================================
# 安装流程
# ==========================================================

run_install() {
    check_root
    
    # 强制清理端口
    force_release_ports
    
    # 1. IP 选择
    IPV4=$(curl -4s --max-time 3 api.ip.sb/ip || curl -4s --max-time 3 ifconfig.me)
    IPV6=$(curl -6s --max-time 3 api.ip.sb/ip || curl -6s --max-time 3 ifconfig.co)
    echo -e "\n${SKY}检测本机 IP:${NC}"
    echo -e "1. IPv4: ${GREEN}${IPV4:-无}${NC}"
    echo -e "2. IPv6: ${GREEN}${IPV6:-无}${NC}"
    echo "3. 手动输入"
    read -p "选择 [1-3] (默认1): " IP_OPT
    case $IP_OPT in
        2) FINAL_IP=$IPV6 ;;
        3) read -p "输入IP: " FINAL_IP ;;
        *) FINAL_IP=$IPV4 ;;
    esac
    if [ -z "$FINAL_IP" ]; then echo -e "${RED}IP 无效${NC}"; return; fi

    # 2. 模式选择
    echo -e "\n${SKY}部署模式:${NC}"
    echo -e "${YELLOW}注意: 如果 Docker 模式安装后端口仍不监听，请务必使用【原生模式】${NC}"
    echo "1. Docker 模式 (环境隔离)"
    echo "2. 原生模式 (推荐! 更稳定、省资源)"
    read -p "选择 [1-2] (默认1): " MODE_OPT
    if [ "$MODE_OPT" == "2" ]; then DEPLOY_MODE="native"; else DEPLOY_MODE="docker"; fi

    # 3. 服务选择
    select_services_logic

    # === 原生模式 ===
    if [ "$DEPLOY_MODE" == "native" ]; then
        echo -e "${YELLOW}>>> 正在安装原生依赖...${NC}"
        apt-get update && apt-get install -y dnsmasq sniproxy
        
        # 确保停止并禁用 systemd-resolved
        systemctl stop systemd-resolved 2>/dev/null
        systemctl disable systemd-resolved 2>/dev/null
        
        cat > /etc/dnsmasq.conf <<EOF
port=53
no-resolv
server=8.8.8.8
conf-dir=/etc/dnsmasq.d/,*.conf
cache-size=1000
EOF
        mkdir -p /etc/dnsmasq.d
        cp "$WORK_DIR/dnsmasq.conf" /etc/dnsmasq.d/unlock.conf
        
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
        
    # === Docker 模式 ===
    else
        echo -e "${YELLOW}>>> 正在配置 Docker 环境...${NC}"
        if ! command -v docker &> /dev/null; then curl -fsSL https://get.docker.com | bash; fi
        
        cd "$WORK_DIR"
        
        # Dockerfile
        cat > Dockerfile <<EOF
FROM alpine:latest
RUN apk add --no-cache dnsmasq sniproxy
# 启动脚本
RUN echo '#!/bin/sh' > /entrypoint.sh && \\
    echo 'dnsmasq --no-daemon --conf-file=/etc/dnsmasq.conf &' >> /entrypoint.sh && \\
    echo 'sniproxy -c /etc/sniproxy.conf -f' >> /entrypoint.sh && \\
    chmod +x /entrypoint.sh
# 基础配置
RUN echo 'port=53' > /etc/dnsmasq.conf && \\
    echo 'no-resolv' >> /etc/dnsmasq.conf && \\
    echo 'server=8.8.8.8' >> /etc/dnsmasq.conf && \\
    echo 'conf-dir=/etc/dnsmasq.d/,*.conf' >> /etc/dnsmasq.conf && \\
    echo 'cache-size=1000' >> /etc/dnsmasq.conf
ENTRYPOINT ["/entrypoint.sh"]
EOF

        # sniproxy.conf
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

        # docker-compose.yml
        cat > docker-compose.yml <<EOF
services:
  unlock:
    build: .
    container_name: dns_unlock
    restart: always
    network_mode: host
    privileged: true
    volumes:
      - ./dnsmasq.conf:/etc/dnsmasq.d/custom_unlock.conf
      - ./sniproxy.conf:/etc/sniproxy.conf
EOF
        
        echo -e "${YELLOW}启动容器...${NC}"
        docker compose down 2>/dev/null
        docker compose up -d --build
    fi

    save_config
    echo -e "${GREEN}安装完成！${NC}"
    read -p "按回车返回菜单..." _
}

# ==========================================================
# 辅助功能
# ==========================================================

fw_settings() {
    echo -e "${SKY}输入允许连接的落地机 IP (多个用空格分隔)${NC}"
    read -p "IP: " ips
    if [ -n "$ips" ]; then
        if command -v ufw &> /dev/null; then
            ufw allow 22/tcp >/dev/null 2>&1
            echo "y" | ufw enable >/dev/null 2>&1
            for ip in $ips; do ufw allow from "$ip" to any; done
            ufw reload
        else
            iptables -A INPUT -p tcp --dport 22 -j ACCEPT
            for ip in $ips; do
                iptables -I INPUT -s "$ip" -p tcp --dport 53 -j ACCEPT
                iptables -I INPUT -s "$ip" -p udp --dport 53 -j ACCEPT
                iptables -I INPUT -s "$ip" -p tcp --dport 80 -j ACCEPT
                iptables -I INPUT -s "$ip" -p tcp --dport 443 -j ACCEPT
            done
            iptables -A INPUT -p tcp --dport 53 -j DROP
            iptables -A INPUT -p udp --dport 53 -j DROP
            iptables -A INPUT -p tcp --dport 80 -j DROP
            iptables -A INPUT -p tcp --dport 443 -j DROP
        fi
        echo -e "${GREEN}规则已更新${NC}"
    fi
    read -p "按回车返回..." _
}

check_status() {
    clear
    echo -e "${SKY}>>> 系统状态检查${NC}"
    echo -e "本机 IP: ${GREEN}${FINAL_IP:-未知}${NC}"
    echo -e "模式: ${YELLOW}${DEPLOY_MODE:-未知}${NC}"
    
    echo -e "\n端口监听状态 (53/80/443):"
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
        systemctl is-active dnsmasq >/dev/null && echo -e "Dnsmasq: ${GREEN}运行中${NC}" || echo -e "Dnsmasq: ${RED}停止${NC}"
        systemctl is-active sniproxy >/dev/null && echo -e "Sniproxy: ${GREEN}运行中${NC}" || echo -e "Sniproxy: ${RED}停止${NC}"
    fi
    read -p "按回车返回..." _
}

view_logs() {
    clear
    echo -e "${SKY}>>> 查看日志${NC}"
    if [ "$DEPLOY_MODE" == "docker" ]; then
        docker logs dns_unlock | tail -n 20
    else
        echo "--- Dnsmasq Log ---"
        journalctl -u dnsmasq --no-pager | tail -n 10
        echo ""
        echo "--- Sniproxy Log ---"
        journalctl -u sniproxy --no-pager | tail -n 10
    fi
    read -p "按回车返回..." _
}

uninstall_all() {
    echo -e "${RED}正在卸载...${NC}"
    if command -v docker &> /dev/null; then docker rm -f dns_unlock 2>/dev/null; fi
    systemctl stop dnsmasq sniproxy 2>/dev/null
    rm -rf "$WORK_DIR"
    echo -e "${GREEN}卸载完成${NC}"
    read -p "按回车返回..." _
}

gen_json() {
    if [ -z "$FINAL_IP" ]; then echo -e "${RED}请先安装!${NC}"; read -p "" _; return; fi
    
    # 构造 IP CIDR
    if [[ "$FINAL_IP" == *":"* ]]; then IP_CIDR="${FINAL_IP}/128"; else IP_CIDR="${FINAL_IP}/32"; fi

    clear
    echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
    echo -e "${GREEN}   🎉 V2bX / NodePass 专用配置 (含审计)   ${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
    echo -e "解锁 IP: ${YELLOW}$FINAL_IP${NC}"
    echo -e "功能: ${SKY}审计屏蔽 + 选定解锁规则 + 兼容新版核心${NC}\n"

    # 原版 JSON 结构
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
    {
      "tag": "direct",
      "type": "direct"
    },
    {
      "type": "block",
      "tag": "block"
    }
  ],
  "route": {
    "rules": [
      {
        "protocol": "dns",
        "outbound": "direct"
      },
      {
        "ip_cidr": ["${IP_CIDR}"],
        "outbound": "direct"
      },
      {
        "protocol": "quic",
        "outbound": "block"
      },
      {
        "domain_suffix": [${FINAL_JSON_LIST}],
        "outbound": "direct"
      },
      {
        "ip_is_private": true,
        "outbound": "block"
      },
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
        "outbound": "direct",
        "network": [
          "udp","tcp"
        ]
      }
    ],
    "auto_detect_interface": false
  },
  "experimental": {
    "cache_file": {
      "enabled": true
    }
  }
}
EOF
    echo ""
    read -p "按回车返回菜单..." _
}

# ==========================================================
# 主菜单
# ==========================================================

while true; do
    clear
    echo -e "${SKY}==================================================${NC}"
    echo -e "${SKY}  V2bX 专用解锁服务总控 (V10.0 终极排错版)${NC}"
    echo -e "${SKY}==================================================${NC}\n"
    echo -e "${GREEN}当前 IP: ${FINAL_IP:-未安装}${NC}"
    echo -e "${GREEN}当前模式: ${DEPLOY_MODE:-未安装}${NC}\n"

    echo -e "${YELLOW}1) 安装 / 重装解锁服务 (Docker/原生)${NC}"
    echo -e "${YELLOW}2) 设置白名单 IP (防火墙)${NC}"
    echo -e "${YELLOW}3) 生成 V2bX/Sing-box JSON 配置 (含审计)${NC}"
    echo -e "${YELLOW}4) 查看运行状态${NC}"
    echo -e "${YELLOW}5) 查看错误日志 (Debug)${NC}"
    echo -e "${RED}6) 卸载服务${NC}"
    echo -e "${RED}0) 退出${NC}"
    echo ""
    read -p ">> " choice

    case "$choice" in
        1) run_install ;;
        2) fw_settings ;;
        3) gen_json ;;
        4) check_status ;;
        5) view_logs ;;
        6) uninstall_all ;;
        0) exit 0 ;;
        *) ;;
    esac
done
