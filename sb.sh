#!/bin/bash

# ==========================================
# Sing-box 6-in-1  ·  v7.0
#  - 免域名：ACME / 自签 / 无 TLS 三档证书策略，永不因证书中止
#  - 纯 IPv6：网络栈自动探测 + DNS / 监听地址自适应
#  - 容器友好：无 systemd / openrc 时自动 nohup + 守护循环
# ==========================================

# --- 扩展视觉与色彩引擎 ---
RED='\033[1;31m'; GREEN='\033[1;32m'; YELLOW='\033[1;33m'; PURPLE='\033[1;35m'; CYAN='\033[1;36m'
BG_RED='\033[41;37;1m'; BG_GREEN='\033[42;37;1m'; BG_BLUE='\033[44;37;1m'; BG_PURPLE='\033[45;37;1m'
BOLD='\033[1m'; NC='\033[0m'

msg_info() { echo -e " ${BG_BLUE} INFO ${NC} ${CYAN}$1${NC}"; }
msg_success() { echo -e " ${BG_GREEN}  OK  ${NC} ${GREEN}$1${NC}"; }
msg_warn() { echo -e " ${YELLOW}${BOLD}[⚠️ WARN]${NC} $1"; }
msg_error() { echo -e " ${BG_RED} ERROR ${NC} ${RED}$1${NC}"; }
reading() { echo -ne "\n ${CYAN}➤ ${BOLD}$1${NC} ➔ "; read -r "$2"; }
divider() { echo -e "${PURPLE}┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫${NC}"; }

print_logo() {
    if [ -n "$TERM" ] && command -v clear >/dev/null 2>&1; then clear; else echo ""; fi
    echo -e "${PURPLE}╭━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━╮${NC}"
    echo -e "${PURPLE}┃${NC}   ${CYAN}███████╗██╗███╗   ██╗ ██████╗       ██████╗  ██████╗ ██╗  ██╗${NC}   ${PURPLE}┃${NC}"
    echo -e "${PURPLE}┃${NC}   ${CYAN}██╔════╝██║████╗  ██║██╔════╝       ██╔══██╗██╔═══██╗╚██╗██╔╝${NC}   ${PURPLE}┃${NC}"
    echo -e "${PURPLE}┃${NC}   ${CYAN}███████╗██║██╔██╗ ██║██║  ███╗█████╗██████╔╝██║   ██║ ╚███╔╝ ${NC}   ${PURPLE}┃${NC}"
    echo -e "${PURPLE}┃${NC}   ${CYAN}╚════██║██║██║╚██╗██║██║   ██║╚════╝██╔══██╗██║   ██║ ██╔██╗ ${NC}   ${PURPLE}┃${NC}"
    echo -e "${PURPLE}┃${NC}   ${CYAN}███████║██║██║ ╚████║╚██████╔╝      ██████╔╝╚██████╔╝██╔╝ ██╗${NC}   ${PURPLE}┃${NC}"
    echo -e "${PURPLE}┃${NC}   ${CYAN}╚══════╝╚═╝╚═╝  ╚═══╝ ╚═════╝       ╚═════╝  ╚═════╝ ╚═╝  ╚═╝${NC}   ${PURPLE}┃${NC}"
    divider
    echo -e "${PURPLE}┃${NC}          ${YELLOW}${BOLD}✨ Kele's Sing-box 6-in-1 极致稳定架构 (v7.0) ✨${NC}         ${PURPLE}┃${NC}"
    echo -e "${PURPLE}┃${NC}            ${CYAN}免域名自签 · 纯 IPv6 自适应 · 容器裸跑兼容${NC}             ${PURPLE}┃${NC}"
    echo -e "${PURPLE}╰━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━╯${NC}"
    echo ""
}

# --- 全局变量 ---

# JSON字符串转义（防止用户输入破坏config.json）
json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

# URL编码（防止特殊字符污染订阅链接）
url_encode() {
    local s="$1"
    local result=""
    local i c
    # IPv6地址含方括号时，保留方括号不编码
    for ((i=0; i<${#s}; i++)); do
        c="${s:$i:1}"
        if [[ "$c" =~ ^[a-zA-Z0-9_.~%-\[\]]+$ ]]; then
            result+="$c"
        else
            result+=$(printf '%%%02X' "'$c")
        fi
    done
    printf '%s' "$result"
}

# 检测systemd是否支持append语法
systemd_supports_append() {
    if command -v systemctl >/dev/null 2>&1; then
        local ver
        ver=$(systemd --version 2>/dev/null | head -n1 | grep -oE '[0-9]+' | head -n1)
        if [ -n "$ver" ] && [ "$ver" -ge 240 ]; then
            return 0
        fi
    fi
    return 1
}
SB_DIR="/etc/sing-box"
SB_CONF="${SB_DIR}/config.json"
SB_INFO="${SB_DIR}/install.info"
SB_BIN="/usr/local/bin/sing-box"
ARGO_BIN="/usr/local/bin/cloudflared"
ARGO_LOG="${SB_DIR}/argo.log"
SB_LOG="${SB_DIR}/sing-box.log"

# ==========================================
# v7 基础设施：网络栈探测 / 证书策略 / 服务后端
# ==========================================
HAS_V4=""; HAS_V6=""; WAN4=""; WAN6=""
NET_STACK=""; DNS_STRATEGY=""; LISTEN_ADDR=""
ARGO_LOOP_HOST="127.0.0.1"; ARGO_BIND_ADDR="127.0.0.1"; SERVICE_BACKEND=""; IS_CONTAINER="0"
NAT_LOCAL="0"; LOCAL_ADDR4=""
CERT_SOURCE=""; TLS_SELF_SIGNED="0"
SB_GUARD="/usr/local/bin/sb-guard"
ARGO_GUARD="/usr/local/bin/sb-argo-guard"

# 单次 curl 取值（强制地址族，避免 curl 自己挑栈导致误判）
_fetch_family() { curl -s"$1" --connect-timeout 4 --max-time 6 "$2" 2>/dev/null | tr -d '[:space:]'; }

probe_ip4() {
    local ip u
    for u in https://api.ipify.org https://ipv4.icanhazip.com https://ifconfig.me/ip https://ip.gs; do
        ip=$(_fetch_family 4 "$u")
        [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] && { printf '%s' "$ip"; return 0; }
    done
    return 1
}

probe_ip6() {
    local ip u
    for u in https://api6.ipify.org https://ipv6.icanhazip.com https://v6.ip.sb https://ipv6.ip.sb; do
        ip=$(_fetch_family 6 "$u")
        [[ "$ip" == *:* ]] && [[ "$ip" =~ ^[0-9a-fA-F:]+$ ]] && { printf '%s' "$ip"; return 0; }
    done
    return 1
}

# 探测失败时从网卡兜底（纯 IPv6 机器上 api6 常被墙 / 超时）
nic_ip() {
    local fam="$1" addr=""
    if command -v ip >/dev/null 2>&1; then
        if [ "$fam" = "4" ]; then
            addr=$(ip -4 -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 \
                | grep -vE '^(10\.|127\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.|100\.(6[4-9]|[7-9][0-9]|1[0-2][0-9])\.|169\.254\.)' | head -n1)
            [ -z "$addr" ] && addr=$(ip -4 addr show scope global 2>/dev/null | sed -n 's/.*inet \([0-9.]*\)\/.*/\1/p' \
                | grep -vE '^(10\.|127\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.|100\.(6[4-9]|[7-9][0-9]|1[0-2][0-9])\.|169\.254\.)' | head -n1)
        elif [ "$fam" = "6" ]; then
            addr=$(ip -6 -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 \
                | grep -E '^(2[0-9a-fA-F]{3}|3[0-9a-fA-F]{3}):' | head -n1)
        fi
    fi
    if [ -z "$addr" ] && [ "$fam" = "6" ] && [ -f /proc/net/if_inet6 ]; then
        addr=$(awk '{print $1}' /proc/net/if_inet6 \
            | while read -r h; do printf '%s:%s:%s:%s:%s:%s:%s:%s\n' \
                "${h:0:4}" "${h:4:4}" "${h:8:4}" "${h:12:4}" "${h:16:4}" "${h:20:4}" "${h:24:4}" "${h:28:4}"; done \
            | grep -E '^(2[0-9a-f]{3}|3[0-9a-f]{3}):' | head -n1)
    fi
    [ -n "$addr" ] && { printf '%s' "$addr"; return 0; }
    return 1
}

# 核心：判定本机网络栈，并给 DNS 策略 / 监听地址 / 回环地址定调
detect_net_stack() {
    local v6_bind=0 v4_loop=1
    WAN4=$(probe_ip4 || true); [ -z "$WAN4" ] && WAN4=$(nic_ip 4 || true)
    WAN6=$(probe_ip6 || true); [ -z "$WAN6" ] && WAN6=$(nic_ip 6 || true)

    HAS_V4=0; HAS_V6=0
    [ -n "$WAN4" ] && HAS_V4=1
    [ -n "$WAN6" ] && HAS_V6=1

    # IPv6 是否具备绑定能力：内核关掉 IPv6 时绑 "::" 会直接失败，导致所有入站全灭
    if [ -f /proc/net/if_inet6 ] && grep -qvE '^0{32}' /proc/net/if_inet6 2>/dev/null; then
        v6_bind=1
    elif command -v ip >/dev/null 2>&1 && ip -6 addr show lo 2>/dev/null | grep -q '::1'; then
        v6_bind=1
    fi
    if [ "$HAS_V4" = "0" ] && command -v ip >/dev/null 2>&1 \
        && ! ip -4 addr show lo 2>/dev/null | grep -q '127\.0\.0\.1'; then
        v4_loop=0
    fi

    case "${HAS_V4}${HAS_V6}" in
        11) NET_STACK="dual";    DNS_STRATEGY="prefer_ipv4" ;;
        10) NET_STACK="ipv4";    DNS_STRATEGY="ipv4_only" ;;
        01) NET_STACK="ipv6";    DNS_STRATEGY="ipv6_only" ;;
        *)  NET_STACK="unknown"; DNS_STRATEGY="prefer_ipv4" ;;
    esac
    case "${PREFERRED_IP:-auto}" in
        4) [ "$HAS_V4" = "1" ] && DNS_STRATEGY="prefer_ipv4" ;;
        6) [ "$HAS_V6" = "1" ] && DNS_STRATEGY="prefer_ipv6" ;;
    esac

    if [ "$v6_bind" = "1" ]; then LISTEN_ADDR="::"; else LISTEN_ADDR="0.0.0.0"; fi
    if [ "$v4_loop" = "1" ]; then
        ARGO_LOOP_HOST="127.0.0.1"; ARGO_BIND_ADDR="127.0.0.1"
    else
        ARGO_LOOP_HOST="[::1]"; ARGO_BIND_ADDR="::1"
    fi

    # NAT / 容器识别：本机只有内网地址时，出网 IP ≠ 入口 IP（CDN 出口、反代转发都会踩到）
    NAT_LOCAL="0"; LOCAL_ADDR4=""
    if command -v ip >/dev/null 2>&1; then
        LOCAL_ADDR4=$(ip -4 -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1)
        case "$LOCAL_ADDR4" in
            10.*|192.168.*|172.1[6-9].*|172.2[0-9].*|172.3[01].*|100.6[4-9].*|100.[7-9][0-9].*|100.1[0-2][0-9].*)
                NAT_LOCAL="1" ;;
        esac
    fi
    [ "$IS_CONTAINER" = "1" ] && NAT_LOCAL="1"
    return 0
}

ensure_net_stack() { [ -z "$LISTEN_ADDR" ] && detect_net_stack; return 0; }

net_stack_label() {
    case "$NET_STACK" in
        dual) printf '%s' "双栈 IPv4+IPv6" ;;
        ipv4) printf '%s' "纯 IPv4" ;;
        ipv6) printf '%s' "纯 IPv6" ;;
        *)    printf '%s' "未知" ;;
    esac
}

# 系统自带 DNS 是否可用（容器里 resolv.conf 可能是空的）
local_dns_usable() {
    [ -s /etc/resolv.conf ] || return 1
    grep -qE '^[[:space:]]*nameserver[[:space:]]+[0-9a-fA-F:.]+' /etc/resolv.conf 2>/dev/null || return 1
    return 0
}

# ---------- 证书策略 ----------
cert_is_valid() {
    [ -s "${SB_DIR}/server.crt" ] && [ -s "${SB_DIR}/server.key" ] || return 1
    openssl x509 -checkend 604800 -noout -in "${SB_DIR}/server.crt" >/dev/null 2>&1 || return 1
    return 0
}

# subject == issuer 即自签，否则视为受信任证书
detect_cert_source() {
    local subj issu
    if [ ! -s "${SB_DIR}/server.crt" ]; then
        CERT_SOURCE="none"; TLS_SELF_SIGNED="0"; return 1
    fi
    subj=$(openssl x509 -noout -subject -in "${SB_DIR}/server.crt" 2>/dev/null | sed 's/^subject=//')
    issu=$(openssl x509 -noout -issuer  -in "${SB_DIR}/server.crt" 2>/dev/null | sed 's/^issuer=//')
    if [ -n "$subj" ] && [ "$subj" = "$issu" ]; then
        CERT_SOURCE="selfsigned"; TLS_SELF_SIGNED="1"
    else
        CERT_SOURCE="acme"; TLS_SELF_SIGNED="0"
    fi
    return 0
}

