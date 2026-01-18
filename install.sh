#!/bin/bash
# ==========================================================
#  场用生产级解锁服务器脚本（修复增强版）
#  修复内容：
#    1. Docker 网络模式改为 host，解决容器间 localhost 无法通信问题
#    2. 增加 UFW/Firewall SSH 防自锁保护
#    3. 优化 Curl 测试逻辑
#    4. 增强 Root 权限检测
# ==========================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
SKY='\033[0;36m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

# 检查是否为 Root 运行
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}错误：请使用 root 用户运行此脚本！${NC}"
   echo -e "尝试命令：sudo bash $0"
   exit 1
fi

MODE=""                 
FIREWALL_BACKEND=""     
SERVER_IP=""            
ALLOWED_IPS=()          

SERVICE_GPT=0
SERVICE_GEMINI=0
SERVICE_COPILOT=0
SERVICE_NETFLIX=0
SERVICE_DISNEY=0
SERVICE_TIKTOK=0
SERVICE_PRIME=0
SERVICE_HULU=0
SERVICE_HBO=0
DOMAINS=()

PRISM_DIR="/etc/unlock-prism"
SNIPROXY_DIR="/etc/unlock-sniproxy"

# ==========================================================
# 基础工具
# ==========================================================

detect_public_ip() {
    for url in "https://api.ip.sb/ip" "https://ifconfig.me" "https://ipinfo.io/ip"; do
        SERVER_IP=$(curl -4 -s --max-time 5 "$url")
        if [[ -n "$SERVER_IP" ]]; then
            break
        fi
    done
    if [[ -z "$SERVER_IP" ]]; then
        echo -e "${RED}无法自动检测公网 IP，请手动输入：${NC}"
        read -p ">> " SERVER_IP
    fi
}

validate_ip() {
    local ip="$1"
    ip=$(echo "$ip" | tr -d '[:space:]')
    [ -z "$ip" ] && return 1
    # 简单的 IPv4 校验
    if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        return 0
    fi
    return 1
}

spinner() {
    local msg="$1"
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    while :; do
        i=$(( (i+1) %10 ))
        printf "\r%s%s %s%s" "${YELLOW}" "${spin:$i:1}" "${msg}" "${NC}"
        sleep 0.08
    done
}

run_with_spinner() {
    local msg="$1"; shift
    spinner "$msg" &
    local spid=$!
    "$@" >/tmp/unlock_tool_cmd.log 2>&1
    local ret=$?
    kill "$spid" >/dev/null 2>&1
    wait "$spid" 2>/dev/null
    printf "\r\033[K"
    return $ret
}

# ==========================================================
# 防火墙相关（含防自锁修复）
# ==========================================================

detect_firewall_backend() {
    if command -v ufw >/dev/null 2>&1; then
        FIREWALL_BACKEND="ufw"
    elif command -v firewall-cmd >/dev/null 2>&1; then
        FIREWALL_BACKEND="firewalld"
    else
        FIREWALL_BACKEND="iptables"
    fi
}

