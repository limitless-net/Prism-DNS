#!/bin/bash

# ==========================================================
#   NodePass/V2bX 专用解锁服务搭建脚本 (Refactored/重构版)
#   功能：双栈IP选择 + 精细化服务选择 + 审计规则集成 + 全菜单交互
#   Prism-DNS Unlock Service Setup Script
# ==========================================================

# --- 1. 全局配置与状态 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
SKY='\033[0;36m'
NC='\033[0m'

WORK_DIR="/root/dns_unlock"
STATE_FILE="${WORK_DIR}/state.env"
WHITELIST_FILE="${WORK_DIR}/whitelist.txt"
LOG_FILE="${WORK_DIR}/prism-dns.log"
LANG_CHOICE="zh"

# Runtime Variables
FINAL_IP=""
DEPLOY_MODE="docker"
FINAL_JSON_LIST=""
TYPE_NAME=""

# --- 2. 基础工具函数 (UI & Log) ---

_now() { date '+%Y-%m-%d %H:%M:%S'; }

log_write() {
    local level="$1"
    local msg="$2"
    mkdir -p "$WORK_DIR" 2>/dev/null
    echo "$(_now) [$level] $msg" >> "$LOG_FILE" 2>/dev/null
}

msg_info() { echo -e "${SKY}$1${NC}"; log_write "INFO" "$1"; }
msg_ok()   { echo -e "${GREEN}✓ $1${NC}"; log_write "OK" "$1"; }
msg_warn() { echo -e "${YELLOW}⚠ $1${NC}"; log_write "WARN" "$1"; }
msg_err()  { echo -e "${RED}✗ $1${NC}"; log_write "ERR" "$1"; }

# 确保运行时目录存在
ensure_env() {
    mkdir -p "$WORK_DIR" 2>/dev/null
    chmod 755 "$WORK_DIR" 2>/dev/null
    touch "$LOG_FILE" 2>/dev/null
    touch "$WHITELIST_FILE" 2>/dev/null
}

# 状态持久化
save_state() {
    ensure_env
    cat > "$STATE_FILE" <<EOF
LANG_CHOICE="$LANG_CHOICE"
FINAL_IP="$FINAL_IP"
DEPLOY_MODE="$DEPLOY_MODE"
TYPE_NAME="$TYPE_NAME"
# JSON list omitted to keep file clean, regenerated on demand if needed
EOF
}

load_state() {
    if [ -f "$STATE_FILE" ]; then
        # shellcheck disable=SC1090
        . "$STATE_FILE"
    fi
}

pause_key() {
    echo ""
    if [ "$LANG_CHOICE" = "en" ]; then
        read -r -p "Press Enter to return..." _
    else
        read -r -p "按回车键返回..." _
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
    printf "\r%-60s\r" " " # clear line
}

validate_ip() {
    local ip="$1"
    ip=$(echo "$ip" | tr -d '[:space:]')
    [ -z "$ip" ] && return 1
    # Simple rigorous validation logic
    if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        return 0
    elif [[ "$ip" =~ : ]]; then
        return 0
    fi
    return 1
}

# --- 3. 核心业务逻辑 (配置生成 & 安装) ---
# 这些函数包含 heredoc，绝不修改内容

gen_dnsmasq_conf_native() {
    # 原生模式的 dnsmasq 配置
    cat > /etc/dnsmasq.conf <<EOF
# Prism-DNS Configuration
port=53
no-resolv
server=8.8.8.8
server=8.8.4.4
conf-dir=/etc/dnsmasq.d/,*.conf
no-hosts
cache-size=1000
EOF
}

gen_sniproxy_conf() {
    # Sniproxy 配置
    mkdir -p /var/log/sniproxy
    chmod 755 /var/log/sniproxy
    cat > /etc/sniproxy.conf <<EOF
user daemon
pidfile /var/run/sniproxy.pid

error_log {
    filename /var/log/sniproxy/error.log
    priority notice
}

access_log {
    filename /var/log/sniproxy/access.log
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
    .* *:80
}

table https_hosts {
    .* *:443
}
EOF
}

gen_docker_compose() {
    # Docker Compose 配置
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
}

