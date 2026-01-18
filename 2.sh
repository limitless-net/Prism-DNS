#!/bin/bash
# ==========================================================
#   Prism-DNS 解锁服务总控脚本 (V8.0 交互式菜单版)
#   Features:
#     1. 美观的交互式菜单 UI
#     2. 安装/卸载/一键清理
#     3. 生成配置文件
#     4. IP 白名单管理 (添加/删除/查看)
#     5. 一键检测运行状态
#     6. 一键测试劫持是否成功
#     7. 防火墙自锁保护 (强制 SSH 放行)
#     8. Docker/原生双模式优化
# ==========================================================

# ======================== 颜色定义 ========================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'

# ======================== 路径定义 ========================
WORK_DIR="/root/dns_unlock"
WHITELIST_FILE="$WORK_DIR/whitelist.txt"
CONFIG_INFO_FILE="$WORK_DIR/install_info.conf"
LOG_FILE="$WORK_DIR/install.log"

# ======================== 全局变量 ========================
SERVER_IP=""
DEPLOY_MODE=""
SERVICES=""
INSTALLED_STATUS="未安装"

# ======================== UI 辅助函数 ========================

# 清屏并显示标题
show_header() {
    clear
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}     ${WHITE}${BOLD}🌐 Prism-DNS 解锁服务管理面板 V8.0${NC}     ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}     ${DIM}NodePass / V2bX 专用 DNS 劫持 + SNI 代理${NC}     ${CYAN}║${NC}"
    echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}  ${GREEN}当前解锁模式：${WHITE}${DEPLOY_MODE:-未安装}${NC}                                   ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${GREEN}当前解锁机 IP：${WHITE}${SERVER_IP:-未检测}${NC}                           ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# 显示分隔线
show_divider() {
    echo -e "${CYAN}──────────────────────────────────────────────────────────────────${NC}"
}

# 显示子标题
show_subtitle() {
    local title="$1"
    echo ""
    echo -e "${CYAN}┌─────────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│${NC} ${WHITE}${BOLD}$title${NC}"
    echo -e "${CYAN}└─────────────────────────────────────────────────────────────────┘${NC}"
    echo ""
}

# 成功消息
msg_ok() {
    echo -e "  ${GREEN}✓${NC} $1"
}

# 错误消息
msg_err() {
    echo -e "  ${RED}✗${NC} $1"
}

# 警告消息
msg_warn() {
    echo -e "  ${YELLOW}⚠${NC} $1"
}

# 信息消息
msg_info() {
    echo -e "  ${BLUE}ℹ${NC} $1"
}

# 加载动画
spinner() {
    local pid=$1
    local msg=$2
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    
    while kill -0 $pid 2>/dev/null; do
        i=$(( (i+1) % 10 ))
        printf "\r  ${CYAN}${spin:$i:1}${NC} ${msg}"
        sleep 0.1
    done
    printf "\r"
}

# 按回车继续
press_enter() {
    echo ""
    read -p "  按 Enter 键返回主菜单..." _
}

# ======================== 基础工具函数 ========================

# 检查 Root 权限
check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo -e "${RED}错误: 必须使用 root 权限运行此脚本${NC}"
        exit 1
    fi
}

# IP 格式验证
validate_ip() {
    local ip="$1"
    ip=$(echo "$ip" | tr -d '[:space:]')
    
    if [ -z "$ip" ]; then
        return 1
    fi
    
    # 检查危险字符
    case "$ip" in
        *[!.:0-9a-fA-F]*)
            return 1
            ;;
    esac
    
    # IPv4 验证
    if [[ "$ip" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]]; then
        local octet
        for octet in "${BASH_REMATCH[@]:1}"; do
            if [ "$((10#$octet))" -gt 255 ]; then
                return 1
            fi
        done
        return 0
    fi
    
    # IPv6 验证
    if [[ "$ip" =~ ^[0-9a-fA-F:]+$ ]] && [[ "$ip" == *:* ]]; then
        if [[ "$ip" =~ :::+ ]]; then
            return 1
        fi
        case "$ip" in
            *::*::*)
                return 1
                ;;
        esac
        return 0
    fi
    
    return 1
}

# 自动检测公网 IP
detect_public_ip() {
    # 先从配置文件读取
    if [ -f "$CONFIG_INFO_FILE" ]; then
        source "$CONFIG_INFO_FILE"
    fi
    
    if [ -z "$SERVER_IP" ]; then
        SERVER_IP=$(curl -4 -s --max-time 5 api.ip.sb/ip 2>/dev/null || curl -4 -s --max-time 5 ifconfig.me 2>/dev/null)
        if [ -z "$SERVER_IP" ]; then
            SERVER_IP=$(curl -6 -s --max-time 5 api.ip.sb/ip 2>/dev/null)
        fi
    fi
}