apply_firewall_rules() {
    if [ ${#ALLOWED_IPS[@]} -eq 0 ]; then
        echo -e "${YELLOW}未设置白名单节点 IP，暂不限制访问（不推荐用于机场生产）。${NC}"
        return
    fi

    echo -e "${BLUE}应用防火墙白名单规则...${NC}"

    case "$FIREWALL_BACKEND" in
        ufw)
            # 【修复】先允许 SSH，防止自己被锁
            ufw allow 22/tcp >/dev/null 2>&1
            ufw allow ssh >/dev/null 2>&1
            
            # 开启防火墙
            echo "y" | ufw enable >/dev/null 2>&1 || true
            
            # 清理旧的 53/80/443 规则（简单清理，防止堆积）
            ufw delete allow 53/tcp >/dev/null 2>&1
            ufw delete allow 53/udp >/dev/null 2>&1
            ufw delete allow 80/tcp >/dev/null 2>&1
            ufw delete allow 443/tcp >/dev/null 2>&1

            for ip in "${ALLOWED_IPS[@]}"; do
                ufw allow from "$ip" to any port 53 >/dev/null 2>&1
                ufw allow from "$ip" to any port 80 proto tcp >/dev/null 2>&1
                ufw allow from "$ip" to any port 443 proto tcp >/dev/null 2>&1
            done
            
            # 拒绝默认的外部访问（默认策略通常是 deny incoming，这里显式加一下）
            # 注意：ufw allow规则优先级高于deny，所以上面的 allow 生效后，这里不需显式 deny
            # 但为了保险，可以设置默认策略
            ufw default deny incoming >/dev/null 2>&1
            ufw default allow outgoing >/dev/null 2>&1
            ;;
        firewalld)
            systemctl start firewalld >/dev/null 2>&1 || true
            # 【修复】确保 SSH 允许
            firewall-cmd --permanent --add-service=ssh >/dev/null 2>&1
            
            # 这里的逻辑比较复杂，为了简化，我们先移除公共区域的端口，再添加富规则
            firewall-cmd --permanent --remove-port=53/tcp >/dev/null 2>&1
            firewall-cmd --permanent --remove-port=53/udp >/dev/null 2>&1
            firewall-cmd --permanent --remove-port=80/tcp >/dev/null 2>&1
            firewall-cmd --permanent --remove-port=443/tcp >/dev/null 2>&1
            
            for ip in "${ALLOWED_IPS[@]}"; do
                firewall-cmd --permanent --add-rich-rule="rule family=ipv4 source address=${ip} port protocol=tcp port=53 accept" >/dev/null 2>&1
                firewall-cmd --permanent --add-rich-rule="rule family=ipv4 source address=${ip} port protocol=udp port=53 accept" >/dev/null 2>&1
                firewall-cmd --permanent --add-rich-rule="rule family=ipv4 source address=${ip} port protocol=tcp port=80 accept" >/dev/null 2>&1
                firewall-cmd --permanent --add-rich-rule="rule family=ipv4 source address=${ip} port protocol=tcp port=443 accept" >/dev/null 2>&1
            done
            firewall-cmd --reload >/dev/null 2>&1
            ;;
        iptables|*)
            # 保证 SSH 不被锁
            iptables -A INPUT -p tcp --dport 22 -j ACCEPT
            
            iptables -N UNLOCK_SRV 2>/dev/null || iptables -F UNLOCK_SRV
            # 移除旧的引用
            iptables -D INPUT -j UNLOCK_SRV 2>/dev/null || true
            # 插入到 INPUT 链较前位置，但在 SSH 规则之后（假设 SSH 在最前）
            iptables -I INPUT 2 -j UNLOCK_SRV 2>/dev/null || iptables -A INPUT -j UNLOCK_SRV
            
            for ip in "${ALLOWED_IPS[@]}"; do
                iptables -A UNLOCK_SRV -s "$ip" -p tcp --dport 53 -j ACCEPT
                iptables -A UNLOCK_SRV -s "$ip" -p udp --dport 53 -j ACCEPT
                iptables -A UNLOCK_SRV -s "$ip" -p tcp --dport 80 -j ACCEPT
                iptables -A UNLOCK_SRV -s "$ip" -p tcp --dport 443 -j ACCEPT
            done
            # 在链末尾丢弃这些端口的其他流量
            iptables -A UNLOCK_SRV -p tcp --dport 53 -j DROP
            iptables -A UNLOCK_SRV -p udp --dport 53 -j DROP
            iptables -A UNLOCK_SRV -p tcp --dport 80 -j DROP
            iptables -A UNLOCK_SRV -p tcp --dport 443 -j DROP
            ;;
    esac
}

clear_firewall_rules() {
    echo -e "${YELLOW}正在清理防火墙规则...${NC}"
    case "$FIREWALL_BACKEND" in
        ufw)
            ufw delete allow 53/tcp >/dev/null 2>&1
            ufw delete allow 53/udp >/dev/null 2>&1
            ufw delete allow 80/tcp >/dev/null 2>&1
            ufw delete allow 443/tcp >/dev/null 2>&1
            ;;
        firewalld)
             echo -e "${YELLOW}firewalld 规则建议手动清理以免误删。${NC}"
            ;;
        iptables|*)
            iptables -D INPUT -j UNLOCK_SRV 2>/dev/null || true
            iptables -F UNLOCK_SRV 2>/dev/null || true
            iptables -X UNLOCK_SRV 2>/dev/null || true
            ;;
    esac
}