gen_final_json() {
    # 最终 JSON 输出
    local ip_cidr
    if [[ "$FINAL_IP" == *":"* ]]; then
        ip_cidr="${FINAL_IP}/128"
    else
        ip_cidr="${FINAL_IP}/32"
    fi

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
    "strategy": "prefer_ipv4",
    "disable_cache": false
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
}

# --- 4. 功能流程函数 ---

# 4.1 语言选择流程
flow_select_language() {
    clear
    echo "=================================================="
    echo "  Prism-DNS Unlock Service Setup / 解锁服务部署"
    echo "=================================================="
    echo ""
    echo "Please select language / 请选择语言:"
    echo "1) 简体中文 (Chinese)"
    echo "2) English"
    echo ""
    read -r -p "Select [1-2]: " choice
    case "$choice" in
        2) LANG_CHOICE="en" ;;
        *) LANG_CHOICE="zh" ;;
    esac
    msg_ok "$([ "$LANG_CHOICE" = "en" ] && echo "Language set to English" || echo "语言已设置为中文")"
    sleep 1
}

# 4.2 端口检测流程
flow_check_ports() {
    echo -e "\n${SKY}═══════════════════════════════════════════════${NC}"
    [ "$LANG_CHOICE" = "en" ] && echo -e "${SKY}  Checking Port Availability${NC}" || echo -e "${SKY}  检查端口占用情况${NC}"
    echo -e "${SKY}═══════════════════════════════════════════════${NC}\n"
    
    local ports=(53 80 443)
    local conflict=false

    for port in "${ports[@]}"; do
        if ss -tuln 2>/dev/null | grep -E "(:|\\])${port}\\b" >/dev/null; then
            conflict=true
            msg_err "$([ "$LANG_CHOICE" = "en" ] && echo "Port $port occupied" || echo "端口 $port 已被占用")"
        else
            msg_ok "$([ "$LANG_CHOICE" = "en" ] && echo "Port $port available" || echo "端口 $port 可用")"
        fi
    done

    if [ "$conflict" = true ]; then
        echo ""
        msg_warn "$([ "$LANG_CHOICE" = "en" ] && echo "Port conflicts detected!" || echo "发现端口冲突！")"
        while true; do
            echo -e "${YELLOW}1) $([ "$LANG_CHOICE" = "en" ] && echo "Continue anyway (May fail)" || echo "强制继续（可能会失败）")${NC}"
            echo -e "${YELLOW}2) $([ "$LANG_CHOICE" = "en" ] && echo "Cancel installation" || echo "取消安装")${NC}"
            read -r -p "Select [1-2]: " c
            case "$c" in
                1) return 0 ;;
                2) return 1 ;;
                *) ;;
            esac
        done
    else
        return 0
    fi
}

# 4.3 IP 选择流程
flow_select_ip() {
    clear
    echo -e "${SKY}═══════════════════════════════════════════════${NC}"
    [ "$LANG_CHOICE" = "en" ] && echo -e "${SKY}  Select Unlock Service IP${NC}" || echo -e "${SKY}  选择解锁服务 IP${NC}"
    echo -e "${SKY}═══════════════════════════════════════════════${NC}\n"

    msg_info "$([ "$LANG_CHOICE" = "en" ] && echo "Detecting IPs..." || echo "正在检测本机 IP...")"
    
    local ipv4 ipv6
    ipv4=$(curl -4s --max-time 3 ifconfig.me 2>/dev/null)
    ipv6=$(curl -6s --max-time 3 ifconfig.co 2>/dev/null)

    while true; do
        echo ""
        local i=1
        if [ -n "$ipv4" ]; then echo "$i) IPv4: $ipv4"; ipv4_idx=$i; ((i++)); fi
        if [ -n "$ipv6" ]; then echo "$i) IPv6: $ipv6"; ipv6_idx=$i; ((i++)); fi
        echo "$i) $([ "$LANG_CHOICE" = "en" ] && echo "Manual Input" || echo "手动输入")"
        local manual_idx=$i
        echo ""
        
        read -r -p "Select [1-$manual_idx]: " choice
        
        if [ -n "$ipv4" ] && [ "$choice" = "$ipv4_idx" ]; then
            FINAL_IP="$ipv4"
            break
        elif [ -n "$ipv6" ] && [ "$choice" = "$ipv6_idx" ]; then
            FINAL_IP="$ipv6"
            break
        elif [ "$choice" = "$manual_idx" ]; then
            read -r -p "Input IP: " user_ip
            if validate_ip "$user_ip"; then
                FINAL_IP="$user_ip"
                break
            else
                msg_err "Invalid IP"
            fi
        fi
    done
    msg_ok "Selected IP: $FINAL_IP"
    sleep 1
}

