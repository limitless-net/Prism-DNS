#!/bin/bash
# ==========================================================
#   V2bX 专用解锁服务总控脚本 (V28.0 逻辑重构版)
#   
#   修复核心：
#   1. [重构] 废弃 install.env 缓存域名列表的逻辑，改为现场生成
#   2. [移除] 移除了导致 JSON 语法错误的复杂 Regex 审计规则
#   3. [回归] 配置生成逻辑回归 V18 极简风格，确保 100% 可用
# ==========================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
SKY='\033[0;36m'
NC='\033[0m'

WORK_DIR="/root/dns_unlock"
CONFIG_FILE="$WORK_DIR/install.env"
WHITELIST_FILE="$WORK_DIR/whitelist.txt"

mkdir -p "$WORK_DIR"
touch "$WHITELIST_FILE"

# 加载配置
if [ -f "$CONFIG_FILE" ]; then source "$CONFIG_FILE"; fi

# ==========================================================
# 基础工具
# ==========================================================

check_root() {
    if [ "$(id -u)" != "0" ]; then echo -e "${RED}错误: 需 root 权限${NC}"; exit 1; fi
}

install_base_tools() {
    if ! command -v netstat &> /dev/null || ! command -v dig &> /dev/null || ! command -v lsof &> /dev/null; then
        echo -e "${YELLOW}>>> 补全基础工具...${NC}"
        if [ -f /etc/debian_version ]; then apt-get update -y && apt-get install -y net-tools dnsutils lsof procps; 
        elif [ -f /etc/redhat-release ]; then yum install -y net-tools bind-utils lsof; fi
    fi
}

validate_ip() {
    local ip="$1"
    ip=$(echo "$ip" | tr -d '[:space:]')
    if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then return 0; fi
    if [[ "$ip" =~ ^[0-9a-fA-F:]+$ ]]; then return 0; fi
    return 1
}

# 只保存简单的变量，不保存复杂字符串
save_config() {
    echo "FINAL_IP=\"$FINAL_IP\"" > "$CONFIG_FILE"
    echo "DEPLOY_MODE=\"$DEPLOY_MODE\"" >> "$CONFIG_FILE"
    echo "SELECTED_SERVICES=\"$SELECTED_SERVICES\"" >> "$CONFIG_FILE"
}

# ==========================================================
# 端口清理
# ==========================================================

kill_port_process() {
    local port=$1
    pids=$(lsof -t -i:$port 2>/dev/null || netstat -nlp | grep ":$port " | awk '{print $7}' | cut -d'/' -f1)
    if [ -n "$pids" ]; then for pid in $pids; do kill -9 $pid 2>/dev/null; done; fi
}

force_cleanup() {
    echo -e "${YELLOW}>>> 清理环境...${NC}"
    if command -v docker &> /dev/null; then
        docker rm -f dns_unlock sniproxy_unlock 2>/dev/null
        cd "$WORK_DIR" 2>/dev/null && docker compose down --remove-orphans 2>/dev/null
    fi
    systemctl stop nginx apache2 caddy systemd-resolved dnsmasq sniproxy 2>/dev/null
    systemctl disable nginx apache2 caddy systemd-resolved 2>/dev/null
    kill_port_process 53; kill_port_process 80; kill_port_process 443
    rm -f /etc/resolv.conf
    echo "nameserver 8.8.8.8" > /etc/resolv.conf
}

# ==========================================================
# 核心安装逻辑 (V18 Debian版)
# ==========================================================