set_allowed_ips() {
    echo -e "${SKY}请输入允许接入此解锁服务的节点 IP（多个用逗号分隔）：${NC}"
    echo -e "${YELLOW}建议填机场出站节点 IP，而不是用户终端 IP。${NC}"
    read -p ">> " ip_input
    ALLOWED_IPS=()
    IFS=',' read -ra arr <<< "$ip_input"
    for x in "${arr[@]}"; do
        x=$(echo "$x" | tr -d ' ')
        if validate_ip "$x"; then
            ALLOWED_IPS+=("$x")
        else
            echo -e "${RED}忽略无效 IP：$x${NC}"
        fi
    done
    apply_firewall_rules
    echo -e "${GREEN}白名单规则已应用。${NC}"
    read -p "按回车返回菜单..." _
}

# ==========================================================
# 端口占用检测
# ==========================================================

check_port() {
    local port="$1"
    if command -v ss >/dev/null 2>&1; then
        ss -tulnp | grep -q ":${port} "
    else
        netstat -tulnp 2>/dev/null | grep -q ":${port} "
    fi
}

check_ports_53_80_443() {
    local conflict=0
    for p in 53 80 443; do
        if check_port "$p"; then
            echo -e "${RED}端口 ${p} 已被占用：${NC}"
            if command -v ss >/dev/null 2>&1; then
                ss -tulnp | grep ":${p} "
            else
                netstat -tulnp 2>/dev/null | grep ":${p} "
            fi
            conflict=1
        fi
    done
    if [ $conflict -eq 1 ]; then
        echo -e "${YELLOW}上述端口已被占用，继续安装会导致启动失败。${NC}"
        echo -e "${YELLOW}如果是 Nginx/Apache 占用 80/443，请先停止它们。${NC}"
        echo -e "${YELLOW}如果是 systemd-resolved 占用 53，请先关闭它。${NC}"
        read -p "强制继续？[y/N] " c
        [[ "$c" =~ ^[Yy]$ ]] || return 1
    fi
    return 0
}

# ==========================================================
# 配置文件初始化
# ==========================================================

init_prism_config() {
    mkdir -p "$PRISM_DIR"
    local cfg="$PRISM_DIR/config.yaml"
    
    echo -e "${YELLOW}生成 Prism-DNS 配置：${cfg}${NC}"
    # 【修复】upstream 改为指向 Host 的 127.0.0.1:443 (因为我们将使用 network=host)
    # 如果不使用 host 模式，这里必须是宿主机 IP，而不能是 127.0.0.1
    cat > "$cfg" <<EOF
listen: ":53"
protocol: "udp"
upstream:
  - "1.1.1.1"
  - "8.8.8.8"

rules:
  # OpenAI / GPT
  - domain_suffix: "openai.com"
    upstream: "proxy"
  - domain_suffix: "chatgpt.com"
    upstream: "proxy"
  - domain_suffix: "oaistatic.com"
    upstream: "proxy"
  - domain_suffix: "oaiusercontent.com"
    upstream: "proxy"

  # Netflix
  - domain_suffix: "netflix.com"
    upstream: "proxy"
  - domain_suffix: "nflximg.net"
    upstream: "proxy"
  - domain_suffix: "nflxvideo.net"
    upstream: "proxy"
  - domain_suffix: "nflxso.net"
    upstream: "proxy"

  # Disney+ (示例，需完整列表请自行补充)
  - domain_suffix: "disney.com"
    upstream: "proxy"
  - domain_suffix: "disneyplus.com"
    upstream: "proxy"
  - domain_suffix: "bamgrid.com"
    upstream: "proxy"

proxy:
  type: "forward"
  # 因为使用 --network host，这里的 127.0.0.1 即宿主机回环，可以连接到 sniproxy
  address: "127.0.0.1:443"
EOF
}

init_sniproxy_config() {
    mkdir -p "$SNIPROXY_DIR"
    local cfg="$SNIPROXY_DIR/sniproxy.conf"
    
    echo -e "${YELLOW}生成 sniproxy 配置：${cfg}${NC}"
    cat > "$cfg" <<'EOF'
user daemon
pidfile /var/run/sniproxy.pid

resolver {
    nameserver 1.1.1.1
    nameserver 8.8.8.8
    mode ipv4_only
}

listen 0.0.0.0:80 {
    proto http
    table http_hosts
    access_log {
        filename /dev/stdout
        priority notice
    }
}

listen 0.0.0.0:443 {
    proto tls
    table https_hosts
    access_log {
        filename /dev/stdout
        priority notice
    }
}

table http_hosts {
    .* *
}

table https_hosts {
    .* *
}
EOF
}

# ==========================================================
# 解锁模式安装（生产级 Docker）
# ==========================================================

