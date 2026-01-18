#!/bin/bash
# ==========================================================
#  一键解锁服务器总控脚本（谁运行谁就是解锁机）
#  功能：
#    - 本机作为解锁服务器（Prism-DNS+sniproxy / sing-box 二选一）
#    - 自动检测系统 & 防火墙后端（ufw / firewalld / iptables）
#    - 端口占用检测（53 / 80 / 443）
#    - 防火墙白名单：只允许指定节点 IP 使用解锁服务
#    - 一键卸载（清理服务 + 防火墙规则）
#    - 自动生成“节点后端 sing-box JSON 配置”（指向本机）
#    - 自动测试解锁机连通性
#    - 自动测试 GPT / Netflix 解锁状态（通过本机 IP）
# ==========================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
SKY='\033[0;36m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

MODE=""                 # prism/sniproxy 或 singbox
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

# ==========================================================
# 基础工具
# ==========================================================

detect_public_ip() {
    # 尽量多源获取公网 IP
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
    case "$ip" in
        *[!.:0-9a-fA-F]*)
            return 1
            ;;
    esac
    if [[ "$ip" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]]; then
        local octet
        for octet in "${BASH_REMATCH[@]:1}"; do
            if [ "$((10#$octet))" -gt 255 ]; then
                return 1
            fi
        done
        return 0
    fi
    if [[ "$ip" =~ ^[0-9a-fA-F:]+$ ]]; then
        if [[ "$ip" == *:* ]]; then
            if [[ "$ip" =~ :::+ ]]; then
                return 1
            fi
            case "$ip" in
                *::*::*)
                    return 1
                    ;;
                *::*)
                    return 0
                    ;;
                ::)
                    return 0
                    ;;
                *)
                    if [[ "$ip" =~ ^[0-9a-fA-F]+:[0-9a-fA-F:]+$ ]]; then
                        return 0
                    fi
                    ;;
            esac
        fi
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
    local msg="$1"
    shift
    local cmd=("$@")
    spinner "$msg" &
    local spid=$!
    "${cmd[@]}" >/tmp/unlock_tool_cmd.log 2>&1
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
    # 只允许 ALLOWED_IPS 访问 53/80/443，其余全部拒绝
    if [ ${#ALLOWED_IPS[@]} -eq 0 ]; then
        echo -e "${YELLOW}未设置白名单节点 IP，暂不限制访问（不安全）。${NC}"
        return
    fi

    echo -e "${BLUE}应用防火墙白名单规则（允许以下 IP 使用解锁服务）：${NC}"
    printf '  %s\n' "${ALLOWED_IPS[@]}"

    case "$FIREWALL_BACKEND" in
        ufw)
            echo -e "${YELLOW}使用 ufw 管理防火墙规则...${NC}"
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
            echo -e "${YELLOW}使用 firewalld 管理防火墙规则...${NC}"
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
            echo -e "${YELLOW}使用 iptables 管理防火墙规则...${NC}"
            # 先清理旧规则（简单粗暴：打上自定义链）
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
            echo -e "${YELLOW}清理 ufw 相关规则（需要你自己确认 ufw 状态）${NC}"
            ;;
        firewalld)
            echo -e "${YELLOW}清理 firewalld 相关规则（建议手动检查）${NC}"
            ;;
        iptables|*)
            echo -e "${YELLOW}清理 iptables UNLOCK_SRV 链${NC}"
            iptables -D INPUT -j UNLOCK_SRV 2>/dev/null || true
            iptables -F UNLOCK_SRV 2>/dev/null || true
            iptables -X UNLOCK_SRV 2>/dev/null || true
            ;;
    esac
}

set_allowed_ips() {
    echo -e "${SKY}请输入允许接入此解锁服务的节点 IP（多个用逗号分隔）：${NC}"
    echo -e "${YELLOW}例如：1.2.3.4, 5.6.7.8${NC}"
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
        echo -e "${YELLOW}上述端口已被占用，继续安装可能导致冲突。${NC}"
        read -p "仍然继续？[y/N] " c
        [[ "$c" =~ ^[Yy]$ ]] || return 1
    fi
    return 0
}

# ==========================================================
# 解锁模式安装（这里只给出结构，你可以按自己习惯填充具体实现）
# 为了不污染系统，这里默认用 docker 方式部署，原生你可以再细化
# ==========================================================

install_prism_sniproxy_mode() {
    MODE="prism"
    clear
    echo -e "${SKY}安装 Prism-DNS + sniproxy 解锁模式（示例用 docker，你可按需改原生）${NC}"

    check_ports_53_80_443 || return

    if ! command -v docker >/dev/null 2>&1; then
        echo -e "${YELLOW}未检测到 docker，尝试安装...${NC}"
        if command -v apt >/dev/null 2>&1; then
            sudo apt update && sudo apt install -y docker.io
        elif command -v yum >/dev/null 2>&1; then
            sudo yum install -y docker
        fi
        sudo systemctl enable docker --now
    fi

    echo -e "${YELLOW}此处请替换为你实际使用的 Prism-DNS/sniproxy 镜像和参数${NC}"
    echo -e "${YELLOW}示例：docker run -d --name prism-dns -p 53:53/udp your/prism-image${NC}"
    echo -e "${YELLOW}示例：docker run -d --name sniproxy -p 80:80 -p 443:443 your/sniproxy-image${NC}"

    # 这里先用 echo 占位，避免误导你真实环境
    # 你可以把下面两行替换成你自己的 docker run 命令
    echo "docker run -d --name prism-dns -p 53:53/udp prism-dns-image"
    echo "docker run -d --name sniproxy -p 80:80 -p 443:443 sniproxy-image"

    echo -e "${GREEN}Prism-DNS + sniproxy 模式已标记为安装（请按你实际环境补全 docker 命令）。${NC}"
    read -p "按回车返回菜单..." _
}

