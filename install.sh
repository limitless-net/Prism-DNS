#!/bin/bash
# ==========================================================
#   V2bX 专用解锁服务总控脚本 (V22.6 强制封锁版)
#   
#   更新日志 (V22.6):
#   1. [高危修复] 修复白名单不生效问题 (采用强制置顶策略)
#   2. [新增] 增加 Gemini (aistudio.google.com) 支持
#   3. [工具] 增加防火墙生效自检工具
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
    if ! command -v netstat &> /dev/null || ! command -v dig &> /dev/null || ! command -v iptables &> /dev/null; then
        echo -e "${YELLOW}>>> 补全基础工具...${NC}"
        if [ -f /etc/debian_version ]; then
            apt-get update -y && apt-get install -y net-tools dnsutils lsof procps iptables
        elif [ -f /etc/redhat-release ]; then
            yum install -y net-tools bind-utils lsof iptables-services
        fi
    fi
}

validate_ip() {
    local ip="$1"
    ip=$(echo "$ip" | tr -d '[:space:]')
    if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then echo "v4"; return 0; fi
    if [[ "$ip" =~ ^[0-9a-fA-F:]+$ ]]; then echo "v6"; return 0; fi
    return 1
}

save_config() {
    echo "FINAL_IP=\"$FINAL_IP\"" > "$CONFIG_FILE"
    echo "DEPLOY_MODE=\"$DEPLOY_MODE\"" >> "$CONFIG_FILE"
    echo "FINAL_JSON_LIST='$FINAL_JSON_LIST'" >> "$CONFIG_FILE"
    echo "TYPE_NAME='$TYPE_NAME'" >> "$CONFIG_FILE"
}

# ==========================================================
# 强力防火墙 (修复版)
# ==========================================================

clean_whitelist_file() {
    [ -f "$WHITELIST_FILE" ] || touch "$WHITELIST_FILE"
    sed -i 's/\r//g' "$WHITELIST_FILE"
    sed -i 's/^[ \t]*//;s/[ \t]*$//' "$WHITELIST_FILE"
    sed -i '/^$/d' "$WHITELIST_FILE"
}

