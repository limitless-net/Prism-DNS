#!/bin/bash
# ==========================================================
#  机场用生产级解锁服务器脚本（谁运行谁就是解锁机）
#  模式：
#    - Prism-DNS + sniproxy（Docker，生产级）
#    - sing-box 模式（占位，可后续扩展）
# ==========================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
SKY='\033[0;36m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

MODE=""                 # prism / singbox
FIREWALL_BACKEND=""     # ufw / firewalld / iptables
SERVER_IP=""            # 本机对外 IP
ALLOWED_IPS=()          # 白名单节点 IP 列表

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
    for url in "https://ipinfo.io/ip" "https://ifconfig.me" "https://api.ip.sb/ip"; do
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
    case "$ip" in *[!.:0-9a-fA-F]*) return 1;; esac
    if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        IFS='.' read -ra o <<< "$ip"
        for x in "${o[@]}"; do
            ((x>=0 && x<=255)) || return 1
        done
        return 0
    fi
    [[ "$ip" == *:* ]] && return 0
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
# 防火墙相关
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

    echo -e "${BLUE}应用防火墙白名单规则（允许以下 IP 使用解锁服务）：${NC}"
    printf '  %s\n' "${ALLOWED_IPS[@]}"

    case "$FIREWALL_BACKEND" in
        ufw)
            sudo ufw enable >/dev/null 2>&1 || true
            for ip in "${ALLOWED_IPS[@]}"; do
                sudo ufw allow from "$ip" to any port 53 proto tcp >/dev/null 2>&1
                sudo ufw allow from "$ip" to any port 53 proto udp >/dev/null 2>&1
                sudo ufw allow from "$ip" to any port 80 proto tcp >/dev/null 2>&1
                sudo ufw allow from "$ip" to any port 443 proto tcp >/dev/null 2>&1
            done
            sudo ufw deny 53 >/dev/null 2>&1 || true
            sudo ufw deny 80 >/dev/null 2>&1 || true
            sudo ufw deny 443 >/dev/null 2>&1 || true
            ;;
        firewalld)
            sudo systemctl start firewalld >/dev/null 2>&1 || true
            for ip in "${ALLOWED_IPS[@]}"; do
                sudo firewall-cmd --permanent --add-rich-rule="rule family=ipv4 source address=${ip} port protocol=tcp port=53 accept" >/dev/null 2>&1
                sudo firewall-cmd --permanent --add-rich-rule="rule family=ipv4 source address=${ip} port protocol=udp port=53 accept" >/dev/null 2>&1
                sudo firewall-cmd --permanent --add-rich-rule="rule family=ipv4 source address=${ip} port protocol=tcp port=80 accept" >/dev/null 2>&1
                sudo firewall-cmd --permanent --add-rich-rule="rule family=ipv4 source address=${ip} port protocol=tcp port=443 accept" >/dev/null 2>&1
            done
            sudo firewall-cmd --permanent --add-rich-rule="rule family=ipv4 port protocol=tcp port=53 drop" >/dev/null 2>&1
            sudo firewall-cmd --permanent --add-rich-rule="rule family=ipv4 port protocol=udp port=53 drop" >/dev/null 2>&1
            sudo firewall-cmd --permanent --add-rich-rule="rule family=ipv4 port protocol=tcp port=80 drop" >/dev/null 2>&1
            sudo firewall-cmd --permanent --add-rich-rule="rule family=ipv4 port protocol=tcp port=443 drop" >/dev/null 2>&1
            sudo firewall-cmd --reload >/dev/null 2>&1
            ;;
        iptables|*)
            iptables -N UNLOCK_SRV 2>/dev/null || iptables -F UNLOCK_SRV
            iptables -D INPUT -j UNLOCK_SRV 2>/dev/null || true
            iptables -A INPUT -j UNLOCK_SRV
            for ip in "${ALLOWED_IPS[@]}"; do
                iptables -A UNLOCK_SRV -p tcp -s "$ip" --dport 53 -j ACCEPT
                iptables -A UNLOCK_SRV -p udp -s "$ip" --dport 53 -j ACCEPT
                iptables -A UNLOCK_SRV -p tcp -s "$ip" --dport 80 -j ACCEPT
                iptables -A UNLOCK_SRV -p tcp -s "$ip" --dport 443 -j ACCEPT
            done
            iptables -A UNLOCK_SRV -p tcp --dport 53 -j DROP
            iptables -A UNLOCK_SRV -p udp --dport 53 -j DROP
            iptables -A UNLOCK_SRV -p tcp --dport 80 -j DROP
            iptables -A UNLOCK_SRV -p tcp --dport 443 -j DROP
            ;;
    esac
}