install_singbox_mode() {
    MODE="singbox"
    clear
    echo -e "${SKY}安装 sing-box 解锁模式（轻量示例）${NC}"

    check_ports_53_80_443 || return

    if ! command -v sing-box >/dev/null 2>&1; then
        echo -e "${YELLOW}未检测到 sing-box，请按你自己的方式安装（此处仅示意）。${NC}"
        echo -e "${YELLOW}例如：wget 官方二进制 / 使用包管理器 / docker 等。${NC}"
    fi

    echo -e "${YELLOW}你可以在这里生成一个 sing-box 解锁配置并以 systemd 方式运行。${NC}"
    echo -e "${YELLOW}由于每个人的 sing-box 用法差异较大，这里只给出结构，你可以按需填充。${NC}"
    read -p "按回车返回菜单..." _
}

uninstall_all() {
    clear
    echo -e "${RED}即将卸载所有解锁服务，并清理防火墙规则...${NC}"
    read -p "确认卸载？[y/N] " c
    [[ "$c" =~ ^[Yy]$ ]] || return

    # 停止 docker 容器（示例）
    docker rm -f prism-dns sniproxy >/dev/null 2>&1 || true

    # 停止 sing-box（如果你用 systemd，可以在这里加 systemctl stop）
    # systemctl stop sing-box-unlock.service 2>/dev/null || true
    # systemctl disable sing-box-unlock.service 2>/dev/null || true

    clear_firewall_rules

    MODE=""
    echo -e "${GREEN}卸载完成（请根据你实际部署方式检查是否还有残留）。${NC}"
    read -p "按回车返回菜单..." _
}

# ==========================================================
# 解锁服务选择 & 节点 JSON 生成（核心：谁运行谁就是解锁机）
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
    echo -e "${SKY}选择需要解锁的服务（这些会写进节点后端 JSON 的 domain_suffix）${NC}\n"

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

    echo ""
    echo "已选择解锁服务："
    [ $SERVICE_GPT -eq 1 ] && echo "  - GPT（OpenAI）"
    [ $SERVICE_GEMINI -eq 1 ] && echo "  - Gemini（Google）"
    [ $SERVICE_COPILOT -eq 1 ] && echo "  - Copilot（Microsoft）"
    [ $SERVICE_NETFLIX -eq 1 ] && echo "  - Netflix"
    [ $SERVICE_DISNEY -eq 1 ] && echo "  - Disney+"
    [ $SERVICE_TIKTOK -eq 1 ] && echo "  - TikTok"
    [ $SERVICE_PRIME -eq 1 ] && echo "  - Prime Video"
    [ $SERVICE_HULU -eq 1 ] && echo "  - Hulu"
    [ $SERVICE_HBO -eq 1 ] && echo "  - HBO Max"

    echo ""
    read -p "确认选择并继续？[Y/n] " confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        select_services
    fi
}

build_domain_list() {
    DOMAINS=()

    if [ $SERVICE_GPT -eq 1 ]; then
        DOMAINS+=(
            "openai.com" "chatgpt.com" "oaistatic.com" "oaiusercontent.com"
            "auth0.com" "sentry.io" "identrust.com" "challenges.cloudflare.com"
            "ai.com" "intercom.io" "intercomcdn.com" "featuregates.org"
            "statsigapi.net" "stripe.com" "openaiapi-site.azureedge.net"
            "client.crisp.chat" "livekit.cloud" "launchdarkly.com"
            "cloudflareinsights.com" "clarity.ms" "hcaptcha.com" "turnstile.com"
        )
    fi

    if [ $SERVICE_GEMINI -eq 1 ]; then
        DOMAINS+=(
            "bard.google.com" "gemini.google.com" "ai.google.dev"
            "generativelanguage.googleapis.com" "makersuite.google.com"
            "deepmind.com" "googleapis.com"
        )
    fi

    if [ $SERVICE_COPILOT -eq 1 ]; then
        DOMAINS+=(
            "copilot.microsoft.com" "bing.com" "live.com"
        )
    fi

    if [ $SERVICE_NETFLIX -eq 1 ]; then
        DOMAINS+=(
            "netflix.com" "netflix.net" "nflximg.net" "nflxvideo.net"
            "nflxso.net" "nflxext.com" "nflxext.net"
        )
    fi

    if [ $SERVICE_DISNEY -eq 1 ]; then
        DOMAINS+=(
            "disney.com" "disneyplus.com" "dssott.com" "bamgrid.com"
            "go.com" "max.com" "disneynow.com" "disneystreaming.com"
            "starplus.com" "d23.com"
        )
    fi

    if [ $SERVICE_TIKTOK -eq 1 ]; then
        DOMAINS+=(
            "tiktok.com" "tiktokv.com" "tiktokcdn.com"
            "byteoversea.com" "ibytedtos.com" "ipstatp.com"
            "muscdn.com" "musical.ly"
        )
    fi

    if [ $SERVICE_PRIME -eq 1 ]; then
        DOMAINS+=(
            "primevideo.com" "amazonvideo.com"
        )
    fi

    if [ $SERVICE_HULU -eq 1 ]; then
        DOMAINS+=(
            "hulu.com"
        )
    fi

    if [ $SERVICE_HBO -eq 1 ]; then
        DOMAINS+=(
            "hbo.com" "hbogo.com" "hbomax.com" "onetrust.com"
        )
    fi
}

