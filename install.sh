#!/bin/bash

# ==========================================================
#   NodePass/V2bX 专用解锁服务搭建脚本 (V6.0 增强交互版)
#   功能：交互式菜单 + 双栈IP选择 + 精细化服务选择 + 审计规则集成 + 自动配置 + 一键卸载
#   Prism-DNS Unlock Service Setup Script (V6.0 Enhanced Interactive)
#   Features: Interactive Menu + Dual-stack IP + Granular service selection + Audit rules + Auto config + Uninstall
# ==========================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
SKY='\033[0;36m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
WHITE='\033[1;37m'
NC='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'
WORK_DIR="/root/dns_unlock"
WHITELIST_FILE="$WORK_DIR/whitelist.txt"
CONFIG_INFO_FILE="$WORK_DIR/install_info.conf"

# Language selection (default: Chinese)
LANG_CHOICE="zh"

# Global variables for status tracking
SERVER_IP=""
DEPLOY_MODE=""
SERVICES=""
INSTALLED_STATUS=""

# ======================== UI Helper Functions ========================

# Show enhanced header with status / 显示增强的标题头
show_header() {
    clear
    local status_text
    local mode_text
    local ip_text
    
    detect_install_status
    detect_public_ip
    
    status_text="$INSTALLED_STATUS"
    [ -n "$DEPLOY_MODE" ] && mode_text="$DEPLOY_MODE" || { [ "$LANG_CHOICE" = "en" ] && mode_text="Not Installed" || mode_text="未安装"; }
    [ -n "$SERVER_IP" ] && ip_text="$SERVER_IP" || { [ "$LANG_CHOICE" = "en" ] && ip_text="Not Detected" || ip_text="未检测"; }
    
    echo ""
    echo -e "${SKY}+===============================================================+${NC}"
    if [ "$LANG_CHOICE" = "en" ]; then
        echo -e "${SKY}|${NC}        ${WHITE}${BOLD}Prism-DNS Unlock Service Manager V6.0${NC}             ${SKY}|${NC}"
        echo -e "${SKY}|${NC}        ${DIM}NodePass / V2bX DNS Hijack + SNI Proxy${NC}             ${SKY}|${NC}"
    else
        echo -e "${SKY}|${NC}          ${WHITE}${BOLD}Prism-DNS 解锁服务管理面板 V6.0${NC}                ${SKY}|${NC}"
        echo -e "${SKY}|${NC}        ${DIM}NodePass / V2bX 专用 DNS 劫持 + SNI 代理${NC}           ${SKY}|${NC}"
    fi
    echo -e "${SKY}+---------------------------------------------------------------+${NC}"
    if [ "$LANG_CHOICE" = "en" ]; then
        printf "${SKY}|${NC}  ${GREEN}Mode:${NC} %-15s ${GREEN}IP:${NC} %-24s ${SKY}|${NC}\n" "$mode_text" "$ip_text"
    else
        printf "${SKY}|${NC}  ${GREEN}模式:${NC} %-15s ${GREEN}IP:${NC} %-24s ${SKY}|${NC}\n" "$mode_text" "$ip_text"
    fi
    echo -e "${SKY}+===============================================================+${NC}"
    echo ""
}

# Show divider line / 显示分隔线
show_divider() {
    echo -e "${SKY}---------------------------------------------------------------${NC}"
}

# Show subtitle / 显示子标题
show_subtitle() {
    local title="$1"
    echo ""
    echo -e "${SKY}+-------------------------------------------------------------+${NC}"
    echo -e "${SKY}|${NC} ${WHITE}${BOLD}$title${NC}"
    echo -e "${SKY}+-------------------------------------------------------------+${NC}"
    echo ""
}

# Success message / 成功消息
msg_ok() {
    echo -e "  ${GREEN}[OK]${NC} $1"
}

# Error message / 错误消息
msg_err() {
    echo -e "  ${RED}[ERR]${NC} $1"
}

# Warning message / 警告消息
msg_warn() {
    echo -e "  ${YELLOW}[WARN]${NC} $1"
}

# Info message / 信息消息
msg_info() {
    echo -e "  ${BLUE}[INFO]${NC} $1"
}

# Press enter to continue / 按回车继续
press_enter() {
    echo ""
    if [ "$LANG_CHOICE" = "en" ]; then
        read -p "  Press Enter to return to main menu..." _
    else
        read -p "  按 Enter 键返回主菜单..." _
    fi
}

# Detect public IP / 检测公网IP
detect_public_ip() {
    if [ -f "$CONFIG_INFO_FILE" ]; then
        source "$CONFIG_INFO_FILE" 2>/dev/null
    fi
    
    if [ -z "$SERVER_IP" ]; then
        SERVER_IP=$(curl -4 -s --max-time 3 ifconfig.me 2>/dev/null)
        if [ -z "$SERVER_IP" ]; then
            SERVER_IP=$(curl -6 -s --max-time 3 ifconfig.co 2>/dev/null)
        fi
    fi
}

# Detect installation status / 检测安装状态
detect_install_status() {
    if [ -f "$CONFIG_INFO_FILE" ]; then
        source "$CONFIG_INFO_FILE" 2>/dev/null
    fi
    
    # Check Docker mode
    if command -v docker &> /dev/null && docker ps 2>/dev/null | grep -q "dns_unlock"; then
        [ "$LANG_CHOICE" = "en" ] && INSTALLED_STATUS="Running (Docker)" || INSTALLED_STATUS="运行中 (Docker)"
        DEPLOY_MODE="Docker"
        return 0
    fi
    
    # Check Native mode
    if systemctl is-active dnsmasq >/dev/null 2>&1 && [ -f /etc/dnsmasq.d/unlock.conf ]; then
        [ "$LANG_CHOICE" = "en" ] && INSTALLED_STATUS="Running (Native)" || INSTALLED_STATUS="运行中 (原生)"
        [ "$LANG_CHOICE" = "en" ] && DEPLOY_MODE="Native" || DEPLOY_MODE="原生"
        return 0
    fi
    
    if [ -f "$WORK_DIR/dnsmasq.conf" ]; then
        [ "$LANG_CHOICE" = "en" ] && INSTALLED_STATUS="Installed (Stopped)" || INSTALLED_STATUS="已安装 (已停止)"
    else
        [ "$LANG_CHOICE" = "en" ] && INSTALLED_STATUS="Not Installed" || INSTALLED_STATUS="未安装"
        DEPLOY_MODE=""
    fi
}

# Save configuration / 保存配置
save_config() {
    mkdir -p "$WORK_DIR"
    cat > "$CONFIG_INFO_FILE" << EOF
SERVER_IP="$SERVER_IP"
DEPLOY_MODE="$DEPLOY_MODE"
SERVICES="$SERVICES"
INSTALL_DATE="$(date '+%Y-%m-%d %H:%M:%S')"
EOF
}

# Validate IP address format / 验证 IP 地址格式
# Returns 0 for valid IP, 1 for invalid
validate_ip() {
    local ip="$1"
    
    # Remove leading/trailing whitespace
    ip=$(echo "$ip" | tr -d '[:space:]')
    
    # Check for empty input
    if [ -z "$ip" ]; then
        return 1
    fi
    
    # Check for dangerous characters (command injection prevention)
    # Using case statement with shell globbing - only allow dots, colons, and hex digits
    case "$ip" in
        *[!.:0-9a-fA-F]*)
            # Contains characters other than dots, colons, and hex digits
            return 1
            ;;
    esac
    
    # IPv4 validation: must be exactly 4 octets of 0-255
    if [[ "$ip" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]]; then
        local octet
        for octet in "${BASH_REMATCH[@]:1}"; do
            # Remove leading zeros to avoid octal interpretation, use 10# to force decimal
            if [ "$((10#$octet))" -gt 255 ]; then
                return 1
            fi
        done
        return 0
    fi
    
    # IPv6 validation: basic check for valid characters and format
    # Accept common IPv6 formats including compressed notation
    if [[ "$ip" =~ ^[0-9a-fA-F:]+$ ]]; then
        # Must contain at least one colon
        if [[ "$ip" == *:* ]]; then
            # Reject if three or more consecutive colons (like ":::" or "::::")
            if [[ "$ip" =~ :::+ ]]; then
                return 1
            fi
            case "$ip" in
                *::*::*)
                    # Multiple double colons - invalid
                    return 1
                    ;;
                *::*)
                    # Single double colon - valid (compressed notation, includes "::")
                    return 0
                    ;;
                ::)
                    # Special case: "::" is valid (represents all zeros)
                    return 0
                    ;;
                *)
                    # No double colon - check for full format (must have at least one hex digit)
                    if [[ "$ip" =~ ^[0-9a-fA-F]+:[0-9a-fA-F:]+$ ]]; then
                        return 0
                    fi
                    ;;
            esac
        fi
    fi
    
    return 1
}

# Select language / 选择语言
select_language() {
    clear
    echo ""
    echo -e "${SKY}+===============================================================+${NC}"
    echo -e "${SKY}|${NC}          ${WHITE}${BOLD}Prism-DNS Unlock Service Manager${NC}                  ${SKY}|${NC}"
    echo -e "${SKY}|${NC}        ${DIM}解锁服务部署 / Unlock Service Setup${NC}                 ${SKY}|${NC}"
    echo -e "${SKY}+===============================================================+${NC}"
    echo ""
    echo -e "  ${YELLOW}Please select language / 请选择语言:${NC}"
    echo ""
    echo -e "  ${GREEN}1)${NC} 简体中文 (Chinese)"
    echo -e "  ${GREEN}2)${NC} English"
    echo ""
    read -p "  Enter your choice / 输入选项 [1-2] (default/默认: 1): " lang_input
    
    case $lang_input in
        2)
            LANG_CHOICE="en"
            ;;
        *)
            LANG_CHOICE="zh"
            ;;
    esac
}

# ======================== Management Functions ========================

# View running status / 查看运行状态
view_status() {
    show_header
    if [ "$LANG_CHOICE" = "en" ]; then
        show_subtitle "System Running Status"
    else
        show_subtitle "系统运行状态"
    fi
    
    detect_install_status
    detect_public_ip
    
    # Basic info
    if [ "$LANG_CHOICE" = "en" ]; then
        echo -e "  ${SKY}Basic Information${NC}"
        echo -e "  - Server IP:     ${GREEN}${SERVER_IP:-Not Detected}${NC}"
        echo -e "  - Deploy Mode:   ${YELLOW}${DEPLOY_MODE:-Unknown}${NC}"
        echo -e "  - Status:        ${WHITE}${INSTALLED_STATUS}${NC}"
    else
        echo -e "  ${SKY}基本信息${NC}"
        echo -e "  - 本机 IP:       ${GREEN}${SERVER_IP:-未检测}${NC}"
        echo -e "  - 部署模式:      ${YELLOW}${DEPLOY_MODE:-未知}${NC}"
        echo -e "  - 安装状态:      ${WHITE}${INSTALLED_STATUS}${NC}"
    fi
    echo ""
    
    # Port listening status
    if [ "$LANG_CHOICE" = "en" ]; then
        echo -e "  ${SKY}Port Listening Status${NC}"
    else
        echo -e "  ${SKY}端口监听状态${NC}"
    fi
    
    for port in 53 80 443; do
        if ss -tuln 2>/dev/null | grep -qE "(::|0\.0\.0\.0|\*):${port}[[:space:]]"; then
            if [ "$LANG_CHOICE" = "en" ]; then
                echo -e "  - Port $port:     ${GREEN}[OK] Active (Listening)${NC}"
            else
                echo -e "  - 端口 $port:     ${GREEN}[OK] 正常 (监听中)${NC}"
            fi
        else
            if [ "$LANG_CHOICE" = "en" ]; then
                echo -e "  - Port $port:     ${RED}[X] Inactive${NC}"
            else
                echo -e "  - 端口 $port:     ${RED}[X] 异常 (未监听)${NC}"
            fi
        fi
    done
    echo ""
    
    # Service running status
    if [ "$LANG_CHOICE" = "en" ]; then
        echo -e "  ${SKY}Service Status${NC}"
    else
        echo -e "  ${SKY}服务运行状态${NC}"
    fi
    
    if [ "$DEPLOY_MODE" = "Docker" ] || [ "$DEPLOY_MODE" = "docker" ]; then
        if docker ps 2>/dev/null | grep -q "dns_unlock"; then
            if [ "$LANG_CHOICE" = "en" ]; then
                echo -e "  - Docker:      ${GREEN}[OK] Running${NC}"
            else
                echo -e "  - Docker 容器: ${GREEN}[OK] 运行中${NC}"
            fi
            local mem=$(docker stats dns_unlock --no-stream --format "{{.MemUsage}}" 2>/dev/null | cut -d'/' -f1)
            if [ "$LANG_CHOICE" = "en" ]; then
                echo -e "  - Memory:      ${WHITE}${mem:-Unknown}${NC}"
            else
                echo -e "  - 内存占用:    ${WHITE}${mem:-未知}${NC}"
            fi
        else
            if [ "$LANG_CHOICE" = "en" ]; then
                echo -e "  - Docker:      ${RED}[X] Stopped${NC}"
            else
                echo -e "  - Docker 容器: ${RED}[X] 已停止${NC}"
            fi
        fi
    else
        if systemctl is-active dnsmasq >/dev/null 2>&1; then
            echo -e "  - Dnsmasq:     ${GREEN}[OK] $([ "$LANG_CHOICE" = "en" ] && echo "Running" || echo "运行中")${NC}"
        else
            echo -e "  - Dnsmasq:     ${RED}[X] $([ "$LANG_CHOICE" = "en" ] && echo "Stopped" || echo "已停止")${NC}"
        fi
        if systemctl is-active sniproxy >/dev/null 2>&1; then
            echo -e "  - Sniproxy:    ${GREEN}[OK] $([ "$LANG_CHOICE" = "en" ] && echo "Running" || echo "运行中")${NC}"
        else
            echo -e "  - Sniproxy:    ${RED}[X] $([ "$LANG_CHOICE" = "en" ] && echo "Stopped" || echo "已停止")${NC}"
        fi
    fi
    
    press_enter
}

