#!/bin/bash

# ==========================================================
#   NodePass/V2bX 专用解锁服务搭建脚本 (V3.0 GitHub版)
#   功能：双栈IP选择 + 解锁模式选择 + 审计规则集成 + 自动配置
# ==========================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
SKY='\033[0;36m'
NC='\033[0m'
WORK_DIR="/root/dns_unlock"

# 1. 检查 Root 权限
if [ "$(id -u)" != "0" ]; then
    echo -e "${RED}错误: 必须使用 root 权限运行此脚本${NC}"
    exit 1
fi

# 2. 智能 IP 检测与选择
select_public_ip() {
    clear
    echo -e "${YELLOW}正在检测本机 IP...${NC}"
    IPV4=$(curl -4s --max-time 5 ifconfig.me)
    IPV6=$(curl -6s --max-time 5 ifconfig.co)

    echo -e "\n${SKY}检测到以下 IP 地址：${NC}"
    if [ -n "$IPV4" ]; then echo -e "1. IPv4: ${GREEN}$IPV4${NC} (推荐)"; else echo "1. IPv4: 未检测到"; fi
    if [ -n "$IPV6" ]; then echo -e "2. IPv6: ${GREEN}$IPV6${NC}"; else echo "2. IPv6: 未检测到"; fi
    echo "3. 手动输入其他 IP"

    echo -e "\n${YELLOW}请选择作为解锁服务的 IP (将写入配置文件)：${NC}"
    read -p "请输入选项 [1-3]: " IP_CHOICE

    case $IP_CHOICE in
        1)
            if [ -z "$IPV4" ]; then echo -e "${RED}无效的 IPv4${NC}"; exit 1; fi
            FINAL_IP="$IPV4"
            ;;
        2)
            if [ -z "$IPV6" ]; then echo -e "${RED}无效的 IPv6${NC}"; exit 1; fi
            FINAL_IP="$IPV6"
            ;;
        3)
            read -p "请输入 IP 地址: " FINAL_IP
            ;;
        *)
            echo -e "${RED}选项错误，默认使用自动检测到的第一个 IP${NC}"
            FINAL_IP="${IPV4:-$IPV6}"
            ;;
    esac
    echo -e "已选择服务 IP: ${GREEN}${FINAL_IP}${NC}"
}

# 3. 安装 Docker
install_docker() {
    if ! command -v docker &> /dev/null; then
        echo -e "${YELLOW}正在安装 Docker...${NC}"
        curl -fsSL https://get.docker.com | bash
        systemctl enable docker
        systemctl start docker
    fi
    if ! command -v docker-compose &> /dev/null; then
        apt-get install -y docker-compose-plugin 2>/dev/null || apt-get install -y docker-compose 2>/dev/null
    fi
}