generate_node_singbox_json() {
    if [[ -z "$SERVER_IP" ]]; then
        detect_public_ip
    fi

    select_services
    build_domain_list

    clear
    echo -e "${SKY}下面是【节点后端】要用的 sing-box 配置 JSON：${NC}"
    echo -e "${YELLOW}注意：这里的 address/ip_cidr 都指向本机（解锁机）IP：${SERVER_IP}${NC}\n"

    cat <<EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "dns": {
    "servers": [
      {
        "tag": "unlock_dns",
        "address": "${SERVER_IP}",
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
    "final": "local_dns",
    "strategy": "prefer_ipv4",
    "disable_cache": true,
    "independent_cache": false
  },
  "inbounds": [
    {
      "type": "direct",
      "tag": "in-0"
    }
  ],
  "outbounds": [
    {
      "tag": "direct",
      "type": "direct"
    },
    {
      "tag": "block",
      "type": "block"
    }
  ],
  "route": {
    "rules": [
      {
        "protocol": "dns",
        "outbound": "direct"
      },
      {
        "ip_cidr": ["${SERVER_IP}/32"],
        "outbound": "direct"
      },
      {
        "protocol": "quic",
        "outbound": "block"
      },
      {
        "protocol": "bittorrent",
        "outbound": "block"
      },
      {
        "ip_is_private": true,
        "outbound": "block"
      },
      {
        "outbound": "direct",
        "network": ["udp", "tcp"]
      }
    ],
    "auto_detect_interface": false
  }
}
EOF

    echo ""
    read -p "复制完成后按回车返回菜单..." _
}

# ==========================================================
# 连通性 & 解锁测试（通过本机 IP）
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
    if [[ "$gpt_code" == "200" || "$gpt_code" == "301" || "$gpt_code" == "302" ]]; then
        echo -e "${GREEN}✓ GPT 站点可访问（解锁链路基本正常）${NC}"
    else
        echo -e "${RED}✗ GPT 访问异常（可能地区封锁 / 解锁机未正确转发）${NC}"
    fi
    echo ""

    echo -e "${YELLOW}2) Netflix：www.netflix.com${NC}"
    run_with_spinner "curl --resolve www.netflix.com:443:${SERVER_IP} ..." \
        curl -k -s -o /tmp/unlock_nf_body.txt -w "%{http_code}" \
        --resolve "www.netflix.com:443:${SERVER_IP}" \
        "https://www.netflix.com"
    nf_code=$(tail -n1 /tmp/unlock_nf_body.txt)
    echo -e "HTTP 状态码：${nf_code}"
    if [[ "$nf_code" == "200" || "$nf_code" == "301" || "$nf_code" == "302" ]]; then
        echo -e "${GREEN}✓ Netflix 站点可访问（解锁链路基本正常）${NC}"
    else
        echo -e "${RED}✗ Netflix 访问异常（可能地区限制 / 解锁机未正确转发）${NC}"
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
        echo -e "${SKY}  一键解锁服务器管理工具（谁运行谁就是解锁机）${NC}"
        echo -e "${SKY}==================================================${NC}\n"

        echo -e "${GREEN}当前解锁模式：${MODE:-未安装}${NC}"
        echo -e "${GREEN}当前解锁机 IP：${SERVER_IP:-未检测}${NC}\n"

        echo -e "${YELLOW}1) 安装 Prism-DNS + sniproxy 解锁模式（稳定，需你补全 docker/原生实现）${NC}"
        echo -e "${YELLOW}2) 安装 sing-box 解锁模式（轻量，需你按习惯填充）${NC}"
        echo -e "${YELLOW}3) 生成【节点后端】sing-box JSON 配置（指向本机）${NC}"
        echo -e "${YELLOW}4) 测试解锁机连通性（ping/TCP/TLS）${NC}"
        echo -e "${YELLOW}5) 测试 GPT / Netflix 解锁状态${NC}"
        echo -e "${YELLOW}6) 设置允许接入的节点 IP（防火墙白名单）${NC}"
        echo -e "${RED}7) 一键卸载解锁服务（含防火墙规则）${NC}"
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