# Manage IP whitelist / 管理IP白名单
manage_whitelist() {
    while true; do
        show_header
        if [ "$LANG_CHOICE" = "en" ]; then
            show_subtitle "Manage IP Whitelist (Firewall Security)"
        else
            show_subtitle "管理 IP 白名单 (防火墙安全设置)"
        fi
        
        # Show current whitelist
        mkdir -p "$WORK_DIR"
        touch "$WHITELIST_FILE" 2>/dev/null
        local current_ips=$(cat "$WHITELIST_FILE" 2>/dev/null | sort | uniq)
        
        if [ "$LANG_CHOICE" = "en" ]; then
            echo -e "  ${SKY}Current Allowed IPs:${NC}"
        else
            echo -e "  ${SKY}当前允许的 IP 列表：${NC}"
        fi
        
        if [ -z "$current_ips" ]; then
            if [ "$LANG_CHOICE" = "en" ]; then
                echo -e "  ${YELLOW}(Empty) - Any IP can access, recommend adding landing server IPs${NC}"
            else
                echo -e "  ${YELLOW}(空) - 任何 IP 都可访问，建议尽快添加落地机 IP${NC}"
            fi
        else
            local i=1
            while IFS= read -r ip; do
                [ -n "$ip" ] && echo -e "  ${GREEN}$i.${NC} $ip" && ((i++))
            done <<< "$current_ips"
        fi
        echo ""
        
        show_divider
        if [ "$LANG_CHOICE" = "en" ]; then
            echo -e "  ${YELLOW}Options:${NC}"
            echo -e "  ${GREEN}1)${NC} Add IP"
            echo -e "  ${GREEN}2)${NC} Delete IP"
            echo -e "  ${GREEN}3)${NC} Clear All IPs"
            echo -e "  ${GREEN}4)${NC} Apply Firewall Rules"
            echo -e "  ${RED}0)${NC} Return to Main Menu"
        else
            echo -e "  ${YELLOW}操作选项：${NC}"
            echo -e "  ${GREEN}1)${NC} 添加 IP"
            echo -e "  ${GREEN}2)${NC} 删除指定 IP"
            echo -e "  ${GREEN}3)${NC} 清空所有 IP"
            echo -e "  ${GREEN}4)${NC} 应用防火墙规则"
            echo -e "  ${RED}0)${NC} 返回主菜单"
        fi
        echo ""
        read -p "  $([ "$LANG_CHOICE" = "en" ] && echo "Select [0-4]: " || echo "请选择 [0-4]: ")" fw_opt
        
        case "$fw_opt" in
            1)
                echo ""
                if [ "$LANG_CHOICE" = "en" ]; then
                    echo -e "  ${SKY}Enter IPs to add (space separated):${NC}"
                else
                    echo -e "  ${SKY}请输入要添加的 IP (多个 IP 用空格分隔):${NC}"
                fi
                read -p "  IP: " new_ips
                for ip in $new_ips; do
                    if validate_ip "$ip"; then
                        echo "$ip" >> "$WHITELIST_FILE"
                        msg_ok "$([ "$LANG_CHOICE" = "en" ] && echo "Added: $ip" || echo "已添加: $ip")"
                    else
                        msg_err "$([ "$LANG_CHOICE" = "en" ] && echo "Invalid IP: $ip (skipped)" || echo "无效的 IP: $ip (已跳过)")"
                    fi
                done
                sort "$WHITELIST_FILE" | uniq > "${WHITELIST_FILE}.tmp" && mv "${WHITELIST_FILE}.tmp" "$WHITELIST_FILE"
                sleep 1
                ;;
            2)
                echo ""
                read -p "  $([ "$LANG_CHOICE" = "en" ] && echo "Enter IP to delete: " || echo "请输入要删除的 IP: ")" del_ip
                if grep -q "^${del_ip}$" "$WHITELIST_FILE" 2>/dev/null; then
                    grep -v "^${del_ip}$" "$WHITELIST_FILE" > "${WHITELIST_FILE}.tmp" && mv "${WHITELIST_FILE}.tmp" "$WHITELIST_FILE"
                    msg_ok "$([ "$LANG_CHOICE" = "en" ] && echo "Deleted: $del_ip" || echo "已删除: $del_ip")"
                else
                    msg_err "$([ "$LANG_CHOICE" = "en" ] && echo "IP not in whitelist: $del_ip" || echo "IP 不在白名单中: $del_ip")"
                fi
                sleep 1
                ;;
            3)
                echo ""
                read -p "  $([ "$LANG_CHOICE" = "en" ] && echo "Confirm clear all IPs? [y/N]: " || echo "确定要清空所有 IP 吗? [y/N]: ")" confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    > "$WHITELIST_FILE"
                    msg_ok "$([ "$LANG_CHOICE" = "en" ] && echo "Whitelist cleared" || echo "白名单已清空")"
                fi
                sleep 1
                ;;
            4)
                apply_firewall_rules
                sleep 2
                ;;
            0)
                return
                ;;
        esac
    done
}

# Apply firewall rules / 应用防火墙规则
apply_firewall_rules() {
    echo ""
    msg_info "$([ "$LANG_CHOICE" = "en" ] && echo "Applying firewall rules..." || echo "正在应用防火墙规则...")"
    
    local ips=$(cat "$WHITELIST_FILE" 2>/dev/null | sort | uniq)
    
    # SSH protection
    local ssh_port=22
    if [ -f /etc/ssh/sshd_config ]; then
        local detected_port=$(grep -E "^[[:space:]]*Port[[:space:]]+" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' | head -1)
        if [ -n "$detected_port" ] && [ "$detected_port" -gt 0 ] 2>/dev/null; then
            ssh_port=$detected_port
        fi
    fi
    msg_warn "$([ "$LANG_CHOICE" = "en" ] && echo "Firewall protection: Force allowing SSH (port $ssh_port)" || echo "防火墙自锁保护：强制放行 SSH (端口 $ssh_port)")"
    
    if command -v ufw &> /dev/null; then
        ufw allow ssh >/dev/null 2>&1
        ufw allow "$ssh_port/tcp" >/dev/null 2>&1
        echo "y" | ufw enable >/dev/null 2>&1
        
        ufw delete allow 53 >/dev/null 2>&1
        ufw delete allow 80/tcp >/dev/null 2>&1
        ufw delete allow 443/tcp >/dev/null 2>&1
        
        if [ -n "$ips" ]; then
            for ip in $ips; do
                ufw allow from "$ip" to any port 53 >/dev/null 2>&1
                ufw allow from "$ip" to any port 80 >/dev/null 2>&1
                ufw allow from "$ip" to any port 443 >/dev/null 2>&1
            done
            ufw reload >/dev/null 2>&1
            msg_ok "$([ "$LANG_CHOICE" = "en" ] && echo "UFW rules updated, only whitelist IPs allowed" || echo "UFW 规则已更新，仅允许白名单 IP 访问")"
        else
            ufw allow 53 >/dev/null 2>&1
            ufw allow 80/tcp >/dev/null 2>&1
            ufw allow 443/tcp >/dev/null 2>&1
            ufw reload >/dev/null 2>&1
            msg_warn "$([ "$LANG_CHOICE" = "en" ] && echo "Whitelist empty, all IPs allowed" || echo "白名单为空，已开放所有 IP 访问")"
        fi
    else
        iptables -C INPUT -p tcp --dport "$ssh_port" -j ACCEPT 2>/dev/null || iptables -I INPUT -p tcp --dport "$ssh_port" -j ACCEPT
        
        iptables -D INPUT -j UNLOCK_WHITELIST 2>/dev/null || true
        iptables -F UNLOCK_WHITELIST 2>/dev/null || true
        iptables -X UNLOCK_WHITELIST 2>/dev/null || true
        
        iptables -N UNLOCK_WHITELIST 2>/dev/null
        
        if [ -n "$ips" ]; then
            for ip in $ips; do
                iptables -A UNLOCK_WHITELIST -s "$ip" -p tcp --dport 53 -j ACCEPT
                iptables -A UNLOCK_WHITELIST -s "$ip" -p udp --dport 53 -j ACCEPT
                iptables -A UNLOCK_WHITELIST -s "$ip" -p tcp --dport 80 -j ACCEPT
                iptables -A UNLOCK_WHITELIST -s "$ip" -p tcp --dport 443 -j ACCEPT
            done
            
            iptables -A UNLOCK_WHITELIST -p tcp --dport 53 -j DROP
            iptables -A UNLOCK_WHITELIST -p udp --dport 53 -j DROP
            iptables -A UNLOCK_WHITELIST -p tcp --dport 80 -j DROP
            iptables -A UNLOCK_WHITELIST -p tcp --dport 443 -j DROP
            
            iptables -I INPUT -j UNLOCK_WHITELIST
            msg_ok "$([ "$LANG_CHOICE" = "en" ] && echo "iptables rules updated, only whitelist IPs allowed" || echo "iptables 规则已更新，仅允许白名单 IP 访问")"
        else
            msg_warn "$([ "$LANG_CHOICE" = "en" ] && echo "Whitelist empty, no IP restrictions" || echo "白名单为空，未限制 IP 访问")"
        fi
    fi
}

# Test unlock status / 测试解锁状态
test_unlock() {
    show_header
    if [ "$LANG_CHOICE" = "en" ]; then
        show_subtitle "Test Unlock Status"
    else
        show_subtitle "测试解锁状态"
    fi
    
    detect_public_ip
    
    if ! validate_ip "$SERVER_IP"; then
        msg_err "$([ "$LANG_CHOICE" = "en" ] && echo "Invalid server IP: $SERVER_IP" || echo "无效的服务器 IP: $SERVER_IP")"
        press_enter
        return
    fi
    
    # Connectivity test
    if [ "$LANG_CHOICE" = "en" ]; then
        echo -e "  ${SKY}[1/3] Testing Connectivity${NC}"
    else
        echo -e "  ${SKY}[1/3] 测试解锁机连通性${NC}"
    fi
    echo ""
    
    echo -n "  - Ping $([ "$LANG_CHOICE" = "en" ] && echo "test" || echo "测试"):    "
    if ping -c 1 -W 2 "$SERVER_IP" >/dev/null 2>&1; then
        echo -e "${GREEN}[OK] $([ "$LANG_CHOICE" = "en" ] && echo "Success" || echo "成功")${NC}"
    else
        echo -e "${YELLOW}[X] $([ "$LANG_CHOICE" = "en" ] && echo "Failed (ICMP may be disabled)" || echo "失败 (可能禁用 ICMP)")${NC}"
    fi
    
    for port in 53 80 443; do
        echo -n "  - TCP $port $([ "$LANG_CHOICE" = "en" ] && echo "test" || echo "测试"):  "
        local port_open=false
        if command -v nc &> /dev/null; then
            if nc -z -w 2 "$SERVER_IP" "$port" 2>/dev/null; then
                port_open=true
            fi
        elif command -v timeout &> /dev/null; then
            if timeout 2 bash -c "echo >/dev/tcp/$SERVER_IP/$port" 2>/dev/null; then
                port_open=true
            fi
        fi
        
        if [ "$port_open" = true ]; then
            echo -e "${GREEN}[OK] $([ "$LANG_CHOICE" = "en" ] && echo "Open" || echo "开放")${NC}"
        else
            echo -e "${RED}[X] $([ "$LANG_CHOICE" = "en" ] && echo "Closed" || echo "关闭")${NC}"
        fi
    done
    echo ""
    
    # DNS hijack test
    if [ "$LANG_CHOICE" = "en" ]; then
        echo -e "  ${SKY}[2/3] Testing DNS Hijack${NC}"
    else
        echo -e "  ${SKY}[2/3] 测试 DNS 劫持${NC}"
    fi
    echo ""
    
    local test_domains=("openai.com" "netflix.com" "google.com")
    for domain in "${test_domains[@]}"; do
        echo -n "  - $domain: "
        local result=""
        if command -v dig &> /dev/null; then
            result=$(dig +short @$SERVER_IP $domain 2>/dev/null | tail -1)
        elif command -v nslookup &> /dev/null; then
            result=$(nslookup $domain $SERVER_IP 2>/dev/null | grep -A1 "Name:" | grep "Address" | awk '{print $2}' | tail -1)
        fi
        
        if [ "$result" = "$SERVER_IP" ]; then
            echo -e "${GREEN}[OK] $([ "$LANG_CHOICE" = "en" ] && echo "Hijack OK" || echo "劫持成功") -> $result${NC}"
        elif [ -n "$result" ]; then
            echo -e "${YELLOW}-> $result ($([ "$LANG_CHOICE" = "en" ] && echo "Not hijacked" || echo "未劫持"))${NC}"
        else
            echo -e "${RED}[X] $([ "$LANG_CHOICE" = "en" ] && echo "No response" || echo "无响应")${NC}"
        fi
    done
    echo ""
    
    # Test suggestions
    if [ "$LANG_CHOICE" = "en" ]; then
        echo -e "  ${SKY}[3/3] Test Suggestions${NC}"
        echo ""
        echo -e "  ${DIM}After connecting to landing node, visit these sites to test:${NC}"
    else
        echo -e "  ${SKY}[3/3] 解锁测试建议${NC}"
        echo ""
        echo -e "  ${DIM}从您的客户端连接落地节点后，访问以下网站测试：${NC}"
    fi
    echo -e "  - ChatGPT: https://chat.openai.com"
    echo -e "  - Netflix: https://www.netflix.com"
    echo -e "  - TikTok:  $([ "$LANG_CHOICE" = "en" ] && echo "Open TikTok APP" || echo "打开 TikTok APP")"
    
    press_enter
}

# View service logs / 查看服务日志
view_logs() {
    show_header
    if [ "$LANG_CHOICE" = "en" ]; then
        show_subtitle "View Service Logs"
        echo -e "  ${SKY}Select log type:${NC}"
        echo ""
        echo -e "  ${GREEN}1)${NC} Real-time logs ${DIM}(Ctrl+C to exit)${NC}"
        echo -e "  ${GREEN}2)${NC} Last 50 lines"
        echo -e "  ${GREEN}3)${NC} Last 100 lines"
        echo -e "  ${GREEN}4)${NC} DNS query logs only"
        echo -e "  ${RED}0)${NC} Return to main menu"
    else
        show_subtitle "查看服务日志"
        echo -e "  ${SKY}请选择要查看的日志类型：${NC}"
        echo ""
        echo -e "  ${GREEN}1)${NC} 实时日志 ${DIM}(按 Ctrl+C 退出)${NC}"
        echo -e "  ${GREEN}2)${NC} 最近 50 行日志"
        echo -e "  ${GREEN}3)${NC} 最近 100 行日志"
        echo -e "  ${GREEN}4)${NC} DNS 查询日志 ${DIM}(仅显示 DNS 请求)${NC}"
        echo -e "  ${RED}0)${NC} 返回主菜单"
    fi
    echo ""
    read -p "  $([ "$LANG_CHOICE" = "en" ] && echo "Select [0-4]: " || echo "请选择 [0-4]: ")" log_opt
    
    detect_install_status
    
    case "$log_opt" in
        1)
            echo ""
            msg_info "$([ "$LANG_CHOICE" = "en" ] && echo "Showing real-time logs, press Ctrl+C to exit..." || echo "显示实时日志，按 Ctrl+C 退出...")"
            echo ""
            if [ "$DEPLOY_MODE" = "Docker" ] || [ "$DEPLOY_MODE" = "docker" ]; then
                docker logs -f dns_unlock 2>&1
            else
                journalctl -u dnsmasq -u sniproxy -f 2>&1
            fi
            ;;
        2)
            echo ""
            msg_info "$([ "$LANG_CHOICE" = "en" ] && echo "Last 50 lines:" || echo "最近 50 行日志：")"
            echo ""
            if [ "$DEPLOY_MODE" = "Docker" ] || [ "$DEPLOY_MODE" = "docker" ]; then
                docker logs --tail 50 dns_unlock 2>&1
            else
                journalctl -u dnsmasq -u sniproxy -n 50 --no-pager 2>&1
            fi
            press_enter
            ;;
        3)
            echo ""
            msg_info "$([ "$LANG_CHOICE" = "en" ] && echo "Last 100 lines:" || echo "最近 100 行日志：")"
            echo ""
            if [ "$DEPLOY_MODE" = "Docker" ] || [ "$DEPLOY_MODE" = "docker" ]; then
                docker logs --tail 100 dns_unlock 2>&1
            else
                journalctl -u dnsmasq -u sniproxy -n 100 --no-pager 2>&1
            fi
            press_enter
            ;;
        4)
            echo ""
            msg_info "$([ "$LANG_CHOICE" = "en" ] && echo "DNS query logs..." || echo "DNS 查询日志...")"
            echo ""
            local dns_logs=""
            if [ "$DEPLOY_MODE" = "Docker" ] || [ "$DEPLOY_MODE" = "docker" ]; then
                dns_logs=$(docker logs --tail 100 dns_unlock 2>&1 | grep -E "(query|reply|cached)" || true)
            else
                dns_logs=$(journalctl -u dnsmasq -n 100 --no-pager 2>&1 | grep -E "(query|reply|cached)" || true)
            fi
            if [ -n "$dns_logs" ]; then
                echo "$dns_logs"
            else
                msg_warn "$([ "$LANG_CHOICE" = "en" ] && echo "No DNS query records found" || echo "未找到 DNS 查询记录")"
            fi
            press_enter
            ;;
        0|*)
            return
            ;;
    esac
}

