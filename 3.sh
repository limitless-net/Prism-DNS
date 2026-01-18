#!/bin/bash
# ==========================================================
#   V2bX 专用解锁服务总控脚本 (V20.0 铁壁铜墙版)
#   
#   修复日志：
#   1. [安全] 重写防火墙逻辑，实行"默认拒绝"策略
#   2. [安全] 引入专用链 UNLOCK_FW，防止规则混乱
#   3. [优化] 修复白名单不生效问题，强制拦截非授权 IP
# ==========================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
SKY='\033[0;36m'
NC='\033[0m'

WORK_DIR="/root/dns_unlock"
CONFIG_FILE="$WORK_DIR/install.env"
WHITELIST_FILE="$WORK_DIR/whitelist.txt"

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

install_base_tools() {
    if ! command -v netstat &> /dev/null || ! command -v dig &> /dev/null || ! command -v lsof &> /dev/null; then
        echo -e "${YELLOW}>>> 补全基础工具...${NC}"
        if [ -f /etc/debian_version ]; then
            apt-get update -y && apt-get install -y net-tools dnsutils lsof procps
        elif [ -f /etc/redhat-release ]; then
            yum install -y net-tools bind-utils lsof
        fi
    fi
}

save_config() {
    mkdir -p "$WORK_DIR"
    echo "FINAL_IP=\"$FINAL_IP\"" > "$CONFIG_FILE"
    echo "DEPLOY_MODE=\"$DEPLOY_MODE\"" >> "$CONFIG_FILE"
    echo "FINAL_JSON_LIST='$FINAL_JSON_LIST'" >> "$CONFIG_FILE"
    echo "TYPE_NAME='$TYPE_NAME'" >> "$CONFIG_FILE"
}

# 暴力释放端口
kill_port_process() {
    local port=$1
    pids=$(lsof -t -i:$port 2>/dev/null || netstat -nlp | grep ":$port " | awk '{print $7}' | cut -d'/' -f1)
    if [ -n "$pids" ]; then
        # echo -e "${YELLOW}清理端口 $port...${NC}" 
        for pid in $pids; do kill -9 $pid 2>/dev/null; done
    fi
}

force_cleanup() {
    echo -e "${YELLOW}>>> 清理环境...${NC}"
    if command -v docker &> /dev/null; then
        docker rm -f dns_unlock sniproxy_unlock 2>/dev/null
        cd "$WORK_DIR" 2>/dev/null && docker compose down --remove-orphans 2>/dev/null
    fi
    services=("nginx" "apache2" "caddy" "systemd-resolved" "dnsmasq" "sniproxy")
    for svc in "${services[@]}"; do
        systemctl stop "$svc" 2>/dev/null
        systemctl disable "$svc" 2>/dev/null
    done
    kill_port_process 53
    kill_port_process 80
    kill_port_process 443
    rm -f /etc/resolv.conf
    echo "nameserver 8.8.8.8" > /etc/resolv.conf
}

# ==========================================================
# 防火墙核心逻辑 (V20.0 重写)
# ==========================================================