# 自签证书：无域名、无 ACME、无 80 端口也能起 TLS
gen_self_signed_cert() {
    local sni="${1:-}" crt="${SB_DIR}/server.crt" key="${SB_DIR}/server.key"
    local conf ok=0 san
    mkdir -p "$SB_DIR"
    [ -z "$sni" ] && sni=$(tls_server_name)
    [ -z "$sni" ] && sni="${WAN4:-${WAN6:-www.bing.com}}"

    san="DNS:${sni}"
    [ -n "$WAN4" ] && [ "$WAN4" != "$sni" ] && san="${san},IP:${WAN4},DNS:${WAN4}"
    [ -n "$WAN6" ] && [ "$WAN6" != "$sni" ] && san="${san},IP:${WAN6},DNS:${WAN6}"
    [ "$sni" != "www.bing.com" ] && san="${san},DNS:www.bing.com"

    msg_info "正在生成自签 TLS 证书（无需域名，10 年有效期）..."
    conf=$(mktemp 2>/dev/null || echo "/tmp/sb_cert_$$.conf")
    cat > "$conf" <<CERTEOF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = ${sni}
[v3]
subjectAltName = ${san}
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
CERTEOF

    if openssl ecparam -genkey -name prime256v1 -out "$key" >/dev/null 2>&1; then
        openssl req -new -x509 -days 3650 -key "$key" -out "$crt" -config "$conf" -extensions v3 >/dev/null 2>&1 && ok=1
    fi
    if [ "$ok" != "1" ]; then
        rm -f "$key"
        if openssl genrsa -out "$key" 2048 >/dev/null 2>&1; then
            openssl req -new -x509 -days 3650 -key "$key" -out "$crt" -config "$conf" -extensions v3 >/dev/null 2>&1 && ok=1
        fi
    fi
    rm -f "$conf"

    if [ "$ok" != "1" ] || [ ! -s "$crt" ] || [ ! -s "$key" ]; then
        msg_error "自签证书生成失败，请检查 openssl 是否可用。"
        return 1
    fi
    chmod 600 "$crt" "$key"
    CERT_SOURCE="selfsigned"; TLS_SELF_SIGNED="1"
    msg_success "自签证书已就绪（客户端需开启 insecure / 跳过证书验证）"
    return 0
}

# 统一入口：有真实证书就用；否则按策略申请 ACME 或回落自签，绝不中止部署
ensure_tls_cert() {
    if cert_is_valid; then detect_cert_source; return 0; fi
    case "${CERT_SOURCE}" in
        none)
            msg_warn "证书策略为「无 TLS」，跳过证书准备。"
            return 0 ;;
        acme)
            if [ -n "$VD_DOMAIN" ] && apply_cert "$VD_DOMAIN"; then
                CERT_SOURCE="acme"; TLS_SELF_SIGNED="0"; return 0
            fi
            msg_warn "域名证书申请失败，自动回落自签证书（客户端需 insecure）。"
            gen_self_signed_cert "" ;;
        selfsigned)
            gen_self_signed_cert "" ;;
        *)
            if [ -n "$VD_DOMAIN" ] && apply_cert "$VD_DOMAIN"; then
                CERT_SOURCE="acme"; TLS_SELF_SIGNED="0"; return 0
            fi
            [ -n "$VD_DOMAIN" ] && msg_warn "域名证书申请失败，改用自签证书。"
            gen_self_signed_cert "" ;;
    esac
}

tls_server_name() {
    if [ -n "$VD_DOMAIN" ]; then printf '%s' "$VD_DOMAIN"; else printf '%s' "www.bing.com"; fi
}

# ---------- 内核版本探测（用于 1.12+ 域解析器迁移） ----------
singbox_version() {
    [ -x "$SB_BIN" ] || return 1
    "$SB_BIN" version 2>/dev/null | sed -n 's/^sing-box version \([0-9][0-9.]*\).*/\1/p' | head -n1
}

# ver_ge 1.12  → 当前内核版本 >= 1.12 返回 0
ver_ge() {
    local need="$1" cur
    cur=$(singbox_version)
    [ -z "$cur" ] && return 1
    awk -v c="$cur" -v n="$need" 'BEGIN{
        nc = split(c, C, "."); nn = split(n, N, ".");
        for (i = 1; i <= 3; i++) {
            a = (i <= nc ? C[i] : 0) + 0; b = (i <= nn ? N[i] : 0) + 0;
            if (a > b) exit 0;
            if (a < b) exit 1;
        }
        exit 0 }'
}

# ---------- 服务后端：systemd / openrc / 裸跑(容器) ----------
detect_service_backend() {
    local pid1=""
    pid1=$(ps -p 1 -o comm= 2>/dev/null | tr -d ' ')
    case "$pid1" in
        systemd) SERVICE_BACKEND="systemd" ;;
        init|openrc-init)
            if is_alpine; then SERVICE_BACKEND="openrc"; else SERVICE_BACKEND="systemd"; fi ;;
        *) SERVICE_BACKEND="raw" ;;
    esac
    [ "$SERVICE_BACKEND" = "systemd" ] && ! command -v systemctl >/dev/null 2>&1 && SERVICE_BACKEND="raw"
    [ "$SERVICE_BACKEND" = "openrc" ]  && ! command -v rc-service >/dev/null 2>&1 && SERVICE_BACKEND="raw"
    [ "$SERVICE_BACKEND" = "raw" ] && IS_CONTAINER="1"
    return 0
}

[[ $EUID -ne 0 ]] && msg_error "必须以 root 用户运行此脚本！" && exit 1

if [[ "$0" != "/usr/bin/sb" ]]; then
    _script_name=$(basename "$0")
    if [[ -f "$0" && "$_script_name" != "bash" && "$_script_name" != "sh" && "$_script_name" != "dash" ]]; then
        rm -f /usr/bin/sb 2>/dev/null
        cp -f "$0" /usr/bin/sb
        chmod +x /usr/bin/sb
        msg_success "快捷指令 'sb' 已就绪，以后直接输入 sb 即可唤出面板！"
        sleep 1
    else
        msg_warn "检测到内存管道执行，跳过快捷指令 'sb' 生成。如需生成，请将脚本下载到本地执行。"
        sleep 2
    fi
fi

load_config() {
    [ -f "$SB_INFO" ] && source "$SB_INFO"
    [ -z "$VD_MODE" ] && VD_MODE="2"
    [ -z "$VD_DOMAIN" ] && VD_DOMAIN=""
    # ---- v7 证书来源迁移 ----
    # CERT_SOURCE: acme(真实域名证书) | selfsigned(自签) | none(纯无 TLS)
    # 老版本无此字段：VD_MODE=3 → acme；VD_MODE=2 且无域名(旧的"自签伪装"已失效) → none
    if [ -z "$CERT_SOURCE" ]; then
        if [ "$VD_MODE" == "3" ]; then
            VD_MODE="2"; CERT_SOURCE="acme"
        elif [ "$VD_MODE" == "2" ] && [ -z "$VD_DOMAIN" ]; then
            VD_MODE="1"; CERT_SOURCE="none"
        elif [ -s "${SB_DIR}/server.crt" ]; then
            CERT_SOURCE="acme"
        else
            CERT_SOURCE="none"
        fi
    fi
    [ -z "$TLS_SELF_SIGNED" ] && TLS_SELF_SIGNED="0"
    [ -z "$PREFERRED_IP" ] && PREFERRED_IP="auto"
    [ -z "$NET_STACK" ] && NET_STACK=""
    [ -z "$DNS_STRATEGY" ] && DNS_STRATEGY=""
    [ -z "$LISTEN_ADDR" ] && LISTEN_ADDR=""
    [ -z "$ARGO_LOOP_HOST" ] && ARGO_LOOP_HOST="127.0.0.1"
    [ -z "$ARGO_BIND_ADDR" ] && ARGO_BIND_ADDR="127.0.0.1"
    [ -z "$NAT_LOCAL" ] && NAT_LOCAL="0"
    [ -z "$PREFERRED_IP" ] && PREFERRED_IP="auto"
    [ -z "$ENABLE_VD" ] && ENABLE_VD="1"
    [ -z "$ENABLE_RE" ] && ENABLE_RE="1"
    [ -z "$ENABLE_HY" ] && ENABLE_HY="1"
    [ -z "$ENABLE_TC" ] && ENABLE_TC="1"
    [ -z "$ENABLE_S5" ] && ENABLE_S5="1"
    [ -z "$ENABLE_ARGO" ] && ENABLE_ARGO="1"
    [ -z "$HY_HOPPING" ] && HY_HOPPING="0"
    [ -z "$HY_PORTS" ] && HY_PORTS=""
}

save_config() {
    cat > "$SB_INFO" << EOF
UUID_VD=$UUID_VD
UUID_RE=$UUID_RE
UUID_ARGO=$UUID_ARGO
UUID_TC=$UUID_TC
PW_HY=$PW_HY
PW_TC=$PW_TC
S5_U=$S5_U
S5_P=$S5_P
PORT_VD=$PORT_VD
PORT_RE=$PORT_RE
PORT_HY=$PORT_HY
PORT_TC=$PORT_TC
PORT_S5=$PORT_S5
REALITY_PRK=$REALITY_PRK
REALITY_PBK=$REALITY_PBK
REALITY_SNI=$REALITY_SNI
REALITY_SHORT_ID=$REALITY_SHORT_ID
WARP_MODE=$WARP_MODE
WARP_DOMAINS=$WARP_DOMAINS
CUSTOM_IP=$CUSTOM_IP
ARGO_MODE=$ARGO_MODE
ARGO_TOKEN=$ARGO_TOKEN
ARGO_DOMAIN=$ARGO_DOMAIN
VD_MODE=$VD_MODE
VD_DOMAIN=$VD_DOMAIN
ENABLE_VD=$ENABLE_VD
ENABLE_RE=$ENABLE_RE
ENABLE_HY=$ENABLE_HY
ENABLE_TC=$ENABLE_TC
ENABLE_S5=$ENABLE_S5
ENABLE_ARGO=$ENABLE_ARGO
HY_HOPPING=$HY_HOPPING
HY_PORTS=$HY_PORTS
CERT_SOURCE=$CERT_SOURCE
TLS_SELF_SIGNED=$TLS_SELF_SIGNED
PREFERRED_IP=${PREFERRED_IP:-auto}
NET_STACK=$NET_STACK
DNS_STRATEGY=$DNS_STRATEGY
LISTEN_ADDR=$LISTEN_ADDR
ARGO_LOOP_HOST=$ARGO_LOOP_HOST
ARGO_BIND_ADDR=$ARGO_BIND_ADDR
NAT_LOCAL=$NAT_LOCAL
LOCAL_ADDR4=$LOCAL_ADDR4
HAS_V4=$HAS_V4
HAS_V6=$HAS_V6
WAN4=$WAN4
WAN6=$WAN6
EOF
    chmod 600 "$SB_INFO"
}

is_alpine() { [ -f /etc/alpine-release ]; }

# ---------- 裸跑(容器)后端：无 systemd / openrc 时的进程管理 ----------
raw_pidfile() {
    local dir="/var/run"
    [ -w "$dir" ] || dir="$SB_DIR"
    case "$1" in
        sing-box) printf '%s' "$dir/sing-box.pid" ;;
        sb-argo)  printf '%s' "$dir/sb-argo.pid" ;;
    esac
}

raw_stop() {
    local svc="$1" pidf pid
    pidf=$(raw_pidfile "$svc"); [ -z "$pidf" ] && return 0
    if [ -f "$pidf" ]; then
        pid=$(cat "$pidf" 2>/dev/null)
        if [ -n "$pid" ]; then
            # setsid 启动时 pid 即进程组组长，反向 kill 连带子进程一起收
            kill -TERM "-$pid" >/dev/null 2>&1 || kill "$pid" >/dev/null 2>&1
        fi
    fi
    rm -f "$pidf"
    if [ "$svc" = "sing-box" ]; then
        pkill -f "$SB_GUARD" >/dev/null 2>&1; pkill -f "$SB_BIN run -c" >/dev/null 2>&1
    else
        pkill -f "$ARGO_GUARD" >/dev/null 2>&1; pkill -f "$ARGO_BIN tunnel" >/dev/null 2>&1
    fi
    return 0
}

raw_start() {
    local svc="$1" pidf pid
    pidf=$(raw_pidfile "$svc"); [ -z "$pidf" ] && return 1
    raw_stop "$svc"
    case "$svc" in
        sing-box) [ -x "$SB_GUARD" ] || return 1; nohup "$SB_GUARD" >>"$SB_LOG" 2>&1 & ;;
        sb-argo)  [ -x "$ARGO_GUARD" ] || return 1; nohup "$ARGO_GUARD" >>"$ARGO_LOG" 2>&1 & ;;
    esac
    pid=$!
    disown >/dev/null 2>&1
    [ -n "$pid" ] && echo "$pid" > "$pidf"
    sleep 1
    if [ -f "$pidf" ] && kill -0 "$(cat "$pidf")" 2>/dev/null; then return 0; fi
    msg_warn "服务 $svc 启动后立即退出，请检查日志：$([ "$svc" = "sing-box" ] && echo "$SB_LOG" || echo "$ARGO_LOG")"
    return 1
}

svc_action() {
    local action="$1"; local service="$2"
    [ -z "$SERVICE_BACKEND" ] && detect_service_backend
    case "$SERVICE_BACKEND" in
        raw)
            case "$action" in
                enable|start|restart) raw_start "$service" ;;
                stop|disable) raw_stop "$service" ;;
                reload) ;;
            esac
            ;;
        openrc)
            case "$action" in
                enable) rc-update add "$service" default >/dev/null 2>&1 ;;
                disable) rc-update del "$service" default >/dev/null 2>&1 ;;
                start|stop|restart) rc-service "$service" "$action" >/dev/null 2>&1 ;;
                reload) ;;
            esac
            ;;
        *)
            case "$action" in
                enable) systemctl enable --now "$service" >/dev/null 2>&1 ;;
                disable) systemctl disable --now "$service" >/dev/null 2>&1 ;;
                start|stop|restart) systemctl "$action" "$service" >/dev/null 2>&1 ;;
                reload) systemctl daemon-reload >/dev/null 2>&1 ;;
            esac
            ;;
    esac
}