# Restart service / 重启服务
restart_service() {
    show_header
    if [ "$LANG_CHOICE" = "en" ]; then
        show_subtitle "Restart Service"
    else
        show_subtitle "重启服务"
    fi
    
    detect_install_status
    
    if [ "$DEPLOY_MODE" = "Docker" ] || [ "$DEPLOY_MODE" = "docker" ]; then
        msg_info "$([ "$LANG_CHOICE" = "en" ] && echo "Restarting Docker container..." || echo "重启 Docker 容器...")"
        if [ -d "$WORK_DIR" ]; then
            cd "$WORK_DIR" && docker compose restart 2>/dev/null
            sleep 2
            if docker ps | grep -q "dns_unlock"; then
                msg_ok "$([ "$LANG_CHOICE" = "en" ] && echo "Docker container restarted successfully" || echo "Docker 容器重启成功")"
            else
                msg_err "$([ "$LANG_CHOICE" = "en" ] && echo "Docker container restart failed" || echo "Docker 容器重启失败")"
            fi
        else
            msg_err "$([ "$LANG_CHOICE" = "en" ] && echo "Work directory not found: $WORK_DIR" || echo "工作目录不存在: $WORK_DIR")"
        fi
    elif [ "$DEPLOY_MODE" = "原生" ] || [ "$DEPLOY_MODE" = "Native" ] || [ "$DEPLOY_MODE" = "native" ]; then
        msg_info "$([ "$LANG_CHOICE" = "en" ] && echo "Restarting native services..." || echo "重启原生服务...")"
        systemctl restart dnsmasq sniproxy 2>/dev/null
        sleep 2
        if systemctl is-active dnsmasq >/dev/null && systemctl is-active sniproxy >/dev/null; then
            msg_ok "$([ "$LANG_CHOICE" = "en" ] && echo "Services restarted successfully" || echo "服务重启成功")"
        else
            msg_err "$([ "$LANG_CHOICE" = "en" ] && echo "Service restart failed" || echo "服务重启失败")"
        fi
    else
        msg_warn "$([ "$LANG_CHOICE" = "en" ] && echo "No service installed" || echo "未安装服务")"
    fi
    
    press_enter
}

# One-click cleanup / 一键清理
cleanup_all() {
    show_header
    if [ "$LANG_CHOICE" = "en" ]; then
        show_subtitle "One-Click Cleanup"
        echo -e "  ${YELLOW}This will clean up the following:${NC}"
        echo -e "  - Stop all unlock services"
        echo -e "  - Delete temporary files and logs"
        echo -e "  - Reset firewall rules"
    else
        show_subtitle "一键清理"
        echo -e "  ${YELLOW}此功能将清理以下内容：${NC}"
        echo -e "  - 停止所有解锁服务"
        echo -e "  - 删除临时文件和日志"
        echo -e "  - 重置防火墙规则"
    fi
    echo ""
    read -p "  $([ "$LANG_CHOICE" = "en" ] && echo "Confirm? [y/N]: " || echo "确定要继续吗? [y/N]: ")" confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        msg_warn "$([ "$LANG_CHOICE" = "en" ] && echo "Operation cancelled" || echo "操作已取消")"
        press_enter
        return
    fi
    
    echo ""
    
    # Stop services
    msg_info "$([ "$LANG_CHOICE" = "en" ] && echo "Stopping services..." || echo "停止服务...")"
    docker stop dns_unlock 2>/dev/null || true
    systemctl stop dnsmasq sniproxy 2>/dev/null || true
    msg_ok "$([ "$LANG_CHOICE" = "en" ] && echo "Services stopped" || echo "服务已停止")"
    
    # Clean logs
    msg_info "$([ "$LANG_CHOICE" = "en" ] && echo "Cleaning log files..." || echo "清理日志文件...")"
    rm -rf /var/log/sniproxy/* 2>/dev/null
    msg_ok "$([ "$LANG_CHOICE" = "en" ] && echo "Logs cleaned" || echo "日志已清理")"
    
    # Reset firewall
    msg_info "$([ "$LANG_CHOICE" = "en" ] && echo "Resetting firewall rules..." || echo "重置防火墙规则...")"
    if command -v ufw &> /dev/null; then
        ufw allow ssh >/dev/null 2>&1
        ufw allow 53 >/dev/null 2>&1
        ufw allow 80/tcp >/dev/null 2>&1
        ufw allow 443/tcp >/dev/null 2>&1
        ufw reload >/dev/null 2>&1
    else
        iptables -D INPUT -j UNLOCK_WHITELIST 2>/dev/null || true
        iptables -F UNLOCK_WHITELIST 2>/dev/null || true
        iptables -X UNLOCK_WHITELIST 2>/dev/null || true
    fi
    msg_ok "$([ "$LANG_CHOICE" = "en" ] && echo "Firewall rules reset" || echo "防火墙规则已重置")"
    
    echo ""
    msg_ok "$([ "$LANG_CHOICE" = "en" ] && echo "Cleanup complete! Restart service if needed." || echo "清理完成！如需使用请重新启动服务。")"
    
    press_enter
}

# Select action: install or uninstall / 选择操作：安装或卸载 (Original function, now used by menu)
select_action() {
    clear
    echo -e "${SKY}===============================================${NC}"
    [ "$LANG_CHOICE" = "en" ] && echo -e "${SKY}  Select Action${NC}" || echo -e "${SKY}  选择操作${NC}"
    echo -e "${SKY}===============================================${NC}\n"
    
    if [ "$LANG_CHOICE" = "en" ]; then
        echo "Please select an action:"
        echo "1. Install / Reinstall Unlock Service"
        echo "2. Uninstall Unlock Service"
        echo ""
    else
        echo "请选择操作："
        echo "1. 安装 / 重新安装解锁服务"
        echo "2. 卸载解锁服务"
        echo ""
    fi
    
    read -p "$([ "$LANG_CHOICE" = "en" ] && echo "Enter option [1-2] (default: 1): " || echo "请输入选项 [1-2] (默认: 1): ")" action_input
    
    case $action_input in
        2)
            uninstall_service
            exit 0
            ;;
        *)
            # Continue with installation
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
            [ "$LANG_CHOICE" = "en" ] && echo "[OK] All required ports are available" || echo "[OK] 所有必需端口可用"
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
        "port_kill_ask")
            [ "$LANG_CHOICE" = "en" ] && echo "Do you want to kill processes occupying ports? [y/N]:" || echo "是否终止占用端口的进程? [y/N]:"
            ;;
        "port_killing")
            [ "$LANG_CHOICE" = "en" ] && echo "Killing processes on port $2..." || echo "正在终止端口 $2 的进程..."
            ;;
        "port_killed")
            [ "$LANG_CHOICE" = "en" ] && echo "Processes on port $2 killed successfully" || echo "端口 $2 的进程已终止"
            ;;
        "port_kill_failed")
            [ "$LANG_CHOICE" = "en" ] && echo "Failed to kill processes on port $2" || echo "无法终止端口 $2 的进程"
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
    local spin='|/-\'
    local i=0
    
    while kill -0 $pid 2>/dev/null; do
        i=$(( (i+1) % 4 ))
        printf "\r%s%s %s%s" "${YELLOW}" "${spin:$i:1}" "${msg}" "${NC}"
        sleep 0.2
    done
    printf "\r"
}

# Kill process by port / 根据端口终止进程
kill_port_process() {
    local port=$1
    local pids=""
    
    # Get PIDs using the port
    if command -v lsof &> /dev/null; then
        pids=$(lsof -t -i :"$port" 2>/dev/null)
    elif command -v ss &> /dev/null; then
        # Extract PID from ss output using portable sed
        pids=$(ss -tlnp 2>/dev/null | grep ":$port" | sed -n 's/.*pid=\([0-9]*\).*/\1/p' | sort -u)
    elif command -v fuser &> /dev/null; then
        pids=$(fuser "$port/tcp" 2>/dev/null | tr -s ' ')
    fi
    
    if [ -n "$pids" ]; then
        for pid in $pids; do
            if [ -n "$pid" ] && [ "$pid" -gt 0 ] 2>/dev/null; then
                kill -9 "$pid" 2>/dev/null
            fi
        done
        return 0
    fi
    return 1
}

# 1. Check Root privileges / 检查 Root 权限
if [ "$(id -u)" != "0" ]; then
    echo -e "${RED}$(txt check_root_err)${NC}"
    exit 1
fi

# 2. Check port availability / 检查端口占用
check_port_availability() {
    echo -e "\n${SKY}===============================================${NC}"
    echo -e "${SKY}  $(txt port_check_title)${NC}"
    echo -e "${SKY}===============================================${NC}\n"
    
    local ports=(53 80 443)
    local port_conflict=false
    local conflicting_ports=()
    
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
            conflicting_ports+=("$port")
            echo -e "${RED}[X] $(txt port_occupied "$port")${NC}"
            
            # Try to identify the process using the port
            if command -v lsof &> /dev/null; then
                lsof -i :"$port" 2>/dev/null | grep LISTEN | awk '{print "    "$1" (PID: "$2")"}'
            elif command -v ss &> /dev/null; then
                # Extract process info from ss output, handling different formats
                ss -tlnp 2>/dev/null | grep ":$port" | sed 's/.*users:((\([^)]*\)).*/    \1/' | head -1
            fi
        else
            echo -e "${GREEN}[OK] $(txt port_available "$port")${NC}"
        fi
    done
    
    echo ""
    
    if [ "$port_conflict" = true ]; then
        echo -e "${YELLOW}$(txt port_conflict_warn)${NC}"
        echo ""
        
        # Ask user if they want to kill the processes
        read -p "  $(txt port_kill_ask) " kill_confirm
        
        if [[ "$kill_confirm" =~ ^[Yy]$ ]]; then
            echo ""
            for port in "${conflicting_ports[@]}"; do
                echo -e "  ${YELLOW}$(txt port_killing "$port")${NC}"
                if kill_port_process "$port"; then
                    sleep 1
                    # Verify the port is now free
                    local still_occupied=""
                    if command -v ss &> /dev/null; then
                        still_occupied=$(ss -tuln 2>/dev/null | grep -E "(::|0\.0\.0\.0|\\*):${port}\\b")
                    fi
                    if [ -z "$still_occupied" ]; then
                        echo -e "  ${GREEN}[OK] $(txt port_killed "$port")${NC}"
                    else
                        echo -e "  ${RED}[X] $(txt port_kill_failed "$port")${NC}"
                    fi
                else
                    echo -e "  ${RED}[X] $(txt port_kill_failed "$port")${NC}"
                fi
            done
            echo ""
            echo -e "${GREEN}$([ "$LANG_CHOICE" = "en" ] && echo "Port cleanup completed, continuing installation..." || echo "端口清理完成，继续安装...")${NC}"
        else
            echo ""
            echo -e "${YELLOW}$(txt tip_prefix) $(txt port_conflict_tip)${NC}"
            echo ""
            read -p "  $(txt port_continue) " continue_install
            
            if [[ ! "$continue_install" =~ ^[Yy]$ ]]; then
                echo -e "${RED}$([ "$LANG_CHOICE" = "en" ] && echo "Installation cancelled" || echo "安装已取消")${NC}"
                exit 1
            fi
        fi
    else
        echo -e "${GREEN}$(txt port_check_pass)${NC}"
    fi
    
    sleep 2
}