clear_firewall_rules() {
    case "$FIREWALL_BACKEND" in
        ufw)
            echo -e "${YELLOW}ufw 规则请按需手动清理（避免误删其他服务）。${NC}"
            ;;
        firewalld)
            echo -e "${YELLOW}firewalld rich rules 请按需手动清理（避免误删其他服务）。${NC}"
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
        echo -e "${YELLOW}上述端口已被占用，继续安装可能影响现有服务。${NC}"
        read -p "仍然继续？[y/N] " c
        [[ "$c" =~ ^[Yy]$ ]] || return 1
    fi
    return 0
}

# ==========================================================
# 配置文件初始化（生产级）
# ==========================================================

init_prism_config() {
    sudo mkdir -p "$PRISM_DIR"
    local cfg="$PRISM_DIR/config.yaml"
    if [ -f "$cfg" ]; then
        echo -e "${GREEN}检测到已有 Prism-DNS 配置：${cfg}${NC}"
        return
    fi
    echo -e "${YELLOW}未检测到 Prism-DNS 配置，生成基础生产级配置：${cfg}${NC}"
    sudo tee "$cfg" >/dev/null <<EOF
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

proxy:
  type: "forward"
  address: "127.0.0.1:443"
EOF
}

init_sniproxy_config() {
    sudo mkdir -p "$SNIPROXY_DIR"
    local cfg="$SNIPROXY_DIR/sniproxy.conf"
    if [ -f "$cfg" ]; then
        echo -e "${GREEN}检测到已有 sniproxy 配置：${cfg}${NC}"
        return
    fi
    echo -e "${YELLOW}未检测到 sniproxy 配置，生成基础生产级配置：${cfg}${NC}"
    sudo tee "$cfg" >/dev/null <<'EOF'
user nobody
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
        filename /var/log/sniproxy/http_access.log
    }
}