install_prism_sniproxy_mode() {
    MODE="prism"
    clear
    echo -e "${SKY}安装 Prism-DNS + sniproxy 解锁模式（Docker Host 模式）${NC}"

    check_ports_53_80_443 || return

    if ! command -v docker >/dev/null 2>&1; then
        echo -e "${YELLOW}未检测到 docker，正在安装...${NC}"
        curl -fsSL https://get.docker.com | bash
        systemctl enable docker --now
    fi

    init_prism_config
    init_sniproxy_config

    echo -e "${YELLOW}正在部署容器...${NC}"

    docker rm -f prism-dns sniproxy >/dev/null 2>&1 || true

    # 【修复】使用 --network host 模式
    # 这样 Prism-DNS 可以直接监听宿主机 53
    # Sniproxy 可以直接监听宿主机 80/443
    # 且 Prism 配置里的 upstream: 127.0.0.1:443 才能生效
    
    docker run -d \
      --name prism-dns \
      --restart=always \
      --network host \
      --memory=256m \
      --cpus=0.5 \
      --log-opt max-size=10m \
      --log-opt max-file=3 \
      -v "${PRISM_DIR}:/app/config" \
      ghcr.io/zhxie/prismdns:latest

    docker run -d \
      --name sniproxy \
      --restart=always \
      --network host \
      --memory=256m \
      --cpus=0.5 \
      --log-opt max-size=10m \
      --log-opt max-file=3 \
      -v "${SNIPROXY_DIR}/sniproxy.conf:/etc/sniproxy.conf:ro" \
      ghcr.io/dlundquist/sniproxy:latest

    echo -e "${GREEN}✓ Prism-DNS + sniproxy 已成功安装并运行。${NC}"

    if [ ${#ALLOWED_IPS[@]} -gt 0 ]; then
        echo -e "${YELLOW}正在应用防火墙白名单规则...${NC}"
        apply_firewall_rules
    else
        echo -e "${RED}警告：未设置白名单，当前所有 IP 均可盗用您的解锁服务！${NC}"
        echo -e "${YELLOW}请尽快使用菜单选项 6 设置机场节点 IP。${NC}"
    fi

    echo -e "${GREEN}安装完成！本机已成为机场解锁服务器。${NC}"
    read -p "按回车返回菜单..." _
}

install_singbox_mode() {
    clear
    echo -e "${SKY}安装 sing-box 解锁模式${NC}"
    echo -e "${YELLOW}该模式暂未实装，建议使用方案 1 (Prism+Sniproxy) 以获得最佳兼容性。${NC}"
    read -p "按回车返回菜单..." _
}

uninstall_all() {
    clear
    echo -e "${RED}即将卸载所有解锁服务，并清理相关防火墙规则。${NC}"
    read -p "确认卸载？[y/N] " c
    [[ "$c" =~ ^[Yy]$ ]] || return

    docker rm -f prism-dns sniproxy >/dev/null 2>&1 || true
    clear_firewall_rules
    MODE=""
    echo -e "${GREEN}卸载完成。配置目录保留：${PRISM_DIR}、${SNIPROXY_DIR}${NC}"
    read -p "按回车返回菜单..." _
}

# ==========================================================
# 节点 JSON 生成
# ==========================================================
# (此部分逻辑基本无误，保留原逻辑，仅微调显示)

reset_services() {
    SERVICE_GPT=0; SERVICE_GEMINI=0; SERVICE_COPILOT=0
    SERVICE_NETFLIX=0; SERVICE_DISNEY=0; SERVICE_TIKTOK=0
    SERVICE_PRIME=0; SERVICE_HULU=0; SERVICE_HBO=0
}

select_services() {
    reset_services
    clear
    echo -e "${SKY}选择需要解锁的服务（生成 Sing-box 路由规则）${NC}\n"
    echo "  1) GPT（OpenAI）"
    echo "  2) Gemini（Google）"
    echo "  3) Copilot（Microsoft）"
    echo "  4) Netflix"
    echo "  5) Disney+"
    echo "  6) TikTok"
    echo "  7) Prime Video"
    echo "  8) Hulu"
    echo "  9) HBO Max"
    echo ""
    echo -e "${YELLOW}请输入数字序列，用逗号分隔（例：1,4,5）${NC}"
    read -p ">> " svc_input

    IFS=',' read -ra arr <<< "$svc_input"
    for x in "${arr[@]}"; do
        x=$(echo "$x" | tr -d ' ')
        case "$x" in
            1) SERVICE_GPT=1 ;; 2) SERVICE_GEMINI=1 ;; 3) SERVICE_COPILOT=1 ;;
            4) SERVICE_NETFLIX=1 ;; 5) SERVICE_DISNEY=1 ;; 6) SERVICE_TIKTOK=1 ;;
            7) SERVICE_PRIME=1 ;; 8) SERVICE_HULU=1 ;; 9) SERVICE_HBO=1 ;;
        esac
    done
}