# 3. Intelligent IP detection and selection / 智能 IP 检测与选择
select_public_ip() {
    clear
    echo -e "${SKY}===============================================${NC}"
    [ "$LANG_CHOICE" = "en" ] && echo -e "${SKY}  Detecting Public IP Addresses${NC}" || echo -e "${SKY}  正在检测本机 IP${NC}"
    echo -e "${SKY}===============================================${NC}\n"
    
    # Use secure temporary files to prevent race conditions
    local tmp_ipv4
    local tmp_ipv6
    tmp_ipv4=$(mktemp 2>/dev/null)
    tmp_ipv6=$(mktemp 2>/dev/null)
    
    if [ -z "$tmp_ipv4" ] || [ -z "$tmp_ipv6" ]; then
        # Clean up any partially created files
        [ -n "$tmp_ipv4" ] && rm -f "$tmp_ipv4"
        [ -n "$tmp_ipv6" ] && rm -f "$tmp_ipv6"
        echo -e "${RED}$([ "$LANG_CHOICE" = "en" ] && echo "Error: Failed to create secure temporary files" || echo "错误: 无法创建安全的临时文件")${NC}"
        exit 1
    fi
    
    # Detect IPs with spinner
    (curl -4s --max-time 5 ifconfig.me 2>/dev/null > "$tmp_ipv4") &
    local pid_v4=$!
    spinner $pid_v4 "Detecting IPv4 / 检测 IPv4 地址..."
    wait $pid_v4
    IPV4=$(cat "$tmp_ipv4" 2>/dev/null)
    
    (curl -6s --max-time 5 ifconfig.co 2>/dev/null > "$tmp_ipv6") &
    local pid_v6=$!
    spinner $pid_v6 "Detecting IPv6 / 检测 IPv6 地址..."
    wait $pid_v6
    IPV6=$(cat "$tmp_ipv6" 2>/dev/null)
    
    # Clean up temporary files
    rm -f "$tmp_ipv4" "$tmp_ipv6"

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
            # Validate manually entered IP address
            if ! validate_ip "$FINAL_IP"; then
                echo -e "${RED}$([ "$LANG_CHOICE" = "en" ] && echo "Invalid IP address format" || echo "无效的 IP 地址格式")${NC}"
                exit 1
            fi
            ;;
        *)
            echo -e "${YELLOW}Invalid option, using auto-detected IP / 选项错误，使用自动检测到的 IP${NC}"
            FINAL_IP="${IPV4:-$IPV6}"
            ;;
    esac
    echo -e "\n${GREEN}[OK] Selected service IP / 已选择服务 IP: ${FINAL_IP}${NC}"
    sleep 1
}

# 4. Install Docker / 安装 Docker
install_docker() {
    echo -e "\n${SKY}===============================================${NC}"
    [ "$LANG_CHOICE" = "en" ] && echo -e "${SKY}  Installing Docker Environment${NC}" || echo -e "${SKY}  安装 Docker 环境${NC}"
    echo -e "${SKY}===============================================${NC}\n"
    
    if ! command -v docker &> /dev/null; then
        echo -e "${YELLOW}$([ "$LANG_CHOICE" = "en" ] && echo "Installing Docker..." || echo "正在安装 Docker...")${NC}"
        if [ "$LANG_CHOICE" = "en" ]; then
            echo -e "${SKY}This may take 1-3 minutes depending on network speed. Please wait...${NC}"
        else
            echo -e "${SKY}这可能需要 1-3 分钟，具体取决于网络速度。请稍候...${NC}"
        fi
        
        (curl -fsSL https://get.docker.com | bash > /tmp/docker_install.log 2>&1) &
        local pid=$!
        spinner $pid "Downloading and installing Docker / 下载并安装 Docker..."
        wait $pid
        
        # Verify Docker was installed successfully
        if ! command -v docker &> /dev/null; then
            echo -e "${RED}[X] $([ "$LANG_CHOICE" = "en" ] && echo "Docker installation failed. Check /tmp/docker_install.log for details." || echo "Docker 安装失败。请查看 /tmp/docker_install.log 获取详情。")${NC}"
            echo -e "${YELLOW}$([ "$LANG_CHOICE" = "en" ] && echo "Tip: You can try the native mode (without Docker) for low-resource VPS by re-running the script." || echo "提示：对于低配 VPS，您可以重新运行脚本并选择原生模式（无需 Docker）。")${NC}"
            exit 1
        fi
        
        systemctl enable docker > /dev/null 2>&1
        systemctl start docker
        
        # Verify Docker service is running
        if ! systemctl is-active --quiet docker 2>/dev/null; then
            echo -e "${YELLOW}[!] $([ "$LANG_CHOICE" = "en" ] && echo "Docker service may not have started properly" || echo "Docker 服务可能未正常启动")${NC}"
        fi
        
        echo -e "${GREEN}[OK] Docker installed successfully / Docker 安装成功${NC}"
    else
        echo -e "${GREEN}[OK] Docker already installed / Docker 已安装${NC}"
    fi
    
    # Check for docker compose (v2) or docker-compose (v1)
    echo -e "\n${YELLOW}$([ "$LANG_CHOICE" = "en" ] && echo "Checking Docker Compose..." || echo "检查 Docker Compose...")${NC}"
    if ! docker compose version &> /dev/null && ! command -v docker-compose &> /dev/null; then
        echo -e "${YELLOW}$([ "$LANG_CHOICE" = "en" ] && echo "Installing Docker Compose..." || echo "正在安装 Docker Compose...")${NC}"
        
        (apt-get install -y docker-compose-plugin 2>/dev/null || apt-get install -y docker-compose 2>/dev/null) &
        local pid=$!
        spinner $pid "Installing Docker Compose / 安装 Docker Compose..."
        wait $pid
        
        # Verify Docker Compose was installed
        if ! docker compose version &> /dev/null && ! command -v docker-compose &> /dev/null; then
            echo -e "${RED}[X] $([ "$LANG_CHOICE" = "en" ] && echo "Docker Compose installation failed" || echo "Docker Compose 安装失败")${NC}"
            exit 1
        fi
        echo -e "${GREEN}[OK] Docker Compose installed / Docker Compose 已安装${NC}"
    else
        echo -e "${GREEN}[OK] Docker Compose already installed / Docker Compose 已安装${NC}"
    fi
    
    sleep 1
}

# Global variable for deployment mode
DEPLOY_MODE="docker"

# 4.5. Select deployment mode / 选择部署模式
select_deploy_mode() {
    echo -e "\n${SKY}===============================================${NC}"
    [ "$LANG_CHOICE" = "en" ] && echo -e "${SKY}  Select Deployment Mode${NC}" || echo -e "${SKY}  选择部署模式${NC}"
    echo -e "${SKY}===============================================${NC}\n"
    
    if [ "$LANG_CHOICE" = "en" ]; then
        echo "Please select deployment mode:"
        echo "1. Docker Mode (Recommended) - Isolated container, easy to manage"
        echo "2. Native Mode (Low Resource) - Direct installation, lower memory usage (~50MB vs ~150MB)"
        echo ""
        echo -e "${YELLOW}Tip: Use Native Mode if Docker installation fails or on low-memory VPS (< 512MB RAM)${NC}"
    else
        echo "请选择部署模式："
        echo "1. Docker 模式 (推荐) - 容器隔离，便于管理"
        echo "2. 原生模式 (低资源) - 直接安装，内存占用更低 (~50MB vs ~150MB)"
        echo ""
        echo -e "${YELLOW}提示：如果 Docker 安装失败或者 VPS 内存较小（< 512MB），建议使用原生模式${NC}"
    fi
    
    read -p "$([ "$LANG_CHOICE" = "en" ] && echo "Enter option [1-2] (default: 1): " || echo "请输入选项 [1-2] (默认: 1): ")" mode_input
    
    case $mode_input in
        2)
            DEPLOY_MODE="native"
            echo -e "\n${GREEN}[OK] $([ "$LANG_CHOICE" = "en" ] && echo "Selected: Native Mode" || echo "已选择: 原生模式")${NC}"
            ;;
        *)
            DEPLOY_MODE="docker"
            echo -e "\n${GREEN}[OK] $([ "$LANG_CHOICE" = "en" ] && echo "Selected: Docker Mode" || echo "已选择: Docker 模式")${NC}"
            ;;
    esac
    
    sleep 1
}

# Install native dependencies (dnsmasq + sniproxy) / 安装原生依赖
install_native() {
    echo -e "\n${SKY}===============================================${NC}"
    [ "$LANG_CHOICE" = "en" ] && echo -e "${SKY}  Installing Native Dependencies${NC}" || echo -e "${SKY}  安装原生依赖${NC}"
    echo -e "${SKY}===============================================${NC}\n"
    
    echo -e "${YELLOW}[1/3] $([ "$LANG_CHOICE" = "en" ] && echo "Updating package list..." || echo "更新软件包列表...")${NC}"
    if [ "$LANG_CHOICE" = "en" ]; then
        echo -e "${SKY}This may take a moment. Please wait...${NC}"
    else
        echo -e "${SKY}这可能需要一些时间。请稍候...${NC}"
    fi
    
    (apt-get update > /tmp/apt_update.log 2>&1) &
    local pid=$!
    spinner $pid "Updating package list / 更新软件包列表..."
    wait $pid
    local update_status=$?
    
    if [ $update_status -ne 0 ]; then
        echo -e "${YELLOW}[!] $([ "$LANG_CHOICE" = "en" ] && echo "Package update had warnings, continuing..." || echo "软件包更新有警告，继续...")${NC}"
    else
        echo -e "${GREEN}[OK] $([ "$LANG_CHOICE" = "en" ] && echo "Package list updated" || echo "软件包列表已更新")${NC}"
    fi
    
    # Install dnsmasq
    echo -e "\n${YELLOW}[2/3] $([ "$LANG_CHOICE" = "en" ] && echo "Installing dnsmasq (DNS server)..." || echo "安装 dnsmasq (DNS 服务器)...")${NC}"
    if ! command -v dnsmasq &> /dev/null; then
        (apt-get install -y dnsmasq > /tmp/dnsmasq_install.log 2>&1) &
        local pid=$!
        spinner $pid "Installing dnsmasq / 安装 dnsmasq..."
        wait $pid
        
        if ! command -v dnsmasq &> /dev/null; then
            echo -e "${RED}[X] $([ "$LANG_CHOICE" = "en" ] && echo "Failed to install dnsmasq. Check /tmp/dnsmasq_install.log" || echo "dnsmasq 安装失败。查看 /tmp/dnsmasq_install.log")${NC}"
            exit 1
        fi
        echo -e "${GREEN}[OK] dnsmasq installed successfully / dnsmasq 安装成功${NC}"
    else
        echo -e "${GREEN}[OK] dnsmasq already installed / dnsmasq 已安装${NC}"
    fi
    
    # Install sniproxy
    echo -e "\n${YELLOW}[3/3] $([ "$LANG_CHOICE" = "en" ] && echo "Installing sniproxy (SNI proxy)..." || echo "安装 sniproxy (SNI 代理)...")${NC}"
    if ! command -v sniproxy &> /dev/null; then
        (apt-get install -y sniproxy > /tmp/sniproxy_install.log 2>&1) &
        local pid=$!
        spinner $pid "Installing sniproxy / 安装 sniproxy..."
        wait $pid
        
        if ! command -v sniproxy &> /dev/null; then
            echo -e "${RED}[X] $([ "$LANG_CHOICE" = "en" ] && echo "Failed to install sniproxy. Check /tmp/sniproxy_install.log" || echo "sniproxy 安装失败。查看 /tmp/sniproxy_install.log")${NC}"
            exit 1
        fi
        echo -e "${GREEN}[OK] sniproxy installed successfully / sniproxy 安装成功${NC}"
    else
        echo -e "${GREEN}[OK] sniproxy already installed / sniproxy 已安装${NC}"
    fi
    
    echo -e "\n${GREEN}[OK] $([ "$LANG_CHOICE" = "en" ] && echo "All dependencies installed successfully" || echo "所有依赖安装成功")${NC}"
    sleep 1
}