check_port_usage() {
    local port="$1"; [ -z "$port" ] && return 0
    if command -v lsof >/dev/null 2>&1; then
        lsof -i "TCP:$port" -sTCP:LISTEN >/dev/null 2>&1 && return 1
        lsof -i "UDP:$port" >/dev/null 2>&1 && return 1
    fi
    if command -v ss >/dev/null 2>&1; then
        ss -tuln | grep -qE ":[0-9]*$port\>" && return 1
        ss -uuln | grep -qE ":[0-9]*$port\>" && return 1
    elif command -v netstat >/dev/null 2>&1; then
        netstat -tuln | grep -qE ":[0-9]*$port\>" && return 1
        netstat -uuln | grep -qE ":[0-9]*$port\>" && return 1
    fi
    return 0
}

get_random_port() {
    local port
    while true; do
        port=$(( ((RANDOM << 15) | RANDOM) % 50000 + 10000 ))
        if check_port_usage "$port"; then
            echo "$port"
            return 0
        fi
    done
}

ask_port() {
    local prompt_text="$1"; local var_name="$2"; local temp_input
    while true; do
        reading "$prompt_text" temp_input
        if [ -z "$temp_input" ]; then eval "$var_name=\"\""; return; fi
        if [[ ! "$temp_input" =~ ^[0-9]+$ ]] || [ "$temp_input" -lt 1 ] || [ "$temp_input" -gt 65535 ]; then
            msg_error "非法输入！端口必须是 1-65535 之间的纯数字。"
            continue
        fi
        if ! check_port_usage "$temp_input"; then
            msg_error "端口 $temp_input 已被系统占用！"
            continue
        fi
        eval "$var_name=\"$temp_input\""
        return
    done
}

ask_uuid() {
    local prompt_text="$1"; local var_name="$2"; local temp_input
    while true; do
        reading "$prompt_text" temp_input
        if [ -z "$temp_input" ]; then eval "$var_name=\"\""; return; fi
        if [[ ! "$temp_input" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
            msg_error "必须是标准的 UUID 格式！"
            continue
        fi
        eval "$var_name=\"$temp_input\""
        return
    done
}

ask_port_range() {
    local prompt_text="$1"; local var_name="$2"; local target_port="$3"; local temp_input
    while true; do
        reading "$prompt_text" temp_input
        if [ -z "$temp_input" ]; then eval "$var_name=\"\""; return; fi
        if [[ ! "$temp_input" =~ ^([0-9]+)-([0-9]+)$ ]]; then
            msg_error "格式错误！请输入类似 20000-30000 的端口段。"
            continue
        fi
        local p_start="${BASH_REMATCH[1]}"; local p_end="${BASH_REMATCH[2]}"
        if [ "$p_start" -ge "$p_end" ] || [ "$p_start" -lt 1 ] || [ "$p_end" -gt 65535 ]; then
            msg_error "范围不合法！起始端口必须小于结束端口，且均在 1-65535 之间。"
            continue
        fi
        if [ -n "$target_port" ]; then
            if [ "$target_port" -lt "$p_start" ] || [ "$target_port" -gt "$p_end" ]; then
                msg_error "逻辑错误！主端口 ($target_port) 必须包含在你填写的跳跃段 ($p_start-$p_end) 内，否则节点必定失联！"
                continue
            fi
        fi
        eval "$var_name=\"$temp_input\""
        return
    done
}

get_outbound_ip() {
    ensure_net_stack
    local ip=""
    case "${PREFERRED_IP:-auto}" in
        4) ip="$WAN4" ;;
        6) ip="$WAN6" ;;
        *)
            if [ "$NET_STACK" = "ipv6" ]; then ip="$WAN6"
            elif [ -n "$WAN4" ]; then ip="$WAN4"
            else ip="$WAN6"; fi
            ;;
    esac
    [ -z "$ip" ] && ip="${WAN4:-$WAN6}"
    [ -z "$ip" ] && ip=$(nic_ip 4 || nic_ip 6 || true)
    if [ -z "$ip" ]; then
        msg_error "无法自动探测公网 IP，请手动指定 IP / 域名。"
        echo "127.0.0.1"
        return 1
    fi
    printf '%s' "$ip"
    return 0
}

get_country_prefix() {
    local cc
    cc=$(curl -s --max-time 3 http://ip-api.com/line/?fields=countryCode 2>/dev/null)
    [ -z "$cc" ] && cc=$(curl -s --max-time 3 https://ipinfo.io/country 2>/dev/null)
    case "$cc" in
        "CN") echo "🇨🇳中国" ;; "HK") echo "🇭🇰香港" ;; "TW") echo "🇹🇼台湾" ;;
        "MO") echo "🇲🇴澳门" ;; "JP") echo "🇯🇵日本" ;; "KR") echo "🇰🇷韩国" ;;
        "SG") echo "🇸🇬新加坡" ;; "US") echo "🇺🇸美国" ;; "GB") echo "🇬🇧英国" ;;
        "DE") echo "🇩🇪德国" ;; "FR") echo "🇫🇷法国" ;; "NL") echo "🇳🇱荷兰" ;;
        *) echo "🌍未知" ;;
    esac
}

optimize_network() {
    cat > /etc/sysctl.d/99-singbox-optimize.conf << EOF
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_keepalive_time=30
net.ipv4.tcp_keepalive_intvl=10
net.ipv4.tcp_keepalive_probes=6
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.core.rmem_max=33554432
net.core.wmem_max=33554432
net.ipv4.tcp_rmem=4096 87380 33554432
net.ipv4.tcp_wmem=4096 65536 33554432
net.core.netdev_max_backlog=10000
EOF
    sysctl -p /etc/sysctl.d/99-singbox-optimize.conf >/dev/null 2>&1 || true
}

install_deps() {
    echo ""; msg_info "正在检查并安装基础依赖环境 (包含 iptables)..."
    if is_alpine; then
        apk update >/dev/null 2>&1
        apk add bash curl wget jq openssl lsof socat procps libc6-compat gcompat iptables ip6tables iproute2 ca-certificates >/dev/null 2>&1
    else
        if command -v apt-get >/dev/null 2>&1; then
            apt-get update -y >/dev/null 2>&1
            local apt_pkgs=("curl" "wget" "jq" "openssl" "lsof" "socat" "procps" "lsb-release" "iptables" "iproute2" "ca-certificates")
            for pkg in "${apt_pkgs[@]}"; do
                local cmd_name="$pkg"
                [ "$pkg" = "lsb-release" ] && cmd_name="lsb_release"
                [ "$pkg" = "iproute2" ] && cmd_name="ip"
                [ "$pkg" = "ca-certificates" ] && cmd_name="update-ca-certificates"
                [ "$pkg" = "procps" ] && cmd_name="ps"
                [ "$pkg" = "iptables" ] && cmd_name="iptables"
                ! command -v "$cmd_name" >/dev/null 2>&1 && apt-get install -y "$pkg" >/dev/null 2>&1
            done
        elif command -v yum >/dev/null 2>&1; then
            yum makecache -y >/dev/null 2>&1
            yum install -y epel-release >/dev/null 2>&1
            local yum_pkgs=("curl" "wget" "jq" "openssl" "lsof" "socat" "procps-ng" "redhat-lsb-core" "iptables" "iproute" "ca-certificates")
            for pkg in "${yum_pkgs[@]}"; do
                local cmd_name="$pkg"
                [ "$pkg" = "redhat-lsb-core" ] && cmd_name="lsb_release"
                [ "$pkg" = "iproute" ] && cmd_name="ip"
                [ "$pkg" = "ca-certificates" ] && cmd_name="update-ca-trust"
                [ "$pkg" = "procps-ng" ] && cmd_name="ps"
                ! command -v "$cmd_name" >/dev/null 2>&1 && yum install -y "$pkg" >/dev/null 2>&1
            done
        else
            msg_error "不支持的包管理器，请手动安装核心依赖。"
            exit 1
        fi
    fi
    optimize_network
}

safe_download() {
    local url="$1"; local dest="$2"
    msg_info "正在下载核心组件: $(basename "$dest")..."
    local http_code
    http_code=$(curl -sL -w "%{http_code}" -o "$dest" "$url")
    if [ "$http_code" != "200" ]; then msg_error "文件下载失败！"; rm -f "$dest"; return 1; fi
    if [ ! -s "$dest" ]; then msg_error "下载失败！文件为空。"; rm -f "$dest"; return 1; fi
    return 0
}

apply_cert() {
    local domain=$1
    if [ ! -d ~/.acme.sh ]; then msg_warn "正在安装 acme.sh 证书工具..."; curl -fsSL https://get.acme.sh | sh >/dev/null 2>&1; fi
    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt >/dev/null 2>&1

    echo -e "\n${BG_BLUE} 证书申请 ${NC} 开始为 ${YELLOW}$domain${NC} 申请 TLS 证书..."
    local standalone_success=false
    if check_port_usage 80; then
        if ~/.acme.sh/acme.sh --issue -d "$domain" --standalone -k ec-256 --force; then
            standalone_success=true
        fi
    else msg_warn "80 端口被占用或不可达，跳过 Standalone 模式。"; fi

    if [ "$standalone_success" = false ]; then
        msg_error "Standalone 模式失败，切换至 API 验证模式。"
        reading "是否启用 Cloudflare API 继续申请？[y/n]" use_dns
        use_dns=${use_dns,,}; [ -z "$use_dns" ] && use_dns="y"
        if [[ "$use_dns" != "y" ]]; then msg_error "已取消证书申请。"; return 1; fi

        reading "请输入 Cloudflare API Token" cf_token; export CF_Token="$cf_token"
        reading "请输入域名的 Zone ID" cf_zone_id; export CF_Zone_ID="$cf_zone_id"

        msg_info "API 申请中，请耐心等待 1-2 分钟..."
        if ! ~/.acme.sh/acme.sh --issue --dns dns_cf -d "$domain" -k ec-256 --force; then
            msg_error "证书申请彻底失败！"; return 1
        fi
    fi

    mkdir -p "${SB_DIR}"
    ~/.acme.sh/acme.sh --installcert -d "$domain" --fullchain-file "${SB_DIR}/server.crt" --key-file "${SB_DIR}/server.key" --ecc >/dev/null 2>&1
    chmod 600 "${SB_DIR}/server.crt" "${SB_DIR}/server.key"
    msg_success "真实域名证书部署成功！"
    return 0
}

install_singbox() {
    if [ ! -f "$SB_BIN" ]; then
        local ARCH S_ARCH TAG
        ARCH=$(uname -m); case "${ARCH}" in x86_64) S_ARCH="amd64" ;; aarch64|arm64) S_ARCH="arm64" ;; *) msg_error "不支持的架构"; exit 1 ;; esac
        # 仅拉取最新 stable 版（过滤 prerelease == true），避免使用 alpha 内核
        TAG=$(curl -s "https://api.github.com/repos/SagerNet/sing-box/releases?per_page=20" | jq -r '.[] | select(.prerelease == false) | .tag_name' 2>/dev/null | head -n 1)
        if [ -z "$TAG" ] || [ "$TAG" == "null" ]; then
            TAG=$(curl -s "https://api.github.com/repos/SagerNet/sing-box/releases/latest" | jq -r '.tag_name' 2>/dev/null)
            [ -z "$TAG" ] || [ "$TAG" == "null" ] && TAG="v1.11.5"
        fi
        msg_info "正在下载 sing-box ${TAG} (最新稳定版)..."
        if safe_download "https://github.com/SagerNet/sing-box/releases/download/${TAG}/sing-box-${TAG#v}-linux-${S_ARCH}.tar.gz" "sb.tar.gz"; then
            tar -xzf sb.tar.gz || { msg_error "解压失败"; exit 1; }
            mv sing-box-*/sing-box "$SB_BIN"; rm -rf sb.tar.gz sing-box-*
            chmod +x "$SB_BIN"
        else exit 1; fi
    fi
}

# 生成Reality密钥对，增加健壮性校验
generate_reality_keys() {
    local keys
    keys=$($SB_BIN generate reality-keypair 2>/dev/null)
    if [ -z "$keys" ]; then
        msg_error "sing-box 生成 Reality 密钥对失败，请检查二进制文件是否完整。"
        return 1
    fi
    REALITY_PRK=$(echo "$keys" | awk '/PrivateKey/ {print $2}')
    REALITY_PBK=$(echo "$keys" | awk '/PublicKey/ {print $2}')
    if [ -z "$REALITY_PRK" ] || [ -z "$REALITY_PBK" ]; then
        msg_error "解析 Reality 密钥失败，输出格式异常：$keys"
        return 1
    fi
    return 0
}

install_argo() {
    if [ ! -f "$ARGO_BIN" ]; then
        local ARCH A_ARCH
        ARCH=$(uname -m); case "${ARCH}" in x86_64) A_ARCH="amd64" ;; aarch64|arm64) A_ARCH="arm64" ;; *) msg_error "不支持的架构"; return 1 ;; esac
        if safe_download "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${A_ARCH}" "$ARGO_BIN"; then
            chmod +x "$ARGO_BIN"
        fi
    fi
}