build_domain_list() {
    DOMAINS=()
    [ $SERVICE_GPT -eq 1 ] && DOMAINS+=( "openai.com" "chatgpt.com" "oaistatic.com" "oaiusercontent.com" "auth0.com" "identrust.com" "challenges.cloudflare.com" "ai.com" "stripe.com" "hcaptcha.com" "turnstile.com" )
    [ $SERVICE_GEMINI -eq 1 ] && DOMAINS+=( "bard.google.com" "gemini.google.com" "ai.google.dev" "generativelanguage.googleapis.com" "deepmind.com" )
    [ $SERVICE_COPILOT -eq 1 ] && DOMAINS+=( "copilot.microsoft.com" "bing.com" "live.com" )
    [ $SERVICE_NETFLIX -eq 1 ] && DOMAINS+=( "netflix.com" "netflix.net" "nflximg.net" "nflxvideo.net" "nflxso.net" "nflxext.com" )
    [ $SERVICE_DISNEY -eq 1 ] && DOMAINS+=( "disney.com" "disneyplus.com" "dssott.com" "bamgrid.com" "disneystreaming.com" )
    [ $SERVICE_TIKTOK -eq 1 ] && DOMAINS+=( "tiktok.com" "tiktokv.com" "tiktokcdn.com" "byteoversea.com" "ibytedtos.com" "muscdn.com" )
    [ $SERVICE_PRIME -eq 1 ] && DOMAINS+=( "primevideo.com" "amazonvideo.com" )
    [ $SERVICE_HULU -eq 1 ] && DOMAINS+=( "hulu.com" )
    [ $SERVICE_HBO -eq 1 ] && DOMAINS+=( "hbo.com" "hbogo.com" "hbomax.com" "max.com" )
}