# Deploy service in native mode / 原生模式部署服务
deploy_service_native() {
    echo -e "\n${SKY}===============================================${NC}"
    [ "$LANG_CHOICE" = "en" ] && echo -e "${SKY}  Deploying Native Services${NC}" || echo -e "${SKY}  部署原生服务${NC}"
    echo -e "${SKY}===============================================${NC}\n"
    
    # Stop existing services
    echo -e "${YELLOW}$([ "$LANG_CHOICE" = "en" ] && echo "Stopping existing services..." || echo "停止现有服务...")${NC}"
    systemctl stop dnsmasq 2>/dev/null || true
    systemctl stop sniproxy 2>/dev/null || true
    
    # Configure dnsmasq
    echo -e "${YELLOW}$([ "$LANG_CHOICE" = "en" ] && echo "Configuring dnsmasq..." || echo "配置 dnsmasq...")${NC}"
    
    # Backup original config if exists
    if [ -f /etc/dnsmasq.conf ] && [ ! -f /etc/dnsmasq.conf.bak ]; then
        cp /etc/dnsmasq.conf /etc/dnsmasq.conf.bak
    fi
    
    # Create dnsmasq main config
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
    
    # Copy unlock rules to dnsmasq.d
    mkdir -p /etc/dnsmasq.d
    cp "$WORK_DIR/dnsmasq.conf" /etc/dnsmasq.d/unlock.conf
    
    # Configure sniproxy
    echo -e "${YELLOW}$([ "$LANG_CHOICE" = "en" ] && echo "Configuring sniproxy..." || echo "配置 sniproxy...")${NC}"
    
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
    
    # Enable and start services
    echo -e "${YELLOW}$([ "$LANG_CHOICE" = "en" ] && echo "Starting services..." || echo "启动服务...")${NC}"
    
    systemctl enable dnsmasq > /dev/null 2>&1
    systemctl restart dnsmasq
    
    if ! systemctl is-active --quiet dnsmasq; then
        echo -e "${RED}[X] $([ "$LANG_CHOICE" = "en" ] && echo "Failed to start dnsmasq" || echo "dnsmasq 启动失败")${NC}"
        echo -e "${YELLOW}$([ "$LANG_CHOICE" = "en" ] && echo "Check logs: journalctl -u dnsmasq" || echo "查看日志: journalctl -u dnsmasq")${NC}"
        exit 1
    fi
    echo -e "${GREEN}[OK] dnsmasq started / dnsmasq 已启动${NC}"
    
    systemctl enable sniproxy > /dev/null 2>&1
    systemctl restart sniproxy
    
    if ! systemctl is-active --quiet sniproxy; then
        echo -e "${RED}[X] $([ "$LANG_CHOICE" = "en" ] && echo "Failed to start sniproxy" || echo "sniproxy 启动失败")${NC}"
        echo -e "${YELLOW}$([ "$LANG_CHOICE" = "en" ] && echo "Check logs: journalctl -u sniproxy" || echo "查看日志: journalctl -u sniproxy")${NC}"
        exit 1
    fi
    echo -e "${GREEN}[OK] sniproxy started / sniproxy 已启动${NC}"
    
    echo -e "\n${GREEN}[OK] $([ "$LANG_CHOICE" = "en" ] && echo "Native services deployed successfully" || echo "原生服务部署成功")${NC}"
    sleep 2
}