# 4.4 部署模式选择
flow_select_mode() {
    clear
    echo -e "${SKY}═══════════════════════════════════════════════${NC}"
    [ "$LANG_CHOICE" = "en" ] && echo -e "${SKY}  Select Deployment Mode${NC}" || echo -e "${SKY}  选择部署模式${NC}"
    echo -e "${SKY}═══════════════════════════════════════════════${NC}\n"

    while true; do
        echo -e "${YELLOW}1) Docker Mode (Recommended)${NC}"
        echo -e "${YELLOW}2) Native Mode (Low RAM)${NC}"
        read -r -p "Select [1-2]: " m
        case "$m" in
            1) DEPLOY_MODE="docker"; break ;;
            2) DEPLOY_MODE="native"; break ;;
            *) ;;
        esac
    done
    msg_ok "Mode: $DEPLOY_MODE"
    sleep 1
}

# 4.5 依赖安装
flow_install_deps() {
    echo -e "\n${SKY}═══════════════════════════════════════════════${NC}"
    msg_info "$([ "$LANG_CHOICE" = "en" ] && echo "Installing Dependencies..." || echo "正在安装依赖...")"
    echo -e "${SKY}═══════════════════════════════════════════════${NC}\n"

    if [ "$DEPLOY_MODE" = "native" ]; then
        apt-get update -y >/dev/null 2>&1
        apt-get install -y dnsmasq sniproxy >/dev/null 2>&1
        if command -v dnsmasq >/dev/null && command -v sniproxy >/dev/null; then
            msg_ok "Native dependencies installed."
        else
            msg_err "Failed to install dnsmasq/sniproxy."
            exit 1
        fi
    else
        # Docker
        if ! command -v docker >/dev/null; then
            curl -fsSL https://get.docker.com | bash
            systemctl enable docker
            systemctl start docker
        fi
        # Compose check
        if ! docker compose version >/dev/null 2>&1 && ! command -v docker-compose >/dev/null; then
             apt-get install -y docker-compose-plugin 2>/dev/null || apt-get install -y docker-compose 2>/dev/null
        fi
        msg_ok "Docker environment ready."
    fi
    sleep 1
}