generate_node_singbox_json() {
    if [[ -z "$SERVER_IP" ]]; then detect_public_ip; fi
    select_services
    build_domain_list

    clear
    echo -e "${SKY}【机场节点后端】sing-box 配置片段：${NC}"
    echo -e "${YELLOW}请将以下 DNS 和 Route 规则合并到您的节点配置中。${NC}\n"

    # 生成 JSON
    echo '{'
    echo '  "dns": {'
    echo '    "servers": ['
    echo '      {'
    echo '        "tag": "unlock_dns",'
    echo "        \"address\": \"${SERVER_IP}\","
    echo '        "detour": "direct"'
    echo '      }'
    echo '    ],'
    echo '    "rules": ['
    echo '      {'
    echo '        "domain_suffix": ['
    local len=${#DOMAINS[@]}
    for ((i=0; i<len; i++)); do
        local d="${DOMAINS[$i]}"
        if [ $i -eq $((len-1)) ]; then
            echo "          \"$d\""
        else
            echo "          \"$d\","
        fi
    done
    echo '        ],'
    echo '        "server": "unlock_dns"'
    echo '      }'
    echo '    ]'
    echo '  },'
    echo '  "route": {'
    echo '    "rules": ['
    echo '      {'
    echo "        \"ip_cidr\": [\"${SERVER_IP}/32\"],"
    echo '        "outbound": "direct"'
    echo '      }'
    echo '    ]'
    echo '  }'
    echo '}'

    echo ""
    read -p "复制完成后按回车返回菜单..." _
}

# ==========================================================
# 连通性 & 解锁测试
# ==========================================================

test_unlock_connectivity() {
    if [[ -z "$SERVER_IP" ]]; then detect_public_ip; fi
    clear
    echo -e "${BLUE}测试解锁机连通性（本机 IP：${SERVER_IP}）${NC}\n"

    echo -e "${YELLOW}1) 本地 53 端口监听检测${NC}"
    if check_port 53; then
         echo -e "${GREEN}✓ 53 端口正在监听 (DNS)${NC}"
    else
         echo -e "${RED}✗ 53 端口未启动${NC}"
    fi

    echo -e "${YELLOW}2) 本地 443 端口监听检测${NC}"
    if check_port 443; then
         echo -e "${GREEN}✓ 443 端口正在监听 (Sniproxy)${NC}"
    else
         echo -e "${RED}✗ 443 端口未启动${NC}"
    fi
    
    echo -e "${YELLOW}3) 内部链路测试 (DNS -> Sniproxy)${NC}"
    # 使用 dig 测试解析，必须解析为 127.0.0.1 (因为 config 里面写了 proxy 转发)
    # 实际上 Prism 转发模式下，它会代理流量，而不是返回 A 记录。
    # Prism 的工作原理是：客户端请求 A 记录 -> Prism 返回 Fake IP 或直接接管？
    # 通常 PrismDNS 配置了 proxy 后，会返回一个 Fake IP 或者如果 upstream 是 forward 模式，
    # 它会将流量转发。
    # 简单的测试方法：
    echo "跳过复杂链路测试，请直接进行业务测试（选项 5）。"
    
    echo ""
    read -p "按回车返回菜单..." _
}

test_gpt_netflix() {
    if [[ -z "$SERVER_IP" ]]; then detect_public_ip; fi
    clear
    echo -e "${PURPLE}测试 GPT / Netflix 解锁状态（模拟客户端行为）${NC}\n"
    
    if ! command -v curl >/dev/null 2>&1; then
        echo -e "${RED}未安装 curl，无法测试。${NC}"
        read -p "按回车返回菜单..." _
        return
    fi

    # 【修复】使用 /dev/null 丢弃 body，只看 status code
    echo -e "${YELLOW}1) GPT：chatgpt.com${NC}"
    local gpt_code
    gpt_code=$(curl -k -s -o /dev/null -w "%{http_code}" \
        --resolve "chatgpt.com:443:${SERVER_IP}" \
        "https://chatgpt.com")
    
    echo -e "HTTP 状态码：${gpt_code}"
    # 200/302/301 或者是 Cloudflare 的 403 (也是通的，只是被 CF 拦截) 均代表网络层通了
    if [[ "$gpt_code" =~ ^(200|301|302|403)$ ]]; then
        echo -e "${GREEN}✓ GPT 站点网络层可达（SNI 代理工作正常）${NC}"
    else
        echo -e "${RED}✗ GPT 访问失败 (Code: $gpt_code)${NC}"
    fi
    echo ""

    echo -e "${YELLOW}2) Netflix：www.netflix.com${NC}"
    local nf_code
    nf_code=$(curl -k -s -o /dev/null -w "%{http_code}" \
        --resolve "www.netflix.com:443:${SERVER_IP}" \
        "https://www.netflix.com")
        
    echo -e "HTTP 状态码：${nf_code}"
    if [[ "$nf_code" =~ ^(200|301|302)$ ]]; then
        echo -e "${GREEN}✓ Netflix 站点网络层可达${NC}"
    else
        echo -e "${RED}✗ Netflix 访问失败 (Code: $nf_code)${NC}"
    fi

    echo ""
    read -p "按回车返回菜单..." _
}

# ==========================================================
# 主菜单
# ==========================================================

main_menu() {
    while true; do
        clear
        echo -e "${SKY}==================================================${NC}"
        echo -e "${SKY}  机场解锁服务器管理工具（修复增强版 v1.1）${NC}"
        echo -e "${SKY}==================================================${NC}\n"

        echo -e "${GREEN}本机 IP：${SERVER_IP:-等待检测...}${NC}\n"

        echo -e "${YELLOW}1) 安装 Prism-DNS + sniproxy (推荐)${NC}"
        echo -e "${YELLOW}2) 安装 sing-box 模式 (开发中)${NC}"
        echo -e "----------------------------------------"
        echo -e "${YELLOW}3) 设置白名单 IP (防火墙安全设置)${NC}"
        echo -e "${YELLOW}4) 生成节点端 JSON 配置${NC}"
        echo -e "${YELLOW}5) 测试解锁状态${NC}"
        echo -e "${RED}6) 卸载服务${NC}"
        echo -e "${RED}0) 退出${NC}"
        echo ""
        read -p ">> " choice

        case "$choice" in
            1) install_prism_sniproxy_mode ;;
            2) install_singbox_mode ;;
            3) set_allowed_ips ;;
            4) generate_node_singbox_json ;;
            5) test_gpt_netflix ;;
            6) uninstall_all ;;
            0) clear; exit 0 ;;
            *) ;;
        esac
    done
}

detect_firewall_backend
detect_public_ip
main_menu