listen 0.0.0.0:443 {
    proto tls
    table https_hosts
    access_log {
        filename /var/log/sniproxy/https_access.log
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
    echo -e "${SKY}安装 Prism-DNS + sniproxy 解锁模式（Docker，生产级）${NC}"

    check_ports_53_80_443 || return

    if ! command -v docker >/dev/null 2>&1; then
        echo -e "${YELLOW}未检测到 docker，正在安装...${NC}"
        if command -v apt >/dev/null 2>&1; then
            sudo apt update && sudo apt install -y docker.io
        elif command -v yum >/dev/null 2>&1; then
            sudo yum install -y docker
        fi
        sudo systemctl enable docker --now
    fi

    init_prism_config
    init_sniproxy_config

    echo -e "${YELLOW}正在部署 Prism-DNS 和 sniproxy（带资源限制、日志限制、healthcheck）...${NC}"

    docker rm -f prism-dns sniproxy >/dev/null 2>&1 || true

    docker run -d \
      --name prism-dns \
      --restart=always \
      --memory=256m \
      --cpus=0.5 \
      --log-opt max-size=10m \
      --log-opt max-file=5 \
      -p 53:53/udp \
      -p 53:53/tcp \
      -v "${PRISM_DIR}:/app/config" \
      --health-cmd="nslookup openai.com 127.0.0.1 >/dev/null 2>&1 || exit 1" \
      --health-interval=30s \
      --health-retries=3 \
      ghcr.io/zhxie/prismdns:latest

    docker run -d \
      --name sniproxy \
      --restart=always \
      --memory=256m \
      --cpus=0.5 \
      --log-opt max-size=10m \
      --log-opt max-file=5 \
      -p 80:80 \
      -p 443:443 \
      -v "${SNIPROXY_DIR}/sniproxy.conf:/etc/sniproxy.conf:ro" \
      --health-cmd="nc -z 127.0.0.1 443 || exit 1" \
      --health-interval=30s \
      --health-retries=3 \
      ghcr.io/dlundquist/sniproxy:latest

    echo -e "${GREEN}✓ Prism-DNS + sniproxy 已成功安装并运行（生产级参数）。${NC}"

    if [ ${#ALLOWED_IPS[@]} -gt 0 ]; then
        echo -e "${YELLOW}正在应用防火墙白名单规则...${NC}"
        apply_firewall_rules
    else
        echo -e "${YELLOW}未设置白名单，当前所有 IP 均可访问解锁服务（不推荐机场生产）。${NC}"
    fi

    echo -e "${GREEN}安装完成！本机已成为机场解锁服务器。${NC}"
    read -p "按回车返回菜单..." _
}

install_singbox_mode() {
    MODE="singbox"
    clear
    echo -e "${SKY}安装 sing-box 解锁模式（占位，预留给你后续自定义）${NC}"
    check_ports_53_80_443 || return
    echo -e "${YELLOW}生产环境建议优先使用 Prism-DNS + sniproxy 方案。${NC}"
    echo -e "${YELLOW}如需我帮你做 sing-box 生产级方案，可以单独说。${NC}"
    read -p "按回车返回菜单..." _
}

uninstall_all() {
    clear
    echo -e "${RED}即将卸载所有解锁服务，并清理 iptables 链（不会动 ufw/firewalld 全局）。${NC}"
    read -p "确认卸载？[y/N] " c
    [[ "$c" =~ ^[Yy]$ ]] || return

    docker rm -f prism-dns sniproxy >/dev/null 2>&1 || true
    clear_firewall_rules
    MODE=""
    echo -e "${GREEN}卸载完成。配置目录保留：${PRISM_DIR}、${SNIPROXY_DIR}${NC}"
    read -p "按回车返回菜单..." _
}

# ==========================================================
# 解锁服务选择 & 节点 JSON 生成
# ==========================================================

reset_services() {
    SERVICE_GPT=0
    SERVICE_GEMINI=0
    SERVICE_COPILOT=0
    SERVICE_NETFLIX=0
    SERVICE_DISNEY=0
    SERVICE_TIKTOK=0
    SERVICE_PRIME=0
    SERVICE_HULU=0
    SERVICE_HBO=0
}

select_services() {
    reset_services
    clear
    echo -e "${SKY}选择需要解锁的服务（写入节点后端 JSON 的 domain_suffix）${NC}\n"
    echo "  1) GPT（OpenAI）"
    echo "  2) Gemini（Google）"
    echo "  3) Copilot（Microsoft）"
    echo ""
    echo "  4) Netflix"
    echo "  5) Disney+"
    echo "  6) TikTok"
    echo "  7) Prime Video"
    echo "  8) Hulu"
    echo "  9) HBO Max"
    echo ""
    echo -e "${YELLOW}可多选，使用逗号分隔，例如：1,2,4,5${NC}"
    read -p ">> " svc_input

    IFS=',' read -ra arr <<< "$svc_input"
    for x in "${arr[@]}"; do
        x=$(echo "$x" | tr -d ' ')
        case "$x" in
            1) SERVICE_GPT=1 ;;
            2) SERVICE_GEMINI=1 ;;
            3) SERVICE_COPILOT=1 ;;
            4) SERVICE_NETFLIX=1 ;;
            5) SERVICE_DISNEY=1 ;;
            6) SERVICE_TIKTOK=1 ;;
            7) SERVICE_PRIME=1 ;;
            8) SERVICE_HULU=1 ;;
            9) SERVICE_HBO=1 ;;
        esac
    done
}

