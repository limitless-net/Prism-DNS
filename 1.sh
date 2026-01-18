#!/bin/bash
# ==========================================================
#   V2bX 专用解锁服务总控脚本 (V7.0 终极UI版)
#   功能：
#     1. 交互式菜单 UI，管理所有功能
#     2. 修复 DNS 劫持逻辑 (强制解析为公网 IP)
#     3. 动态管理白名单 IP (随时添加/删除)
#     4. 内置 Docker/原生 双模式
#     5. 自动生成 V2bX 审计版 JSON
# ==========================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
SKY='\033[0;36m'
NC='\033[0m'

WORK_DIR="/root/dns_unlock"
WHITELIST_FILE="$WORK_DIR/whitelist.txt"
CONFIG_INFO_FILE="$WORK_DIR/install_info.conf"

# ==========================================================
# 基础工具
# ==========================================================

# 检查 Root
check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo -e "${RED}错误: 必须使用 root 权限运行此脚本${NC}"
        exit 1
    fi
}

# IP 格式验证
validate_ip() {
    local ip="$1"
    if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then return 0; fi
    if [[ "$ip" =~ ^[0-9a-fA-F:]+$ ]] && [[ "$ip" == *:* ]]; then return 0; fi
    return 1
}

# 自动检测公网 IP
detect_public_ip() {
    if [ -f "$CONFIG_INFO_FILE" ]; then
        source "$CONFIG_INFO_FILE"
    fi
    
    if [ -z "$SERVER_IP" ]; then
        echo -e "${YELLOW}正在检测本机公网 IP...${NC}"
        SERVER_IP=$(curl -4 -s --max-time 5 api.ip.sb/ip || curl -4 -s --max-time 5 ifconfig.me)
        if [ -z "$SERVER_IP" ]; then
            SERVER_IP=$(curl -6 -s --max-time 5 api.ip.sb/ip)
        fi
    fi
}

# 保存安装信息
save_config() {
    mkdir -p "$WORK_DIR"
    echo "SERVER_IP=\"$SERVER_IP\"" > "$CONFIG_INFO_FILE"
    echo "DEPLOY_MODE=\"$DEPLOY_MODE\"" >> "$CONFIG_INFO_FILE"
    echo "SERVICES=\"$SERVICES\"" >> "$CONFIG_INFO_FILE"
}

# ==========================================================
# 核心安装逻辑
# ==========================================================

install_environment() {
    echo -e "\n${SKY}>>> 选择部署模式${NC}"
    echo "1. Docker 模式 (推荐，环境隔离)"
    echo "2. 原生模式 (省内存，适合 < 512MB 机器)"
    read -p "选择 [1-2] (默认1): " mode_opt
    
    if [ "$mode_opt" == "2" ]; then
        DEPLOY_MODE="native"
        echo -e "${YELLOW}正在安装原生依赖 (dnsmasq + sniproxy)...${NC}"
        apt-get update -y && apt-get install -y dnsmasq sniproxy
        systemctl stop dnsmasq sniproxy systemd-resolved 2>/dev/null || true
    else
        DEPLOY_MODE="docker"
        if ! command -v docker &> /dev/null; then
            echo -e "${YELLOW}正在安装 Docker...${NC}"
            curl -fsSL https://get.docker.com | bash
            systemctl enable docker --now
        fi
        if ! docker compose version &> /dev/null; then
            apt-get install -y docker-compose-plugin
        fi
    fi
}