apply_firewall() {
    local ips=$1
    echo -e "${YELLOW}>>> 正在应用铁壁防火墙策略...${NC}"
    
    # 1. 优先使用 UFW (简单、有效)
    if command -v ufw &> /dev/null; then
        # 重置规则 (慎用，这里只操作特定端口)
        ufw allow ssh >/dev/null  # 必须先放行 SSH
        ufw allow 22/tcp >/dev/null
        
        # 删除旧的 53/80/443 规则
        ufw delete allow 53/tcp >/dev/null 2>&1
        ufw delete allow 53/udp >/dev/null 2>&1
        ufw delete allow 80/tcp >/dev/null 2>&1
        ufw delete allow 443/tcp >/dev/null 2>&1
        
        # 允许白名单
        for ip in $ips; do
            echo -e "放行: ${GREEN}$ip${NC}"
            ufw allow from "$ip" to any port 53 >/dev/null
            ufw allow from "$ip" to any port 80 >/dev/null
            ufw allow from "$ip" to any port 443 >/dev/null
        done
        
        # 启用并重新加载
        echo "y" | ufw enable >/dev/null
        ufw reload >/dev/null
        echo -e "${GREEN}UFW 规则已更新 (默认拒绝非白名单连接)${NC}"
        
    # 2. 回退到 Iptables (复杂但底层)
    else
        # 创建专用链，方便管理
        iptables -N UNLOCK_FW 2>/dev/null
        iptables -F UNLOCK_FW # 清空专用链
        
        # 确保 INPUT 链引用了 UNLOCK_FW
        # 先删除旧的引用防止重复
        iptables -D INPUT -j UNLOCK_FW 2>/dev/null
        # 插入到最前面，确保生效
        iptables -I INPUT -j UNLOCK_FW
        
        # === 专用链规则 ===
        
        # 1. 放行白名单 IP
        for ip in $ips; do
            echo -e "放行: ${GREEN}$ip${NC}"
            iptables -A UNLOCK_FW -s "$ip" -p tcp --dport 53 -j ACCEPT
            iptables -A UNLOCK_FW -s "$ip" -p udp --dport 53 -j ACCEPT
            iptables -A UNLOCK_FW -s "$ip" -p tcp --dport 80 -j ACCEPT
            iptables -A UNLOCK_FW -s "$ip" -p tcp --dport 443 -j ACCEPT
        done
        
        # 2. 放行本地回环 (本机测试需要)
        iptables -A UNLOCK_FW -s 127.0.0.1 -j ACCEPT
        
        # 3. 关键：拒绝所有其他访问这些端口的请求
        iptables -A UNLOCK_FW -p tcp --dport 53 -j DROP
        iptables -A UNLOCK_FW -p udp --dport 53 -j DROP
        iptables -A UNLOCK_FW -p tcp --dport 80 -j DROP
        iptables -A UNLOCK_FW -p tcp --dport 443 -j DROP
        
        # 4. 返回主链 (让 SSH 等其他端口走默认规则)
        iptables -A UNLOCK_FW -j RETURN
        
        # 保存规则 (CentOS/Debian 不同，这里只做内存生效，重启可能失效，建议手动做持久化)
        echo -e "${GREEN}Iptables 规则已更新 (非白名单 IP 将无法连接端口)${NC}"
    fi
}

fw_settings() {
    echo -e "${SKY}输入允许连接的落地机 IP (多个用空格分隔)${NC}"
    echo -e "${YELLOW}警告: 未输入的 IP 将完全无法使用此解锁服务！${NC}"
    
    # 读取旧配置
    if [ -f "$WHITELIST_FILE" ]; then
        OLD_IPS=$(cat "$WHITELIST_FILE")
        echo -e "当前白名单: ${GREEN}${OLD_IPS:-无}${NC}"
    fi
    
    read -p "输入新 IP 列表 (留空则不修改): " input_ips
    
    if [ -z "$input_ips" ]; then
        if [ -n "$OLD_IPS" ]; then
            ips="$OLD_IPS"
        else
            echo -e "${RED}未设置白名单，防火墙未启用拦截！${NC}"
            return
        fi
    else
        ips="$input_ips"
        echo "$ips" > "$WHITELIST_FILE"
    fi
    
    apply_firewall "$ips"
    read -p "按回车返回..." _
}

# ==========================================================
# 规则定义
# ==========================================================

define_rules() {
    CONF_GPT="address=/openai.com/$FINAL_IP
address=/chatgpt.com/$FINAL_IP
address=/oaistatic.com/$FINAL_IP
address=/oaiusercontent.com/$FINAL_IP
address=/ai.com/$FINAL_IP"
    JSON_GPT='"openai.com", "chatgpt.com", "oaistatic.com", "oaiusercontent.com", "ai.com"'

    CONF_GEMINI="address=/gemini.google.com/$FINAL_IP
address=/bard.google.com/$FINAL_IP
address=/ai.google.dev/$FINAL_IP
address=/generativelanguage.googleapis.com/$FINAL_IP
address=/makersuite.google.com/$FINAL_IP
address=/deepmind.com/$FINAL_IP
address=/deepmind.google/$FINAL_IP"
    JSON_GEMINI='"gemini.google.com", "bard.google.com", "ai.google.dev", "generativelanguage.googleapis.com", "makersuite.google.com", "deepmind.com", "deepmind.google"'

    CONF_COPILOT="address=/copilot.microsoft.com/$FINAL_IP
address=/copilot.cloud.microsoft/$FINAL_IP
address=/bing.com/$FINAL_IP
address=/bingapis.com/$FINAL_IP"
    JSON_COPILOT='"copilot.microsoft.com", "copilot.cloud.microsoft", "bing.com", "bingapis.com"'

    CONF_CLAUDE="address=/anthropic.com/$FINAL_IP
address=/claude.ai/$FINAL_IP"
    JSON_CLAUDE='"anthropic.com", "claude.ai"'

    CONF_NETFLIX="address=/netflix.com/$FINAL_IP
address=/netflix.net/$FINAL_IP
address=/nflxvideo.net/$FINAL_IP
address=/nflximg.net/$FINAL_IP
address=/nflxext.com/$FINAL_IP"
    JSON_NETFLIX='"netflix.com", "netflix.net", "nflxvideo.net", "nflximg.net", "nflxext.com"'

    CONF_DISNEY="address=/disney.com/$FINAL_IP
address=/disneyplus.com/$FINAL_IP
address=/dssott.com/$FINAL_IP
address=/bamgrid.com/$FINAL_IP"
    JSON_DISNEY='"disney.com", "disneyplus.com", "dssott.com", "bamgrid.com"'

    CONF_TIKTOK="address=/tiktok.com/$FINAL_IP
address=/tiktokv.com/$FINAL_IP
address=/tiktokcdn.com/$FINAL_IP
address=/musical.ly/$FINAL_IP"
    JSON_TIKTOK='"tiktok.com", "tiktokv.com", "tiktokcdn.com", "musical.ly"'

    CONF_YOUTUBE="address=/youtube.com/$FINAL_IP
address=/googlevideo.com/$FINAL_IP
address=/ytimg.com/$FINAL_IP
address=/ggpht.com/$FINAL_IP"
    JSON_YOUTUBE='"youtube.com", "googlevideo.com", "ytimg.com", "ggpht.com"'

    CONF_SPOTIFY="address=/spotify.com/$FINAL_IP
address=/scdn.co/$FINAL_IP
address=/spotifycdn.com/$FINAL_IP"
    JSON_SPOTIFY='"spotify.com", "scdn.co", "spotifycdn.com"'

    CONF_HBO="address=/hbomax.com/$FINAL_IP
address=/max.com/$FINAL_IP
address=/hbo.com/$FINAL_IP"
    JSON_HBO='"hbomax.com", "max.com", "hbo.com"'
}