# 5. Select unlock mode & deploy service / 选择解锁模式 & 部署服务
deploy_service() {
    echo -e "\n${SKY}===============================================${NC}"
    [ "$LANG_CHOICE" = "en" ] && echo -e "${SKY}  Select Unlock Services (Multi-select)${NC}" || echo -e "${SKY}  选择解锁服务 (可多选)${NC}"
    echo -e "${SKY}===============================================${NC}\n"
    
    # --- Define simplified rules / 定义精简规则变量 ---
    # Only essential domains for each service / 每个服务只保留必要域名
    
    # 1. ChatGPT (OpenAI) - 精简版，只保留核心域名
    CONF_GPT="address=/openai.com/$FINAL_IP
address=/chatgpt.com/$FINAL_IP
address=/oaistatic.com/$FINAL_IP
address=/oaiusercontent.com/$FINAL_IP
address=/ai.com/$FINAL_IP"
    JSON_GPT='"openai.com", "chatgpt.com", "oaistatic.com", "oaiusercontent.com", "ai.com"'

    # 2. Gemini (Google AI) - 精简版，只保留 AI 核心域名
    CONF_GEMINI="address=/gemini.google.com/$FINAL_IP
address=/bard.google.com/$FINAL_IP
address=/ai.google.dev/$FINAL_IP
address=/generativelanguage.googleapis.com/$FINAL_IP
address=/makersuite.google.com/$FINAL_IP
address=/deepmind.com/$FINAL_IP
address=/deepmind.google/$FINAL_IP"
    JSON_GEMINI='"gemini.google.com", "bard.google.com", "ai.google.dev", "generativelanguage.googleapis.com", "makersuite.google.com", "deepmind.com", "deepmind.google"'

    # 3. Copilot (Microsoft) - 新增
    CONF_COPILOT="address=/copilot.microsoft.com/$FINAL_IP
address=/copilot.cloud.microsoft/$FINAL_IP
address=/bing.com/$FINAL_IP
address=/bingapis.com/$FINAL_IP"
    JSON_COPILOT='"copilot.microsoft.com", "copilot.cloud.microsoft", "bing.com", "bingapis.com"'

    # 4. Claude (Anthropic) - 新增
    CONF_CLAUDE="address=/anthropic.com/$FINAL_IP
address=/claude.ai/$FINAL_IP"
    JSON_CLAUDE='"anthropic.com", "claude.ai"'

    # 5. Netflix - 独立精简
    CONF_NETFLIX="address=/netflix.com/$FINAL_IP
address=/netflix.net/$FINAL_IP
address=/nflxvideo.net/$FINAL_IP
address=/nflximg.net/$FINAL_IP
address=/nflxext.com/$FINAL_IP"
    JSON_NETFLIX='"netflix.com", "netflix.net", "nflxvideo.net", "nflximg.net", "nflxext.com"'

    # 6. Disney+ - 独立精简
    CONF_DISNEY="address=/disney.com/$FINAL_IP
address=/disneyplus.com/$FINAL_IP
address=/dssott.com/$FINAL_IP
address=/bamgrid.com/$FINAL_IP"
    JSON_DISNEY='"disney.com", "disneyplus.com", "dssott.com", "bamgrid.com"'

    # 7. TikTok - 独立精简
    CONF_TIKTOK="address=/tiktok.com/$FINAL_IP
address=/tiktokv.com/$FINAL_IP
address=/tiktokcdn.com/$FINAL_IP
address=/musical.ly/$FINAL_IP"
    JSON_TIKTOK='"tiktok.com", "tiktokv.com", "tiktokcdn.com", "musical.ly"'

    # 8. YouTube - 独立精简
    CONF_YOUTUBE="address=/youtube.com/$FINAL_IP
address=/googlevideo.com/$FINAL_IP
address=/ytimg.com/$FINAL_IP
address=/ggpht.com/$FINAL_IP"
    JSON_YOUTUBE='"youtube.com", "googlevideo.com", "ytimg.com", "ggpht.com"'

    # 9. Spotify - 独立精简
    CONF_SPOTIFY="address=/spotify.com/$FINAL_IP
address=/scdn.co/$FINAL_IP
address=/spotifycdn.com/$FINAL_IP"
    JSON_SPOTIFY='"spotify.com", "scdn.co", "spotifycdn.com"'

    # 10. HBO Max - 独立精简
    CONF_HBO="address=/hbomax.com/$FINAL_IP
address=/max.com/$FINAL_IP
address=/hbo.com/$FINAL_IP"
    JSON_HBO='"hbomax.com", "max.com", "hbo.com"'

    # --- Menu / 菜单 ---
    if [ "$LANG_CHOICE" = "en" ]; then
        echo "Available services (enter numbers separated by commas, e.g. 1,3,5):"
        echo ""
        echo "${SKY}=== AI Services ===${NC}"
        echo "1. ChatGPT (OpenAI)"
        echo "2. Gemini (Google AI)"
        echo "3. Copilot (Microsoft)"
        echo "4. Claude (Anthropic)"
        echo ""
        echo "${SKY}=== Streaming Services ===${NC}"
        echo "5. Netflix"
        echo "6. Disney+"
        echo "7. TikTok"
        echo "8. YouTube"
        echo "9. Spotify"
        echo "10. HBO Max"
        echo ""
        echo "Quick options:"
        echo "  a = All AI (1-4)"
        echo "  s = All Streaming (5-10)"
        echo "  * = Everything"
    else
        echo "可用服务 (输入数字，用逗号分隔，例如 1,3,5):"
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
    fi
    
    echo ""
    read -p "$([ "$LANG_CHOICE" = "en" ] && echo "Enter your choice: " || echo "请输入选择: ")" SERVICE_CHOICE

    # Handle quick options / 处理快捷选项
    case "$SERVICE_CHOICE" in
        a|A)
            SERVICE_CHOICE="1,2,3,4"
            ;;
        s|S)
            SERVICE_CHOICE="5,6,7,8,9,10"
            ;;
        \*|all|ALL)
            SERVICE_CHOICE="1,2,3,4,5,6,7,8,9,10"
            ;;
    esac

    mkdir -p "$WORK_DIR"
    cd "$WORK_DIR" || exit 1
    echo "" > dnsmasq.conf
    
    FINAL_JSON_LIST=""
    TYPE_NAME=""
    local selected_count=0
    
    # Save SERVICE_CHOICE to global SERVICES for config persistence
    SERVICES="$SERVICE_CHOICE"
    
    # Parse selections / 解析选择
    IFS=',' read -ra SERVICE_ARRAY <<< "$SERVICE_CHOICE"
    for service in "${SERVICE_ARRAY[@]}"; do
        # Trim whitespace / 去除空白
        service=$(echo "$service" | tr -d '[:space:]')
        
        case $service in
            1)
                echo "$CONF_GPT" >> dnsmasq.conf
                [ -n "$FINAL_JSON_LIST" ] && FINAL_JSON_LIST="$FINAL_JSON_LIST, "
                FINAL_JSON_LIST="${FINAL_JSON_LIST}${JSON_GPT}"
                [ -n "$TYPE_NAME" ] && TYPE_NAME="$TYPE_NAME+"
                TYPE_NAME="${TYPE_NAME}ChatGPT"
                ((selected_count++))
                ;;
            2)
                echo "$CONF_GEMINI" >> dnsmasq.conf
                [ -n "$FINAL_JSON_LIST" ] && FINAL_JSON_LIST="$FINAL_JSON_LIST, "
                FINAL_JSON_LIST="${FINAL_JSON_LIST}${JSON_GEMINI}"
                [ -n "$TYPE_NAME" ] && TYPE_NAME="$TYPE_NAME+"
                TYPE_NAME="${TYPE_NAME}Gemini"
                ((selected_count++))
                ;;
            3)
                echo "$CONF_COPILOT" >> dnsmasq.conf
                [ -n "$FINAL_JSON_LIST" ] && FINAL_JSON_LIST="$FINAL_JSON_LIST, "
                FINAL_JSON_LIST="${FINAL_JSON_LIST}${JSON_COPILOT}"
                [ -n "$TYPE_NAME" ] && TYPE_NAME="$TYPE_NAME+"
                TYPE_NAME="${TYPE_NAME}Copilot"
                ((selected_count++))
                ;;
            4)
                echo "$CONF_CLAUDE" >> dnsmasq.conf
                [ -n "$FINAL_JSON_LIST" ] && FINAL_JSON_LIST="$FINAL_JSON_LIST, "
                FINAL_JSON_LIST="${FINAL_JSON_LIST}${JSON_CLAUDE}"
                [ -n "$TYPE_NAME" ] && TYPE_NAME="$TYPE_NAME+"
                TYPE_NAME="${TYPE_NAME}Claude"
                ((selected_count++))
                ;;
            5)
                echo "$CONF_NETFLIX" >> dnsmasq.conf
                [ -n "$FINAL_JSON_LIST" ] && FINAL_JSON_LIST="$FINAL_JSON_LIST, "
                FINAL_JSON_LIST="${FINAL_JSON_LIST}${JSON_NETFLIX}"
                [ -n "$TYPE_NAME" ] && TYPE_NAME="$TYPE_NAME+"
                TYPE_NAME="${TYPE_NAME}Netflix"
                ((selected_count++))
                ;;
            6)
                echo "$CONF_DISNEY" >> dnsmasq.conf
                [ -n "$FINAL_JSON_LIST" ] && FINAL_JSON_LIST="$FINAL_JSON_LIST, "
                FINAL_JSON_LIST="${FINAL_JSON_LIST}${JSON_DISNEY}"
                [ -n "$TYPE_NAME" ] && TYPE_NAME="$TYPE_NAME+"
                TYPE_NAME="${TYPE_NAME}Disney+"
                ((selected_count++))
                ;;
            7)
                echo "$CONF_TIKTOK" >> dnsmasq.conf
                [ -n "$FINAL_JSON_LIST" ] && FINAL_JSON_LIST="$FINAL_JSON_LIST, "
                FINAL_JSON_LIST="${FINAL_JSON_LIST}${JSON_TIKTOK}"
                [ -n "$TYPE_NAME" ] && TYPE_NAME="$TYPE_NAME+"
                TYPE_NAME="${TYPE_NAME}TikTok"
                ((selected_count++))
                ;;
            8)
                echo "$CONF_YOUTUBE" >> dnsmasq.conf
                [ -n "$FINAL_JSON_LIST" ] && FINAL_JSON_LIST="$FINAL_JSON_LIST, "
                FINAL_JSON_LIST="${FINAL_JSON_LIST}${JSON_YOUTUBE}"
                [ -n "$TYPE_NAME" ] && TYPE_NAME="$TYPE_NAME+"
                TYPE_NAME="${TYPE_NAME}YouTube"
                ((selected_count++))
                ;;
            9)
                echo "$CONF_SPOTIFY" >> dnsmasq.conf
                [ -n "$FINAL_JSON_LIST" ] && FINAL_JSON_LIST="$FINAL_JSON_LIST, "
                FINAL_JSON_LIST="${FINAL_JSON_LIST}${JSON_SPOTIFY}"
                [ -n "$TYPE_NAME" ] && TYPE_NAME="$TYPE_NAME+"
                TYPE_NAME="${TYPE_NAME}Spotify"
                ((selected_count++))
                ;;
            10)
                echo "$CONF_HBO" >> dnsmasq.conf
                [ -n "$FINAL_JSON_LIST" ] && FINAL_JSON_LIST="$FINAL_JSON_LIST, "
                FINAL_JSON_LIST="${FINAL_JSON_LIST}${JSON_HBO}"
                [ -n "$TYPE_NAME" ] && TYPE_NAME="$TYPE_NAME+"
                TYPE_NAME="${TYPE_NAME}HBO"
                ((selected_count++))
                ;;
            *)
                echo -e "${YELLOW}$([ "$LANG_CHOICE" = "en" ] && echo "Ignoring invalid option: $service" || echo "忽略无效选项: $service")${NC}"
                ;;
        esac
    done
    
    # Check if any service was selected / 检查是否选择了服务
    if [ $selected_count -eq 0 ]; then
        echo -e "${YELLOW}$([ "$LANG_CHOICE" = "en" ] && echo "No valid service selected, defaulting to ChatGPT" || echo "未选择有效服务，默认选择 ChatGPT")${NC}"
        echo "$CONF_GPT" >> dnsmasq.conf
        FINAL_JSON_LIST="$JSON_GPT"
        TYPE_NAME="ChatGPT"
    fi
    
    # Simplify type name if too many services / 简化显示名称
    if [ $selected_count -ge 5 ]; then
        TYPE_NAME="$([ "$LANG_CHOICE" = "en" ] && echo "Custom ($selected_count services)" || echo "自定义 ($selected_count 个服务)")"
    fi
    
    echo -e "\n${GREEN}[OK] $([ "$LANG_CHOICE" = "en" ] && echo "Selected:" || echo "已选择:") ${TYPE_NAME}${NC}\n"
    sleep 1

    # If native mode, deploy using native method
    if [ "$DEPLOY_MODE" = "native" ]; then
        deploy_service_native
        return
    fi

    # Download Dockerfile / 下载 Dockerfile
    echo -e "${SKY}===============================================${NC}"
    [ "$LANG_CHOICE" = "en" ] && echo -e "${SKY}  Building Docker Container${NC}" || echo -e "${SKY}  构建 Docker 容器${NC}"
    echo -e "${SKY}===============================================${NC}\n"
    
    if [ ! -f "Dockerfile" ]; then
        echo -e "${YELLOW}$([ "$LANG_CHOICE" = "en" ] && echo "Downloading Dockerfile..." || echo "正在下载 Dockerfile...")${NC}"
        curl -fsSL https://raw.githubusercontent.com/limitless-net/Prism-DNS/main/Dockerfile -o Dockerfile
        if [ $? -ne 0 ]; then
            echo -e "${RED}$([ "$LANG_CHOICE" = "en" ] && echo "Failed to download Dockerfile" || echo "下载 Dockerfile 失败")${NC}"
            exit 1
        fi
        echo -e "${GREEN}[OK] Dockerfile downloaded / Dockerfile 已下载${NC}"
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
    
    # Show real-time progress during Docker build to avoid appearing frozen
    # Capture build output and status
    echo -e "${YELLOW}Step 1/2: Building Docker image / 步骤 1/2: 构建镜像${NC}"
    if [ "$LANG_CHOICE" = "en" ]; then
        echo -e "${SKY}This may take 1-3 minutes depending on network speed. Please wait...${NC}"
    else
        echo -e "${SKY}这可能需要 1-3 分钟，具体取决于网络速度。请稍候...${NC}"
    fi
    
    # Create temp file for capturing build output
    local build_log=$(mktemp)
    docker compose build > "$build_log" 2>&1 &
    local build_pid=$!
    
    # Show progress while build is running
    (
        tail -f "$build_log" 2>/dev/null | while IFS= read -r line; do
            # Show step progress and important messages
            if [[ "$line" =~ (Step|#[0-9]|Successfully|ERROR|DONE|downloading|extracting) ]]; then
                echo "$line"
            fi
        done
    ) &
    local tail_pid=$!
    
    # Wait for build to complete
    wait $build_pid
    local build_status=$?
    
    # Stop the tail process gracefully
    kill -TERM $tail_pid 2>/dev/null || true
    sleep 0.5
    kill -KILL $tail_pid 2>/dev/null || true
    wait $tail_pid 2>/dev/null || true
    
    # Show any remaining important messages
    grep -E "(Successfully|ERROR)" "$build_log" 2>/dev/null || true
    rm -f "$build_log"
    
    # Check if build succeeded
    if [ $build_status -ne 0 ]; then
        echo -e "${RED}[X] $([ "$LANG_CHOICE" = "en" ] && echo "Docker build failed" || echo "Docker 构建失败")${NC}"
        echo -e "${YELLOW}$([ "$LANG_CHOICE" = "en" ] && echo "Try native mode: re-run script and select option 2" || echo "尝试原生模式：重新运行脚本并选择选项 2")${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}[OK] $([ "$LANG_CHOICE" = "en" ] && echo "Image built successfully" || echo "镜像构建成功")${NC}"
    
    echo -e "${YELLOW}Step 2/2: Starting container / 步骤 2/2: 启动容器${NC}"
    docker compose up -d
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}[OK] Service started successfully / 服务启动成功${NC}"
    else
        echo -e "${RED}[X] Failed to start service / 服务启动失败${NC}"
        exit 1
    fi
    
    sleep 2
}

# 6. Configure firewall whitelist / 配置白名单防火墙
set_firewall() {
    echo -e "\n${SKY}===============================================${NC}"
    [ "$LANG_CHOICE" = "en" ] && echo -e "${SKY}  Security Configuration: Firewall Whitelist${NC}" || echo -e "${SKY}  安全配置：防火墙白名单${NC}"
    echo -e "${SKY}===============================================${NC}\n"
    
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
        # Validate all IPs first to prevent partial configuration
        local valid_ips=()
        local has_invalid=false
        
        for ip in $CLIENT_IPS; do
            if validate_ip "$ip"; then
                valid_ips+=("$ip")
            else
                echo -e "${RED}[X] $([ "$LANG_CHOICE" = "en" ] && echo "Invalid IP address: $ip (skipped)" || echo "无效的 IP 地址: $ip (已跳过)")${NC}"
                has_invalid=true
            fi
        done
        
        if [ "$has_invalid" = true ] && [ ${#valid_ips[@]} -eq 0 ]; then
            echo -e "${RED}$([ "$LANG_CHOICE" = "en" ] && echo "No valid IP addresses provided" || echo "未提供有效的 IP 地址")${NC}"
            return 1
        fi
        
        if command -v ufw &> /dev/null; then
            ufw allow 22/tcp > /dev/null 2>&1
            for ip in "${valid_ips[@]}"; do
                ufw allow from "$ip" to any port 53 > /dev/null 2>&1
                ufw allow from "$ip" to any port 80 > /dev/null 2>&1
                ufw allow from "$ip" to any port 443 > /dev/null 2>&1
                echo -e "${GREEN}[OK] Allowed (UFW) / 已放行 (UFW): $ip${NC}"
            done
        elif command -v iptables &> /dev/null; then
            for ip in "${valid_ips[@]}"; do
                iptables -I INPUT -s "$ip" -p udp --dport 53 -j ACCEPT
                iptables -I INPUT -s "$ip" -p tcp --dport 53 -j ACCEPT
                iptables -I INPUT -s "$ip" -p tcp --dport 80 -j ACCEPT
                iptables -I INPUT -s "$ip" -p tcp --dport 443 -j ACCEPT
                echo -e "${GREEN}[OK] Allowed (iptables) / 已放行 (iptables): $ip${NC}"
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
    echo -e "\n${SKY}===============================================${NC}"
    [ "$LANG_CHOICE" = "en" ] && echo -e "${SKY}  Verifying Service Status${NC}" || echo -e "${SKY}  验证服务状态${NC}"
    echo -e "${SKY}===============================================${NC}\n"
    
    echo -e "${YELLOW}$([ "$LANG_CHOICE" = "en" ] && echo "Waiting for services to initialize..." || echo "等待服务初始化...")${NC}"
    sleep 3
    
    # Check necessary variables / 检查必要的变量是否已设置
    if [ -z "$FINAL_IP" ]; then
        echo -e "${RED}$([ "$LANG_CHOICE" = "en" ] && echo "Error: Unlock IP not detected" || echo "错误: 未检测到解锁 IP 地址")${NC}"
        return 1
    fi
    
    # Check service status based on deploy mode
    if [ "$DEPLOY_MODE" = "native" ]; then
        # Native mode: Check systemd services
        echo -e "${YELLOW}[1/3] $([ "$LANG_CHOICE" = "en" ] && echo "Checking native services..." || echo "检查原生服务...")${NC}"
        
        local services_ok=true
        if systemctl is-active --quiet dnsmasq; then
            echo -e "${GREEN}[OK] dnsmasq service running / dnsmasq 服务运行正常${NC}"
        else
            echo -e "${RED}[X] dnsmasq service not running / dnsmasq 服务未运行${NC}"
            echo -e "${RED}$([ "$LANG_CHOICE" = "en" ] && echo "Check logs: journalctl -u dnsmasq" || echo "请检查日志: journalctl -u dnsmasq")${NC}"
            services_ok=false
        fi
        
        if systemctl is-active --quiet sniproxy; then
            echo -e "${GREEN}[OK] sniproxy service running / sniproxy 服务运行正常${NC}"
        else
            echo -e "${RED}[X] sniproxy service not running / sniproxy 服务未运行${NC}"
            echo -e "${RED}$([ "$LANG_CHOICE" = "en" ] && echo "Check logs: journalctl -u sniproxy" || echo "请检查日志: journalctl -u sniproxy")${NC}"
            services_ok=false
        fi
        
        if [ "$services_ok" = false ]; then
            return 1
        fi
    else
        # Docker mode: Check container status
        echo -e "${YELLOW}[1/3] Checking Docker container / 检查 Docker 容器...${NC}"
        if docker ps | grep -q "dns_unlock"; then
            echo -e "${GREEN}[OK] Docker container running / Docker 容器运行正常${NC}"
        else
            echo -e "${RED}[X] Docker container not running / Docker 容器未运行${NC}"
            echo -e "${RED}$([ "$LANG_CHOICE" = "en" ] && echo "Check logs: docker logs dns_unlock" || echo "请检查日志: docker logs dns_unlock")${NC}"
            return 1
        fi
    fi
    
    # Check port listening / 检查端口监听
    echo -e "\n${YELLOW}[2/3] Checking port listening status / 检查端口监听状态...${NC}"
    
    local dns_ok=false
    local http_ok=false
    local https_ok=false
    
    if netstat -tuln 2>/dev/null | grep -E ':53([[:space:]]|$)' > /dev/null || ss -tuln 2>/dev/null | grep -E ':53([[:space:]]|$)' > /dev/null; then
        echo -e "${GREEN}[OK] DNS port (53) listening / DNS 端口 (53) 正常监听${NC}"
        dns_ok=true
    else
        echo -e "${RED}[X] DNS port (53) not listening / DNS 端口 (53) 未监听${NC}"
    fi
    
    if netstat -tuln 2>/dev/null | grep -E ':80([[:space:]]|$)' > /dev/null || ss -tuln 2>/dev/null | grep -E ':80([[:space:]]|$)' > /dev/null; then
        echo -e "${GREEN}[OK] HTTP port (80) listening / HTTP 端口 (80) 正常监听${NC}"
        http_ok=true
    else
        echo -e "${RED}[X] HTTP port (80) not listening / HTTP 端口 (80) 未监听${NC}"
    fi
    
    if netstat -tuln 2>/dev/null | grep -E ':443([[:space:]]|$)' > /dev/null || ss -tuln 2>/dev/null | grep -E ':443([[:space:]]|$)' > /dev/null; then
        echo -e "${GREEN}[OK] HTTPS port (443) listening / HTTPS 端口 (443) 正常监听${NC}"
        https_ok=true
    else
        echo -e "${RED}[X] HTTPS port (443) not listening / HTTPS 端口 (443) 未监听${NC}"
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
        echo -e "${YELLOW}[!] $([ "$LANG_CHOICE" = "en" ] && echo "Cannot determine test domain, skipping DNS test" || echo "无法确定测试域名，跳过 DNS 解析测试")${NC}"
        return 0
    fi
    
    # Try using dig first (more reliable) / 优先使用 dig (更可靠)
    if command -v dig &> /dev/null; then
        DNS_RESULT=$(dig +short @$FINAL_IP $TEST_DOMAIN 2>/dev/null | tail -1)
        
        if [ "$DNS_RESULT" == "$FINAL_IP" ]; then
            echo -e "${GREEN}[OK] DNS hijack configured correctly / DNS 劫持配置正确${NC}"
            echo -e "${GREEN}  $TEST_DOMAIN -> $FINAL_IP${NC}"
        else
            echo -e "${YELLOW}[!] DNS test result / DNS 测试结果: $TEST_DOMAIN -> ${DNS_RESULT:-no response}${NC}"
            [ "$LANG_CHOICE" = "en" ] && \
                echo -e "${YELLOW}  Tip: Wait for Docker to fully start, then test manually: dig +short @$FINAL_IP $TEST_DOMAIN${NC}" || \
                echo -e "${YELLOW}  提示: 等待 Docker 服务完全启动后，可手动测试: dig +short @$FINAL_IP $TEST_DOMAIN${NC}"
        fi
    # Fall back to nslookup / 降级使用 nslookup
    elif command -v nslookup &> /dev/null; then
        DNS_OUTPUT=$(nslookup $TEST_DOMAIN $FINAL_IP 2>/dev/null)
        DNS_RESULT=$(echo "$DNS_OUTPUT" | grep -v "^Server:" | grep "Address:" | tail -1 | awk '{print $2}' | tr -d '#')
        
        if [ -z "$DNS_RESULT" ]; then
            echo -e "${YELLOW}[!] $([ "$LANG_CHOICE" = "en" ] && echo "DNS test: No result" || echo "DNS 测试未能获取解析结果")${NC}"
            [ "$LANG_CHOICE" = "en" ] && \
                echo -e "${YELLOW}  Tip: Wait for Docker to fully start, then test manually: nslookup $TEST_DOMAIN $FINAL_IP${NC}" || \
                echo -e "${YELLOW}  提示: 等待 Docker 服务完全启动后，可手动测试: nslookup $TEST_DOMAIN $FINAL_IP${NC}"
        elif [ "$DNS_RESULT" == "$FINAL_IP" ]; then
            echo -e "${GREEN}[OK] DNS hijack configured correctly / DNS 劫持配置正确${NC}"
            echo -e "${GREEN}  $TEST_DOMAIN -> $FINAL_IP${NC}"
        else
            echo -e "${YELLOW}[!] DNS test result / DNS 测试结果: $TEST_DOMAIN -> $DNS_RESULT${NC}"
            [ "$LANG_CHOICE" = "en" ] && \
                echo -e "${YELLOW}  Tip: Wait for Docker to fully start, then test manually: nslookup $TEST_DOMAIN $FINAL_IP${NC}" || \
                echo -e "${YELLOW}  提示: 等待 Docker 服务完全启动后，可手动测试: nslookup $TEST_DOMAIN $FINAL_IP${NC}"
        fi
    else
        echo -e "${YELLOW}[!] $([ "$LANG_CHOICE" = "en" ] && echo "dig/nslookup not installed, skipping DNS test" || echo "dig/nslookup 未安装，跳过 DNS 解析测试")${NC}"
        [ "$LANG_CHOICE" = "en" ] && \
            echo -e "${YELLOW}  Install and test: apt install -y dnsutils && dig +short @$FINAL_IP $TEST_DOMAIN${NC}" || \
            echo -e "${YELLOW}  可手动安装后测试: apt install -y dnsutils && dig +short @$FINAL_IP $TEST_DOMAIN${NC}"
    fi
    
    echo ""
    return 0
}

# 8. Generate final JSON configuration / 生成最终 JSON
generate_json() {
    echo -e "${GREEN}===============================================${NC}"
    if [ "$LANG_CHOICE" = "en" ]; then
        echo -e "${GREEN}   === Setup Complete! Copy JSON Below   ${NC}"
    else
        echo -e "${GREEN}   === 搭建完成！请复制下方 JSON 覆盖 V2bX 模版   ${NC}"
    fi
    echo -e "${GREEN}===============================================${NC}"
    
    echo -e "$([ "$LANG_CHOICE" = "en" ] && echo "Unlock IP:" || echo "解锁 IP:") ${YELLOW}$FINAL_IP${NC}"
    echo -e "$([ "$LANG_CHOICE" = "en" ] && echo "Current Mode:" || echo "当前模式:") ${SKY}$TYPE_NAME${NC}"
    
    if [ "$LANG_CHOICE" = "en" ]; then
        echo -e "Features: Audit blocking + Selected unlock rules + New core compatible"
    else
        echo -e "功能: 审计屏蔽 + 选定解锁规则 + 兼容新版核心"
    fi
    
    echo -e "${YELLOW}"

    # Route rules description / 路由规则说明:
    # 1. Unlock domains routed to unlock outbound (via DNS hijack to unlock server) / 解锁域名走 unlock 出站（通过 DNS 劫持到解锁机）
    # 2. Private IP traffic blocked / 私有 IP 流量被屏蔽
    # 3. Audit rule matched traffic blocked (BT, return to China traffic, etc.) / 审计规则匹配的流量被屏蔽 (BT、回国流量等)
    # 4. All other traffic goes direct via UDP/TCP / 其他所有流量通过 UDP/TCP 走 direct
    #
    # Note: domain_suffix appears in BOTH dns.rules AND route.rules intentionally:
    # 注意：domain_suffix 同时出现在 dns.rules 和 route.rules 中是有意为之：
    # - dns.rules: Route DNS queries to unlock_dns (returns unlock server IP)
    #   dns.rules: 将 DNS 查询路由到解锁机（返回解锁机 IP）
    # - route.rules: Ensure traffic for these domains is routed correctly
    #   route.rules: 确保这些域名的流量被正确路由

    # Validate FINAL_IP is set before generating config
    if [ -z "$FINAL_IP" ]; then
        echo -e "${RED}$([ "$LANG_CHOICE" = "en" ] && echo "Error: Unlock IP not set, cannot generate configuration" || echo "错误: 解锁 IP 未设置，无法生成配置")${NC}"
        return 1
    fi

    # Generate IP CIDR format based on IP version
    # IPv6 addresses always contain colons, IPv4 never does
    local IP_CIDR
    if [[ "$FINAL_IP" == *":"* ]]; then
        # IPv6 address (validated by validate_ip function earlier)
        IP_CIDR="${FINAL_IP}/128"
    else
        # IPv4 address (validated by validate_ip function earlier)
        IP_CIDR="${FINAL_IP}/32"
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
    echo -e "${NC}"
    
    # Print usage instructions and verification steps / 打印使用说明和验证步骤
    print_instructions
}

# Print bilingual instructions / 打印双语说明
print_instructions() {
    echo -e "\n${SKY}===============================================${NC}"
    if [ "$LANG_CHOICE" = "en" ]; then
        echo -e "${SKY}     Important Notes & Verification Steps     ${NC}"
    else
        echo -e "${SKY}            重要说明与验证步骤                ${NC}"
    fi
    echo -e "${SKY}===============================================${NC}"
    
    if [ "$LANG_CHOICE" = "en" ]; then
        cat <<'EOF'

0. How Prism-DNS Works (Working Principle):
   +-----------------------------------------------------------+
   |  User Device -> Landing Node (Japan) -> Internet          |
   |       | (DNS query for netflix.com)                       |
   |  Landing Node asks Unlock Server (HK) for DNS             |
   |       | (DNS returns Unlock Server IP)                    |
   |  Landing Node connects to Unlock Server IP                |
   |       | (SNI Proxy on Unlock Server)                      |
   |  Unlock Server forwards to Real Netflix                   |
   |       | (Unlock Server has native HK IP)                  |
   |  Netflix sees Hong Kong IP, not Japan IP! [OK]            |
   +-----------------------------------------------------------+
   
   Key Components:
   a) DNS Hijacking: DNS queries for unlock domains (netflix.com, 
      openai.com, etc.) are sent to unlock server instead of 
      public DNS (1.1.1.1)
   b) Unlock Server Returns Its Own IP: When landing node asks 
      "what is netflix.com?", unlock server replies with its own 
      IP address instead of real Netflix IP
   c) SNI Proxy: When landing node connects to "Netflix" (actually 
      unlock server IP), SNI proxy forwards the connection to real 
      Netflix, using unlock server's native IP
   d) Result: Netflix sees unlock server's Hong Kong IP, not 
      landing server's Japan IP

   Why Your Setup Shows Landing Location:
   - If you still see Japan location after setup, it means:
     [X] DNS queries are NOT going to unlock server (check DNS config)
     [X] Route rules are NOT matching unlock domains (check JSON config)
     [X] Firewall is blocking traffic (check ports 53/80/443)
     [X] Node was not restarted after config change
   
   Complete Traffic Flow for Unlock:
   1. User opens Netflix
   2. Landing node needs to resolve netflix.com
   3. DNS rules in JSON route query to unlock server (not 1.1.1.1)
   4. Unlock server returns its own IP: HK_IP
   5. Landing node connects to HK_IP (thinks it's Netflix)
   6. Route rules match netflix.com domain -> use unlock outbound
   7. SNI proxy on unlock server forwards to real Netflix
   8. Netflix sees Hong Kong IP [OK]

1. Geographic Location Requirements:
   [OK] Unlock server and landing server [DO NOT NEED] to be in the same region
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
        if [ "$DEPLOY_MODE" = "native" ]; then
            echo -e "     ${SKY}journalctl -u dnsmasq -f${NC}"
            echo -e "     ${SKY}journalctl -u sniproxy -f${NC}"
        else
            echo -e "     ${SKY}docker logs -f dns_unlock${NC}"
        fi
        cat <<'EOF'
   Method 2 - Access test from client:
     - ChatGPT: https://chat.openai.com
     - Netflix: https://www.netflix.com
     - TikTok: Open TikTok APP and check content
   Method 3 - Check DNS resolution (MOST IMPORTANT!):
EOF
        echo -e "     ${SKY}nslookup openai.com ${FINAL_IP}${NC}"
        echo -e "     (Should return: ${YELLOW}${FINAL_IP}${NC})"
        cat <<'EOF'
     This test confirms DNS hijacking is working correctly.
     If it returns real OpenAI IP address instead of unlock server IP,
     the DNS configuration has a problem.
   
   Method 4 - Test from landing server:
     After applying JSON config and restarting node, connect to
     the landing node from your device, then:
EOF
        echo -e "     ${SKY}curl -I https://www.netflix.com${NC}"
        echo "     Check if connection succeeds and shows HK region content"
        cat <<'EOF'

5. Common Management Commands:
EOF
        if [ "$DEPLOY_MODE" = "native" ]; then
            echo -e "   View service status: ${SKY}systemctl status dnsmasq sniproxy${NC}"
            echo -e "   View live logs: ${SKY}journalctl -u dnsmasq -u sniproxy -f${NC}"
            echo -e "   Restart service: ${SKY}systemctl restart dnsmasq sniproxy${NC}"
            echo -e "   Stop service: ${SKY}systemctl stop dnsmasq sniproxy${NC}"
        else
            echo -e "   View service status: ${SKY}docker ps${NC}"
            echo -e "   View live logs: ${SKY}docker logs -f dns_unlock${NC}"
            echo -e "   Restart service: ${SKY}cd $WORK_DIR && docker compose restart${NC}"
            echo -e "   Stop service: ${SKY}cd $WORK_DIR && docker compose down${NC}"
        fi
        echo -e "   Redeploy: ${SKY}bash <(curl -Ls https://raw.githubusercontent.com/limitless-net/Prism-DNS/main/install.sh)${NC}"
    else
        cat <<'EOF'

0. Prism-DNS 工作原理说明：
   +-----------------------------------------------------------+
   |  用户设备 -> 落地节点(日本) -> 互联网                     |
   |       | (DNS 查询 netflix.com)                            |
   |  落地节点向解锁机(香港)查询 DNS                           |
   |       | (DNS 返回解锁机 IP)                               |
   |  落地节点连接到解锁机 IP                                  |
   |       | (解锁机上的 SNI 代理)                             |
   |  解锁机转发到真实的 Netflix                               |
   |       | (解锁机有香港原生 IP)                             |
   |  Netflix 看到的是香港 IP，不是日本 IP! [OK]              |
   +-----------------------------------------------------------+
   
   核心组件说明：
   a) DNS 劫持：需要解锁的域名(netflix.com、openai.com等)
      的 DNS 查询会被发送到解锁机，而不是公共 DNS (1.1.1.1)
   b) 解锁机返回自己的 IP：当落地节点询问"netflix.com 的 
      IP 是什么"时，解锁机回答自己的 IP，而不是真实的 
      Netflix IP
   c) SNI 代理：当落地节点连接到"Netflix"(实际是解锁机IP)
      时，SNI 代理会将连接转发到真实的 Netflix，使用解锁
      机的原生 IP
   d) 最终效果：Netflix 看到的是解锁机的香港 IP，而不是
      落地机的日本 IP

   为什么您的配置后还是显示落地地区：
   - 如果配置后还显示日本地区，说明：
     [X] DNS 查询没有发送到解锁机 (检查 DNS 配置)
     [X] 路由规则没有匹配解锁域名 (检查 JSON 配置)
     [X] 防火墙阻止了流量 (检查 53/80/443 端口)
     [X] 节点配置修改后没有重启
   
   完整的解锁流量走向：
   1. 用户打开 Netflix
   2. 落地节点需要解析 netflix.com
   3. JSON 中的 DNS 规则将查询路由到解锁机 (不是 1.1.1.1)
   4. 解锁机返回自己的 IP: HK_IP
   5. 落地节点连接到 HK_IP (以为是 Netflix)
   6. 路由规则匹配 netflix.com 域名 -> 使用 unlock 出站
   7. 解锁机上的 SNI 代理转发到真实的 Netflix
   8. Netflix 看到香港 IP [OK]