install_warp() {
    if is_alpine; then return; fi
    if [ "$NET_STACK" == "ipv6" ]; then
        msg_warn "纯 IPv6 环境 WARP 通常不可用，已跳过。建议改用 Argo 或 NAT64。"
        return 1
    fi
    if ! command -v warp-cli >/dev/null 2>&1; then
        msg_info "正在安装 Cloudflare WARP..."
        if command -v apt-get >/dev/null 2>&1; then
            mkdir -p /usr/share/keyrings
            curl -fsSl https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
            local dist_codename=""
            if command -v lsb_release >/dev/null 2>&1; then dist_codename=$(lsb_release -cs)
            else dist_codename=$(grep '^VERSION_CODENAME=' /etc/os-release 2>/dev/null | cut -d'=' -f2); [ -z "$dist_codename" ] && dist_codename="stable"; fi
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $dist_codename main" | tee /etc/apt/sources.list.d/cloudflare-client.list >/dev/null
            apt-get update -y >/dev/null 2>&1 && apt-get install -y cloudflare-warp >/dev/null 2>&1
        elif command -v yum >/dev/null 2>&1; then msg_error "WARP 不支持 yum 系系统。"; return 1
        else return 1; fi
    fi
    if command -v warp-cli >/dev/null 2>&1; then
        warp-cli --accept-tos registration new >/dev/null 2>&1; warp-cli --accept-tos mode proxy >/dev/null 2>&1
        warp-cli --accept-tos proxy port 40000 >/dev/null 2>&1; warp-cli --accept-tos connect >/dev/null 2>&1
    fi
}

generate_config() {
    mkdir -p "$SB_DIR"
    ensure_net_stack

    # 基础输入安全过滤：禁止JSON破坏性字符进入域名类变量
    VD_DOMAIN="${VD_DOMAIN//\\/}"; VD_DOMAIN="${VD_DOMAIN//\"/}"
    REALITY_SNI="${REALITY_SNI//\\/}"; REALITY_SNI="${REALITY_SNI//\"/}"
    WARP_DOMAINS="${WARP_DOMAINS//\\/}"; WARP_DOMAINS="${WARP_DOMAINS//\"/}"

    # ---------- 证书准备（v7：缺证书不再中止部署） ----------
    local needs_tls=false
    [ "$ENABLE_VD" == "1" ] && [ "$VD_MODE" != "1" ] && needs_tls=true
    [ "$ENABLE_HY" == "1" ] && needs_tls=true
    [ "$ENABLE_TC" == "1" ] && needs_tls=true
    if [ "$needs_tls" == "true" ]; then
        if [ "$CERT_SOURCE" == "none" ]; then
            msg_warn "证书策略为「无 TLS」，但 Hy2 / TUIC / VLESS-TLS 依赖 TLS —— 自动切换为自签证书。"
            CERT_SOURCE="selfsigned"
        fi
        if ! ensure_tls_cert; then
            msg_error "TLS 证书准备失败，无法生成配置。"
            return 1
        fi
    fi

    local TLS_NAME LISTEN
    TLS_NAME=$(tls_server_name)
    LISTEN="${LISTEN_ADDR:-::}"

    local rules_json='{"outbound": "direct-out"}'
    if [ "$WARP_MODE" == "2" ] && ! is_alpine; then rules_json='{"outbound": "warp-out"}'
    elif [ "$WARP_MODE" == "3" ] && ! is_alpine && [ -n "$WARP_DOMAINS" ]; then
        IFS=',' read -ra DOMAINS <<< "$WARP_DOMAINS"; local domain_array=""
        for d in "${DOMAINS[@]}"; do [ -n "$d" ] && domain_array+="\"$d\","; done
        domain_array=${domain_array%,}
        [ -n "$domain_array" ] && rules_json="{ \"domain_suffix\": [${domain_array}], \"outbound\": \"warp-out\" }, { \"outbound\": \"direct-out\" }"
    fi

    local INBOUNDS=""

    if [ "$ENABLE_ARGO" == "1" ]; then
        INBOUNDS="$INBOUNDS { \"type\": \"vless\", \"tag\": \"in-argo\", \"listen\": \"$ARGO_BIND_ADDR\", \"listen_port\": 10086, \"users\": [ { \"uuid\": \"$UUID_ARGO\", \"flow\": \"\" } ], \"transport\": { \"type\": \"ws\", \"path\": \"/argo\" } },"
    fi

    if [ "$ENABLE_RE" == "1" ]; then
        INBOUNDS="$INBOUNDS { \"type\": \"vless\", \"tag\": \"in-reality\", \"listen\": \"$LISTEN\", \"listen_port\": $PORT_RE, \"users\": [ { \"uuid\": \"$UUID_RE\", \"flow\": \"xtls-rprx-vision\" } ], \"tls\": { \"enabled\": true, \"server_name\": \"$REALITY_SNI\", \"reality\": { \"enabled\": true, \"handshake\": { \"server\": \"$REALITY_SNI\", \"server_port\": 443 }, \"private_key\": \"$REALITY_PRK\", \"short_id\": [ \"\" ] } } },"
    fi

    if [ "$ENABLE_VD" == "1" ]; then
        if [ "$VD_MODE" == "1" ]; then
            INBOUNDS="$INBOUNDS { \"type\": \"vless\", \"tag\": \"in-vless\", \"listen\": \"$LISTEN\", \"listen_port\": $PORT_VD, \"users\": [ { \"uuid\": \"$UUID_VD\", \"flow\": \"\" } ], \"transport\": { \"type\": \"ws\", \"path\": \"/ws\" } },"
        else
            INBOUNDS="$INBOUNDS { \"type\": \"vless\", \"tag\": \"in-vless\", \"listen\": \"$LISTEN\", \"listen_port\": $PORT_VD, \"users\": [ { \"uuid\": \"$UUID_VD\", \"flow\": \"\" } ], \"tls\": { \"enabled\": true, \"server_name\": \"$TLS_NAME\", \"certificate_path\": \"${SB_DIR}/server.crt\", \"key_path\": \"${SB_DIR}/server.key\" }, \"transport\": { \"type\": \"ws\", \"path\": \"/ws\" } },"
        fi
    fi

    if [ "$ENABLE_HY" == "1" ]; then
        INBOUNDS="$INBOUNDS { \"type\": \"hysteria2\", \"tag\": \"in-hy2\", \"listen\": \"$LISTEN\", \"listen_port\": $PORT_HY, \"users\": [ { \"password\": \"$PW_HY\" } ], \"tls\": { \"enabled\": true, \"server_name\": \"$TLS_NAME\", \"certificate_path\": \"${SB_DIR}/server.crt\", \"key_path\": \"${SB_DIR}/server.key\" } },"
    fi
    if [ "$ENABLE_TC" == "1" ]; then
        INBOUNDS="$INBOUNDS { \"type\": \"tuic\", \"tag\": \"in-tuic\", \"listen\": \"$LISTEN\", \"listen_port\": $PORT_TC, \"users\": [ { \"uuid\": \"$UUID_TC\", \"password\": \"$PW_TC\" } ], \"tls\": { \"enabled\": true, \"server_name\": \"$TLS_NAME\", \"alpn\": [\"h3\"], \"certificate_path\": \"${SB_DIR}/server.crt\", \"key_path\": \"${SB_DIR}/server.key\" }, \"congestion_control\": \"bbr\" },"
    fi
    if [ "$ENABLE_S5" == "1" ]; then
        INBOUNDS="$INBOUNDS { \"type\": \"socks\", \"tag\": \"in-socks\", \"listen\": \"$LISTEN\", \"listen_port\": $PORT_S5, \"users\": [ { \"username\": \"$S5_U\", \"password\": \"$S5_P\" } ] },"
    fi

    INBOUNDS=${INBOUNDS%,}

    # ---------- DNS：按本机网络栈自适应（纯 IPv6 的关键） ----------
    # 1) 系统解析器可用 → 首选 local，天然跟随本机栈（容器 / NAT / 纯 IPv6 都不会错）
    # 2) 再按地址族补远端 UDP，纯 IPv6 机器绝不塞 IPv4 DNS（否则解析全灭）
    local dns_servers="" dns_final=""
    if local_dns_usable; then
        dns_servers=" { \"tag\": \"dns-local\", \"type\": \"local\" },"
        dns_final="dns-local"
    fi
    if [ "$HAS_V4" == "1" ] || [ "$NET_STACK" == "unknown" ]; then
        dns_servers="$dns_servers { \"tag\": \"dns-v4\", \"type\": \"udp\", \"server\": \"1.1.1.1\" },"
        [ -z "$dns_final" ] && dns_final="dns-v4"
    fi
    if [ "$HAS_V6" == "1" ] || [ "$NET_STACK" == "unknown" ]; then
        dns_servers="$dns_servers { \"tag\": \"dns-v6\", \"type\": \"udp\", \"server\": \"2606:4700:4700::1111\" },"
        [ -z "$dns_final" ] && dns_final="dns-v6"
    fi
    if [ -z "$dns_final" ]; then
        dns_servers=" { \"tag\": \"dns-local\", \"type\": \"local\" },"
        dns_final="dns-local"
    fi
    dns_servers="${dns_servers%,}"

    # sing-box 1.12+ 起，出站解析域名的隐式 DNS 已废弃（1.14 直接 FATAL），
    # 必须显式声明 route.default_domain_resolver，否则配置校验直接失败。
    local resolver_json=""
    if ver_ge 1.12; then
        resolver_json="\"default_domain_resolver\": { \"server\": \"$dns_final\", \"strategy\": \"${DNS_STRATEGY:-prefer_ipv4}\" },"
    fi

    cat > "${SB_CONF}.new" << EOF
{
  "log": { "level": "warn", "timestamp": true },
  "dns": {
    "servers": [ $dns_servers ],
    "final": "$dns_final",
    "strategy": "${DNS_STRATEGY:-prefer_ipv4}"
  },
  "inbounds": [
    $INBOUNDS
  ],
  "outbounds": [
    { "type": "direct", "tag": "direct-out" },
    { "type": "socks", "tag": "warp-out", "server": "127.0.0.1", "server_port": 40000 },
    { "type": "block", "tag": "block-out" }
  ],
  "route": { $resolver_json "rules": [ $rules_json ], "auto_detect_interface": true, "final": "direct-out" }
}
EOF

    # 内核自校验：配置不合法就不覆盖线上配置（热重载不再把节点弄挂）
    if [ -x "$SB_BIN" ]; then
        if ! "$SB_BIN" check -c "${SB_CONF}.new" >/tmp/sb_check.log 2>&1; then
            msg_error "配置校验失败，已保留旧配置。错误摘要："
            sed -n '1,8p' /tmp/sb_check.log 2>/dev/null | sed 's/^/   /'
            rm -f "${SB_CONF}.new"
            return 1
        fi
    fi
    mv -f "${SB_CONF}.new" "$SB_CONF"
    save_config
}

# --- 防火墙端口跳跃模块 (带高级冲突规避) ---
apply_iptables() {
    if ! command -v iptables >/dev/null 2>&1 && ! command -v ip6tables >/dev/null 2>&1; then
        [ "$HY_HOPPING" == "1" ] && msg_warn "未安装 iptables，Hy2 端口跳跃规则已跳过。"
        return 0
    fi
    # 彻底清洗老规则
    while iptables -t nat -D PREROUTING -p udp -m comment --comment "hy2-hopping" -j REDIRECT 2>/dev/null; do :; done
    while ip6tables -t nat -D PREROUTING -p udp -m comment --comment "hy2-hopping" -j REDIRECT 2>/dev/null; do :; done
    while iptables -t nat -D PREROUTING -p udp -m comment --comment "hy2-hopping-exclude" -j ACCEPT 2>/dev/null; do :; done
    while ip6tables -t nat -D PREROUTING -p udp -m comment --comment "hy2-hopping-exclude" -j ACCEPT 2>/dev/null; do :; done

    if [ "$ENABLE_HY" == "1" ] && [ "$HY_HOPPING" == "1" ] && [ -n "$HY_PORTS" ]; then
        local start_port end_port
        start_port=$(echo "$HY_PORTS" | cut -d'-' -f1)
        end_port=$(echo "$HY_PORTS" | cut -d'-' -f2)

        # 核心逻辑：为 TUIC 和 SOCKS5 建立豁免通道，防止被 Hy2 规则强行劫持
        if [ "$ENABLE_TC" == "1" ] && [ -n "$PORT_TC" ]; then
            iptables -t nat -A PREROUTING -p udp --dport "$PORT_TC" -m comment --comment "hy2-hopping-exclude" -j ACCEPT 2>/dev/null
            ip6tables -t nat -A PREROUTING -p udp --dport "$PORT_TC" -m comment --comment "hy2-hopping-exclude" -j ACCEPT 2>/dev/null
        fi
        if [ "$ENABLE_S5" == "1" ] && [ -n "$PORT_S5" ]; then
            iptables -t nat -A PREROUTING -p udp --dport "$PORT_S5" -m comment --comment "hy2-hopping-exclude" -j ACCEPT 2>/dev/null
            ip6tables -t nat -A PREROUTING -p udp --dport "$PORT_S5" -m comment --comment "hy2-hopping-exclude" -j ACCEPT 2>/dev/null
        fi

        # 建立跳跃劫持规则
        iptables -t nat -A PREROUTING -p udp --dport "${start_port}:${end_port}" -m comment --comment "hy2-hopping" -j REDIRECT --to-ports "$PORT_HY" 2>/dev/null
        ip6tables -t nat -A PREROUTING -p udp --dport "${start_port}:${end_port}" -m comment --comment "hy2-hopping" -j REDIRECT --to-ports "$PORT_HY" 2>/dev/null
    fi
}