# 检测安装状态
detect_install_status() {
    if [ -f "$CONFIG_INFO_FILE" ]; then
        source "$CONFIG_INFO_FILE"
    fi
    
    # 检测 Docker 模式
    if command -v docker &> /dev/null && docker ps 2>/dev/null | grep -q "dns_unlock"; then
        INSTALLED_STATUS="运行中 (Docker)"
        DEPLOY_MODE="Docker"
        return 0
    fi
    
    # 检测原生模式
    if systemctl is-active dnsmasq >/dev/null 2>&1 && [ -f /etc/dnsmasq.d/unlock.conf ]; then
        INSTALLED_STATUS="运行中 (原生)"
        DEPLOY_MODE="原生"
        return 0
    fi
    
    if [ -f "$WORK_DIR/dnsmasq_rules.conf" ]; then
        INSTALLED_STATUS="已安装 (已停止)"
    else
        INSTALLED_STATUS="未安装"
        DEPLOY_MODE=""
    fi
}

# 保存配置信息
save_config() {
    mkdir -p "$WORK_DIR"
    cat > "$CONFIG_INFO_FILE" << EOF
SERVER_IP="$SERVER_IP"
DEPLOY_MODE="$DEPLOY_MODE"
SERVICES="$SERVICES"
INSTALL_DATE="$(date '+%Y-%m-%d %H:%M:%S')"
EOF
}

# ======================== 核心功能函数 ========================

# 1. 安装/重装解锁服务
install_service() {
    show_header
    show_subtitle "🔧 安装 / 重装解锁服务"
    
    # 选择部署模式
    echo -e "  ${YELLOW}请选择部署模式：${NC}"
    echo ""
    echo -e "  ${GREEN}1)${NC} Docker 模式 ${CYAN}(推荐)${NC}"
    echo -e "     ${DIM}├─ 环境隔离，便于管理${NC}"
    echo -e "     ${DIM}├─ 内置 Alpine 极简镜像，体积更小${NC}"
    echo -e "     ${DIM}└─ 内存占用约 100MB${NC}"
    echo ""
    echo -e "  ${GREEN}2)${NC} 原生模式 ${CYAN}(低资源)${NC}"
    echo -e "     ${DIM}├─ 直接安装 dnsmasq + sniproxy${NC}"
    echo -e "     ${DIM}├─ 优化的 systemd 服务配置${NC}"
    echo -e "     ${DIM}└─ 内存占用约 50MB，适合 < 512MB 机器${NC}"
    echo ""
    read -p "  选择 [1-2] (默认 1): " mode_opt
    
    if [ "$mode_opt" == "2" ]; then
        DEPLOY_MODE="native"
        install_native_mode
    else
        DEPLOY_MODE="docker"
        install_docker_mode
    fi
    
    if [ $? -eq 0 ]; then
        configure_unlock_services
        save_config
        
        show_divider
        msg_ok "解锁服务安装完成！"
        echo ""
        msg_info "提示：请使用菜单选项 4 生成 V2bX/Sing-box 配置"
        msg_info "提示：请使用菜单选项 3 设置 IP 白名单以保护服务"
    fi
    
    press_enter
}

# 安装 Docker 模式
install_docker_mode() {
    echo ""
    show_divider
    msg_info "正在安装 Docker 环境..."
    
    if ! command -v docker &> /dev/null; then
        msg_warn "Docker 未安装，正在安装..."
        # 下载脚本并安装，添加错误处理
        local docker_script="/tmp/get-docker.sh"
        if curl -fsSL https://get.docker.com -o "$docker_script" 2>/dev/null; then
            chmod +x "$docker_script"
            (bash "$docker_script" > "$LOG_FILE" 2>&1) &
            spinner $! "下载并安装 Docker..."
            wait $!
            rm -f "$docker_script"
        else
            msg_err "无法下载 Docker 安装脚本，请检查网络连接"
            return 1
        fi
        
        if ! command -v docker &> /dev/null; then
            msg_err "Docker 安装失败，请检查 $LOG_FILE"
            return 1
        fi
        systemctl enable docker --now >/dev/null 2>&1
        msg_ok "Docker 安装成功"
    else
        msg_ok "Docker 已安装"
    fi
    
    if ! docker compose version &> /dev/null; then
        msg_warn "安装 Docker Compose..."
        apt-get install -y docker-compose-plugin >/dev/null 2>&1 || apt-get install -y docker-compose >/dev/null 2>&1
        msg_ok "Docker Compose 已安装"
    fi
    
    return 0
}

# 安装原生模式
install_native_mode() {
    echo ""
    show_divider
    msg_info "正在安装原生依赖..."
    
    # 停止 systemd-resolved 以释放 53 端口
    systemctl stop systemd-resolved 2>/dev/null || true
    systemctl disable systemd-resolved 2>/dev/null || true
    
    msg_info "更新软件包列表..."
    apt-get update -y > "$LOG_FILE" 2>&1
    
    msg_info "安装 dnsmasq..."
    apt-get install -y dnsmasq >> "$LOG_FILE" 2>&1
    if ! command -v dnsmasq &> /dev/null; then
        msg_err "dnsmasq 安装失败"
        return 1
    fi
    msg_ok "dnsmasq 已安装"
    
    msg_info "安装 sniproxy..."
    apt-get install -y sniproxy >> "$LOG_FILE" 2>&1
    if ! command -v sniproxy &> /dev/null; then
        msg_err "sniproxy 安装失败"
        return 1
    fi
    msg_ok "sniproxy 已安装"
    
    # 停止服务准备配置
    systemctl stop dnsmasq sniproxy 2>/dev/null || true
    
    return 0
}