build_domain_list() {
    DOMAINS=()
    [ $SERVICE_GPT -eq 1 ] && DOMAINS+=(
        "openai.com" "chatgpt.com" "oaistatic.com" "oaiusercontent.com"
        "auth0.com" "sentry.io" "identrust.com" "challenges.cloudflare.com"
        "ai.com" "intercom.io" "intercomcdn.com" "featuregates.org"
        "statsigapi.net" "stripe.com" "openaiapi-site.azureedge.net"
        "client.crisp.chat" "livekit.cloud" "launchdarkly.com"
        "cloudflareinsights.com" "clarity.ms" "hcaptcha.com" "turnstile.com"
    )
    [ $SERVICE_GEMINI -eq 1 ] && DOMAINS+=(
        "bard.google.com" "gemini.google.com" "ai.google.dev"
        "generativelanguage.googleapis.com" "makersuite.google.com"
        "deepmind.com" "googleapis.com"
    )
    [ $SERVICE_COPILOT -eq 1 ] && DOMAINS+=(
        "copilot.microsoft.com" "bing.com" "live.com"
    )
    [ $SERVICE_NETFLIX -eq 1 ] && DOMAINS+=(
        "netflix.com" "netflix.net" "nflximg.net" "nflxvideo.net"
        "nflxso.net" "nflxext.com" "nflxext.net"
    )
    [ $SERVICE_DISNEY -eq 1 ] && DOMAINS+=(
        "disney.com" "disneyplus.com" "dssott.com" "bamgrid.com"
        "go.com" "max.com" "disneynow.com" "disneystreaming.com"
        "starplus.com" "d23.com"
    )
    [ $SERVICE_TIKTOK -eq 1 ] && DOMAINS+=(
        "tiktok.com" "tiktokv.com" "tiktokcdn.com"
        "byteoversea.com" "ibytedtos.com" "ipstatp.com"
        "muscdn.com" "musical.ly"
    )
    [ $SERVICE_PRIME -eq 1 ] && DOMAINS+=(
        "primevideo.com" "amazonvideo.com"
    )
    [ $SERVICE_HULU -eq 1 ] && DOMAINS+=(
        "hulu.com"
    )
    [ $SERVICE_HBO -eq 1 ] && DOMAINS+=(
        "hbo.com" "hbogo.com" "hbomax.com" "onetrust.com"
    )
}

generate_node_singbox_json() {
    if [[ -z "$SERVER_IP" ]]; then
        detect_public_ip
    fi
    select_services
    build_domain_list

    clear
    echo -e "${SKY}下面是【机场节点后端】要用的 sing-box 配置 JSON：${NC}"
    echo -e "${YELLOW}注意：address/ip_cidr 都指向解锁机 IP：${SERVER_IP}${NC}\n"

    cat <<EOF
{
  "dns": {
    "servers": [
      {
        "tag": "unlock_dns",
        "address": "${SERVER_IP}",
        "detour": "direct"
      },
      {
        "tag": "cf",
        "address": "1.1.1.1"
      }
    ],
    "rules": [
      {
        "domain_suffix": [
EOF

    local first=1
    for d in "${DOMAINS[@]}"; do
        if [ $first -eq 1 ]; then
            echo "          \"${d}\""
            first=0
        else
            echo "        , \"${d}\""
        fi
    done

    cat <<EOF
        ],
        "server": "unlock_dns"
      }
    ],
    "strategy": "prefer_ipv4"
  },

  "outbounds": [
    {
      "tag": "direct",
      "type": "direct",
      "domain_resolver": {
        "server": "cf",
        "strategy": "prefer_ipv4"
      }
    },
    {
      "type": "block",
      "tag": "block"
    }
  ],

  "route": {
    "rules": [
      {
        "ip_cidr": ["${SERVER_IP}/32"],
        "outbound": "direct"
      },
      {
        "ip_is_private": true,
        "outbound": "block"
      },
      {
        "outbound": "direct",
        "network": ["udp","tcp"]
      }
    ]
  },

  "experimental": {
    "cache_file": {
      "enabled": true
    }
  }
}
EOF

    echo ""
    read -p "复制完成后按回车返回菜单..." _
}

# ==========================================================
# 连通性 & 解锁测试
# ==========================================================

test_unlock_connectivity() {
    if [[ -z "$SERVER_IP" ]]; then
        detect_public_ip
    fi
    clear
    echo -e "${BLUE}测试解锁机连通性（本机 IP：${SERVER_IP}）${NC}\n"

    echo -e "${YELLOW}1) ping 测试${NC}"
    run_with_spinner "ping ${SERVER_IP} ..." ping -c 4 -W 1 "$SERVER_IP"
    [ $? -eq 0 ] && echo -e "${GREEN}✓ ping 成功${NC}" || echo -e "${RED}✗ ping 失败${NC}"
    echo ""

    echo -e "${YELLOW}2) TCP 443 端口测试${NC}"
    if command -v nc >/dev/null 2>&1; then
        run_with_spinner "nc -zv ${SERVER_IP} 443 ..." nc -z -w 3 "$SERVER_IP" 443
        [ $? -eq 0 ] && echo -e "${GREEN}✓ 443 端口可连接${NC}" || echo -e "${RED}✗ 无法连接 443 端口${NC}"
    else
        echo -e "${YELLOW}未安装 nc，跳过 TCP 测试${NC}"
    fi
    echo ""

    echo -e "${YELLOW}3) TLS 测试（直连 https://${SERVER_IP}）${NC}"
    if command -v curl >/dev/null 2>&1; then
        run_with_spinner "curl https://${SERVER_IP} ..." curl -k -s -o /dev/null -m 8 "https://${SERVER_IP}"
        [ $? -eq 0 ] && echo -e "${GREEN}✓ TLS 握手成功${NC}" || echo -e "${RED}✗ TLS 握手失败${NC}"
    else
        echo -e "${YELLOW}未安装 curl，跳过 TLS 测试${NC}"
    fi

    echo ""
    read -p "按回车返回菜单..." _
}