# 裸跑守护脚本（等价 systemd Restart=always）
write_guards() {
    printf '%s\n' '#!/bin/bash' '# sb-guard: 裸跑模式守护循环' 'while true; do' \
        "  $(printf '%q' "$SB_BIN") run -c $(printf '%q' "$SB_CONF")" '  sleep 3' 'done' > "$SB_GUARD" 2>/dev/null
    chmod +x "$SB_GUARD" 2>/dev/null
    if [ "$ARGO_MODE" == "fixed" ] && [ -n "$ARGO_TOKEN" ]; then
        printf '%s\n' '#!/bin/bash' '# sb-argo-guard: 裸跑模式守护循环' 'while true; do' \
            "  $(printf '%q' "$ARGO_BIN") tunnel run --token $(printf '%q' "$ARGO_TOKEN")" '  sleep 3' 'done' > "$ARGO_GUARD" 2>/dev/null
    else
        printf '%s\n' '#!/bin/bash' '# sb-argo-guard: 裸跑模式守护循环' 'while true; do' \
            "  $(printf '%q' "$ARGO_BIN") tunnel --url $(printf '%q' "http://${ARGO_LOOP_HOST}:10086") --no-autoupdate --edge-ip-version auto" '  sleep 3' 'done' > "$ARGO_GUARD" 2>/dev/null
    fi
    chmod +x "$ARGO_GUARD" 2>/dev/null
}

setup_services() {
    detect_service_backend
    apply_iptables

    if [ "$SERVICE_BACKEND" == "raw" ]; then
        msg_info "未检测到 systemd / openrc 可用（容器或非 init 环境），切换为内置守护循环运行。"
        write_guards
        svc_action restart sing-box
        if [ "$ENABLE_ARGO" == "1" ]; then svc_action restart sb-argo; else svc_action stop sb-argo; fi
        return 0
    fi

    local ARGO_CMD="$ARGO_BIN tunnel --url http://${ARGO_LOOP_HOST}:10086 --no-autoupdate --edge-ip-version auto"
    if [ "$ARGO_MODE" == "fixed" ] && [ -n "$ARGO_TOKEN" ]; then
        ARGO_CMD="$ARGO_BIN tunnel run --token $(printf '%q' "$ARGO_TOKEN")"
    fi

    if [ "$SERVICE_BACKEND" == "openrc" ]; then
        cat > /etc/init.d/sing-box << 'RCINIT'
#!/sbin/openrc-run
command="SB_BIN_PLACEHOLDER"
command_args="run -c SB_CONF_PLACEHOLDER"
command_background=true
pidfile="/var/run/sing-box.pid"
output_log="SB_LOG_PLACEHOLDER"
error_log="SB_LOG_PLACEHOLDER"
RCINIT
        sed -i "s|SB_BIN_PLACEHOLDER|$SB_BIN|g; s|SB_CONF_PLACEHOLDER|$SB_CONF|g; s|SB_LOG_PLACEHOLDER|$SB_LOG|g" /etc/init.d/sing-box

        cat > /etc/init.d/sb-argo << 'RCINIT'
#!/sbin/openrc-run
command="ARGO_BIN_PLACEHOLDER"
command_args="ARGO_CMD_PLACEHOLDER"
command_background=true
pidfile="/var/run/sb-argo.pid"
output_log="ARGO_LOG_PLACEHOLDER"
error_log="ARGO_LOG_PLACEHOLDER"
RCINIT
        local _argo_args="${ARGO_CMD#* }"
        sed -i "s|ARGO_BIN_PLACEHOLDER|$ARGO_BIN|g; s|ARGO_CMD_PLACEHOLDER|$_argo_args|g; s|ARGO_LOG_PLACEHOLDER|$ARGO_LOG|g" /etc/init.d/sb-argo
        chmod +x /etc/init.d/sing-box /etc/init.d/sb-argo
    else
        local sb_std argo_std
        if systemd_supports_append; then
            sb_std="StandardOutput=append:$SB_LOG\nStandardError=append:$SB_LOG"
            argo_std="StandardOutput=append:$ARGO_LOG\nStandardError=append:$ARGO_LOG"
        else
            sb_std="StandardOutput=file:$SB_LOG\nStandardError=file:$SB_LOG"
            argo_std="StandardOutput=file:$ARGO_LOG\nStandardError=file:$ARGO_LOG"
        fi
        printf '%b\n' "[Unit]" "Description=Sing-box Core Service" "After=network.target" "[Service]" "ExecStart=$SB_BIN run -c $SB_CONF" "Restart=always" "RestartSec=3" "StartLimitInterval=0" "LimitNOFILE=1048576" "WorkingDirectory=$SB_DIR" "$sb_std" "[Install]" "WantedBy=multi-user.target" > /etc/systemd/system/sing-box.service
        if [ "$ARGO_MODE" == "temp" ] || [ -z "$ARGO_TOKEN" ]; then
            printf '%b\n' "[Unit]" "Description=Argo Tunnel for Sing-box" "After=network.target" "[Service]" "ExecStart=$ARGO_BIN tunnel --url http://${ARGO_LOOP_HOST}:10086 --no-autoupdate --edge-ip-version auto" "Restart=always" "RestartSec=3" "StartLimitInterval=0" "WorkingDirectory=$SB_DIR" "$argo_std" "[Install]" "WantedBy=multi-user.target" > /etc/systemd/system/sb-argo.service
        else
            printf '%b\n' "[Unit]" "Description=Argo Tunnel for Sing-box" "After=network.target" "[Service]" "ExecStart=$ARGO_BIN tunnel run --token $ARGO_TOKEN" "Restart=always" "RestartSec=3" "StartLimitInterval=0" "WorkingDirectory=$SB_DIR" "$argo_std" "[Install]" "WantedBy=multi-user.target" > /etc/systemd/system/sb-argo.service
        fi
        svc_action reload
    fi

    svc_action enable sing-box; svc_action restart sing-box

    if [ "$ENABLE_ARGO" == "1" ]; then
        svc_action enable sb-argo; svc_action restart sb-argo
    else
        svc_action stop sb-argo >/dev/null 2>&1; svc_action disable sb-argo >/dev/null 2>&1
    fi
}

check_existing() {
    if [ -f "$SB_INFO" ]; then
        msg_warn "检测到系统已部署过节点！"
        reading "是否确定要清除旧配置并重新安装？[y/n]" confirm
        confirm=${confirm,,}; if [[ "$confirm" != "y" ]]; then return 1; fi
        find "$SB_DIR" -type f ! -name "server.crt" ! -name "server.key" -delete 2>/dev/null
    fi
    return 0
}

# ---------- v7：证书策略选择器（免域名核心） ----------
choose_cert_strategy() {
    local cm vd_input vd_retry
    echo -e "\n${BG_BLUE} 证书策略 ${NC} ${CYAN}(v7：无域名也能直接跑，不再强制申请证书)${NC}"
    echo -e "   ${GREEN}[1]${NC} 有域名 → 自动申请 Let's Encrypt 真证书 ${YELLOW}(最稳，客户端免设置)${NC}"
    echo -e "   ${GREEN}[2]${NC} 没域名 / 临时机 → 自动生成自签证书 ${YELLOW}(容器首选，客户端需 insecure)${NC}"
    echo -e "   ${GREEN}[3]${NC} 完全无 TLS → VLESS 明文 WS + Argo ${YELLOW}(连 openssl 都不用跑)${NC}"
    reading "请选择证书策略 [1-3] (默认 2)" cm
    [ -z "$cm" ] && cm="2"
    case "$cm" in
        1)
            while true; do
                reading "请输入一个已解析到此 VPS 的真实域名 (例如: vpn.example.com)" vd_input
                if [ -z "$vd_input" ]; then
                    msg_warn "域名为空，自动改用自签证书。"
                    CERT_SOURCE="selfsigned"; TLS_SELF_SIGNED="1"; VD_DOMAIN=""
                    return 0
                fi
                VD_DOMAIN="$vd_input"
                if apply_cert "$VD_DOMAIN"; then
                    CERT_SOURCE="acme"; TLS_SELF_SIGNED="0"
                    echo -e "  ${GREEN}➤ 已为 ${VD_DOMAIN} 部署真实证书${NC}"
                    return 0
                fi
                msg_warn "申请失败：请检查 DNS 解析 / 80 端口，或直接改用自签。"
                reading "输入 s 改用自签证书，直接回车重试" vd_retry
                if [ "${vd_retry,,}" == "s" ]; then
                    CERT_SOURCE="selfsigned"; TLS_SELF_SIGNED="1"; VD_DOMAIN=""
                    msg_success "已切换为自签证书策略。"
                    return 0
                fi
            done
            ;;
        3)
            CERT_SOURCE="none"; TLS_SELF_SIGNED="0"
            msg_info "无 TLS 模式：VLESS 走明文 WS，TLS 由 Argo(Cloudflare) 侧提供。"
            ;;
        *)
            CERT_SOURCE="selfsigned"; TLS_SELF_SIGNED="1"; VD_DOMAIN=""
            msg_info "自签模式：Hy2 / TUIC / VLESS-WS-TLS 共用一张 10 年自签证书。"
            ;;
    esac
    return 0
}

install_fast() {
    print_logo
    echo -e "${BG_PURPLE} 一键极速部署 ${NC} ${YELLOW}开始部署全协议...${NC}\n"
    check_existing || return

    install_deps; install_singbox; install_argo

    msg_info "正在探测本机网络栈..."
    detect_net_stack
    echo -e "  ${CYAN}➤ 网络栈: ${GREEN}$(net_stack_label)${NC}  ${CYAN}DNS策略: ${GREEN}${DNS_STRATEGY}${NC}  ${CYAN}监听: ${GREEN}${LISTEN_ADDR}${NC}"
    [ -n "$WAN4" ] && echo -e "  ${CYAN}➤ IPv4: ${GREEN}$WAN4${NC}"
    [ -n "$WAN6" ] && echo -e "  ${CYAN}➤ IPv6: ${GREEN}$WAN6${NC}"

    choose_cert_strategy "一键部署" || return 1

    UUID_VD=$(cat /proc/sys/kernel/random/uuid); UUID_RE=$(cat /proc/sys/kernel/random/uuid)
    UUID_ARGO=$(cat /proc/sys/kernel/random/uuid); UUID_TC=$(cat /proc/sys/kernel/random/uuid)
    PW_HY=$(tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 10); PW_TC=$(tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 10)
    S5_U="user"; S5_P=$(tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 8)

    ENABLE_VD=1; ENABLE_RE=1; ENABLE_HY=1; ENABLE_TC=1; ENABLE_S5=1; ENABLE_ARGO=1
    if [ "$CERT_SOURCE" == "none" ]; then
        # 无 TLS 策略下 Hy2 / TUIC 无法起飞，一键部署时直接关掉，避免节点直接不可用
        ENABLE_HY=0; ENABLE_TC=0
        msg_warn "无 TLS 模式下已自动关闭 Hy2 / TUIC（这两个协议强依赖 TLS）。"
    fi

    msg_info "正在自动分配系统可用端口..."
    PORT_VD=$(get_random_port); PORT_RE=$(get_random_port); PORT_HY=$(get_random_port)
    PORT_TC=$(get_random_port); PORT_S5=$(get_random_port)

    msg_info "正在生成 Reality 专属密钥对..."
    if ! generate_reality_keys; then
        msg_error "Reality 密钥生成失败，安装中止。"
        exit 1
    fi
    REALITY_SHORT_ID=""
    REALITY_SNI="addons.mozilla.org"

    ARGO_MODE="temp"; ARGO_TOKEN=""; ARGO_DOMAIN=""
    WARP_MODE="1"; WARP_DOMAINS=""
    if [ "$CERT_SOURCE" == "none" ]; then VD_MODE="1"; else VD_MODE="2"; fi
    [ "$ENABLE_HY" != "1" ] && PORT_HY=""
    [ "$ENABLE_TC" != "1" ] && PORT_TC=""
    HY_HOPPING="0"; HY_PORTS=""

    msg_info "正在写入底层架构并启动守护进程..."
    if ! generate_config; then
        msg_error "配置生成失败，部署中止。"
        exit 1
    fi
    setup_services
    echo ""; msg_success "一键部署已完成！"; sleep 2
}