configure_services() {
    echo -e "\n${SKY}>>> 选择解锁服务${NC}"
    echo "1. ChatGPT + AI (OpenAI/Gemini/Copilot)"
    echo "2. Netflix"
    echo "3. Disney+"
    echo "4. TikTok"
    echo "5. YouTube"
    echo "6. Spotify/HBO/Prime"
    echo "a. 全选 (推荐)"
    read -p "输入数字(逗号分隔) 或 a: " svc_in
    
    if [[ "$svc_in" == "a" || "$svc_in" == "A" ]]; then
        SERVICES="1,2,3,4,5,6"
    else
        SERVICES="$svc_in"
    fi
    
    # 再次确认 IP，防止 DNS 劫持到内网
    if [ -z "$SERVER_IP" ]; then
        read -p "未检测到IP，请手动输入本机公网IP: " SERVER_IP
    else
        echo -e "本机公网 IP: ${GREEN}$SERVER_IP${NC}"
        read -p "确认使用此 IP 进行 DNS 劫持吗? [Y/n]: " ip_conf
        if [[ "$ip_conf" =~ ^[Nn]$ ]]; then
            read -p "请输入正确的公网 IP: " SERVER_IP
        fi
    fi

    # 生成配置文件
    mkdir -p "$WORK_DIR"
    cd "$WORK_DIR"
    
    # 生成 Dnsmasq 规则
    # 关键修复：这里的 IP 必须是 SERVER_IP，绝不能是 127.0.0.1
    echo "# Generated Config" > dnsmasq_rules.conf
    
    FINAL_JSON_LIST=""
    add_rule() {
        local d=$1
        echo "address=/$d/$SERVER_IP" >> dnsmasq_rules.conf
        [ -n "$FINAL_JSON_LIST" ] && FINAL_JSON_LIST="$FINAL_JSON_LIST, "
        FINAL_JSON_LIST="${FINAL_JSON_LIST}\"$d\""
    }
    
    if [[ $SERVICES == *"1"* ]]; then for d in openai.com chatgpt.com oaistatic.com oaiusercontent.com ai.com gemini.google.com bard.google.com copilot.microsoft.com bing.com; do add_rule $d; done; fi
    if [[ $SERVICES == *"2"* ]]; then for d in netflix.com netflix.net nflxvideo.net nflximg.net nflxext.com nflxso.net; do add_rule $d; done; fi
    if [[ $SERVICES == *"3"* ]]; then for d in disney.com disneyplus.com dssott.com bamgrid.com; do add_rule $d; done; fi
    if [[ $SERVICES == *"4"* ]]; then for d in tiktok.com tiktokv.com tiktokcdn.com musical.ly; do add_rule $d; done; fi
    if [[ $SERVICES == *"5"* ]]; then for d in youtube.com googlevideo.com ytimg.com ggpht.com; do add_rule $d; done; fi
    if [[ $SERVICES == *"6"* ]]; then for d in spotify.com hbomax.com hbo.com max.com amazonvideo.com primevideo.com; do add_rule $d; done; fi

    # 生成 Sniproxy 配置
    cat > sniproxy.conf <<EOF
user daemon
pidfile /var/run/sniproxy.pid
error_log {
    filename /dev/stderr
    priority notice
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

    # 启动服务
    if [ "$DEPLOY_MODE" = "docker" ]; then
        # 生成 Dockerfile
        cat > Dockerfile <<EOF
FROM alpine:latest
RUN apk add --no-cache dnsmasq sniproxy
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
        docker compose down 2>/dev/null
        docker compose up -d --build
    else
        # 原生模式
        cat > /etc/dnsmasq.conf <<EOF
port=53
no-resolv
server=8.8.8.8
conf-dir=/etc/dnsmasq.d/,*.conf
cache-size=1000
EOF
        mkdir -p /etc/dnsmasq.d /var/log/sniproxy
        cp dnsmasq_rules.conf /etc/dnsmasq.d/unlock.conf
        sed -i 's|/dev/stderr|/var/log/sniproxy/error.log|g' sniproxy.conf
        cp sniproxy.conf /etc/sniproxy.conf
        systemctl restart dnsmasq sniproxy
        systemctl enable dnsmasq sniproxy
    fi

    save_config
    echo -e "${GREEN}>>> 服务部署完成!${NC}"
}

# ==========================================================
# 防火墙管理 (白名单)
# ==========================================================

manage_firewall() {
    echo -e "\n${SKY}>>> 管理防火墙白名单 IP${NC}"
    
    # 读取现有白名单
    touch "$WHITELIST_FILE"
    CURRENT_IPS=$(cat "$WHITELIST_FILE")
    
    echo -e "当前允许的 IP 列表:"
    if [ -z "$CURRENT_IPS" ]; then
        echo -e "${YELLOW}(空) - 建议尽快添加落地机 IP，否则任何人都能盗用${NC}"
    else
        echo -e "${GREEN}$CURRENT_IPS${NC}"
    fi
    
    echo -e "\n操作选择:"
    echo "1. 添加 IP"
    echo "2. 清空重置所有 IP"
    echo "3. 返回主菜单"
    read -p "选择: " fw_opt
    
    if [ "$fw_opt" == "3" ]; then return; fi
    
    if [ "$fw_opt" == "2" ]; then
        > "$WHITELIST_FILE"
        echo -e "${YELLOW}白名单已清空${NC}"
    fi
    
    if [ "$fw_opt" == "1" ]; then
        echo "请输入 IP (多个 IP 用空格分隔):"
        read -p "IP: " new_ips
        for ip in $new_ips; do
            if validate_ip "$ip"; then
                echo "$ip" >> "$WHITELIST_FILE"
            else
                echo -e "${RED}忽略无效 IP: $ip${NC}"
            fi
        done
    fi
    
    # 应用规则
    echo -e "${YELLOW}正在刷新防火墙规则...${NC}"
    IPS=$(cat "$WHITELIST_FILE" | sort | uniq)
    
    if command -v ufw &> /dev/null; then
        ufw allow ssh >/dev/null 2>&1
        ufw allow 22/tcp >/dev/null 2>&1
        echo "y" | ufw enable >/dev/null 2>&1
        
        # 清理旧的
        ufw delete allow 53/tcp >/dev/null 2>&1
        ufw delete allow 53/udp >/dev/null 2>&1
        ufw delete allow 80/tcp >/dev/null 2>&1
        ufw delete allow 443/tcp >/dev/null 2>&1
        
        for ip in $IPS; do
            ufw allow from "$ip" to any port 53 >/dev/null 2>&1
            ufw allow from "$ip" to any port 80 >/dev/null 2>&1
            ufw allow from "$ip" to any port 443 >/dev/null 2>&1
        done
        ufw reload >/dev/null 2>&1
        
    else
        # iptables
        iptables -A INPUT -p tcp --dport 22 -j ACCEPT
        iptables -N UNLOCK_LIMIT 2>/dev/null || iptables -F UNLOCK_LIMIT
        iptables -D INPUT -j UNLOCK_LIMIT 2>/dev/null || true
        iptables -I INPUT -j UNLOCK_LIMIT
        
        for ip in $IPS; do
            iptables -A UNLOCK_LIMIT -s "$ip" -p tcp --dport 53 -j ACCEPT
            iptables -A UNLOCK_LIMIT -s "$ip" -p udp --dport 53 -j ACCEPT
            iptables -A UNLOCK_LIMIT -s "$ip" -p tcp --dport 80 -j ACCEPT
            iptables -A UNLOCK_LIMIT -s "$ip" -p tcp --dport 443 -j ACCEPT
        done
        
        iptables -A UNLOCK_LIMIT -p tcp --dport 53 -j DROP
        iptables -A UNLOCK_LIMIT -p udp --dport 53 -j DROP
        iptables -A UNLOCK_LIMIT -p tcp --dport 80 -j DROP
        iptables -A UNLOCK_LIMIT -p tcp --dport 443 -j DROP
    fi
    
    echo -e "${GREEN}>>> 防火墙规则已更新${NC}"
    read -p "按回车继续..."
}

# ==========================================================
# 状态检查 & JSON 生成
# ==========================================================

check_status() {
    clear
    echo -e "${SKY}>>> 系统状态检查${NC}"
    echo -e "本机 IP: ${GREEN}$SERVER_IP${NC}"
    echo -e "部署模式: ${YELLOW}${DEPLOY_MODE:-未知}${NC}"
    
    echo -e "\n端口监听状态:"
    for p in 53 80 443; do
        if ss -tuln | grep -q ":$p "; then
            echo -e "端口 $p: ${GREEN}正常 (监听中)${NC}"
        else
            echo -e "端口 $p: ${RED}异常 (未监听)${NC}"
        fi
    done
    
    echo -e "\n服务运行状态:"
    if [ "$DEPLOY_MODE" == "docker" ]; then
        if docker ps | grep -q "dns_unlock"; then echo -e "Docker 容器: ${GREEN}运行中${NC}"; else echo -e "Docker 容器: ${RED}停止${NC}"; fi
    else
        systemctl is-active dnsmasq >/dev/null && echo -e "Dnsmasq: ${GREEN}运行中${NC}" || echo -e "Dnsmasq: ${RED}停止${NC}"
        systemctl is-active sniproxy >/dev/null && echo -e "Sniproxy: ${GREEN}运行中${NC}" || echo -e "Sniproxy: ${RED}停止${NC}"
    fi
    
    read -p "按回车返回..."
}

generate_v2bx_json() {
    # 必须先重新构建一下 DOMAIN 列表，因为这部分逻辑在 install 里
    # 这里为了简化，直接读取配置文件里的 rules
    if [ ! -f "$WORK_DIR/dnsmasq_rules.conf" ]; then
        echo -e "${RED}未找到配置文件，请先安装服务！${NC}"
        read -p "按回车返回..."
        return
    fi
    
    # 从配置文件提取域名列表 (hacky but works)
    DOMAINS_JSON=$(grep "address=/" "$WORK_DIR/dnsmasq_rules.conf" | cut -d/ -f2 | awk '{printf "\"%s\", ", $0}' | sed 's/, $//')
    
    # CIDR
    if [[ "$SERVER_IP" == *":"* ]]; then CIDR="${SERVER_IP}/128"; else CIDR="${SERVER_IP}/32"; fi
    
    clear
    echo -e "${SKY}>>> V2bX / Sing-box 专用配置 (含审计规则)${NC}"
    echo -e "${YELLOW}请将下方 JSON 复制到 V2bX 后端模版中：${NC}"
    echo ""
    cat <<EOF
{
  "dns": {
    "servers": [
      {
        "tag": "unlock_dns",
        "address": "${SERVER_IP}",
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
        "domain_suffix": [${DOMAINS_JSON}],
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
      { "domain_suffix": [${DOMAINS_JSON}], "outbound": "direct" },
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
    read -p "按回车返回..."
}

uninstall_all() {
    echo -e "${RED}警告: 即将删除所有服务和文件！${NC}"
    read -p "确认吗? [y/N]: " conf
    if [[ "$conf" =~ ^[Yy]$ ]]; then
        if command -v docker &> /dev/null; then docker rm -f dns_unlock 2>/dev/null; fi
        systemctl stop dnsmasq sniproxy 2>/dev/null
        rm -rf "$WORK_DIR"
        rm -f /etc/dnsmasq.d/unlock.conf
        echo -e "${GREEN}已卸载。防火墙规则建议保留以免失联，如需清理请手动执行 iptables/ufw 命令。${NC}"
    fi
    read -p "按回车返回..."
}

# ==========================================================
# 主菜单循环
# ==========================================================

check_root
detect_public_ip

while true; do
    clear
    echo -e "${SKY}==================================================${NC}"
    echo -e "${SKY}   V2bX 机场专用解锁总控脚本 (V7.0 终极版)${NC}"
    echo -e "${SKY}   本机 IP: ${GREEN}${SERVER_IP}${NC}"
    echo -e "${SKY}==================================================${NC}\n"
    
    echo -e "${YELLOW}1) 安装 / 重装解锁服务 (Docker/原生)${NC}"
    echo -e "${YELLOW}2) 管理白名单 IP (防火墙安全设置)${NC}"
    echo -e "${YELLOW}3) 查看运行状态${NC}"
    echo -e "${YELLOW}4) 生成 V2bX/Sing-box JSON 配置${NC}"
    echo -e "${RED}5) 卸载服务${NC}"
    echo -e "${RED}0) 退出${NC}"
    echo ""
    read -p "请选择 [0-5]: " choice
    
    case "$choice" in
        1) install_environment; configure_services ;;
        2) manage_firewall ;;
        3) check_status ;;
        4) generate_v2bx_json ;;
        5) uninstall_all ;;
        0) exit 0 ;;
        *) echo "无效选项" ;;
    esac
done