apply_firewall() {
    echo -e "${YELLOW}>>> 正在执行强制封锁策略...${NC}"
    clean_whitelist_file
    local ips
    ips=$(cat "$WHITELIST_FILE")

    # 1. 停用干扰服务
    if systemctl is-active --quiet firewalld; then
        echo -e "${YELLOW}警告: 停止 firewalld 以确保规则生效...${NC}"
        systemctl stop firewalld
        systemctl disable firewalld >/dev/null 2>&1
    fi

    # 2. 清理旧规则 (核弹模式：删除所有 INPUT 链中涉及 53/80/443 的规则)
    # 避免规则重复叠加
    iptables -D INPUT -j UNLOCK_FW 2>/dev/null
    while iptables -D INPUT -j UNLOCK_FW 2>/dev/null; do :; done
    iptables -F UNLOCK_FW 2>/dev/null
    iptables -X UNLOCK_FW 2>/dev/null

    # 3. 创建新链
    iptables -N UNLOCK_FW
    
    # 4. 放行白名单 IP
    for ip in $ips; do
        ip_type=$(validate_ip "$ip")
        if [ "$ip_type" == "v4" ]; then
            iptables -A UNLOCK_FW -s "$ip" -j ACCEPT
            echo -e "放行(IPv4): ${GREEN}$ip${NC}"
        fi
    done

    # 5. 放行本机 (回环) 和 已建立连接
    iptables -A UNLOCK_FW -s 127.0.0.1 -j ACCEPT
    # 关键：允许本机公网IP访问自己，防止你在本机测试时以为不通
    if [ -n "$FINAL_IP" ]; then iptables -A UNLOCK_FW -s "$FINAL_IP" -j ACCEPT; fi
    iptables -A UNLOCK_FW -m state --state RELATED,ESTABLISHED -j ACCEPT
    
    # 6. 拦截核心端口 (53/80/443)，其他端口(22) RETURN 回主链
    iptables -A UNLOCK_FW -p tcp --dport 53 -j DROP
    iptables -A UNLOCK_FW -p udp --dport 53 -j DROP
    iptables -A UNLOCK_FW -p tcp --dport 80 -j DROP
    iptables -A UNLOCK_FW -p tcp --dport 443 -j DROP
    iptables -A UNLOCK_FW -j RETURN

    # 7. 强制插入到 INPUT 第一位 (防止 Docker 规则抢占)
    iptables -I INPUT 1 -j UNLOCK_FW

    # --- IPv6 处理 ---
    if command -v ip6tables &> /dev/null; then
        ip6tables -D INPUT -j UNLOCK_FW6 2>/dev/null
        while ip6tables -D INPUT -j UNLOCK_FW6 2>/dev/null; do :; done
        ip6tables -F UNLOCK_FW6 2>/dev/null
        ip6tables -X UNLOCK_FW6 2>/dev/null
        
        ip6tables -N UNLOCK_FW6
        for ip in $ips; do
            ip_type=$(validate_ip "$ip")
            if [ "$ip_type" == "v6" ]; then
                ip6tables -A UNLOCK_FW6 -s "$ip" -j ACCEPT
                echo -e "放行(IPv6): ${GREEN}$ip${NC}"
            fi
        done
        ip6tables -A UNLOCK_FW6 -s ::1 -j ACCEPT
        ip6tables -A UNLOCK_FW6 -m state --state RELATED,ESTABLISHED -j ACCEPT
        ip6tables -A UNLOCK_FW6 -p tcp --dport 53 -j DROP
        ip6tables -A UNLOCK_FW6 -p udp --dport 53 -j DROP
        ip6tables -A UNLOCK_FW6 -p tcp --dport 80 -j DROP
        ip6tables -A UNLOCK_FW6 -p tcp --dport 443 -j DROP
        ip6tables -A UNLOCK_FW6 -j RETURN
        ip6tables -I INPUT 1 -j UNLOCK_FW6
    fi

    echo -e "${GREEN}防火墙规则已强制重写并置顶！${NC}"
    echo -e "${YELLOW}提示: 如果你是在本机测试 nslookup，由于本机放行规则，你是可以通的。${NC}"
    echo -e "${YELLOW}请务必找一台不在白名单的机器进行测试！${NC}"
}

manage_whitelist() {
    while true; do
        clear
        clean_whitelist_file
        echo -e "${SKY}>>> 白名单管理 (V22.6 强力版)${NC}"
        echo -e "当前状态: ${YELLOW}规则强制置顶 INPUT 链首位${NC}"
        echo -e "----------------------------------------"
        if [ -s "$WHITELIST_FILE" ]; then
            i=1
            while IFS= read -r line; do
                if [ -n "$line" ]; then
                    echo -e "  ${YELLOW}$i)${NC} ${GREEN}$line${NC}"
                    ((i++))
                fi
            done < "$WHITELIST_FILE"
        else
            echo -e "  ${RED}(空) - 当前应拒绝所有外部连接！${NC}"
        fi
        echo -e "----------------------------------------"
        echo -e "${YELLOW}1) 添加 IP${NC}"
        echo -e "${YELLOW}2) 删除 IP${NC}"
        echo -e "${YELLOW}3) 清空所有 IP${NC}"
        echo -e "${YELLOW}4) 立即重载防火墙规则${NC}"
        echo -e "${RED}0) 返回主菜单${NC}"
        echo ""
        read -p ">> " wl_choice
        case "$wl_choice" in
            1)
                echo -e "输入 IP:"
                read -p ">> " new_ips
                new_ips=${new_ips//,/ }
                for ip in $new_ips; do
                    ip=$(echo "$ip" | tr -d '[:space:]')
                    if [ -n "$(validate_ip "$ip")" ]; then
                        if ! grep -q "^$ip$" "$WHITELIST_FILE"; then
                            echo "$ip" >> "$WHITELIST_FILE"
                            echo -e "添加: ${GREEN}$ip${NC}"
                        fi
                    fi
                done
                clean_whitelist_file
                read -p "按回车继续..."
                ;;
            2)
                read -p "输入要删除的 IP: " del_ip
                if [ -n "$del_ip" ]; then 
                    sed -i "/^$del_ip$/d" "$WHITELIST_FILE"
                    clean_whitelist_file
                    echo -e "已删除"
                fi
                read -p "按回车继续..."
                ;;
            3) > "$WHITELIST_FILE"; echo -e "已清空";;
            4) apply_firewall; read -p "按回车返回..." _; return;;
            0) return;;
            *) ;;
        esac
    done
}