install_custom() {
    print_logo
    echo -e "${BG_PURPLE} 自定义部署 ${NC} ${YELLOW}进入按需部署模式...${NC}\n"
    check_existing || return

    install_deps; install_singbox; install_argo

    msg_info "正在探测本机网络栈..."
    detect_net_stack
    echo -e "  ${CYAN}➤ 网络栈: ${GREEN}$(net_stack_label)${NC}  ${CYAN}DNS策略: ${GREEN}${DNS_STRATEGY}${NC}  ${CYAN}监听: ${GREEN}${LISTEN_ADDR}${NC}"

    choose_cert_strategy "自定义部署" || return 1

    UUID_VD=$(cat /proc/sys/kernel/random/uuid); UUID_RE=$(cat /proc/sys/kernel/random/uuid)
    UUID_ARGO=$(cat /proc/sys/kernel/random/uuid); UUID_TC=$(cat /proc/sys/kernel/random/uuid)
    PW_HY=$(tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 10); PW_TC=$(tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 10)
    S5_U="user"; S5_P=$(tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 8)

    echo -e "${BG_BLUE} 协议开关 ${NC} (NAT 环境建议自定义端口)"
    reading "启用 VLESS (WS) [y/n] (默认 y)" c_vd; c_vd=${c_vd,,}; [ -z "$c_vd" ] && c_vd="y"; ENABLE_VD=$([[ "$c_vd" == "y" ]] && echo 1 || echo 0)
    reading "启用 VLESS (XTLS-Reality) [y/n] (默认 y)" c_re; c_re=${c_re,,}; [ -z "$c_re" ] && c_re="y"; ENABLE_RE=$([[ "$c_re" == "y" ]] && echo 1 || echo 0)
    reading "启用 Hysteria 2 (UDP) [y/n] (默认 y)" c_hy; c_hy=${c_hy,,}; [ -z "$c_hy" ] && c_hy="y"; ENABLE_HY=$([[ "$c_hy" == "y" ]] && echo 1 || echo 0)
    reading "启用 TUIC v5 (UDP) [y/n] (默认 y)" c_tc; c_tc=${c_tc,,}; [ -z "$c_tc" ] && c_tc="y"; ENABLE_TC=$([[ "$c_tc" == "y" ]] && echo 1 || echo 0)
    reading "启用 SOCKS5 [y/n] (默认 y)" c_s5; c_s5=${c_s5,,}; [ -z "$c_s5" ] && c_s5="y"; ENABLE_S5=$([[ "$c_s5" == "y" ]] && echo 1 || echo 0)
    reading "启用 Argo 隧道 [y/n] (默认 y)" c_ar; c_ar=${c_ar,,}; [ -z "$c_ar" ] && c_ar="y"; ENABLE_ARGO=$([[ "$c_ar" == "y" ]] && echo 1 || echo 0)

    if [ "$CERT_SOURCE" == "none" ] && { [ "$ENABLE_HY" == "1" ] || [ "$ENABLE_TC" == "1" ]; }; then
        msg_warn "Hy2 / TUIC 强依赖 TLS，已自动把证书策略从「无 TLS」切换为「自签」。"
        CERT_SOURCE="selfsigned"; TLS_SELF_SIGNED="1"
    fi

    echo -e "\n${BG_BLUE} 端口与参数分配 ${NC}"
    
    if [ "$ENABLE_VD" == "1" ]; then
        ask_port "VLESS (WS) 外网端口 (回车随机)" PORT_VD
        if [ -z "$PORT_VD" ]; then PORT_VD=$(get_random_port); echo -e "  ${CYAN}➤ 自动分配 VLESS 端口: ${GREEN}$PORT_VD${NC}"; fi
    fi
    if [ "$ENABLE_RE" == "1" ]; then
        ask_port "Reality 外网端口 (建议443，回车随机)" PORT_RE
        if [ -z "$PORT_RE" ]; then PORT_RE=$(get_random_port); echo -e "  ${CYAN}➤ 自动分配 Reality 端口: ${GREEN}$PORT_RE${NC}"; fi
        msg_info "正在生成 Reality 密钥对..."
        if ! generate_reality_keys; then
            msg_error "Reality 密钥生成失败，安装中止。"
            exit 1
        fi
        REALITY_SHORT_ID=""
        REALITY_SNI="addons.mozilla.org"
    fi
    if [ "$ENABLE_HY" == "1" ]; then
        ask_port "Hysteria2 外网端口 (回车随机)" PORT_HY
        if [ -z "$PORT_HY" ]; then PORT_HY=$(get_random_port); echo -e "  ${CYAN}➤ 自动分配 Hysteria2 端口: ${GREEN}$PORT_HY${NC}"; fi
        
        reading "是否开启端口跳跃 (Port Hopping)? [y/n] (默认 n)" ph
        if [[ "${ph,,}" == "y" ]]; then
            HY_HOPPING=1
            ask_port_range "请输入连续跳跃端口段 (例如: 20000-30000)" HY_PORTS "$PORT_HY"
        else HY_HOPPING=0; HY_PORTS=""; fi
    fi
    if [ "$ENABLE_TC" == "1" ]; then
        ask_port "TUIC 外网端口 (回车随机)" PORT_TC
        if [ -z "$PORT_TC" ]; then PORT_TC=$(get_random_port); echo -e "  ${CYAN}➤ 自动分配 TUIC 端口: ${GREEN}$PORT_TC${NC}"; fi
    fi
    if [ "$ENABLE_S5" == "1" ]; then
        ask_port "SOCKS5 外网端口 (回车随机)" PORT_S5
        if [ -z "$PORT_S5" ]; then PORT_S5=$(get_random_port); echo -e "  ${CYAN}➤ 自动分配 SOCKS5 端口: ${GREEN}$PORT_S5${NC}"; fi
    fi

    ARGO_MODE="temp"; ARGO_TOKEN=""; ARGO_DOMAIN=""
    WARP_MODE="1"; WARP_DOMAINS=""
    if [ "$CERT_SOURCE" == "none" ]; then VD_MODE="1"; else VD_MODE="2"; fi

    echo ""; msg_info "正在写入底层架构并启动守护进程..."
    if ! generate_config; then
        msg_error "配置生成失败，部署中止。"
        exit 1
    fi
    setup_services
    echo ""; msg_success "自定义部署已完成！"; sleep 2
}

manage_protocols() {
    [ ! -f "$SB_INFO" ] && msg_error "请先进行部署！" && sleep 1 && return
    load_config
    while true; do
        print_logo
        echo -e "${PURPLE}╭━━━ ⚙️ ${BG_BLUE} 协议精细化管理 ${NC} ${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━╮${NC}"
        [ "$ENABLE_VD" == "1" ] && printf '%b\n' "${PURPLE}┃${NC}  [1]\t⚡ 修改 VLESS (WS)   ${YELLOW}(端口: $PORT_VD)${NC}"
        [ "$ENABLE_RE" == "1" ] && printf '%b\n' "${PURPLE}┃${NC}  [2]\t🎭 修改 Reality      ${YELLOW}(端口: $PORT_RE)${NC}"
        [ "$ENABLE_HY" == "1" ] && printf '%b\n' "${PURPLE}┃${NC}  [3]\t🚀 修改 Hy2          ${YELLOW}(端口: $PORT_HY)${NC}"
        [ "$ENABLE_TC" == "1" ] && printf '%b\n' "${PURPLE}┃${NC}  [4]\t🏎️ 修改 TUIC v5      ${YELLOW}(端口: $PORT_TC)${NC}"
        [ "$ENABLE_S5" == "1" ] && printf '%b\n' "${PURPLE}┃${NC}  [5]\t🛡️ 修改 SOCKS5       ${YELLOW}(端口: $PORT_S5)${NC}"
        [ "$ENABLE_ARGO" == "1" ] && printf '%b\n' "${PURPLE}┃${NC}  [6]\t☁️  配置 Argo 隧道    ${YELLOW}(模式: $ARGO_MODE)${NC}"
        echo -e "${PURPLE}┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫${NC}"
        printf '%b\n' "${PURPLE}┃${NC}  ${RED}[7]\t🛑 停用/卸载单独协议${NC}"
        printf '%b\n' "${PURPLE}┃${NC}  [8]\t🔏 证书策略 ${YELLOW}(当前: ${CERT_SOURCE}${VD_DOMAIN:+ / ${VD_DOMAIN}})${NC}"
        printf '%b\n' "${PURPLE}┃${NC}  [0]\t↩️  返回主菜单${NC}"
        echo -e "${PURPLE}╰━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━╯${NC}"
        reading "请选择操作 [0-8]" choice
        case $choice in
            1)
                [ "$ENABLE_VD" != "1" ] && continue
                ask_port "新 VLESS 端口 (回车不变)" p; [ -n "$p" ] && PORT_VD=$p
                ask_uuid "新 VLESS 独立 UUID (回车不变)" u; [ -n "$u" ] && UUID_VD=$u
                
                local current_vd_mode_str="关闭 TLS (纯普通直连)"
                if [ "$VD_MODE" == "2" ]; then
                    if [ "$TLS_SELF_SIGNED" == "1" ]; then current_vd_mode_str="开启 TLS (自签证书)"
                    else current_vd_mode_str="开启 TLS (真实证书: ${VD_DOMAIN:-未配置})"; fi
                fi

                echo -e "\n  ${YELLOW}当前 VLESS 模式: ${GREEN}${current_vd_mode_str}${NC}"
                echo -e "  ${YELLOW}请选择新的 VLESS 模式 (直接回车保持不变)：${NC}"
                echo -e "  [1] 关闭 TLS (纯普通直连)"
                echo -e "  [2] 开启 TLS (申请真实域名证书)"
                echo -e "  [3] 开启 TLS (自签证书，免域名)"
                reading "模式选择 [1-3]" vm
                if [ "$vm" == "2" ]; then
                    reading "请输入已解析到此VPS的真实域名" vd
                    if [ -n "$vd" ]; then
                        if apply_cert "$vd"; then
                            VD_MODE="2"; VD_DOMAIN="$vd"; CERT_SOURCE="acme"; TLS_SELF_SIGNED="0"
                        else
                            msg_warn "真实证书失败，已回落自签证书。"
                            VD_DOMAIN=""; VD_MODE="2"; gen_self_signed_cert ""
                        fi
                    else
                        msg_warn "操作取消。"
                    fi
                elif [[ "$vm" == "3" ]]; then
                    VD_MODE="2"; VD_DOMAIN=""; gen_self_signed_cert ""
                elif [[ "$vm" == "1" ]]; then VD_MODE="1"; VD_DOMAIN=""; fi
                ;;
            2)
                [ "$ENABLE_RE" != "1" ] && continue
                ask_port "新 Reality 端口 (回车不变)" p; [ -n "$p" ] && PORT_RE=$p
                ask_uuid "新 Reality 独立 UUID (回车不变)" u; [ -n "$u" ] && UUID_RE=$u
                reading "伪装 SNI 域名 (当前: $REALITY_SNI)" s; [ -n "$s" ] && REALITY_SNI=$s
                ;;
            3)
                [ "$ENABLE_HY" != "1" ] && continue
                ask_port "新 Hy2 端口 (回车不变)" p; [ -n "$p" ] && PORT_HY=$p
                reading "新密码 (回车不变)" pw; [ -n "$pw" ] && PW_HY=$pw
                
                local current_hop_str
                current_hop_str=$([ "$HY_HOPPING" == "1" ] && echo "已开启 (${HY_PORTS})" || echo "未开启")
                reading "是否开启端口跳跃 (Port Hopping)? [y/n] (默认 n, 当前状态: $current_hop_str)" ph
                ph=${ph,,}
                if [[ "$ph" == "y" ]]; then
                    HY_HOPPING=1
                    ask_port_range "请输入端口段 (例如: 20000-30000)" HY_PORTS "$PORT_HY"
                elif [[ "$ph" == "n" ]]; then
                    HY_HOPPING=0; HY_PORTS=""
                fi
                ;;
            4)
                [ "$ENABLE_TC" != "1" ] && continue
                ask_port "新 TUIC 端口 (回车不变)" p; [ -n "$p" ] && PORT_TC=$p
                ask_uuid "新 TUIC 独立 UUID (回车不变)" u; [ -n "$u" ] && UUID_TC=$u
                reading "新密码 (回车不变)" pw; [ -n "$pw" ] && PW_TC=$pw
                ;;
            5)
                [ "$ENABLE_S5" != "1" ] && continue
                ask_port "新 Socks5 端口 (回车不变)" p; [ -n "$p" ] && PORT_S5=$p
                reading "新密码 (回车不变)" pw; [ -n "$pw" ] && S5_P=$pw
                ;;
            6)
                [ "$ENABLE_ARGO" != "1" ] && continue
                ask_uuid "新 Argo 独立 UUID (回车不变)" u; [ -n "$u" ] && UUID_ARGO=$u
                reading "[1]=临时隧道(随机域名)  [2]=固定隧道 (直接回车保持不变)" am
                if [ "$am" == "2" ]; then
                    ARGO_MODE="fixed"
                    while true; do reading "请输入绑定的固定域名" d; if [ -n "$d" ]; then ARGO_DOMAIN=$d; break; else msg_error "域名不能为空！"; fi; done
                    while true; do reading "请输入 Cloudflare Token" t; if [ ${#t} -gt 50 ]; then ARGO_TOKEN=$t; break; else msg_error "Token 过短！"; fi; done
                elif [ "$am" == "1" ]; then
                    ARGO_MODE="temp"; ARGO_TOKEN=""; ARGO_DOMAIN=""
                fi
                ;;
            8)
                echo -e "\n  ${YELLOW}当前证书来源: ${GREEN}${CERT_SOURCE}${NC}    域名: ${GREEN}${VD_DOMAIN:-无}${NC}    VLESS-TLS: $([ "$VD_MODE" == "2" ] && echo 开启 || echo 关闭)"
                echo -e "  [1] 申请 / 续期真实域名证书 (需要 DNS 解析 + 80 端口或 CF API)"
                echo -e "  [2] 改为自签证书 (免域名，客户端需 insecure)"
                echo -e "  [3] 改为无 TLS (VLESS 走明文 WS；Hy2/TUIC 会自动改自签)"
                echo -e "  [4] 强制重新生成自签证书"
                echo -e "  [0] 取消"
                reading "选择 [0-4]" cs
                case "$cs" in
                    1)
                        reading "域名 (回车沿用 ${VD_DOMAIN:-空})" d
                        [ -z "$d" ] && d="$VD_DOMAIN"
                        if [ -n "$d" ] && apply_cert "$d"; then
                            VD_DOMAIN="$d"; CERT_SOURCE="acme"; TLS_SELF_SIGNED="0"
                            msg_success "真实证书已部署。"
                        else
                            msg_warn "真实证书未成功，自动回落自签证书。"
                            VD_DOMAIN=""; gen_self_signed_cert ""
                        fi
                        ;;
                    2) VD_DOMAIN=""; gen_self_signed_cert "" ;;
                    3) CERT_SOURCE="none"; VD_MODE="1"; TLS_SELF_SIGNED="0"; msg_success "已切换为无 TLS 策略（VLESS 走明文 WS）。" ;;
                    4) rm -f "${SB_DIR}/server.crt" "${SB_DIR}/server.key"; gen_self_signed_cert "" ;;
                    0) continue ;;
                    *) msg_warn "无效输入"; sleep 1; continue ;;
                esac
                ;;
            7)
                echo -e "\n  ${YELLOW}请选择要停用的协议 (释放端口及资源)：${NC}"
                [ "$ENABLE_VD" == "1" ] && echo "  [1] VLESS (WS)"
                [ "$ENABLE_RE" == "1" ] && echo "  [2] Reality"
                [ "$ENABLE_HY" == "1" ] && echo "  [3] Hy2"
                [ "$ENABLE_TC" == "1" ] && echo "  [4] TUIC v5"
                [ "$ENABLE_S5" == "1" ] && echo "  [5] SOCKS5"
                [ "$ENABLE_ARGO" == "1" ] && echo "  [6] Argo 隧道"
                echo "  [0] 取消"
                reading "选择停用目标 [0-6]" disable_choice
                case $disable_choice in
                    1) ENABLE_VD=0 ;; 2) ENABLE_RE=0 ;; 3) ENABLE_HY=0 ;; 4) ENABLE_TC=0 ;; 5) ENABLE_S5=0 ;; 6) ENABLE_ARGO=0 ;; 0) continue ;; *) msg_warn "无效输入"; sleep 1; continue ;;
                esac
                msg_success "目标协议已标记为停用！"
                ;;
            0) break ;;
            *) continue ;;
        esac
        msg_info "正在热重载内核配置..."
        if ! generate_config; then
            msg_error "配置重载失败，请检查日志。"
            sleep 1
            continue
        fi
        setup_services
        msg_success "配置热重载完成！"; sleep 1
    done
}