# 4.6 服务配置生成与部署 (核心菜单)
flow_deploy_services() {
    # 定义配置片段
    local C_GPT="address=/openai.com/$FINAL_IP
address=/chatgpt.com/$FINAL_IP
address=/oaistatic.com/$FINAL_IP
address=/oaiusercontent.com/$FINAL_IP
address=/ai.com/$FINAL_IP"
    local J_GPT='"openai.com", "chatgpt.com", "oaistatic.com", "oaiusercontent.com", "ai.com"'

    local C_GEMINI="address=/gemini.google.com/$FINAL_IP
address=/bard.google.com/$FINAL_IP
address=/ai.google.dev/$FINAL_IP
address=/generativelanguage.googleapis.com/$FINAL_IP
address=/makersuite.google.com/$FINAL_IP
address=/deepmind.com/$FINAL_IP
address=/deepmind.google/$FINAL_IP"
    local J_GEMINI='"gemini.google.com", "bard.google.com", "ai.google.dev", "generativelanguage.googleapis.com", "makersuite.google.com", "deepmind.com", "deepmind.google"'

    local C_COPILOT="address=/copilot.microsoft.com/$FINAL_IP
address=/copilot.cloud.microsoft/$FINAL_IP
address=/bing.com/$FINAL_IP
address=/bingapis.com/$FINAL_IP"
    local J_COPILOT='"copilot.microsoft.com", "copilot.cloud.microsoft", "bing.com", "bingapis.com"'

    local C_CLAUDE="address=/anthropic.com/$FINAL_IP
address=/claude.ai/$FINAL_IP"
    local J_CLAUDE='"anthropic.com", "claude.ai"'

    local C_NETFLIX="address=/netflix.com/$FINAL_IP
address=/netflix.net/$FINAL_IP
address=/nflxvideo.net/$FINAL_IP
address=/nflximg.net/$FINAL_IP
address=/nflxext.com/$FINAL_IP"
    local J_NETFLIX='"netflix.com", "netflix.net", "nflxvideo.net", "nflximg.net", "nflxext.com"'

    local C_DISNEY="address=/disney.com/$FINAL_IP
address=/disneyplus.com/$FINAL_IP
address=/dssott.com/$FINAL_IP
address=/bamgrid.com/$FINAL_IP"
    local J_DISNEY='"disney.com", "disneyplus.com", "dssott.com", "bamgrid.com"'

    local C_TIKTOK="address=/tiktok.com/$FINAL_IP
address=/tiktokv.com/$FINAL_IP
address=/tiktokcdn.com/$FINAL_IP
address=/musical.ly/$FINAL_IP"
    local J_TIKTOK='"tiktok.com", "tiktokv.com", "tiktokcdn.com", "musical.ly"'

    local C_YOUTUBE="address=/youtube.com/$FINAL_IP
address=/googlevideo.com/$FINAL_IP
address=/ytimg.com/$FINAL_IP
address=/ggpht.com/$FINAL_IP"
    local J_YOUTUBE='"youtube.com", "googlevideo.com", "ytimg.com", "ggpht.com"'

    local C_SPOTIFY="address=/spotify.com/$FINAL_IP
address=/scdn.co/$FINAL_IP
address=/spotifycdn.com/$FINAL_IP"
    local J_SPOTIFY='"spotify.com", "scdn.co", "spotifycdn.com"'

    local C_HBO="address=/hbomax.com/$FINAL_IP
address=/max.com/$FINAL_IP
address=/hbo.com/$FINAL_IP"
    local J_HBO='"hbomax.com", "max.com", "hbo.com"'

    # 状态变量 (1=selected)
    local s1=0 s2=0 s3=0 s4=0 s5=0 s6=0 s7=0 s8=0 s9=0 s10=0

    while true; do
        clear
        echo -e "${SKY}═══════════════════════════════════════════════${NC}"
        echo -e "${SKY}  Select Services (Toggle)${NC}"
        echo -e "${SKY}═══════════════════════════════════════════════${NC}\n"
        
        printf " %s 1) ChatGPT\n" "$([ "$s1" = 1 ] && echo "[x]" || echo "[ ]")"
        printf " %s 2) Gemini\n" "$([ "$s2" = 1 ] && echo "[x]" || echo "[ ]")"
        printf " %s 3) Copilot\n" "$([ "$s3" = 1 ] && echo "[x]" || echo "[ ]")"
        printf " %s 4) Claude\n" "$([ "$s4" = 1 ] && echo "[x]" || echo "[ ]")"
        echo " ---"
        printf " %s 5) Netflix\n" "$([ "$s5" = 1 ] && echo "[x]" || echo "[ ]")"
        printf " %s 6) Disney+\n" "$([ "$s6" = 1 ] && echo "[x]" || echo "[ ]")"
        printf " %s 7) TikTok\n" "$([ "$s7" = 1 ] && echo "[x]" || echo "[ ]")"
        printf " %s 8) YouTube\n" "$([ "$s8" = 1 ] && echo "[x]" || echo "[ ]")"
        printf " %s 9) Spotify\n" "$([ "$s9" = 1 ] && echo "[x]" || echo "[ ]")"
        printf " %s 10) HBO Max\n" "$([ "$s10" = 1 ] && echo "[x]" || echo "[ ]")"

        echo ""
        echo -e "${YELLOW}Commands: 1-10 (toggle), a (AI), s (Stream), * (All), d (Done), 0 (Back)${NC}"
        read -r -p "Cmd: " cmd
        case "$cmd" in
            1) s1=$((1-s1)) ;; 2) s2=$((1-s2)) ;; 3) s3=$((1-s3)) ;; 4) s4=$((1-s4)) ;;
            5) s5=$((1-s5)) ;; 6) s6=$((1-s6)) ;; 7) s7=$((1-s7)) ;; 8) s8=$((1-s8)) ;;
            9) s9=$((1-s9)) ;; 10) s10=$((1-s10)) ;;
            a|A) s1=1;s2=1;s3=1;s4=1 ;;
            s|S) s5=1;s6=1;s7=1;s8=1;s9=1;s10=1 ;;
            \*) s1=1;s2=1;s3=1;s4=1;s5=1;s6=1;s7=1;s8=1;s9=1;s10=1 ;;
            d|D) break ;;
            0) return 1 ;;
        esac
    done

    # 生成配置
    ensure_env
    mkdir -p "$WORK_DIR"
    echo "" > "$WORK_DIR/dnsmasq.conf"
    FINAL_JSON_LIST=""
    TYPE_NAME="Custom"

    local sep=""
    [ "$s1" -eq 1 ] && { echo "$C_GPT" >> "$WORK_DIR/dnsmasq.conf"; FINAL_JSON_LIST="${FINAL_JSON_LIST}${sep}${J_GPT}"; sep=", "; }
    [ "$s2" -eq 1 ] && { echo "$C_GEMINI" >> "$WORK_DIR/dnsmasq.conf"; FINAL_JSON_LIST="${FINAL_JSON_LIST}${sep}${J_GEMINI}"; sep=", "; }
    [ "$s3" -eq 1 ] && { echo "$C_COPILOT" >> "$WORK_DIR/dnsmasq.conf"; FINAL_JSON_LIST="${FINAL_JSON_LIST}${sep}${J_COPILOT}"; sep=", "; }
    [ "$s4" -eq 1 ] && { echo "$C_CLAUDE" >> "$WORK_DIR/dnsmasq.conf"; FINAL_JSON_LIST="${FINAL_JSON_LIST}${sep}${J_CLAUDE}"; sep=", "; }
    [ "$s5" -eq 1 ] && { echo "$C_NETFLIX" >> "$WORK_DIR/dnsmasq.conf"; FINAL_JSON_LIST="${FINAL_JSON_LIST}${sep}${J_NETFLIX}"; sep=", "; }
    [ "$s6" -eq 1 ] && { echo "$C_DISNEY" >> "$WORK_DIR/dnsmasq.conf"; FINAL_JSON_LIST="${FINAL_JSON_LIST}${sep}${J_DISNEY}"; sep=", "; }
    [ "$s7" -eq 1 ] && { echo "$C_TIKTOK" >> "$WORK_DIR/dnsmasq.conf"; FINAL_JSON_LIST="${FINAL_JSON_LIST}${sep}${J_TIKTOK}"; sep=", "; }
    [ "$s8" -eq 1 ] && { echo "$C_YOUTUBE" >> "$WORK_DIR/dnsmasq.conf"; FINAL_JSON_LIST="${FINAL_JSON_LIST}${sep}${J_YOUTUBE}"; sep=", "; }
    [ "$s9" -eq 1 ] && { echo "$C_SPOTIFY" >> "$WORK_DIR/dnsmasq.conf"; FINAL_JSON_LIST="${FINAL_JSON_LIST}${sep}${J_SPOTIFY}"; sep=", "; }
    [ "$s10" -eq 1 ] && { echo "$C_HBO" >> "$WORK_DIR/dnsmasq.conf"; FINAL_JSON_LIST="${FINAL_JSON_LIST}${sep}${J_HBO}"; sep=", "; }

    # Apply
    cd "$WORK_DIR" || exit 1
    if [ "$DEPLOY_MODE" = "native" ]; then
        msg_info "Configuring Native Services..."
        cp /etc/dnsmasq.conf /etc/dnsmasq.conf.bak 2>/dev/null
        gen_dnsmasq_conf_native
        cp "$WORK_DIR/dnsmasq.conf" /etc/dnsmasq.d/unlock.conf
        gen_sniproxy_conf
        
        systemctl enable dnsmasq sniproxy
        systemctl restart dnsmasq sniproxy
        msg_ok "Native services restarted."
    else
        msg_info "Configuring Docker Services..."
        if [ ! -f Dockerfile ]; then
            curl -fsSL https://raw.githubusercontent.com/limitless-net/Prism-DNS/main/Dockerfile -o Dockerfile
        fi
        gen_docker_compose
        
        docker compose down 2>/dev/null
        docker compose build
        docker compose up -d
        msg_ok "Docker services restarted."
    fi
}