# 4. 选择解锁模式 & 部署服务
deploy_service() {
    # --- 定义规则变量 ---
    
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

    # --- 菜单 ---
    echo -e "\n${SKY}请选择解锁模式：${NC}"
    echo "1. 仅解锁 ChatGPT"
    echo "2. 仅解锁 Google Gemini (含谷歌全家桶)"
    echo "3. 仅解锁 TikTok (国际抖音)"
    echo "4. 解锁所有 AI (GPT + Gemini)"
    echo "5. 解锁所有流媒体 (Netflix/Disney + TikTok)"
    echo "6. 超级全家桶 (AI + 流媒体 + TikTok)"
    read -p "请输入选项 [1-6]: " MODE_CHOICE

    mkdir -p $WORK_DIR
    cd $WORK_DIR
    echo "" > dnsmasq.conf

    case $MODE_CHOICE in
        1)
            echo "$CONF_GPT" >> dnsmasq.conf
            FINAL_JSON_LIST="$JSON_GPT"
            TYPE_NAME="ChatGPT 专用"
            ;;
        2)
            echo "$CONF_GEMINI" >> dnsmasq.conf
            FINAL_JSON_LIST="$JSON_GEMINI"
            TYPE_NAME="Gemini 专用"
            ;;
        3)
            echo "$CONF_TIKTOK" >> dnsmasq.conf
            FINAL_JSON_LIST="$JSON_TIKTOK"
            TYPE_NAME="TikTok 专用"
            ;;
        4)
            echo "$CONF_GPT" >> dnsmasq.conf
            echo "$CONF_GEMINI" >> dnsmasq.conf
            FINAL_JSON_LIST="$JSON_GPT, $JSON_GEMINI"
            TYPE_NAME="所有 AI"
            ;;
        5)
            echo "$CONF_STREAMING" >> dnsmasq.conf
            echo "$CONF_TIKTOK" >> dnsmasq.conf
            FINAL_JSON_LIST="$JSON_STREAMING, $JSON_TIKTOK"
            TYPE_NAME="全流媒体 (含TikTok)"
            ;;
        6)
            echo "$CONF_GPT" >> dnsmasq.conf
            echo "$CONF_GEMINI" >> dnsmasq.conf
            echo "$CONF_STREAMING" >> dnsmasq.conf
            echo "$CONF_TIKTOK" >> dnsmasq.conf
            FINAL_JSON_LIST="$JSON_GPT, $JSON_GEMINI, $JSON_STREAMING, $JSON_TIKTOK"
            TYPE_NAME="超级全家桶"
            ;;
        *)
            echo "默认选择全家桶"
            echo "$CONF_GPT" >> dnsmasq.conf
            echo "$CONF_GEMINI" >> dnsmasq.conf
            echo "$CONF_STREAMING" >> dnsmasq.conf
            echo "$CONF_TIKTOK" >> dnsmasq.conf
            FINAL_JSON_LIST="$JSON_GPT, $JSON_GEMINI, $JSON_STREAMING, $JSON_TIKTOK"
            TYPE_NAME="超级全家桶"
            ;;
    esac

    # 下载 Dockerfile
    if [ ! -f "Dockerfile" ]; then
        echo -e "${YELLOW}正在下载 Dockerfile...${NC}"
        curl -fsSL https://raw.githubusercontent.com/limitless-net/Prism-DNS/main/Dockerfile -o Dockerfile
        if [ $? -ne 0 ]; then
            echo -e "${RED}下载 Dockerfile 失败，请检查网络连接${NC}"
            exit 1
        fi
    fi

    # 生成 docker-compose
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

    echo -e "${YELLOW}正在构建并启动服务...${NC}"
    docker compose down 2>/dev/null
    docker compose build
    docker compose up -d
}

# 5. 配置白名单防火墙
set_firewall() {
    echo -e "\n${YELLOW}--- 安全配置：防火墙白名单 ---${NC}"
    echo "请输入【客户端 IP】（即你的落地机公网IP）"
    echo "多个 IP 用空格隔开，回车跳过"
    read -p "客户端 IP: " CLIENT_IPS

    if [ -n "$CLIENT_IPS" ]; then
        if command -v ufw &> /dev/null; then
            ufw allow 22/tcp
            for ip in $CLIENT_IPS; do
                ufw allow from $ip to any port 53
                ufw allow from $ip to any port 80
                ufw allow from $ip to any port 443
                echo -e "已放行 (UFW): $ip"
            done
        elif command -v iptables &> /dev/null; then
            for ip in $CLIENT_IPS; do
                iptables -I INPUT -s $ip -p udp --dport 53 -j ACCEPT
                iptables -I INPUT -s $ip -p tcp --dport 53 -j ACCEPT
                iptables -I INPUT -s $ip -p tcp --dport 80 -j ACCEPT
                iptables -I INPUT -s $ip -p tcp --dport 443 -j ACCEPT
                echo -e "已放行 (iptables): $ip"
            done
        fi
    else
        echo "跳过防火墙配置。"
    fi
}

# 6. 生成最终 JSON
generate_json() {
    echo -e "\n${GREEN}======================================================${NC}"
    echo -e "${GREEN}   🎉 搭建完成！请复制下方 JSON 覆盖 V2bX 模版   ${NC}"
    echo -e "${GREEN}======================================================${NC}"
    echo -e "解锁 IP : ${YELLOW}$FINAL_IP${NC}"
    echo -e "当前模式: ${SKY}$TYPE_NAME${NC}"
    echo -e "功能: 审计屏蔽 + 选定解锁规则 + 兼容新版核心"
    echo -e "${YELLOW}"

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
    "strategy": "ipv4_only"
  },
  "inbounds": [],
  "outbounds": [
    { "tag": "direct", "type": "direct" },
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
}

# 流程
chmod 777 $WORK_DIR -R 2>/dev/null
select_public_ip
install_docker
deploy_service
set_firewall
generate_json