select_services_logic() {
    define_rules
    echo -e "\n${SKY}可用服务 (输入数字，用逗号分隔，例如 1,3,5):${NC}"
    echo "1. ChatGPT (OpenAI)"
    echo "2. Gemini (Google AI)"
    echo "3. Copilot (Microsoft)"
    echo "4. Claude (Anthropic)"
    echo "5. Netflix"
    echo "6. Disney+"
    echo "7. TikTok"
    echo "8. YouTube"
    echo "9. Spotify"
    echo "10. HBO Max"
    echo "a. 全选"
    read -p "选择: " SERVICE_CHOICE

    case "$SERVICE_CHOICE" in
        a|A) SERVICE_CHOICE="1,2,3,4,5,6,7,8,9,10" ;;
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
# 核心功能
# ==========================================================

run_install() {
    check_root
    install_base_tools
    force_cleanup
    
    IPV4=$(curl -4s --max-time 3 api.ip.sb/ip || curl -4s --max-time 3 ifconfig.me)
    echo -e "\n${SKY}检测本机 IP: ${GREEN}${IPV4:-未知}${NC}"
    read -p "确认使用此 IP? (y/n): " ip_conf
    if [[ "$ip_conf" == "n" ]]; then read -p "输入IP: " FINAL_IP; else FINAL_IP=$IPV4; fi
    if [ -z "$FINAL_IP" ]; then echo -e "${RED}IP 无效${NC}"; return; fi

    echo -e "\n${SKY}部署模式:${NC}"
    echo "1. Docker 模式 (Debian构建)"
    echo "2. 原生模式 (推荐)"
    read -p "选择 [1-2]: " MODE_OPT
    if [ "$MODE_OPT" == "2" ]; then DEPLOY_MODE="native"; else DEPLOY_MODE="docker"; fi

    select_services_logic

    # === 原生模式 ===
    if [ "$DEPLOY_MODE" == "native" ]; then
        echo -e "${YELLOW}>>> 安装原生依赖...${NC}"
        apt-get update && apt-get install -y dnsmasq sniproxy
        systemctl stop systemd-resolved 2>/dev/null
        systemctl disable systemd-resolved 2>/dev/null
        
        cat > /etc/dnsmasq.conf <<EOF
port=53
no-resolv
server=8.8.8.8
conf-dir=/etc/dnsmasq.d/,*.conf
cache-size=1000
listen-address=::,0.0.0.0
bind-interfaces
EOF
        mkdir -p /etc/dnsmasq.d
        cp "$WORK_DIR/dnsmasq.conf" /etc/dnsmasq.d/unlock.conf
        mkdir -p /var/log/sniproxy
        chown daemon:daemon /var/log/sniproxy
        cat > /etc/sniproxy.conf <<EOF
user daemon
pidfile /var/run/sniproxy.pid
resolver { nameserver 8.8.8.8; mode ipv4_only; }
error_log { filename /var/log/sniproxy/error.log; priority notice; }
access_log { filename /var/log/sniproxy/access.log; }
listen 80 { proto http; table http_hosts; }
listen 443 { proto tls; table https_hosts; }
table http_hosts { .* *; }
table https_hosts { .* *; }
EOF
        systemctl restart dnsmasq sniproxy
        systemctl enable dnsmasq sniproxy
        
    # === Docker 模式 ===
    else
        echo -e "${YELLOW}>>> 配置 Docker 环境...${NC}"
        if ! command -v docker &> /dev/null; then curl -fsSL https://get.docker.com | bash; fi
        cd "$WORK_DIR"
        
        cat > Dockerfile <<EOF
FROM debian:bullseye-slim
RUN apt-get update && apt-get install -y dnsmasq sniproxy procps && apt-get clean
RUN echo '#!/bin/sh' > /entrypoint.sh && \\
    echo 'dnsmasq --no-daemon --conf-file=/etc/dnsmasq.conf &' >> /entrypoint.sh && \\
    echo 'sniproxy -c /etc/sniproxy.conf -f' >> /entrypoint.sh && \\
    chmod +x /entrypoint.sh
RUN echo 'port=53' > /etc/dnsmasq.conf && \\
    echo 'no-resolv' >> /etc/dnsmasq.conf && \\
    echo 'server=8.8.8.8' >> /etc/dnsmasq.conf && \\
    echo 'conf-dir=/etc/dnsmasq.d/,*.conf' >> /etc/dnsmasq.conf && \\
    echo 'cache-size=1000' >> /etc/dnsmasq.conf
ENTRYPOINT ["/entrypoint.sh"]
EOF
        cat > sniproxy.conf <<EOF
user daemon
pidfile /var/run/sniproxy.pid
resolver { nameserver 8.8.8.8; mode ipv4_only; }
error_log { filename /dev/stderr; priority notice; }
access_log { filename /dev/stdout; }
listen 80 { proto http; table http_hosts; }
listen 443 { proto tls; table https_hosts; }
table http_hosts { .* *; }
table https_hosts { .* *; }
EOF
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
        docker compose up -d --build --remove-orphans
    fi

    save_config
    echo -e "${GREEN}安装完成!${NC}"
    check_status
}