# 4.7 白名单逻辑
firewall_add_ip() {
    local ip="$1"
    if command -v ufw >/dev/null; then
        ufw allow from "$ip" to any port 53 >/dev/null 2>&1
        ufw allow from "$ip" to any port 80 >/dev/null 2>&1
        ufw allow from "$ip" to any port 443 >/dev/null 2>&1
        return 0
    elif command -v iptables >/dev/null; then
        iptables -I INPUT -s "$ip" -p udp --dport 53 -j ACCEPT
        iptables -I INPUT -s "$ip" -p tcp --dport 53 -j ACCEPT
        iptables -I INPUT -s "$ip" -p tcp --dport 80 -j ACCEPT
        iptables -I INPUT -s "$ip" -p tcp --dport 443 -j ACCEPT
        return 0
    fi
    return 1
}

firewall_del_ip() {
    local ip="$1"
    if command -v ufw >/dev/null; then
        ufw delete allow from "$ip" to any port 53 >/dev/null 2>&1
        return 0
    elif command -v iptables >/dev/null; then
        iptables -D INPUT -s "$ip" -p udp --dport 53 -j ACCEPT 2>/dev/null
        iptables -D INPUT -s "$ip" -p tcp --dport 53 -j ACCEPT 2>/dev/null
        # ... repeated cleanup ...
        return 0
    fi
    return 1
}