manage_warp() {
    [ ! -f "$SB_INFO" ] && msg_error "请先进行部署！" && sleep 1 && return
    if is_alpine; then msg_error "Alpine 系统不支持 WARP。"; sleep 2; return; fi
    load_config
    while true; do
        print_logo
        local mode_str="原生直连"
        [ "$WARP_MODE" == "2" ] && mode_str="全局 WARP"
        [ "$WARP_MODE" == "3" ] && mode_str="路由分流"

        echo -e "${PURPLE}╭━━━ 🌐 ${BG_BLUE} WARP 智能大脑 ${NC} ${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━╮${NC}"
        echo -e "${PURPLE}┃${NC} 当前模式: ${GREEN}$mode_str${NC}"
        [ "$WARP_MODE" == "3" ] && echo -e "${PURPLE}┃${NC} 分流名单: ${YELLOW}${WARP_DOMAINS:-无}${NC}"
        [ "$WARP_MODE" == "3" ] && [ -z "$WARP_DOMAINS" ] && echo -e "${PURPLE}┃${NC} ${RED}⚠ 当前分流模式未指定任何域名，流量将全部直连。${NC}"
        echo -e "${PURPLE}┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫${NC}"
        printf '%b\n' "${PURPLE}┃${NC}  [1]\t🔄 切换 WARP 工作模式"
        printf '%b\n' "${PURPLE}┃${NC}  [2]\t➕ 追加目标分流域名"
        printf '%b\n' "${PURPLE}┃${NC}  [3]\t➖ 移除指定分流域名"
        printf '%b\n' "${PURPLE}┃${NC}  [4]\t🗑️ 清空所有分流名单"
        printf '%b\n' "${PURPLE}┃${NC}  [0]\t↩️  返回主菜单"
        echo -e "${PURPLE}╰━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━╯${NC}"

        reading "请选择操作 [0-4]" choice
        case $choice in
            1) echo -e "  ➤ [1]=关闭  [2]=全局WARP  [3]=指定分流"; reading "选择模式" wm; [ -n "$wm" ] && WARP_MODE=$wm; [[ "$WARP_MODE" == "2" || "$WARP_MODE" == "3" ]] && install_warp ;;
            2) reading "输入要追加的域名 (如 netflix.com)" nd; if [ -n "$nd" ]; then if [ -z "$WARP_DOMAINS" ]; then WARP_DOMAINS="$nd"; else WARP_DOMAINS="$WARP_DOMAINS,$nd"; fi; fi ;;
            3) if [ -z "$WARP_DOMAINS" ]; then msg_warn "无可删除域名！"; sleep 1; continue; fi; reading "输入要移除的域名" rm_d; if [ -n "$rm_d" ]; then IFS=',' read -ra DOMAINS <<< "$WARP_DOMAINS"; local new_arr=""; for d in "${DOMAINS[@]}"; do if [ "$d" != "$rm_d" ] && [ -n "$d" ]; then new_arr+="$d,"; fi; done; WARP_DOMAINS=${new_arr%,}; msg_success "已更新！"; fi ;;
            4) WARP_DOMAINS="" ;;
            0) break ;;
        esac
        generate_config; svc_action restart sing-box; msg_success "WARP 规则已热生效！"; sleep 1
    done
}

show_nodes() {
    print_logo; [ ! -f "$SB_INFO" ] && msg_error "请先部署节点！" && sleep 1 && return
    load_config
    ensure_net_stack
    [ -s "${SB_DIR}/server.crt" ] && detect_cert_source
    local quiet="${1:-}"

    msg_info "正在探测公网 IP (请稍候)..."
    local out_ip; out_ip=$(get_outbound_ip)
    msg_info "正在获取节点物理位置归属地..."
    NODE_PREFIX=$(get_country_prefix)

    if [ -z "$CUSTOM_IP" ]; then
        echo -e " ${BG_BLUE} 网络探针 ${NC} 网络栈: ${GREEN}$(net_stack_label)${NC}"
        [ -n "$WAN4" ] && echo -e " ${BG_BLUE} 网络探针 ${NC} ${CYAN}IPv4:${NC} ${GREEN}$WAN4${NC}"
        [ -n "$WAN6" ] && echo -e " ${BG_BLUE} 网络探针 ${NC} ${CYAN}IPv6:${NC} ${GREEN}$WAN6${NC}"
        echo -e " ${BG_BLUE} 网络探针 ${NC} 入站地址: ${GREEN}$out_ip${NC} (${NODE_PREFIX})"
        if [ "$NAT_LOCAL" = "1" ]; then
            echo -e " ${YELLOW}⚠ 本机在内网 NAT 里（${LOCAL_ADDR4:-内网地址}），上面是【出网】IP，未必是【入口】IP。${NC}"
            echo -e " ${YELLOW}  若节点连不通，请在这里直接填面板/服务商给你的真实入口 IP 或域名。${NC}"
        fi
        if [ "$quiet" == "quiet" ]; then
            CUSTOM_IP="$out_ip"
        else
            reading "若需指定入站IP/域名请在此输入 (一致请直接回车)" in_ip
            if [ -n "$in_ip" ]; then CUSTOM_IP=$in_ip; else CUSTOM_IP=$out_ip; fi
        fi
        save_config
    fi

    local ip=$CUSTOM_IP
    [[ "$ip" =~ .*:.* ]] && ip="[${ip}]"

    # 自签证书 → 客户端必须跳过证书校验
    local selfsign="0" vless_inc="" hy_inc="" tuic_inc=""
    [ "$TLS_SELF_SIGNED" == "1" ] && selfsign="1"
    if [ "$selfsign" == "1" ]; then
        vless_inc="&allowInsecure=1"
        hy_inc="&insecure=1"
        tuic_inc="&allow_insecure=1&insecure=1"
    fi

    local tls_sni tls_host
    tls_sni=$(tls_server_name)
    tls_host="${VD_DOMAIN:-$ip}"

    echo -e "\n${CYAN}╭━━━━━━━━━━━━ 🔗 节点订阅凭证 ━━━━━━━━━━━━╮${NC}"
    local all_links="" link_re link1 link2 link3 link4 link5 argo_type=""

    if [ "$ENABLE_RE" == "1" ]; then
        echo -e "${CYAN}┃${NC} 🎭 ${GREEN}[VLESS + Reality]${NC} (极致隐蔽直连)"
        link_re="vless://${UUID_RE}@${ip}:${PORT_RE}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${REALITY_SNI}&fp=chrome&pbk=${REALITY_PBK}&type=tcp#${NODE_PREFIX}-REALITY"
        echo -e "${CYAN}┃${NC}    ${link_re}"; all_links+="$link_re\n"
    fi

    if [ "$ENABLE_VD" == "1" ]; then
        if [ "$VD_MODE" == "1" ]; then
            echo -e "${CYAN}┃${NC} ⚡ ${GREEN}[VLESS + WS]${NC} (关闭 TLS 纯直连)"
            link1="vless://${UUID_VD}@${ip}:${PORT_VD}?encryption=none&security=none&type=ws&path=%2Fws#${NODE_PREFIX}-VLESS"
        elif [ "$selfsign" == "1" ]; then
            echo -e "${CYAN}┃${NC} ⚡ ${GREEN}[VLESS + WS + TLS]${NC} (自签证书)"
            link1="vless://${UUID_VD}@${tls_host}:${PORT_VD}?encryption=none&security=tls&sni=${tls_sni}&type=ws&host=${tls_host}&path=%2Fws${vless_inc}#${NODE_PREFIX}-VLESS"
        else
            echo -e "${CYAN}┃${NC} ⚡ ${GREEN}[VLESS + WS + TLS]${NC} (真实证书: ${VD_DOMAIN})"
            link1="vless://${UUID_VD}@${tls_host}:${PORT_VD}?encryption=none&security=tls&sni=${tls_sni}&type=ws&host=${tls_host}&path=%2Fws${vless_inc}#${NODE_PREFIX}-VLESS"
        fi
        echo -e "${CYAN}┃${NC}    ${link1}"; all_links+="$link1\n"
    fi

    if [ "$ENABLE_ARGO" == "1" ]; then
        local argo_domain=""
        if [ "$ARGO_MODE" == "temp" ]; then
            for i in $(seq 1 10); do
                [ -f "$ARGO_LOG" ] && argo_domain=$(grep -oE "https://[a-zA-Z0-9-]+\.trycloudflare\.com" "$ARGO_LOG" 2>/dev/null | tail -n 1 | sed 's/https:\/\///')
                [ -n "$argo_domain" ] && break
                sleep 2
            done
            [ -n "$argo_domain" ] && argo_type="临时随机隧道"
        elif [ "$ARGO_MODE" == "fixed" ]; then
            argo_domain="$ARGO_DOMAIN"; argo_type="固定专线隧道"
        fi

        echo -e "${CYAN}┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫${NC}"
        echo -e "${CYAN}┃${NC} ☁️  ${GREEN}[VLESS + Argo]${NC} (${argo_type:-未就绪})"
        if [ -n "$argo_domain" ]; then
            link2="vless://${UUID_ARGO}@www.visa.com.sg:443?encryption=none&security=tls&sni=${argo_domain}&type=ws&host=${argo_domain}&path=%2Fargo#${NODE_PREFIX}-ARGO"
            echo -e "${CYAN}┃${NC}    ${link2}"; all_links+="$link2\n"
        else echo -e "${CYAN}┃${NC}    ${RED}(未能成功获取隧道域名，请稍后重试或检查日志)${NC}"; fi
    fi

    if [ "$ENABLE_HY" == "1" ]; then
        echo -e "${CYAN}┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫${NC}"
        local mport_suffix=""
        [ "$HY_HOPPING" == "1" ] && [ -n "$HY_PORTS" ] && mport_suffix="&mport=${HY_PORTS}"
        echo -e "${CYAN}┃${NC} 🚀 ${GREEN}[Hysteria 2]${NC} (暴力加速)"
        link3="hysteria2://${PW_HY}@${tls_host}:${PORT_HY}?sni=${tls_sni}${hy_inc}${mport_suffix}#${NODE_PREFIX}-HY2"
        echo -e "${CYAN}┃${NC}    ${link3}"; all_links+="$link3\n"
    fi
    if [ "$ENABLE_TC" == "1" ]; then
        echo -e "${CYAN}┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫${NC}"
        echo -e "${CYAN}┃${NC} 🏎️  ${GREEN}[TUIC v5]${NC} (QUIC 协议)"
        link4="tuic://${UUID_TC}:${PW_TC}@${tls_host}:${PORT_TC}?sni=${tls_sni}&alpn=h3&congestion_control=bbr${tuic_inc}#${NODE_PREFIX}-TUIC"
        echo -e "${CYAN}┃${NC}    ${link4}"; all_links+="$link4\n"
    fi
    if [ "$ENABLE_S5" == "1" ]; then
        echo -e "${CYAN}┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫${NC}"
        echo -e "${CYAN}┃${NC} 🛡️  ${GREEN}[SOCKS5]${NC} (基础代理)"
        local cred="${S5_U}:${S5_P}" b64_cred
        b64_cred=$(echo -n "$cred" | base64 -w0 2>/dev/null || echo -n "$cred" | base64)
        link5="socks://${b64_cred}@${ip}:${PORT_S5}#${NODE_PREFIX}-SOCKS5"
        echo -e "${CYAN}┃${NC}    ${link5}"; all_links+="$link5\n"
    fi
    echo -e "${CYAN}╰━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━╯${NC}"

    if [ "$selfsign" == "1" ]; then
        echo -e "\n ${YELLOW}⚠ 本机使用自签证书：Hy2 / TUIC / VLESS-WS 必须在客户端开启「跳过证书验证 / insecure / allowInsecure」。${NC}"
    fi
    if [ "$NET_STACK" == "ipv6" ]; then
        echo -e " ${YELLOW}⚠ 本机为纯 IPv6：客户端需具备 IPv6 出口；仅 IPv4 的目标站点需配合 WARP / NAT64。${NC}"
    fi

    echo -e "\n ${BG_BLUE} Base64 订阅 ${NC} 一键复制以下内容导入客户端:"
    echo -e "$all_links" | sed '/^$/d' | base64 -w0
    echo ""
    [ "$quiet" == "quiet" ] && return 0
    reading "按回车键 (Enter) 返回主菜单..." dummy
}