# 1. 修改解锁规则 (热更新)
modify_services() {
    if [ -z "$FINAL_IP" ]; then echo -e "${RED}请先安装!${NC}"; read -p "" _; return; fi
    echo -e "${SKY}>>> 修改解锁规则 (无需重装)${NC}"
    select_services_logic
    if [ "$DEPLOY_MODE" == "native" ]; then
        cp "$WORK_DIR/dnsmasq.conf" /etc/dnsmasq.d/unlock.conf
        systemctl restart dnsmasq
        echo -e "${GREEN}Native 服务已更新规则并重启${NC}"
    else
        cd "$WORK_DIR"
        docker compose restart
        echo -e "${GREEN}Docker 容器已重启并加载新规则${NC}"
    fi
    save_config
    echo -e "${YELLOW}提示: 请重新生成并复制 JSON 到 V2bX 面板${NC}"
    read -p "是否立即查看新 JSON? (y/n): " view_json
    if [[ "$view_json" == "y" ]]; then gen_json; fi
}

# 2. 重启服务
restart_services() {
    echo -e "${SKY}>>> 正在重启服务...${NC}"
    if [ "$DEPLOY_MODE" == "native" ]; then
        systemctl restart dnsmasq sniproxy
        if systemctl is-active dnsmasq >/dev/null; then
            echo -e "${GREEN}Native 服务重启成功${NC}"
        else
            echo -e "${RED}Native 服务启动失败，请检查日志${NC}"
        fi
    elif [ "$DEPLOY_MODE" == "docker" ]; then
        cd "$WORK_DIR"
        docker compose restart
        echo -e "${GREEN}Docker 容器已重启${NC}"
    else
        echo -e "${RED}未检测到安装模式${NC}"
    fi
    read -p "按回车返回..." _
}

# 3. 实时流量监控
monitor_traffic() {
    if [ -z "$DEPLOY_MODE" ]; then echo -e "${RED}请先安装!${NC}"; read -p "" _; return; fi
    clear
    echo -e "${SKY}>>> 实时流量监控 (Ctrl+C 退出)${NC}"
    echo -e "${YELLOW}显示格式: [来源IP] -> [目标域名]${NC}"
    echo -e "------------------------------------------------"
    
    if [ "$DEPLOY_MODE" == "docker" ]; then
        docker logs -f dns_unlock
    else
        if [ -f /var/log/sniproxy/access.log ]; then
            tail -f /var/log/sniproxy/access.log
        else
            echo -e "${RED}找不到日志文件: /var/log/sniproxy/access.log${NC}"
            read -p "按回车返回..." _
        fi
    fi
}