flow_whitelist() {
    ensure_env
    while true; do
        clear
        echo -e "${SKY}═══════════════════════════════════════════════${NC}"
        [ "$LANG_CHOICE" = "en" ] && echo -e "${SKY}  Whitelist Manager${NC}" || echo -e "${SKY}  白名单管理${NC}"
        echo -e "${SKY}═══════════════════════════════════════════════${NC}\n"
        
        if [ -s "$WHITELIST_FILE" ]; then
            echo -e "${GREEN}Current IPs:${NC}"
            cat -n "$WHITELIST_FILE"
        else
            echo -e "${YELLOW}(List is empty)${NC}"
        fi
        echo ""
        echo -e "${YELLOW}1) Add IP${NC}"
        echo -e "${YELLOW}2) Remove IP${NC}"
        echo -e "${YELLOW}0) Back${NC}"
        
        read -r -p "Select: " c
        case "$c" in
            1)
                read -r -p "Enter IP: " new_ip
                if validate_ip "$new_ip"; then
                    if firewall_add_ip "$new_ip"; then
                        echo "$new_ip" >> "$WHITELIST_FILE"
                        msg_ok "Added $new_ip"
                    else
                        msg_warn "Added to list but firewall cmd not found."
                        echo "$new_ip" >> "$WHITELIST_FILE"
                    fi
                else
                    msg_err "Invalid IP"
                fi
                sleep 1
                ;;
            2)
                read -r -p "Enter IP to remove: " d_ip
                if validate_ip "$d_ip"; then
                    firewall_del_ip "$d_ip"
                    grep -v "$d_ip" "$WHITELIST_FILE" > "${WHITELIST_FILE}.tmp"
                    mv "${WHITELIST_FILE}.tmp" "$WHITELIST_FILE"
                    msg_ok "Removed $d_ip"
                else
                    msg_err "Invalid IP"
                fi
                sleep 1
                ;;
            0) return ;;
        esac
    done
}

# 4.8 卸载流程
flow_uninstall() {
    clear
    echo -e "${SKY}═══════════════════════════════════════════════${NC}"
    [ "$LANG_CHOICE" = "en" ] && echo -e "${SKY}  Uninstall Service${NC}" || echo -e "${SKY}  卸载服务${NC}"
    echo -e "${SKY}═══════════════════════════════════════════════${NC}\n"
    
    echo -e "${RED}Danger Zone / 危险操作${NC}"
    echo ""
    while true; do
        echo -e "${YELLOW}1) Confirm Uninstall (Remove all)${NC}"
        echo -e "${YELLOW}2) Cancel${NC}"
        read -r -p "Select [1-2]: " u
        case "$u" in
            1)
                msg_info "Stopping services..."
                systemctl stop dnsmasq sniproxy 2>/dev/null
                docker stop dns_unlock 2>/dev/null
                rm -rf "$WORK_DIR"
                rm -f /etc/dnsmasq.d/unlock.conf
                msg_ok "Uninstalled."
                pause_key
                return
                ;;
            2) return ;;
        esac
    done
}