1. 地理位置要求：
   [OK] 解锁机和落地机【不需要】在同一地区
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
        if [ "$DEPLOY_MODE" = "native" ]; then
            echo -e "     ${SKY}journalctl -u dnsmasq -f${NC}"
            echo -e "     ${SKY}journalctl -u sniproxy -f${NC}"
        else
            echo -e "     ${SKY}docker logs -f dns_unlock${NC}"
        fi
        cat <<'EOF'
   方法2 - 在客户端访问测试:
     - ChatGPT: https://chat.openai.com
     - Netflix: https://www.netflix.com
     - TikTok: 打开 TikTok APP 查看内容
   方法3 - 检查 DNS 解析 (最重要!):
EOF
        echo -e "     ${SKY}nslookup openai.com ${FINAL_IP}${NC}"
        echo -e "     (应该返回: ${YELLOW}${FINAL_IP}${NC})"
        cat <<'EOF'
     这个测试确认 DNS 劫持是否正常工作。
     如果返回的是真实的 OpenAI IP 而不是解锁机 IP，
     说明 DNS 配置有问题。
   
   方法4 - 从落地机测试:
     应用 JSON 配置并重启节点后，从你的设备连接到
     落地节点，然后执行：
EOF
        echo -e "     ${SKY}curl -I https://www.netflix.com${NC}"
        echo "     检查连接是否成功，是否显示香港地区内容"
        cat <<'EOF'