check_status() {
    install_base_tools
    clear
    echo -e "${SKY}>>> 系统状态检查 (实测模式)${NC}"
    echo -e "本机 IP: ${GREEN}${FINAL_IP:-未知}${NC}"
    
    check_port_active() {
        local port=$1
        local proto=$2
        if ss -"$proto"nlp | grep -q ":$port " || netstat -"$proto"nlp | grep -q ":$port "; then
             echo -e "端口 $port ($proto): ${GREEN}正常 (监听中)${NC}"
        else
             echo -e "端口 $port ($proto): ${RED}异常 (未监听)${NC}"
        fi
    }

    echo -e "\n端口状态:"
    check_port_active 53 u
    check_port_active 80 t
    check_port_active 443 t
    
    echo -e "\n功能实测:"
    if [ -n "$FINAL_IP" ]; then
        echo -n "DNS 劫持测试 (OpenAI): "
        TEST_DNS=$(dig +short @127.0.0.1 openai.com 2>/dev/null)
        if [ "$TEST_DNS" == "$FINAL_IP" ]; then
            echo -e "${GREEN}成功 (解析结果: $TEST_DNS)${NC}"
        else
            echo -e "${RED}失败 (解析结果: ${TEST_DNS:-无})${NC}"
        fi
        
        echo -n "Sniproxy 转发测试 (HTTP): "
        TEST_HTTP=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: whatismyip.akamai.com" http://127.0.0.1)
        if [[ "$TEST_HTTP" =~ ^(200|301|302|400|403|404)$ ]]; then
             echo -e "${GREEN}服务存活 (Code: $TEST_HTTP)${NC}"
        else
             echo -e "${RED}连接失败 (Code: ${TEST_HTTP:-超时})${NC}"
        fi
    fi
    read -p "按回车返回..." _
}

uninstall_all() {
    echo -e "${RED}正在卸载...${NC}"
    if command -v docker &> /dev/null; then docker rm -f dns_unlock sniproxy_unlock 2>/dev/null; fi
    systemctl stop dnsmasq sniproxy 2>/dev/null
    rm -rf "$WORK_DIR"
    echo -e "${GREEN}卸载完成${NC}"
    read -p "按回车返回..." _
}

gen_json() {
    if [ -z "$FINAL_IP" ]; then echo -e "${RED}请先安装!${NC}"; read -p "" _; return; fi
    if [[ "$FINAL_IP" == *":"* ]]; then IP_CIDR="${FINAL_IP}/128"; else IP_CIDR="${FINAL_IP}/32"; fi

    clear
    echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
    echo -e "${GREEN}   🎉 V2bX / NodePass 专用配置 (含审计)   ${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
    echo -e "解锁 IP: ${YELLOW}$FINAL_IP${NC}"
    echo -e "规则列表: ${SKY}${TYPE_NAME}${NC}\n"

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
    echo ""
    read -p "按回车返回菜单..." _
}

# ==========================================================
# 主菜单
# ==========================================================

while true; do
    clear
    echo -e "${SKY}==================================================${NC}"
    echo -e "${SKY}  V2bX 专用解锁服务总控 (V20.0 铁壁铜墙版)${NC}"
    echo -e "${SKY}==================================================${NC}\n"
    echo -e "${GREEN}当前 IP: ${FINAL_IP:-未安装}${NC}"
    echo -e "${GREEN}当前模式: ${DEPLOY_MODE:-未安装}${NC}\n"

    echo -e "${YELLOW}1) 安装 / 重装解锁服务${NC}"
    echo -e "${YELLOW}2) 设置白名单 IP (防火墙安全)${NC}"
    echo -e "${YELLOW}3) 生成 V2bX/Sing-box JSON 配置${NC}"
    echo -e "${YELLOW}4) 查看运行状态${NC}"
    echo -e "${BLUE}5) 实时流量监控${NC}"
    echo -e "${BLUE}6) 修改解锁规则 (热更新)${NC}"
    echo -e "${BLUE}7) 重启服务${NC}"
    echo -e "${RED}8) 卸载服务${NC}"
    echo -e "${RED}0) 退出${NC}"
    echo ""
    read -p ">> " choice

    case "$choice" in
        1) run_install ;;
        2) fw_settings ;;
        3) gen_json ;;
        4) check_status ;;
        5) monitor_traffic ;;
        6) modify_services ;;
        7) restart_services ;;
        8) uninstall_all ;;
        0) exit 0 ;;
        *) ;;
    esac
done