# ==========================================================
# 规则定义 (Gemini 更新)
# ==========================================================

define_rules() {
    CONF_GPT="address=/openai.com/$FINAL_IP
address=/chatgpt.com/$FINAL_IP
address=/oaistatic.com/$FINAL_IP
address=/oaiusercontent.com/$FINAL_IP
address=/ai.com/$FINAL_IP"
    JSON_GPT='"openai.com", "chatgpt.com", "oaistatic.com", "oaiusercontent.com", "ai.com"'

    # 已加入 aistudio.google.com
    CONF_GEMINI="address=/gemini.google.com/$FINAL_IP
address=/bard.google.com/$FINAL_IP
address=/ai.google.dev/$FINAL_IP
address=/generativelanguage.googleapis.com/$FINAL_IP
address=/makersuite.google.com/$FINAL_IP
address=/deepmind.com/$FINAL_IP
address=/deepmind.google/$FINAL_IP
address=/aistudio.google.com/$FINAL_IP"
    JSON_GEMINI='"gemini.google.com", "bard.google.com", "ai.google.dev", "generativelanguage.googleapis.com", "makersuite.google.com", "deepmind.com", "deepmind.google", "aistudio.google.com"'

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
    echo -e "\n${SKY}可用服务 (输入数字，逗号分隔):${NC}"
    echo "1. ChatGPT"
    echo "2. Gemini (含 aistudio)"
    echo "3. Copilot"
    echo "4. Claude"
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
        echo -e "${YELLOW}默认选择 ChatGPT${NC}"
        echo "$CONF_GPT" >> "$WORK_DIR/dnsmasq.conf"
        FINAL_JSON_LIST="$JSON_GPT"
        TYPE_NAME="ChatGPT"
    fi
}

# ==========================================================
# 安装 & 管理
# ==========================================================

run_install() {
    check_root
    install_base_tools
    # 临时清理以便重装
    services=("dnsmasq" "sniproxy")
    for svc in "${services[@]}"; do systemctl stop "$svc" 2>/dev/null; done
    
    IPV4=$(curl -4s --max-time 3 api.ip.sb/ip || curl -4s --max-time 3 ifconfig.me)
    echo -e "\n${SKY}检测本机 IP: ${GREEN}${IPV4:-未知}${NC}"
    read -p "确认使用此 IP? (y/n): " ip_conf
    if [[ "$ip_conf" == "n" ]]; then read -p "输入IP: " FINAL_IP; else FINAL_IP=$IPV4; fi
    
    DEPLOY_MODE="native" # 强制推荐原生模式以减少 iptables 问题
    select_services_logic

    echo -e "${YELLOW}>>> 安装/重置服务...${NC}"
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
    
    # 备份 resolv.conf
    rm -f /etc/resolv.conf
    echo "nameserver 8.8.8.8" > /etc/resolv.conf

    # 立即应用防火墙
    apply_firewall
    save_config
    echo -e "${GREEN}安装并加固完成!${NC}"
}