5. 常用管理命令：
EOF
        if [ "$DEPLOY_MODE" = "native" ]; then
            echo -e "   查看服务状态: ${SKY}systemctl status dnsmasq sniproxy${NC}"
            echo -e "   查看实时日志: ${SKY}journalctl -u dnsmasq -u sniproxy -f${NC}"
            echo -e "   重启服务: ${SKY}systemctl restart dnsmasq sniproxy${NC}"
            echo -e "   停止服务: ${SKY}systemctl stop dnsmasq sniproxy${NC}"
        else
            echo -e "   查看服务状态: ${SKY}docker ps${NC}"
            echo -e "   查看实时日志: ${SKY}docker logs -f dns_unlock${NC}"
            echo -e "   重启服务: ${SKY}cd $WORK_DIR && docker compose restart${NC}"
            echo -e "   停止服务: ${SKY}cd $WORK_DIR && docker compose down${NC}"
        fi
        echo -e "   重新部署: ${SKY}bash <(curl -Ls https://raw.githubusercontent.com/limitless-net/Prism-DNS/main/install.sh)${NC}"
    fi
    
    echo -e "\n${GREEN}===============================================${NC}"
    if [ "$LANG_CHOICE" = "en" ]; then
        echo -e "${GREEN}  For issues, check GitHub Issues or submit feedback  ${NC}"
    else
        echo -e "${GREEN}  如有问题，请查看项目 GitHub Issues 或提交反馈  ${NC}"
    fi
    echo -e "${GREEN}===============================================${NC}\n"
}

# Uninstall service / 卸载服务
uninstall_service() {
    echo -e "\n${SKY}===============================================${NC}"
    [ "$LANG_CHOICE" = "en" ] && echo -e "${SKY}  Uninstalling Prism-DNS Unlock Service${NC}" || echo -e "${SKY}  卸载 Prism-DNS 解锁服务${NC}"
    echo -e "${SKY}===============================================${NC}\n"
    
    # Confirm uninstallation
    if [ "$LANG_CHOICE" = "en" ]; then
        echo -e "${YELLOW}Warning: This will remove all Prism-DNS components and configurations.${NC}"
        read -p "Are you sure you want to continue? [y/N]: " confirm
    else
        echo -e "${YELLOW}警告: 这将删除所有 Prism-DNS 组件和配置。${NC}"
        read -p "确定要继续吗? [y/N]: " confirm
    fi
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}$([ "$LANG_CHOICE" = "en" ] && echo "Uninstallation cancelled" || echo "卸载已取消")${NC}"
        return 0
    fi
    
    # Detect deployment mode by checking what's installed
    local has_docker=false
    local has_native=false
    local docker_container_exists=false
    local docker_image_exists=false
    local workdir_removed=false
    
    # Check for Docker installation
    if command -v docker &> /dev/null; then
        if docker ps -a 2>/dev/null | grep -q "dns_unlock"; then
            docker_container_exists=true
            has_docker=true
        fi
        if docker images 2>/dev/null | grep -q "prism-dns"; then
            docker_image_exists=true
            has_docker=true
        fi
    fi
    
    # Check for Native installation - the presence of unlock.conf is the key indicator
    if [ -f /etc/dnsmasq.d/unlock.conf ]; then
        has_native=true
    fi
    
    # Uninstall Docker mode
    if [ "$has_docker" = true ]; then
        echo -e "\n${YELLOW}$([ "$LANG_CHOICE" = "en" ] && echo "Removing Docker deployment..." || echo "卸载 Docker 部署...")${NC}"
        
        # Stop and remove container
        if [ "$docker_container_exists" = true ]; then
            echo -e "${YELLOW}$([ "$LANG_CHOICE" = "en" ] && echo "Stopping container..." || echo "停止容器...")${NC}"
            docker stop dns_unlock 2>/dev/null || true
            docker rm dns_unlock 2>/dev/null || true
            echo -e "${GREEN}[OK] $([ "$LANG_CHOICE" = "en" ] && echo "Container removed" || echo "容器已删除")${NC}"
        fi
        
        # Remove Docker image
        if [ "$docker_image_exists" = true ]; then
            echo -e "${YELLOW}$([ "$LANG_CHOICE" = "en" ] && echo "Removing Docker image..." || echo "删除 Docker 镜像...")${NC}"
            docker rmi prism-dns:latest 2>/dev/null || true
            echo -e "${GREEN}[OK] $([ "$LANG_CHOICE" = "en" ] && echo "Docker image removed" || echo "Docker 镜像已删除")${NC}"
        fi
    fi
    
    # Uninstall Native mode
    if [ "$has_native" = true ]; then
        echo -e "\n${YELLOW}$([ "$LANG_CHOICE" = "en" ] && echo "Removing native deployment..." || echo "卸载原生部署...")${NC}"
        
        # Check if dnsmasq was enabled before stopping (for later restoration)
        local dnsmasq_was_enabled=false
        if systemctl is-enabled dnsmasq >/dev/null 2>&1; then
            dnsmasq_was_enabled=true
        fi
        
        # Stop services
        echo -e "${YELLOW}$([ "$LANG_CHOICE" = "en" ] && echo "Stopping services..." || echo "停止服务...")${NC}"
        systemctl stop dnsmasq 2>/dev/null || true
        systemctl stop sniproxy 2>/dev/null || true
        systemctl disable dnsmasq 2>/dev/null || true
        systemctl disable sniproxy 2>/dev/null || true
        echo -e "${GREEN}[OK] $([ "$LANG_CHOICE" = "en" ] && echo "Services stopped" || echo "服务已停止")${NC}"
        
        # Remove unlock configuration
        if [ -f /etc/dnsmasq.d/unlock.conf ]; then
            echo -e "${YELLOW}$([ "$LANG_CHOICE" = "en" ] && echo "Removing DNS unlock rules..." || echo "删除 DNS 解锁规则...")${NC}"
            rm -f /etc/dnsmasq.d/unlock.conf
            echo -e "${GREEN}[OK] $([ "$LANG_CHOICE" = "en" ] && echo "DNS unlock rules removed" || echo "DNS 解锁规则已删除")${NC}"
        fi
        
        # Restore original dnsmasq config if backup exists
        if [ -f /etc/dnsmasq.conf.bak ]; then
            echo -e "${YELLOW}$([ "$LANG_CHOICE" = "en" ] && echo "Restoring original dnsmasq config..." || echo "恢复原始 dnsmasq 配置...")${NC}"
            mv /etc/dnsmasq.conf.bak /etc/dnsmasq.conf
            echo -e "${GREEN}[OK] $([ "$LANG_CHOICE" = "en" ] && echo "Original config restored" || echo "原始配置已恢复")${NC}"
        fi
        
        # Restart dnsmasq if it was enabled before we stopped it
        if [ "$dnsmasq_was_enabled" = true ]; then
            systemctl enable dnsmasq 2>/dev/null || true
            systemctl start dnsmasq 2>/dev/null || true
        fi
        
        # Note about packages
        if [ "$LANG_CHOICE" = "en" ]; then
            echo -e "\n${YELLOW}Note: dnsmasq and sniproxy packages were not removed.${NC}"
            echo -e "${YELLOW}If you want to remove them, run:${NC}"
            echo -e "${SKY}  apt-get remove --purge dnsmasq sniproxy${NC}"
        else
            echo -e "\n${YELLOW}注意: dnsmasq 和 sniproxy 软件包未被删除。${NC}"
            echo -e "${YELLOW}如需删除，请运行:${NC}"
            echo -e "${SKY}  apt-get remove --purge dnsmasq sniproxy${NC}"
        fi
    fi
    
    # Remove working directory (common for both modes)
    if [ -d "$WORK_DIR" ]; then
        if [ "$has_docker" = true ]; then
            echo -e "\n${YELLOW}$([ "$LANG_CHOICE" = "en" ] && echo "Removing configuration files..." || echo "删除配置文件...")${NC}"
            rm -rf "$WORK_DIR"
            workdir_removed=true
            echo -e "${GREEN}[OK] $([ "$LANG_CHOICE" = "en" ] && echo "Configuration files removed" || echo "配置文件已删除")${NC}"
        else
            # For native mode, remove silently
            rm -rf "$WORK_DIR"
            workdir_removed=true
        fi
    fi
    
    # Clean up firewall rules (optional, commented out to avoid disrupting other services)
    # Users can manually clean up firewall rules if needed
    
    if [ "$has_docker" = false ] && [ "$has_native" = false ]; then
        echo -e "${YELLOW}$([ "$LANG_CHOICE" = "en" ] && echo "No Prism-DNS installation found" || echo "未找到 Prism-DNS 安装")${NC}"
    else
        echo -e "\n${GREEN}===============================================${NC}"
        echo -e "${GREEN}$([ "$LANG_CHOICE" = "en" ] && echo "[OK] Uninstallation completed successfully" || echo "[OK] 卸载成功完成")${NC}"
        echo -e "${GREEN}===============================================${NC}\n"
        
        if [ "$LANG_CHOICE" = "en" ]; then
            echo "Removed components:"
            [ "$has_docker" = true ] && echo "  - Docker container and image"
            [ "$has_native" = true ] && echo "  - Native service configuration"
            [ "$workdir_removed" = true ] && echo "  - Configuration files in $WORK_DIR"
            echo ""
            echo "Note: Firewall rules were not modified."
            echo "If you configured firewall rules, you may want to review and clean them up manually."
        else
            echo "已删除的组件："
            [ "$has_docker" = true ] && echo "  - Docker 容器和镜像"
            [ "$has_native" = true ] && echo "  - 原生服务配置"
            [ "$workdir_removed" = true ] && echo "  - $WORK_DIR 中的配置文件"
            echo ""
            echo "注意：防火墙规则未被修改。"
            echo "如果您配置了防火墙规则，可能需要手动检查并清理它们。"
        fi
    fi
}

# ======================== Main Menu ========================

# Show main menu / 显示主菜单
show_main_menu() {
    show_header
    
    echo -e "  ${SKY}+-----------------------------------------------+${NC}"
    if [ "$LANG_CHOICE" = "en" ]; then
        echo -e "  ${SKY}|${NC}              ${WHITE}${BOLD}Main Menu${NC}                       ${SKY}|${NC}"
    else
        echo -e "  ${SKY}|${NC}                ${WHITE}${BOLD}主菜单${NC}                        ${SKY}|${NC}"
    fi
    echo -e "  ${SKY}+-----------------------------------------------+${NC}"
    echo ""
    
    if [ "$LANG_CHOICE" = "en" ]; then
        echo -e "  ${GREEN}1)${NC}  Install / Reinstall Unlock Service"
        echo -e "  ${GREEN}2)${NC}  View Running Status"
        echo -e "  ${GREEN}3)${NC}  Manage IP Whitelist"
        echo -e "  ${GREEN}4)${NC}  Generate JSON Config"
        echo -e "  ${GREEN}5)${NC}  Test Unlock Status"
        echo -e "  ${GREEN}6)${NC}  View Service Logs"
        echo -e "  ${GREEN}7)${NC}  Restart Service"
        echo -e "  ${GREEN}8)${NC}  One-Click Cleanup"
        echo ""
        echo -e "  ${SKY}-----------------------------------------------${NC}"
        echo -e "  ${RED}9)${NC}  Uninstall Unlock Service"
        echo -e "  ${RED}0)${NC}  Exit"
    else
        echo -e "  ${GREEN}1)${NC}  安装 / 重装解锁服务"
        echo -e "  ${GREEN}2)${NC}  查看运行状态"
        echo -e "  ${GREEN}3)${NC}  管理 IP 白名单"
        echo -e "  ${GREEN}4)${NC}  生成 JSON 配置"
        echo -e "  ${GREEN}5)${NC}  测试解锁状态"
        echo -e "  ${GREEN}6)${NC}  查看服务日志"
        echo -e "  ${GREEN}7)${NC}  重启服务"
        echo -e "  ${GREEN}8)${NC}  一键清理"
        echo ""
        echo -e "  ${SKY}-----------------------------------------------${NC}"
        echo -e "  ${RED}9)${NC}  卸载解锁服务"
        echo -e "  ${RED}0)${NC}  退出"
    fi
    
    echo ""
    echo -e "  ${SKY}+-----------------------------------------------+${NC}"
    echo ""
}

# Run installation process / 运行安装流程
run_install() {
    # Create working directory with secure permissions
    mkdir -p "$WORK_DIR"
    chmod 755 "$WORK_DIR" 2>/dev/null
    
    check_port_availability
    select_public_ip
    select_deploy_mode
    
    # Install dependencies based on deployment mode
    if [ "$DEPLOY_MODE" = "native" ]; then
        install_native
    else
        install_docker
    fi
    
    deploy_service
    set_firewall
    verify_services
    generate_json
    save_config
    
    press_enter
}

# Main execution flow / 主流程
main() {
    select_language
    
    while true; do
        show_main_menu
        
        read -p "  $([ "$LANG_CHOICE" = "en" ] && echo "Please select [0-9]: " || echo "请选择 [0-9]: ")" choice
        
        case "$choice" in
            1)
                run_install
                ;;
            2)
                view_status
                ;;
            3)
                manage_whitelist
                ;;
            4)
                generate_json
                press_enter
                ;;
            5)
                test_unlock
                ;;
            6)
                view_logs
                ;;
            7)
                restart_service
                ;;
            8)
                cleanup_all
                ;;
            9)
                uninstall_service
                press_enter
                ;;
            0)
                echo ""
                if [ "$LANG_CHOICE" = "en" ]; then
                    echo -e "  ${GREEN}Thank you for using Prism-DNS! Goodbye!${NC}"
                else
                    echo -e "  ${GREEN}感谢使用 Prism-DNS！再见！${NC}"
                fi
                echo ""
                exit 0
                ;;
            *)
                msg_err "$([ "$LANG_CHOICE" = "en" ] && echo "Invalid option, please try again" || echo "无效选项，请重新选择")"
                sleep 1
                ;;
        esac
    done
}

# Run main function / 运行主函数
main