run_install() {
    check_root
    install_base_tools
    force_cleanup
    
    IPV4=$(curl -4s --max-time 3 api.ip.sb/ip || curl -4s --max-time 3 ifconfig.me)
    echo -e "\n${SKY}本机 IP: ${GREEN}${IPV4:-未知}${NC}"
    read -p "确认 IP? (y/n): " ip_conf
    if [[ "$ip_conf" == "n" ]]; then read -p "输入IP: " FINAL_IP; else FINAL_IP=$IPV4; fi
    if [ -z "$FINAL_IP" ]; then echo -e "${RED}IP 无效${NC}"; return; fi

    echo -e "\n${SKY}1. Docker (推荐)  2. 原生模式${NC}"
    read -p "选择: " MODE_OPT
    if [ "$MODE_OPT" == "2" ]; then DEPLOY_MODE="native"; else DEPLOY_MODE="docker"; fi

    echo -e "\n${SKY}可用服务: 1.GPT 2.Netflix 3.Disney+ 4.TikTok 5.YouTube 6.Spotify${NC}"
    echo "a. 全选 (推荐)"
    read -p "选择: " SERVICE_CHOICE
    if [[ "$SERVICE_CHOICE" == "a" ]]; then SERVICE_CHOICE="1,2,3,4,5,6"; fi
    
    # 保存选择的 ID，而不是字符串
    SELECTED_SERVICES="$SERVICE_CHOICE"

    # 生成 Dnsmasq 配置
    mkdir -p "$WORK_DIR"
    > "$WORK_DIR/dnsmasq.conf"
    
    # 定义域名列表
    D_GPT="openai.com chatgpt.com oaistatic.com oaiusercontent.com ai.com"
    D_NF="netflix.com netflix.net nflxvideo.net nflximg.net nflxext.com"
    D_DISNEY="disney.com disneyplus.com dssott.com bamgrid.com"
    D_TIKTOK="tiktok.com tiktokv.com tiktokcdn.com musical.ly"
    D_YT="youtube.com googlevideo.com ytimg.com ggpht.com"
    D_SPOTIFY="spotify.com scdn.co spotifycdn.com"

    IFS=',' read -ra SVS <<< "$SELECTED_SERVICES"
    for s in "${SVS[@]}"; do
        case $s in
            1) LIST="$D_GPT";; 2) LIST="$D_NF";; 3) LIST="$D_DISNEY";;
            4) LIST="$D_TIKTOK";; 5) LIST="$D_YT";; 6) LIST="$D_SPOTIFY";;
        esac
        for d in $LIST; do echo "address=/$d/$FINAL_IP" >> "$WORK_DIR/dnsmasq.conf"; done
    done

    # 部署服务
    if [ "$DEPLOY_MODE" == "native" ]; then
        apt-get update && apt-get install -y dnsmasq sniproxy
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
        cat > /etc/sniproxy.conf <<EOF
user daemon
pidfile /var/run/sniproxy.pid
resolver { nameserver 8.8.8.8; mode ipv4_only; }
listen 80 { proto http; table http_hosts; }
listen 443 { proto tls; table https_hosts; }
table http_hosts { .* *; }
table https_hosts { .* *; }
EOF
        systemctl restart dnsmasq sniproxy
        systemctl enable dnsmasq sniproxy
    else
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

    if [ -s "$WHITELIST_FILE" ]; then apply_firewall; fi
    save_config
    echo -e "${GREEN}安装完成!${NC}"
    check_status
}

# ==========================================================
# 白名单管理
# ==========================================================