# 配置解锁服务
configure_unlock_services() {
    echo ""
    show_divider
    echo -e "  ${YELLOW}请选择需要解锁的服务：${NC}"
    echo ""
    echo -e "  ${CYAN}═══ AI 服务 ═══${NC}"
    echo -e "  ${GREEN}1)${NC} ChatGPT (OpenAI)"
    echo -e "  ${GREEN}2)${NC} Gemini (Google AI)"
    echo -e "  ${GREEN}3)${NC} Copilot (Microsoft)"
    echo -e "  ${GREEN}4)${NC} Claude (Anthropic)"
    echo ""
    echo -e "  ${CYAN}═══ 流媒体服务 ═══${NC}"
    echo -e "  ${GREEN}5)${NC} Netflix"
    echo -e "  ${GREEN}6)${NC} Disney+"
    echo -e "  ${GREEN}7)${NC} TikTok"
    echo -e "  ${GREEN}8)${NC} YouTube"
    echo -e "  ${GREEN}9)${NC} Spotify"
    echo -e "  ${GREEN}10)${NC} HBO Max"
    echo ""
    echo -e "  ${YELLOW}快捷选项：${NC}"
    echo -e "  ${GREEN}a${NC} = 全部 AI 服务 (1-4)"
    echo -e "  ${GREEN}s${NC} = 全部流媒体 (5-10)"
    echo -e "  ${GREEN}*${NC} = 全部服务"
    echo ""
    read -p "  请输入选择 (用逗号分隔，如 1,3,5): " svc_in
    
    # 处理快捷选项
    case "$svc_in" in
        a|A) SERVICES="1,2,3,4" ;;
        s|S) SERVICES="5,6,7,8,9,10" ;;
        \*|all|ALL) SERVICES="1,2,3,4,5,6,7,8,9,10" ;;
        "") SERVICES="1,2,3,4,5,6,7,8,9,10" ;;
        *) SERVICES="$svc_in" ;;
    esac
    
    # 确认 IP
    echo ""
    if [ -z "$SERVER_IP" ]; then
        read -p "  未检测到公网 IP，请手动输入: " SERVER_IP
    else
        echo -e "  检测到公网 IP: ${GREEN}$SERVER_IP${NC}"
        read -p "  确认使用此 IP 进行 DNS 劫持? [Y/n]: " ip_conf
        if [[ "$ip_conf" =~ ^[Nn]$ ]]; then
            read -p "  请输入正确的公网 IP: " SERVER_IP
        fi
    fi
    
    if ! validate_ip "$SERVER_IP"; then
        msg_err "无效的 IP 地址: $SERVER_IP"
        return 1
    fi
    
    # 生成配置文件
    mkdir -p "$WORK_DIR"
    cd "$WORK_DIR"
    
    echo "# Prism-DNS Generated Config - $(date)" > dnsmasq_rules.conf
    
    add_dns_rule() {
        local domain=$1
        echo "address=/$domain/$SERVER_IP" >> dnsmasq_rules.conf
    }
    
    # 根据选择添加规则
    if [[ $SERVICES == *"1"* ]]; then
        for d in openai.com chatgpt.com oaistatic.com oaiusercontent.com ai.com; do add_dns_rule $d; done
    fi
    if [[ $SERVICES == *"2"* ]]; then
        for d in gemini.google.com bard.google.com ai.google.dev generativelanguage.googleapis.com makersuite.google.com deepmind.com deepmind.google; do add_dns_rule $d; done
    fi
    if [[ $SERVICES == *"3"* ]]; then
        for d in copilot.microsoft.com copilot.cloud.microsoft bing.com bingapis.com; do add_dns_rule $d; done
    fi
    if [[ $SERVICES == *"4"* ]]; then
        for d in anthropic.com claude.ai; do add_dns_rule $d; done
    fi
    if [[ $SERVICES == *"5"* ]]; then
        for d in netflix.com netflix.net nflxvideo.net nflximg.net nflxext.com nflxso.net; do add_dns_rule $d; done
    fi
    if [[ $SERVICES == *"6"* ]]; then
        for d in disney.com disneyplus.com dssott.com bamgrid.com; do add_dns_rule $d; done
    fi
    if [[ $SERVICES == *"7"* ]]; then
        for d in tiktok.com tiktokv.com tiktokcdn.com musical.ly; do add_dns_rule $d; done
    fi
    if [[ $SERVICES == *"8"* ]]; then
        for d in youtube.com googlevideo.com ytimg.com ggpht.com; do add_dns_rule $d; done
    fi
    if [[ $SERVICES == *"9"* ]]; then
        for d in spotify.com scdn.co spotifycdn.com; do add_dns_rule $d; done
    fi
    if [[ $SERVICES == *"10"* ]]; then
        for d in hbomax.com max.com hbo.com; do add_dns_rule $d; done
    fi
    
    # 生成 sniproxy 配置
    cat > sniproxy.conf << 'SNICONF'
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
SNICONF
    
    # 根据模式部署
    if [ "$DEPLOY_MODE" = "docker" ]; then
        deploy_docker_service
    else
        deploy_native_service
    fi
}