# 4.9 验证与输出
flow_verify_and_show() {
    # 简单的验证
    if netstat -tuln 2>/dev/null | grep -E ':53\b' >/dev/null; then
        msg_ok "DNS Port (53) Listening"
    else
        msg_warn "DNS Port (53) NOT Listening"
    fi
    gen_final_json
    pause_key
}

# --- 5. 主菜单 ---

main() {
    ensure_env
    load_state
    [ -z "$LANG_CHOICE" ] && flow_select_language

    while true; do
        clear
        echo -e "${SKY}╔══════════════════════════════════════════════════════╗${NC}"
        echo -e "${SKY}║              Prism-DNS 解锁服务管理菜单              ║${NC}"
        echo -e "${SKY}╠══════════════════════════════════════════════════════╣${NC}"
        [ "$LANG_CHOICE" = "en" ] && echo -e "${SKY}║  Install / Uninstall / Status / Whitelist            ║${NC}" || echo -e "${SKY}║  安装/卸载/状态/检测/DNS/白名单/日志                 ║${NC}"
        echo -e "${SKY}╚══════════════════════════════════════════════════════╝${NC}"
        
        echo ""
        echo -e "${YELLOW}1) $([ "$LANG_CHOICE" = "en" ] && echo "Install / Reinstall (Wizard)" || echo "安装 / 重新安装 (向导模式)")${NC}"
        echo -e "${YELLOW}2) $([ "$LANG_CHOICE" = "en" ] && echo "Whitelist Manager" || echo "白名单管理")${NC}"
        echo -e "${YELLOW}3) $([ "$LANG_CHOICE" = "en" ] && echo "Show Status" || echo "状态检测")${NC}"
        echo -e "${YELLOW}4) $([ "$LANG_CHOICE" = "en" ] && echo "Show Config JSON" || echo "查看配置 JSON")${NC}"
        echo -e "${YELLOW}9) $([ "$LANG_CHOICE" = "en" ] && echo "Uninstall" || echo "卸载")${NC}"
        echo -e "${YELLOW}L) Language / 语言${NC}"
        echo -e "${YELLOW}0) Exit / 退出${NC}"
        echo ""
        
        read -r -p "Select: " choice
        case "$choice" in
            1)
                # Wizard Flow
                flow_check_ports || continue
                flow_select_ip
                flow_select_mode
                flow_install_deps
                flow_deploy_services
                
                # Inline Whitelist prompt using MENU, not 'read'
                if [ "$LANG_CHOICE" = "en" ]; then
                    echo -e "\n${YELLOW}Would you like to add client IP to whitelist now?${NC}"
                else
                    echo -e "\n${YELLOW}是否立即添加落地机 IP 到白名单？${NC}"
                fi
                while true; do 
                    echo "1) Yes"
                    echo "2) Skip"
                    read -r -p "Select [1-2]: " wlc
                    case "$wlc" in
                        1) flow_whitelist; break ;;
                        2) break ;;
                    esac
                done
                
                # Finish
                save_state
                flow_verify_and_show
                ;;
            2)
                flow_whitelist
                ;;
            3)
                # Quick Status Check
                echo ""
                if systemctl is-active --quiet dnsmasq || docker ps | grep -q dns_unlock; then
                    msg_ok "Service Running"
                else
                    msg_err "Service Stopped"
                fi
                pause_key
                ;;
            4)
                if [ -n "$FINAL_IP" ]; then
                    gen_final_json
                    pause_key
                else
                    msg_warn "Not installed yet."
                    sleep 1
                fi
                ;;
            9)
                flow_uninstall
                ;;
            L|l)
                flow_select_language
                save_state
                ;;
            0)
                exit 0
                ;;
            *)
                ;;
        esac
    done
}

# Run
if [ "$(id -u)" != "0" ]; then
    echo -e "${RED}Error: Must run as root${NC}"
    exit 1
fi

main