uninstall_script() {
    print_logo; echo -e " ${BG_RED} 危险警告 ${NC} ${RED}你正在执行物理毁灭程序！${NC}\n"
    reading "确定要彻底卸载脚本、核心及配置吗？[y/n]" c
    c=${c,,}; if [[ "$c" != "y" ]]; then return; fi

    echo ""; for i in 3 2 1; do echo -e "${YELLOW}将在 $i 秒后开始清理...${NC}"; sleep 1; done

    msg_info "正在清理后台进程与残留文件..."
    svc_action stop sing-box >/dev/null 2>&1; svc_action stop sb-argo >/dev/null 2>&1
    svc_action disable sing-box >/dev/null 2>&1; svc_action disable sb-argo >/dev/null 2>&1
    # 裸跑(容器)模式残留清理
    raw_stop sing-box >/dev/null 2>&1; raw_stop sb-argo >/dev/null 2>&1
    rm -f "$SB_GUARD" "$ARGO_GUARD" /var/run/sing-box.pid /var/run/sb-argo.pid

    while iptables -t nat -D PREROUTING -p udp -m comment --comment "hy2-hopping" -j REDIRECT 2>/dev/null; do :; done
    while ip6tables -t nat -D PREROUTING -p udp -m comment --comment "hy2-hopping" -j REDIRECT 2>/dev/null; do :; done
    while iptables -t nat -D PREROUTING -p udp -m comment --comment "hy2-hopping-exclude" -j ACCEPT 2>/dev/null; do :; done
    while ip6tables -t nat -D PREROUTING -p udp -m comment --comment "hy2-hopping-exclude" -j ACCEPT 2>/dev/null; do :; done

    if is_alpine; then rm -f /etc/init.d/sing-box /etc/init.d/sb-argo
    else rm -f /etc/systemd/system/sing-box.service /etc/systemd/system/sb-argo.service; systemctl daemon-reload; fi

    if command -v warp-cli >/dev/null 2>&1; then
        warp-cli disconnect >/dev/null 2>&1
        if command -v apt-get >/dev/null 2>&1; then apt-get remove -y cloudflare-warp >/dev/null 2>&1
        elif command -v yum >/dev/null 2>&1; then yum remove -y cloudflare-warp >/dev/null 2>&1; fi
    fi

    # 清理 sysctl 优化配置
    rm -f /etc/sysctl.d/99-singbox-optimize.conf
    sysctl --system >/dev/null 2>&1 || true

    # 此处已删除 ! -name "sub.txt" 的限制，实现彻底销毁
    find "$SB_DIR" -type f -delete 2>/dev/null
    rm -f "$SB_BIN" "$ARGO_BIN" "/usr/bin/sb"
    msg_success "系统已恢复纯净状态，江湖再见！"; rm -f "$0"; exit 0
}

# ---------- v7：全自动部署（无交互，容器 / cloud-init 友好） ----------
auto_deploy() {
    local mode="self" domain="" ip_override="" use_argo=1 ports_override="" use_udp=1
    while [ $# -gt 0 ]; do
        case "$1" in
            --mode=*) mode="${1#*=}" ;;
            --domain=*) domain="${1#*=}" ;;
            --ip=*) ip_override="${1#*=}" ;;
            --no-argo) use_argo=0 ;;
            --ports=*) ports_override="${1#*=}" ;;
            --no-udp|--tcp-only) use_udp=0 ;;
            self|acme|none) mode="$1" ;;
            -h|--help)
                cat <<'USAGE'
用法: sb auto [选项]
  --mode=self|acme|none   证书策略，默认 self（自签，免域名）
  --domain=xxx.com        acme 模式必填
  --ip=1.2.3.4            强制指定节点地址（纯 IPv6 直接填地址）
  --no-argo               不启用 Argo 隧道
  --ports=a,b,c,d,e       固定端口：VLESS,Reality,Hy2,TUIC,SOCKS5（容器端口映射必填）
  --no-udp               不开 Hy2 / TUIC（面板只映射 TCP 时用，避免出现必然超时的节点）

示例:
  bash sb.sh auto
  bash sb.sh auto --mode=self --no-argo
  docker exec -it sb bash /usr/bin/sb auto
USAGE
                return 0 ;;
            *) shift; continue ;;
        esac
        shift
    done

    print_logo
    echo -e "${BG_PURPLE} 全自动部署 ${NC} ${YELLOW}无交互模式${NC}\n"

    install_deps; install_singbox; install_argo
    msg_info "正在探测本机网络栈..."
    detect_net_stack
    echo -e "  ${CYAN}➤ 网络栈: ${GREEN}$(net_stack_label)${NC}  ${CYAN}DNS: ${GREEN}${DNS_STRATEGY}${NC}  ${CYAN}监听: ${GREEN}${LISTEN_ADDR}${NC}"

    if [ -f "$SB_INFO" ]; then
        msg_warn "检测到旧部署，全自动模式直接覆盖。"
        find "$SB_DIR" -type f ! -name "server.crt" ! -name "server.key" -delete 2>/dev/null
    fi

    case "$mode" in
        acme)
            if [ -z "$domain" ]; then msg_error "--mode=acme 需要 --domain=你的域名"; return 1; fi
            VD_DOMAIN="$domain"; CERT_SOURCE="acme"
            if ! apply_cert "$VD_DOMAIN"; then
                msg_warn "真实证书申请失败，自动回落自签证书。"
                CERT_SOURCE="selfsigned"; VD_DOMAIN=""
            fi ;;
        none) CERT_SOURCE="none"; TLS_SELF_SIGNED="0"; VD_DOMAIN="" ;;
        *)    CERT_SOURCE="selfsigned"; TLS_SELF_SIGNED="1"; VD_DOMAIN="" ;;
    esac
    if [ "$CERT_SOURCE" != "none" ]; then ensure_tls_cert || true; fi

    UUID_VD=$(cat /proc/sys/kernel/random/uuid); UUID_RE=$(cat /proc/sys/kernel/random/uuid)
    UUID_ARGO=$(cat /proc/sys/kernel/random/uuid); UUID_TC=$(cat /proc/sys/kernel/random/uuid)
    PW_HY=$(tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 10); PW_TC=$(tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 10)
    S5_U="user"; S5_P=$(tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 8)

    ENABLE_VD=1; ENABLE_RE=1; ENABLE_S5=1
    ENABLE_ARGO=$use_argo
    if [ "$CERT_SOURCE" == "none" ] || [ "$use_udp" == "0" ]; then
        ENABLE_HY=0; ENABLE_TC=0
        [ "$use_udp" == "0" ] && msg_warn "已按 --no-udp 关闭 Hy2 / TUIC（UDP 节点需要面板转发 UDP）。"
    else
        ENABLE_HY=1; ENABLE_TC=1
    fi

    msg_info "正在生成 Reality 专属密钥对..."
    generate_reality_keys || { msg_error "Reality 密钥生成失败，中止。"; return 1; }
    REALITY_SHORT_ID=""; REALITY_SNI="addons.mozilla.org"

    msg_info "正在分配端口..."
    PORT_VD=""; PORT_RE=""; PORT_HY=""; PORT_TC=""; PORT_S5=""
    if [ -n "$ports_override" ]; then
        local _ps
        IFS=',' read -ra _ps <<< "$ports_override"
        PORT_VD="${_ps[0]:-}"; PORT_RE="${_ps[1]:-}"; PORT_HY="${_ps[2]:-}"
        PORT_TC="${_ps[3]:-}"; PORT_S5="${_ps[4]:-}"
        echo -e "  ${CYAN}➤ 使用指定端口: VLESS=$PORT_VD Reality=$PORT_RE Hy2=$PORT_HY TUIC=$PORT_TC SOCKS5=$PORT_S5${NC}"
    fi
    [ -z "$PORT_VD" ] && PORT_VD=$(get_random_port)
    [ -z "$PORT_RE" ] && PORT_RE=$(get_random_port)
    [ -z "$PORT_S5" ] && PORT_S5=$(get_random_port)
    [ "$ENABLE_HY" == "1" ] && [ -z "$PORT_HY" ] && PORT_HY=$(get_random_port)
    [ "$ENABLE_TC" == "1" ] && [ -z "$PORT_TC" ] && PORT_TC=$(get_random_port)

    ARGO_MODE="temp"; ARGO_TOKEN=""; ARGO_DOMAIN=""
    WARP_MODE="1"; WARP_DOMAINS=""
    HY_HOPPING="0"; HY_PORTS=""
    if [ "$CERT_SOURCE" == "none" ]; then VD_MODE="1"; else VD_MODE="2"; fi
    if [ -n "$ip_override" ]; then CUSTOM_IP="$ip_override"; else CUSTOM_IP=$(get_outbound_ip); fi

    if [ "$NAT_LOCAL" = "1" ] && [ -z "$ip_override" ]; then
        msg_warn "本机在内网 NAT 中（${LOCAL_ADDR4:-N/A}）：节点地址取的是出网 IP $CUSTOM_IP，"
        msg_warn "若它不是真实入口 IP，请改用 --ip=真实IP，或部署后执行 sb nodes 手动指定。"
    fi
    if [ "$ENABLE_HY" == "1" ] && [ "$NAT_LOCAL" = "1" ]; then
        msg_warn "NAT / 容器环境：请确认面板已把 $PORT_HY / $PORT_TC 的 UDP 也转发进来，否则 Hy2 / TUIC 必然超时（可用 --no-udp 关掉）。"
    fi

    msg_info "正在写入底层架构并启动守护进程..."
    if ! generate_config; then msg_error "配置生成失败，部署中止。"; return 1; fi
    setup_services
    echo ""; msg_success "全自动部署已完成！"; sleep 1
    show_nodes quiet
}

main_menu() {
    while true; do
        print_logo
        local status="${BG_RED} 休眠中 (未安装) ${NC}"
        [ -f "$SB_INFO" ] && status="${BG_GREEN} 运行中 (已部署) ${NC}"

        echo -e "   系统状态: $status"
        echo -e "   ${CYAN}──────────────────────────────────────────────────${NC}"
        printf '%b\n' "   ${GREEN}[1]${NC}\t🚀 一键快速部署 / 重置引擎"
        printf '%b\n' "   ${GREEN}[2]${NC}\t🛠️ 自定义按需部署 / 重置引擎"
        printf '%b\n' "   ${GREEN}[3]${NC}\t⚙️  单独协议参数管理 (端口/独立UUID/证书/停用)"
        printf '%b\n' "   ${GREEN}[4]${NC}\t🌐 调教 WARP 智能分流规则 (Alpine 系统不支持 WARP)"
        printf '%b\n' "   ${GREEN}[5]${NC}\t🔗 查看提取节点订阅链接"
        printf '%b\n' "   ${GREEN}[6]${NC}\t🤖 全自动部署 (免交互 · 自签 · 容器友好)"
        echo -e "   ${CYAN}──────────────────────────────────────────────────${NC}"
        # 卸载菜单文字已更新，提示会清理所有数据
        printf '%b\n' "   ${RED}[9]${NC}\t🗑️ 彻底卸载"
        printf '%b\n' "   ${RED}[0]${NC}\t🚪 退出面板"
        echo ""
        reading "请输入指令代码" choice
        case $choice in
            1) install_fast ;; 2) install_custom ;; 3) manage_protocols ;; 4) manage_warp ;;
            5) show_nodes ;; 6) auto_deploy ;; 9) uninstall_script ;; 0) clear; exit 0 ;; *) ;;
        esac
    done
}

case "${1:-}" in
    auto|--auto) shift; auto_deploy "$@" ;;
    nodes)       shift; show_nodes "${1:-}" ;;
    apply)
        load_config
        ensure_net_stack
        if generate_config; then setup_services; msg_success "配置已重载并重启服务。"; else msg_error "配置未通过校验，已保留旧配置。"; exit 1; fi
        ;;
    info)
        load_config
        ensure_net_stack
        [ -s "${SB_DIR}/server.crt" ] && detect_cert_source
        echo "网络栈   : $NET_STACK ($(net_stack_label))"
        echo "DNS 策略 : $DNS_STRATEGY"
        echo "监听地址 : $LISTEN_ADDR"
        echo "出网 IPv4: ${WAN4:-无}"
        echo "出网 IPv6: ${WAN6:-无}"
        echo "内网地址 : ${LOCAL_ADDR4:-无}$([ "$NAT_LOCAL" = "1" ] && echo "  (NAT/容器：出网 IP 未必是入口 IP)")"
        echo "节点地址 : ${CUSTOM_IP:-未指定（sb nodes 可改）}"
        echo "证书策略 : $CERT_SOURCE (selfsigned=$TLS_SELF_SIGNED)"
        echo "域名     : ${VD_DOMAIN:-无}"
        echo "服务后端 : ${SERVICE_BACKEND:-$(detect_service_backend; echo "$SERVICE_BACKEND")}"
        ;;
    *)           main_menu ;;
esac