# Docker 模式部署
deploy_docker_service() {
    echo ""
    msg_info "构建 Docker 容器..."
    
    # 生成优化的 Alpine Dockerfile
    cat > Dockerfile << 'DOCKERFILE'
FROM alpine:latest
RUN apk add --no-cache dnsmasq sniproxy bash
RUN mkdir -p /etc/dnsmasq.d /var/log/sniproxy && \
    echo 'port=53' > /etc/dnsmasq.conf && \
    echo 'no-resolv' >> /etc/dnsmasq.conf && \
    echo 'server=8.8.8.8' >> /etc/dnsmasq.conf && \
    echo 'server=8.8.4.4' >> /etc/dnsmasq.conf && \
    echo 'conf-dir=/etc/dnsmasq.d/,*.conf' >> /etc/dnsmasq.conf && \
    echo 'cache-size=1000' >> /etc/dnsmasq.conf
RUN echo '#!/bin/sh' > /start.sh && \
    echo 'trap "kill -TERM \$dnsmasq_pid \$sniproxy_pid 2>/dev/null; exit 0" TERM INT' >> /start.sh && \
    echo 'dnsmasq --no-daemon &' >> /start.sh && \
    echo 'dnsmasq_pid=$!' >> /start.sh && \
    echo 'sleep 1' >> /start.sh && \
    echo 'sniproxy -f -c /etc/sniproxy.conf &' >> /start.sh && \
    echo 'sniproxy_pid=$!' >> /start.sh && \
    echo 'wait' >> /start.sh && \
    chmod +x /start.sh
EXPOSE 53/udp 53/tcp 80/tcp 443/tcp
CMD ["/start.sh"]
DOCKERFILE
    
    cat > docker-compose.yml << 'COMPOSE'
services:
  unlock:
    build: .
    image: prism-dns:alpine
    container_name: dns_unlock
    restart: always
    network_mode: host
    privileged: true
    volumes:
      - ./dnsmasq_rules.conf:/etc/dnsmasq.d/unlock.conf:ro
      - ./sniproxy.conf:/etc/sniproxy.conf:ro
COMPOSE
    
    docker compose down 2>/dev/null
    docker compose up -d --build >> "$LOG_FILE" 2>&1
    
    sleep 3
    if docker ps | grep -q "dns_unlock"; then
        msg_ok "Docker 容器启动成功"
    else
        msg_err "Docker 容器启动失败，请检查 $LOG_FILE"
        return 1
    fi
}

# 原生模式部署
deploy_native_service() {
    echo ""
    msg_info "配置原生服务..."
    
    # 备份原始配置
    [ -f /etc/dnsmasq.conf ] && [ ! -f /etc/dnsmasq.conf.bak ] && cp /etc/dnsmasq.conf /etc/dnsmasq.conf.bak
    
    # 配置 dnsmasq
    cat > /etc/dnsmasq.conf << 'DNSCONF'
port=53
no-resolv
server=8.8.8.8
server=8.8.4.4
conf-dir=/etc/dnsmasq.d/,*.conf
no-hosts
cache-size=1000
DNSCONF
    
    mkdir -p /etc/dnsmasq.d /var/log/sniproxy
    cp "$WORK_DIR/dnsmasq_rules.conf" /etc/dnsmasq.d/unlock.conf
    
    # 配置 sniproxy
    sed 's|/dev/stderr|/var/log/sniproxy/error.log|g' "$WORK_DIR/sniproxy.conf" > /etc/sniproxy.conf
    
    # 创建优化的 systemd 服务 (如果不存在默认的)
    if [ ! -f /etc/systemd/system/sniproxy.service ] && [ ! -f /lib/systemd/system/sniproxy.service ]; then
        cat > /etc/systemd/system/sniproxy.service << 'SVCCONF'
[Unit]
Description=SNI Proxy Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/sbin/sniproxy -f -c /etc/sniproxy.conf
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
SVCCONF
        systemctl daemon-reload
    fi
    
    # 启动服务
    systemctl enable dnsmasq sniproxy >/dev/null 2>&1
    systemctl restart dnsmasq sniproxy
    
    sleep 2
    if systemctl is-active dnsmasq >/dev/null && systemctl is-active sniproxy >/dev/null; then
        msg_ok "原生服务启动成功"
    else
        msg_err "服务启动失败，请检查 journalctl -u dnsmasq -u sniproxy"
        return 1
    fi
}