apply_firewall() {
    echo -e "${YELLOW}>>> 刷新防火墙规则...${NC}"
    sed -i 's/\r//g' "$WHITELIST_FILE"; sed -i '/^$/d' "$WHITELIST_FILE"
    local ips=$(cat "$WHITELIST_FILE")
    
    if command -v ufw &> /dev/null; then
        ufw allow ssh; ufw allow 22/tcp
        ufw delete allow 53/tcp; ufw delete allow 53/udp
        ufw delete allow 80/tcp; ufw delete allow 443/tcp
        for ip in $ips; do
            if validate_ip "$ip"; then ufw allow from "$ip" to any; fi
        done
        echo "y" | ufw enable; ufw reload
    else
        iptables -N UNLOCK_FW 2>/dev/null; iptables -F UNLOCK_FW 
        while iptables -D INPUT -j UNLOCK_FW 2>/dev/null; do :; done
        iptables -I INPUT -j UNLOCK_FW
        iptables -A UNLOCK_FW -i lo -j ACCEPT
        iptables -A UNLOCK_FW -s 127.0.0.1 -j ACCEPT
        for ip in $ips; do
            if validate_ip "$ip"; then
                iptables -A UNLOCK_FW -s "$ip" -p tcp --dport 53 -j ACCEPT
                iptables -A UNLOCK_FW -s "$ip" -p udp --dport 53 -j ACCEPT
                iptables -A UNLOCK_FW -s "$ip" -p tcp --dport 80 -j ACCEPT
                iptables -A UNLOCK_FW -s "$ip" -p tcp --dport 443 -j ACCEPT
            fi
        done
        iptables -A UNLOCK_FW -p tcp --dport 53 -j DROP
        iptables -A UNLOCK_FW -p udp --dport 53 -j DROP
        iptables -A UNLOCK_FW -p tcp --dport 80 -j DROP
        iptables -A UNLOCK_FW -p tcp --dport 443 -j DROP
        iptables -A UNLOCK_FW -j RETURN
    fi
    echo -e "${GREEN}规则已生效${NC}"
}

manage_whitelist() {
    while true; do
        clear
        echo -e "${SKY}>>> 白名单管理${NC}"
        if [ -s "$WHITELIST_FILE" ]; then
            cat -n "$WHITELIST_FILE" | sed "s/^/  ${GREEN}/;s/$/${NC}/"
        else echo -e "  ${RED}(空)${NC}"; fi
        echo -e "${YELLOW}1) 添加 IP${NC}"
        echo -e "${YELLOW}2) 删除 IP${NC}"
        echo -e "${YELLOW}3) 立即应用${NC}"
        echo -e "${RED}0) 返回${NC}"
        read -p ">> " c
        case "$c" in
            1) read -p "IP: " nip; for i in $nip; do echo "$i" >> "$WHITELIST_FILE"; done; sort -u "$WHITELIST_FILE" -o "$WHITELIST_FILE";;
            2) read -p "删除IP: " dip; sed -i "/^$dip$/d" "$WHITELIST_FILE";;
            3) apply_firewall; return;;
            0) return;;
        esac
    done
}

# ==========================================================
# 状态与配置生成
# ==========================================================

check_status() {
    install_base_tools
    clear
    echo -e "${SKY}>>> 状态检查${NC}"
    check_p() { if ss -"$2"nlp | grep -q ":$1 "; then echo -e "端口 $1: ${GREEN}正常${NC}"; else echo -e "端口 $1: ${RED}异常${NC}"; fi; }
    check_p 53 u; check_p 80 t; check_p 443 t
    
    if [ -n "$FINAL_IP" ]; then
        RES=$(dig +short @127.0.0.1 openai.com)
        if [ "$RES" == "$FINAL_IP" ]; then echo -e "DNS劫持: ${GREEN}成功${NC}"; else echo -e "DNS劫持: ${RED}失败${NC}"; fi
    fi
    read -p "按回车返回..." _
}