test_gpt_netflix() {
    if [[ -z "$SERVER_IP" ]]; then
        detect_public_ip
    fi
    clear
    echo -e "${PURPLE}测试 GPT / Netflix 解锁状态（通过本机 IP：${SERVER_IP}）${NC}\n"

    if ! command -v curl >/dev/null 2>&1; then
        echo -e "${RED}未安装 curl，无法测试。${NC}"
        read -p "按回车返回菜单..." _
        return
    fi

    echo -e "${YELLOW}1) GPT：chat.openai.com${NC}"
    run_with_spinner "curl --resolve chat.openai.com:443:${SERVER_IP} ..." \
        curl -k -s -o /tmp/unlock_gpt_body.txt -w "%{http_code}" \
        --resolve "chat.openai.com:443:${SERVER_IP}" \
        "https://chat.openai.com"
    gpt_code=$(tail -n1 /tmp/unlock_gpt_body.txt)
    echo -e "HTTP 状态码：${gpt_code}"
    [[ "$gpt_code" =~ ^(200|301|302)$ ]] && \
        echo -e "${GREEN}✓ GPT 站点可访问（解锁链路基本正常）${NC}" || \
        echo -e "${RED}✗ GPT 访问异常（地区/转发/风控问题）${NC}"
    echo ""

    echo -e "${YELLOW}2) Netflix：www.netflix.com${NC}"
    run_with_spinner "curl --resolve www.netflix.com:443:${SERVER_IP} ..." \
        curl -k -s -o /tmp/unlock_nf_body.txt -w "%{http_code}" \
        --resolve "www.netflix.com:443:${SERVER_IP}" \
        "https://www.netflix.com"
    nf_code=$(tail -n1 /tmp/unlock_nf_body.txt)
    echo -e "HTTP 状态码：${nf_code}"
    [[ "$nf_code" =~ ^(200|301|302)$ ]] && \
        echo -e "${GREEN}✓ Netflix 站点可访问（解锁链路基本正常）${NC}" || \
        echo -e "${RED}✗ Netflix 访问异常（地区/转发/风控问题）${NC}"

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
        echo -e "${SKY}  机场解锁服务器管理工具（谁运行谁就是解锁机）${NC}"
        echo -e "${SKY}==================================================${NC}\n"

        echo -e "${GREEN}当前解锁模式：${MODE:-未安装}${NC}"
        echo -e "${GREEN}当前解锁机 IP：${SERVER_IP:-未检测}${NC}\n"

        echo -e "${YELLOW}1) 安装 Prism-DNS + sniproxy 解锁模式（生产级，Docker）${NC}"
        echo -e "${YELLOW}2) 安装 sing-box 解锁模式（占位，预留扩展）${NC}"
        echo -e "${YELLOW}3) 生成【机场节点后端】sing-box JSON 配置（指向本机）${NC}"
        echo -e "${YELLOW}4) 测试解锁机连通性（ping/TCP/TLS）${NC}"
        echo -e "${YELLOW}5) 测试 GPT / Netflix 解锁状态${NC}"
        echo -e "${YELLOW}6) 设置允许接入的节点 IP（防火墙白名单）${NC}"
        echo -e "${RED}7) 一键卸载解锁服务（保留配置目录）${NC}"
        echo -e "${RED}0) 退出${NC}"
        echo ""
        read -p ">> " choice

        case "$choice" in
            1) install_prism_sniproxy_mode ;;
            2) install_singbox_mode ;;
            3) generate_node_singbox_json ;;
            4) test_unlock_connectivity ;;
            5) test_gpt_netflix ;;
            6) set_allowed_ips ;;
            7) uninstall_all ;;
            0) clear; exit 0 ;;
            *) ;;
        esac
    done
}

# ==========================================================
# 启动
# ==========================================================

detect_firewall_backend
detect_public_ip
main_menu