# 2. 查看运行状态
check_status() {
    show_header
    show_subtitle "📊 系统运行状态"
    
    # 基本信息
    echo -e "  ${CYAN}基本信息${NC}"
    echo -e "  ├─ 本机 IP:     ${GREEN}${SERVER_IP:-未检测}${NC}"
    echo -e "  ├─ 部署模式:   ${YELLOW}${DEPLOY_MODE:-未知}${NC}"
    echo -e "  └─ 安装状态:   ${WHITE}${INSTALLED_STATUS}${NC}"
    echo ""
    
    # 端口监听状态
    echo -e "  ${CYAN}端口监听状态${NC}"
    for port in 53 80 443; do
        if ss -tuln 2>/dev/null | grep -qE ":${port}([[:space:]]|$)"; then
            echo -e "  ├─ 端口 $port:   ${GREEN}● 正常 (监听中)${NC}"
        else
            echo -e "  ├─ 端口 $port:   ${RED}○ 异常 (未监听)${NC}"
        fi
    done
    echo ""
    
    # 服务运行状态
    echo -e "  ${CYAN}服务运行状态${NC}"
    if [ "$DEPLOY_MODE" = "Docker" ] || [ "$DEPLOY_MODE" = "docker" ]; then
        if docker ps 2>/dev/null | grep -q "dns_unlock"; then
            echo -e "  ├─ Docker 容器: ${GREEN}● 运行中${NC}"
            # 显示容器资源占用
            local mem=$(docker stats dns_unlock --no-stream --format "{{.MemUsage}}" 2>/dev/null | cut -d'/' -f1)
            echo -e "  └─ 内存占用:    ${WHITE}${mem:-未知}${NC}"
        else
            echo -e "  └─ Docker 容器: ${RED}○ 已停止${NC}"
        fi
    else
        if systemctl is-active dnsmasq >/dev/null 2>&1; then
            echo -e "  ├─ Dnsmasq:     ${GREEN}● 运行中${NC}"
        else
            echo -e "  ├─ Dnsmasq:     ${RED}○ 已停止${NC}"
        fi
        if systemctl is-active sniproxy >/dev/null 2>&1; then
            echo -e "  └─ Sniproxy:    ${GREEN}● 运行中${NC}"
        else
            echo -e "  └─ Sniproxy:    ${RED}○ 已停止${NC}"
        fi
    fi
    
    press_enter
}

# 3. 管理 IP 白名单
manage_whitelist() {
    while true; do
        show_header
        show_subtitle "🛡️ 管理 IP 白名单 (防火墙安全设置)"
        
        # 显示当前白名单
        touch "$WHITELIST_FILE" 2>/dev/null
        local current_ips=$(cat "$WHITELIST_FILE" 2>/dev/null | sort | uniq)
        
        echo -e "  ${CYAN}当前允许的 IP 列表：${NC}"
        if [ -z "$current_ips" ]; then
            echo -e "  ${YELLOW}(空) - 任何 IP 都可访问，建议尽快添加落地机 IP${NC}"
        else
            local i=1
            while IFS= read -r ip; do
                [ -n "$ip" ] && echo -e "  ${GREEN}$i.${NC} $ip" && ((i++))
            done <<< "$current_ips"
        fi
        echo ""
        
        show_divider
        echo -e "  ${YELLOW}操作选项：${NC}"
        echo -e "  ${GREEN}1)${NC} 添加 IP"
        echo -e "  ${GREEN}2)${NC} 删除指定 IP"
        echo -e "  ${GREEN}3)${NC} 清空所有 IP"
        echo -e "  ${GREEN}4)${NC} 应用防火墙规则"
        echo -e "  ${RED}0)${NC} 返回主菜单"
        echo ""
        read -p "  请选择 [0-4]: " fw_opt
        
        case "$fw_opt" in
            1)
                echo ""
                echo -e "  ${CYAN}请输入要添加的 IP (多个 IP 用空格分隔):${NC}"
                read -p "  IP: " new_ips
                for ip in $new_ips; do
                    if validate_ip "$ip"; then
                        echo "$ip" >> "$WHITELIST_FILE"
                        msg_ok "已添加: $ip"
                    else
                        msg_err "无效的 IP: $ip (已跳过)"
                    fi
                done
                # 去重
                sort "$WHITELIST_FILE" | uniq > "${WHITELIST_FILE}.tmp" && mv "${WHITELIST_FILE}.tmp" "$WHITELIST_FILE"
                sleep 1
                ;;
            2)
                echo ""
                read -p "  请输入要删除的 IP: " del_ip
                if grep -q "^${del_ip}$" "$WHITELIST_FILE" 2>/dev/null; then
                    grep -v "^${del_ip}$" "$WHITELIST_FILE" > "${WHITELIST_FILE}.tmp" && mv "${WHITELIST_FILE}.tmp" "$WHITELIST_FILE"
                    msg_ok "已删除: $del_ip"
                else
                    msg_err "IP 不在白名单中: $del_ip"
                fi
                sleep 1
                ;;
            3)
                echo ""
                read -p "  确定要清空所有 IP 吗? [y/N]: " confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    > "$WHITELIST_FILE"
                    msg_ok "白名单已清空"
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