gen_json() {
    if [ -z "$FINAL_IP" ] || [ -z "$SELECTED_SERVICES" ]; then echo -e "${RED}请先安装!${NC}"; read -p "" _; return; fi
    
    # 现场重建 JSON 列表，确保数据绝对新鲜
    J_GPT='"openai.com", "chatgpt.com", "oaistatic.com", "oaiusercontent.com", "ai.com"'
    J_NF='"netflix.com", "netflix.net", "nflxvideo.net", "nflximg.net", "nflxext.com"'
    J_DISNEY='"disney.com", "disneyplus.com", "dssott.com", "bamgrid.com"'
    J_TIKTOK='"tiktok.com", "tiktokv.com", "tiktokcdn.com", "musical.ly"'
    J_YT='"youtube.com", "googlevideo.com", "ytimg.com", "ggpht.com"'
    J_SPOTIFY='"spotify.com", "scdn.co", "spotifycdn.com"'
    
    FINAL_JSON_LIST=""
    IFS=',' read -ra SVS <<< "$SELECTED_SERVICES"
    for s in "${SVS[@]}"; do
        case $s in
            1) ITEM="$J_GPT";; 2) ITEM="$J_NF";; 3) ITEM="$J_DISNEY";;
            4) ITEM="$J_TIKTOK";; 5) ITEM="$J_YT";; 6) ITEM="$J_SPOTIFY";;
        esac
        [ -n "$FINAL_JSON_LIST" ] && FINAL_JSON_LIST="$FINAL_JSON_LIST, "
        FINAL_JSON_LIST="${FINAL_JSON_LIST}${ITEM}"
    done

    clear
    echo -e "${GREEN}>>> V2bX / NodePass 配置${NC}"
    cat <<EOF
{
  "dns": {
    "servers": [
      { "tag": "unlock_dns", "address": "tcp://${FINAL_IP}", "address_resolver": "local_dns", "detour": "direct" },
      { "tag": "local_dns", "address": "1.1.1.1", "detour": "direct" }
    ],
    "rules": [
      { "domain_suffix": [${FINAL_JSON_LIST}], "server": "unlock_dns", "disable_cache": true, "query_type": ["A"] }
    ],
    "final": "local_dns",
    "strategy": "prefer_ipv4"
  },
  "outbounds": [
    { "tag": "direct", "type": "direct", "domain_strategy": "prefer_ipv4" },
    { "tag": "block", "type": "block" }
  ],
  "route": {
    "rules": [
      { "protocol": "dns", "outbound": "direct" },
      { "ip_cidr": ["${FINAL_IP}/32"], "outbound": "direct" },
      { "domain_suffix": [${FINAL_JSON_LIST}], "outbound": "direct" },
      { "ip_is_private": true, "outbound": "block" },
      { "protocol": "quic", "outbound": "block" }
    ],
    "auto_detect_interface": false
  }
}
EOF
    read -p "按回车返回..." _
}

# --- 辅助 ---
monitor_traffic() { if [ "$DEPLOY_MODE" == "docker" ]; then docker logs -f dns_unlock; else tail -f /var/log/sniproxy/access.log; fi }
restart_services() { if [ "$DEPLOY_MODE" == "native" ]; then systemctl restart dnsmasq sniproxy; else cd "$WORK_DIR" && docker compose restart; fi; echo "已重启"; }
uninstall_all() {
    if command -v docker &> /dev/null; then docker rm -f dns_unlock sniproxy_unlock 2>/dev/null; fi
    systemctl stop dnsmasq sniproxy 2>/dev/null
    iptables -D INPUT -j UNLOCK_FW 2>/dev/null; iptables -F UNLOCK_FW 2>/dev/null; iptables -X UNLOCK_FW 2>/dev/null
    rm -rf "$WORK_DIR"
    echo -e "${GREEN}卸载完成${NC}"
}

# --- 循环 ---
while true; do
    clear
    echo -e "${SKY}== V2bX 解锁总控 (V28.0 重构版) ==${NC}"
    echo -e "${GREEN}IP: ${FINAL_IP:-无} | 模式: ${DEPLOY_MODE:-无}${NC}\n"
    echo -e "${YELLOW}1) 安装/重装服务${NC}"
    echo -e "${YELLOW}2) 管理白名单${NC}"
    echo -e "${YELLOW}3) 生成 JSON 配置${NC}"
    echo -e "${YELLOW}4) 查看状态${NC}"
    echo -e "${YELLOW}5) 实时流量${NC}"
    echo -e "${YELLOW}6) 重启服务${NC}"
    echo -e "${RED}9) 卸载服务${NC}"
    echo -e "${RED}0) 退出${NC}"
    read -p ">> " c
    case "$c" in
        1) run_install ;; 2) manage_whitelist ;; 3) gen_json ;; 4) check_status ;; 5) monitor_traffic ;; 6) restart_services ;; 9) uninstall_all ;; 0) exit ;;
    esac
done