check_status() {
    clear
    echo -e "${SKY}>>> 防火墙与服务状态检查${NC}"
    echo -e "IP: ${GREEN}${FINAL_IP:-未知}${NC}"
    
    # 检查 iptables 链首
    echo -e "\n[1] 防火墙规则检查 (INPUT 链首):"
    FIRST_RULE=$(iptables -S INPUT | head -n 2 | grep UNLOCK_FW)
    if [ -n "$FIRST_RULE" ]; then
        echo -e "${GREEN}正常: UNLOCK_FW 链已置顶${NC}"
    else
        echo -e "${RED}严重错误: 防火墙规则未生效或被覆盖！${NC}"
        echo -e "建议立即执行菜单选项 [2] -> [4] 重新应用规则"
    fi

    echo -e "\n[2] 服务监听:"
    if netstat -nulp | grep ":53 "; then echo -e "DNS (53): ${GREEN}运行中${NC}"; else echo -e "DNS (53): ${RED}未运行${NC}"; fi
    if netstat -ntlp | grep ":80 "; then echo -e "SNI (80): ${GREEN}运行中${NC}"; else echo -e "SNI (80): ${RED}未运行${NC}"; fi
    
    echo -e "\n[3] 本机自我测试 (应该通):"
    TEST=$(dig +short @127.0.0.1 aistudio.google.com)
    if [ "$TEST" == "$FINAL_IP" ]; then echo -e "DNS 劫持: ${GREEN}成功${NC}"; else echo -e "DNS 劫持: ${RED}失败 ($TEST)${NC}"; fi
    
    read -p "按回车返回..." _
}

gen_json() {
    if [ -z "$FINAL_IP" ]; then echo -e "${RED}请先安装!${NC}"; read -p "" _; return; fi
    if [[ "$FINAL_IP" == *":"* ]]; then IP_CIDR="${FINAL_IP}/128"; else IP_CIDR="${FINAL_IP}/32"; fi
    clear
    echo -e "${GREEN}════════ V2bX / NodePass 配置 ════════${NC}"
    echo -e "规则包含: ${TYPE_NAME}"
    echo -e "解锁 IP: ${FINAL_IP}"
    cat <<EOF
{
  "dns": {
    "servers": [
      { "tag": "unlock", "address": "${FINAL_IP}", "address_resolver": "local", "detour": "direct" },
      { "tag": "local", "address": "1.1.1.1", "detour": "direct" }
    ],
    "rules": [
      { "domain_suffix": [${FINAL_JSON_LIST}], "server": "unlock", "disable_cache": true }
    ],
    "final": "local",
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
      { "outbound": "direct", "network": ["udp","tcp"] }
    ]
  }
}
EOF
    echo ""
    read -p "按回车返回..." _
}

modify_services() {
    echo -e "${SKY}>>> 更新服务规则${NC}"
    select_services_logic
    cp "$WORK_DIR/dnsmasq.conf" /etc/dnsmasq.d/unlock.conf
    systemctl restart dnsmasq
    save_config
    echo -e "${GREEN}规则已更新${NC}"
    read -p "是否查看新JSON? (y/n): " v; if [[ "$v" == "y" ]]; then gen_json; fi
}

uninstall_all() {
    echo -e "${RED}正在卸载...${NC}"
    systemctl stop dnsmasq sniproxy
    iptables -D INPUT -j UNLOCK_FW 2>/dev/null
    iptables -F UNLOCK_FW 2>/dev/null
    iptables -X UNLOCK_FW 2>/dev/null
    rm -rf "$WORK_DIR"
    echo -e "${GREEN}已清理${NC}"
}

# ==========================================================
# 菜单
# ==========================================================
while true; do
    clear
    echo -e "${SKY} V2bX 解锁总控 (V22.6 强力封锁版)${NC}"
    echo -e " IP: ${FINAL_IP:-未配置}"
    echo -e "----------------------------------------"
    echo -e "${YELLOW}1) 安装 / 重置服务${NC}"
    echo -e "${YELLOW}2) 管理白名单 (IP Access)${NC}"
    echo -e "${YELLOW}3) 获取 JSON 配置${NC}"
    echo -e "${YELLOW}4) 检查运行状态 (含防火墙自检)${NC}"
    echo -e "${YELLOW}5) 实时日志${NC}"
    echo -e "${YELLOW}6) 修改规则 (Gemini/GPT等)${NC}"
    echo -e "${RED}9) 卸载${NC}"
    echo -e "${RED}0) 退出${NC}"
    echo ""
    read -p ">> " choice
    case "$choice" in
        1) run_install ;;
        2) manage_whitelist ;;
        3) gen_json ;;
        4) check_status ;;
        5) tail -f /var/log/sniproxy/access.log ;;
        6) modify_services ;;
        9) uninstall_all ;;
        0) exit 0 ;;
        *) ;;
    esac
done