# 应用防火墙规则 (带自锁保护)
apply_firewall_rules() {
    echo ""
    msg_info "正在应用防火墙规则..."
    
    local ips=$(cat "$WHITELIST_FILE" 2>/dev/null | sort | uniq)
    
    # ⚠️ 防火墙自锁保护：检测并放行 SSH
    # 从 sshd 配置中检测实际 SSH 端口
    local ssh_port=22
    if [ -f /etc/ssh/sshd_config ]; then
        local detected_port=$(grep -E "^[[:space:]]*Port[[:space:]]+" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' | head -1)
        if [ -n "$detected_port" ] && [ "$detected_port" -gt 0 ] 2>/dev/null; then
            ssh_port=$detected_port
        fi
    fi
    msg_warn "防火墙自锁保护：强制放行 SSH (端口 $ssh_port)"
    
    if command -v ufw &> /dev/null; then
        # UFW 模式
        ufw allow ssh >/dev/null 2>&1
        ufw allow "$ssh_port/tcp" >/dev/null 2>&1
        echo "y" | ufw enable >/dev/null 2>&1
        
        # 清理旧规则
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
            msg_ok "UFW 规则已更新，仅允许白名单 IP 访问"
        else
            ufw allow 53 >/dev/null 2>&1
            ufw allow 80/tcp >/dev/null 2>&1
            ufw allow 443/tcp >/dev/null 2>&1
            ufw reload >/dev/null 2>&1
            msg_warn "白名单为空，已开放所有 IP 访问"
        fi
    else
        # iptables 模式
        # 首先确保 SSH 放行 (使用检测到的端口)
        iptables -C INPUT -p tcp --dport "$ssh_port" -j ACCEPT 2>/dev/null || iptables -I INPUT -p tcp --dport "$ssh_port" -j ACCEPT
        
        # 清理旧的 UNLOCK 链
        iptables -D INPUT -j UNLOCK_WHITELIST 2>/dev/null || true
        iptables -F UNLOCK_WHITELIST 2>/dev/null || true
        iptables -X UNLOCK_WHITELIST 2>/dev/null || true
        
        # 创建新链
        iptables -N UNLOCK_WHITELIST 2>/dev/null
        
        if [ -n "$ips" ]; then
            for ip in $ips; do
                iptables -A UNLOCK_WHITELIST -s "$ip" -p tcp --dport 53 -j ACCEPT
                iptables -A UNLOCK_WHITELIST -s "$ip" -p udp --dport 53 -j ACCEPT
                iptables -A UNLOCK_WHITELIST -s "$ip" -p tcp --dport 80 -j ACCEPT
                iptables -A UNLOCK_WHITELIST -s "$ip" -p tcp --dport 443 -j ACCEPT
            done
            
            # 拒绝其他访问
            iptables -A UNLOCK_WHITELIST -p tcp --dport 53 -j DROP
            iptables -A UNLOCK_WHITELIST -p udp --dport 53 -j DROP
            iptables -A UNLOCK_WHITELIST -p tcp --dport 80 -j DROP
            iptables -A UNLOCK_WHITELIST -p tcp --dport 443 -j DROP
            
            iptables -I INPUT -j UNLOCK_WHITELIST
            msg_ok "iptables 规则已更新，仅允许白名单 IP 访问"
        else
            msg_warn "白名单为空，未限制 IP 访问"
        fi
    fi
}

# 4. 生成 JSON 配置
generate_json_config() {
    show_header
    show_subtitle "📄 生成 V2bX / Sing-box 配置"
    
    if [ ! -f "$WORK_DIR/dnsmasq_rules.conf" ]; then
        msg_err "未找到配置文件，请先安装服务！"
        press_enter
        return
    fi
    
    # 从配置文件提取域名列表
    local domains_json=$(grep "address=/" "$WORK_DIR/dnsmasq_rules.conf" | cut -d/ -f2 | awk '{printf "\"%s\", ", $0}' | sed 's/, $//')
    
    # CIDR 格式
    local cidr
    if [[ "$SERVER_IP" == *":"* ]]; then
        cidr="${SERVER_IP}/128"
    else
        cidr="${SERVER_IP}/32"
    fi
    
    echo -e "  ${YELLOW}请将下方 JSON 配置复制到 V2bX 后端模版中：${NC}"
    echo ""
    show_divider
    echo -e "${GREEN}"
    cat << EOF
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
        "domain_suffix": [${domains_json}],
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
      { "ip_cidr": ["${cidr}"], "outbound": "direct" },
      { "domain_suffix": [${domains_json}], "outbound": "direct" },
      { "ip_is_private": true, "outbound": "block" },
      { "protocol": "quic", "outbound": "block" },
      {
        "domain_regex": [
          "(api|ps|sv|offnavi|newvector|ulog.imap|newloc)(.map|).(baidu|n.shifen).com",
          "(.+.|^)(360|so).(cn|com)",
          "(torrent|.torrent|peer_id=|info_hash|get_peers|find_node|BitTorrent|announce_peer|announce.php?passkey=)",
          "(.?)(xunlei|sandai|Thunder|XLLiveUD)(.)",
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
    echo -e "${NC}"
    show_divider
    
    press_enter
}

# 5. 测试解锁状态
test_unlock() {
    show_header
    show_subtitle "🔍 测试解锁状态"
    
    # 测试连通性
    echo -e "  ${CYAN}[1/3] 测试解锁机连通性${NC}"
    echo ""
    
    # Ping 测试
    echo -n "  ├─ Ping 测试:    "
    if ping -c 1 -W 2 "$SERVER_IP" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ 成功${NC}"
    else
        echo -e "${YELLOW}✗ 失败 (可能禁用 ICMP)${NC}"
    fi
    
    # TCP 端口测试 (使用 nc 或 /dev/tcp 作为后备)
    for port in 53 80 443; do
        echo -n "  ├─ TCP $port 测试:  "
        local port_open=false
        # 优先使用 nc (netcat) 进行测试
        if command -v nc &> /dev/null; then
            if nc -z -w 2 "$SERVER_IP" "$port" 2>/dev/null; then
                port_open=true
            fi
        elif command -v timeout &> /dev/null; then
            # 使用 bash 内置 /dev/tcp (需要先验证 IP)
            if validate_ip "$SERVER_IP"; then
                if timeout 2 bash -c "echo >/dev/tcp/$SERVER_IP/$port" 2>/dev/null; then
                    port_open=true
                fi
            fi
        fi
        
        if [ "$port_open" = true ]; then
            echo -e "${GREEN}✓ 开放${NC}"
        else
            echo -e "${RED}✗ 关闭${NC}"
        fi
    done
    echo ""
    
    # DNS 劫持测试
    echo -e "  ${CYAN}[2/3] 测试 DNS 劫持${NC}"
    echo ""
    
    local test_domains=("openai.com" "netflix.com" "google.com")
    for domain in "${test_domains[@]}"; do
        echo -n "  ├─ $domain: "
        if command -v dig &> /dev/null; then
            local result=$(dig +short @$SERVER_IP $domain 2>/dev/null | tail -1)
        elif command -v nslookup &> /dev/null; then
            local result=$(nslookup $domain $SERVER_IP 2>/dev/null | grep -A1 "Name:" | grep "Address" | awk '{print $2}' | tail -1)
        else
            local result=""
        fi
        
        if [ "$result" = "$SERVER_IP" ]; then
            echo -e "${GREEN}✓ 劫持成功 → $result${NC}"
        elif [ -n "$result" ]; then
            echo -e "${YELLOW}→ $result (未劫持或未配置)${NC}"
        else
            echo -e "${RED}✗ 无响应${NC}"
        fi
    done
    echo ""
    
    # 解锁测试提示
    echo -e "  ${CYAN}[3/3] 解锁测试建议${NC}"
    echo ""
    echo -e "  ${DIM}从您的客户端连接落地节点后，访问以下网站测试：${NC}"
    echo -e "  ├─ ChatGPT: https://chat.openai.com"
    echo -e "  ├─ Netflix: https://www.netflix.com"
    echo -e "  └─ TikTok:  打开 TikTok APP 查看内容"
    
    press_enter
}

# 6. 一键卸载
uninstall_service() {
    show_header
    show_subtitle "🗑️ 卸载解锁服务"
    
    echo -e "  ${RED}警告：此操作将删除所有解锁服务组件和配置！${NC}"
    echo ""
    read -p "  确定要继续吗? [y/N]: " confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        msg_warn "操作已取消"
        press_enter
        return
    fi
    
    echo ""
    
    # Docker 模式卸载
    if command -v docker &> /dev/null; then
        if docker ps -a 2>/dev/null | grep -q "dns_unlock"; then
            msg_info "停止并删除 Docker 容器..."
            if docker stop dns_unlock >/dev/null 2>&1 && docker rm dns_unlock >/dev/null 2>&1; then
                msg_ok "Docker 容器已删除"
            else
                msg_warn "Docker 容器删除可能不完整"
            fi
        fi
        if docker images 2>/dev/null | grep -q "prism-dns"; then
            if docker rmi prism-dns:alpine >/dev/null 2>&1; then
                msg_ok "Docker 镜像已删除"
            else
                msg_warn "Docker 镜像删除失败 (可能正在使用)"
            fi
        fi
    fi
    
    # 原生模式卸载
    if [ -f /etc/dnsmasq.d/unlock.conf ]; then
        msg_info "停止原生服务..."
        systemctl stop dnsmasq sniproxy 2>/dev/null
        systemctl disable dnsmasq sniproxy 2>/dev/null
        rm -f /etc/dnsmasq.d/unlock.conf
        msg_ok "原生服务已停止"
        
        if [ -f /etc/dnsmasq.conf.bak ]; then
            mv /etc/dnsmasq.conf.bak /etc/dnsmasq.conf
            msg_ok "已恢复原始 dnsmasq 配置"
        fi
    fi
    
    # 删除工作目录
    if [ -d "$WORK_DIR" ]; then
        rm -rf "$WORK_DIR"
        msg_ok "配置文件已删除"
    fi
    
    echo ""
    msg_ok "卸载完成！"
    msg_info "防火墙规则未删除，如需清理请手动执行 ufw/iptables 命令"
    
    DEPLOY_MODE=""
    INSTALLED_STATUS="未安装"
    
    press_enter
}

# 7. 一键清理
cleanup_all() {
    show_header
    show_subtitle "🧹 一键清理"
    
    echo -e "  ${YELLOW}此功能将清理以下内容：${NC}"
    echo -e "  ├─ 停止所有解锁服务"
    echo -e "  ├─ 删除临时文件和日志"
    echo -e "  └─ 重置防火墙规则"
    echo ""
    read -p "  确定要继续吗? [y/N]: " confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        msg_warn "操作已取消"
        press_enter
        return
    fi
    
    echo ""
    
    # 停止服务
    msg_info "停止服务..."
    docker stop dns_unlock 2>/dev/null || true
    systemctl stop dnsmasq sniproxy 2>/dev/null || true
    msg_ok "服务已停止"
    
    # 清理日志
    msg_info "清理日志文件..."
    rm -f "$LOG_FILE" 2>/dev/null
    rm -rf /var/log/sniproxy/* 2>/dev/null
    msg_ok "日志已清理"
    
    # 重置防火墙
    msg_info "重置防火墙规则..."
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
    msg_ok "防火墙规则已重置"
    
    echo ""
    msg_ok "清理完成！服务已停止，如需使用请重新启动。"
    
    press_enter
}

# 8. 重启服务
restart_service() {
    show_header
    show_subtitle "🔄 重启服务"
    
    if [ "$DEPLOY_MODE" = "Docker" ] || [ "$DEPLOY_MODE" = "docker" ]; then
        msg_info "重启 Docker 容器..."
        if [ -d "$WORK_DIR" ]; then
            cd "$WORK_DIR" && docker compose restart
            sleep 2
            if docker ps | grep -q "dns_unlock"; then
                msg_ok "Docker 容器重启成功"
            else
                msg_err "Docker 容器重启失败"
            fi
        else
            msg_err "工作目录不存在: $WORK_DIR"
        fi
    else
        msg_info "重启原生服务..."
        systemctl restart dnsmasq sniproxy
        sleep 2
        if systemctl is-active dnsmasq >/dev/null && systemctl is-active sniproxy >/dev/null; then
            msg_ok "服务重启成功"
        else
            msg_err "服务重启失败"
        fi
    fi
    
    press_enter
}

# ======================== 主菜单 ========================

main_menu() {
    check_root
    detect_public_ip
    
    while true; do
        detect_install_status
        show_header
        
        echo -e "  ${CYAN}═══════════════════════════════════════════════${NC}"
        echo -e "  ${WHITE}${BOLD}主菜单${NC}"
        echo -e "  ${CYAN}═══════════════════════════════════════════════${NC}"
        echo ""
        echo -e "  ${YELLOW}1)${NC} 安装 / 重装解锁服务 ${DIM}(Docker/原生双模式)${NC}"
        echo -e "  ${YELLOW}2)${NC} 查看运行状态"
        echo -e "  ${YELLOW}3)${NC} 管理 IP 白名单 ${DIM}(防火墙安全设置)${NC}"
        echo -e "  ${YELLOW}4)${NC} 生成 V2bX / Sing-box JSON 配置"
        echo -e "  ${YELLOW}5)${NC} 测试解锁状态 ${DIM}(连通性/DNS劫持)${NC}"
        echo -e "  ${YELLOW}6)${NC} 重启服务"
        echo -e "  ${YELLOW}7)${NC} 一键清理 ${DIM}(停止服务/清理日志)${NC}"
        echo ""
        echo -e "  ${RED}8)${NC} 卸载解锁服务"
        echo -e "  ${RED}0)${NC} 退出"
        echo ""
        read -p "  请选择 [0-8]: " choice
        
        case "$choice" in
            1) install_service ;;
            2) check_status ;;
            3) manage_whitelist ;;
            4) generate_json_config ;;
            5) test_unlock ;;
            6) restart_service ;;
            7) cleanup_all ;;
            8) uninstall_service ;;
            0) 
                echo ""
                echo -e "  ${GREEN}感谢使用 Prism-DNS！${NC}"
                echo ""
                exit 0
                ;;
            *)
                msg_err "无效选项，请重新选择"
                sleep 1
                ;;
        esac
    done
}

# 运行主菜单
main_menu
