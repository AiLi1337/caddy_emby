#!/bin/bash

# ====================================================
#  Caddy Reverse Proxy for Emby - V5 (Multi-Site Manager)
#  Author: AiLi1337
# ====================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
SKYBLUE='\033[0;36m'
PLAIN='\033[0m'

# 检查 root
[[ $EUID -ne 0 ]] && echo -e "${RED}错误：${PLAIN} 必须使用 root 用户运行！\n" && exit 1

log() { echo -e "${GREEN}[Info]${PLAIN} $1"; }
warn() { echo -e "${YELLOW}[Warning]${PLAIN} $1"; }
error() { echo -e "${RED}[Error]${PLAIN} $1"; }

# 1. 安装基础环境
install_base() {
    log "正在检查并安装基础组件..."
    # 增加 grep, sed, awk 确保文本处理正常
    if [ -f /etc/debian_version ]; then
        apt update -y && apt install -y curl wget sudo socat net-tools psmisc sed grep
    elif [ -f /etc/redhat-release ]; then
        yum install -y curl wget sudo socat net-tools psmisc sed grep
    fi
}

# 2. 端口占用查询
check_port() {
    echo -e "------------------------------------------------"
    echo -e "${SKYBLUE}正在查询 80 和 443 端口占用情况...${PLAIN}"
    echo -e "------------------------------------------------"
    if command -v netstat &> /dev/null; then
        netstat -tunlp | grep -E ":80|:443"
    else
        ss -tulpn | grep -E ":80|:443"
    fi
    echo -e "------------------------------------------------"
    echo -e "如果显示 nginx/apache，请使用菜单 [8] 清理。"
    echo -e "如果显示 caddy，属正常现象。"
}

# 3. 强制清理端口
kill_port() {
    echo -e "${RED}正在强制停止常见 Web 服务并清理端口...${PLAIN}"
    systemctl stop nginx 2>/dev/null
    systemctl disable nginx 2>/dev/null
    systemctl stop apache2 2>/dev/null
    systemctl disable apache2 2>/dev/null
    systemctl stop httpd 2>/dev/null
    
    if command -v fuser &> /dev/null; then
        fuser -k 80/tcp 2>/dev/null
        fuser -k 443/tcp 2>/dev/null
    else
        killall -9 caddy 2>/dev/null
        killall -9 nginx 2>/dev/null
        killall -9 httpd 2>/dev/null
    fi
    log "清理完成！"
    sleep 1
}

# 4. 安装 Caddy
install_caddy() {
    if command -v caddy &> /dev/null; then
        warn "Caddy 已安装。"
    else
        log "正在安装 Caddy..."
        install_base
        if [ -f /etc/debian_version ]; then
            apt install -y debian-keyring debian-archive-keyring apt-transport-https
            curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
            curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
            apt update
            apt install caddy -y
        elif [ -f /etc/redhat-release ]; then
            yum install yum-plugin-copr -y
            yum copr enable @caddyserver/caddy -y
            yum install caddy -y
        fi
        systemctl enable caddy
        log "Caddy 安装完成！"
    fi
}

# 5. 配置向导 (核心升级：支持追加)
configure_caddy() {
    echo -e "------------------------------------------------"
    echo -e "${SKYBLUE}Caddy 反代配置 (支持多站点)${PLAIN}"
    echo -e "------------------------------------------------"

    # 检查是否存在旧配置
    MODE="new"
    if [ -f /etc/caddy/Caddyfile ] && [ -s /etc/caddy/Caddyfile ]; then
        echo -e "检测到已有配置文件。"
        echo -e " ${GREEN}1.${PLAIN} 覆盖 (清空旧配置，仅保留这一个)"
        echo -e " ${GREEN}2.${PLAIN} 追加 (保留旧配置，添加新域名)"
        read -p "请选择模式 [1-2]: " config_mode < /dev/tty
        if [[ "$config_mode" == "2" ]]; then
            MODE="append"
        fi
    fi

    read -p "请输入新域名 (例如 emby2.my.com): " DOMAIN < /dev/tty
    if [[ -z "$DOMAIN" ]]; then error "域名不能为空"; return; fi

    read -p "请输入后端地址 (如 https://remote.com:443 或 127.0.0.1:8096): " EMBY_ADDRESS < /dev/tty
    [[ -z "$EMBY_ADDRESS" ]] && EMBY_ADDRESS="127.0.0.1:8096"

    # 备份
    cp /etc/caddy/Caddyfile /etc/caddy/Caddyfile.bak.$(date +%F_%H%M%S) 2>/dev/null

    # 如果是追加模式，先检查域名是否已存在，防止重复报错
    if [[ "$MODE" == "append" ]]; then
        if grep -q "$DOMAIN {" /etc/caddy/Caddyfile; then
            warn "域名 $DOMAIN 已存在！正在删除旧配置块，写入新配置..."
            # 使用 sed 删除该域名对应的块 (假设格式标准：域名 { ... })
            sed -i "/^$DOMAIN {/,/^}/d" /etc/caddy/Caddyfile
            # 删除多余空行
            sed -i '/^\s*$/d' /etc/caddy/Caddyfile
        fi
    fi

    # 生成配置块内容
    CONFIG_BLOCK="$DOMAIN {
    encode gzip
    header Access-Control-Allow-Origin *

    reverse_proxy $EMBY_ADDRESS {
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
        header_up Host {upstream_hostport}
    }
}"

    log "正在写入配置..."

    if [[ "$MODE" == "new" ]]; then
        echo "$CONFIG_BLOCK" > /etc/caddy/Caddyfile
    else
        # 确保追加前有个空行，美观
        echo "" >> /etc/caddy/Caddyfile
        echo "$CONFIG_BLOCK" >> /etc/caddy/Caddyfile
    fi

    restart_caddy
}

# 6. 删除指定配置 (新功能)
delete_config() {
    echo -e "------------------------------------------------"
    echo -e "${SKYBLUE}删除指定站点配置${PLAIN}"
    echo -e "------------------------------------------------"

    if [ ! -f /etc/caddy/Caddyfile ]; then
        error "未找到配置文件！"
        return
    fi

    # 列出当前配置的域名
    echo -e "当前已配置的域名："
    # 提取以 { 结尾的行首域名
    grep -E "^[a-zA-Z0-9.-]+ \{" /etc/caddy/Caddyfile | awk '{print $1}' > /tmp/caddy_domains.txt
    
    if [ ! -s /tmp/caddy_domains.txt ]; then
        warn "配置文件中未找到有效域名块。"
        return
    fi

    i=1
    while read line; do
        echo -e " ${GREEN}$i.${PLAIN} $line"
        ((i++))
    done < /tmp/caddy_domains.txt

    echo -e "------------------------------------------------"
    read -p "请输入要删除的域名 (完整复制上面的域名): " DEL_DOMAIN < /dev/tty

    if [[ -z "$DEL_DOMAIN" ]]; then return; fi

    # 再次确认
    if grep -q "^$DEL_DOMAIN {" /etc/caddy/Caddyfile; then
        # 备份
        cp /etc/caddy/Caddyfile /etc/caddy/Caddyfile.bak.del
        # 删除操作
        sed -i "/^$DEL_DOMAIN {/,/^}/d" /etc/caddy/Caddyfile
        # 清理空行
        sed -i '/^\s*$/d' /etc/caddy/Caddyfile
        
        log "域名 $DEL_DOMAIN 配置已删除。"
        restart_caddy
    else
        error "未找到域名 $DEL_DOMAIN 的配置！请检查拼写。"
    fi
}

restart_caddy() {
    log "正在重启 Caddy..."
    systemctl restart caddy
    sleep 2
    if systemctl is-active --quiet caddy; then
        echo -e "\n${GREEN}=========================================="
        echo -e " 操作成功！Caddy 运行中。"
        echo -e "==========================================${PLAIN}"
    else
        error "Caddy 启动失败！请检查配置文件或端口占用。"
        echo "日志: systemctl status caddy -l"
    fi
}

# 7. 菜单循环
show_menu() {
    clear
    echo -e "#################################################"
    echo -e "#    Caddy + Emby 多站点管理脚本 (V5 Pro)       #"
    echo -e "#################################################"
    echo -e " ${GREEN}1.${PLAIN} 安装环境 & Caddy"
    echo -e " ${GREEN}2.${PLAIN} 添加/覆盖 反代配置 (支持多站)"
    echo -e " ${GREEN}3.${PLAIN} 删除指定站点配置 ${YELLOW}(NEW!)${PLAIN}"
    echo -e " ${GREEN}4.${PLAIN} 查看 Caddy 配置文件"
    echo -e "-------------------------------------------------"
    echo -e " ${GREEN}5.${PLAIN} 停止 Caddy"
    echo -e " ${GREEN}6.${PLAIN} 重启 Caddy"
    echo -e " ${GREEN}7.${PLAIN} 查询 443/80 端口占用"
    echo -e " ${RED}8.${PLAIN} 暴力处理端口占用 (修复启动失败)"
    echo -e " ${RED}9.${PLAIN} 卸载 Caddy"
    echo -e "-------------------------------------------------"
    echo -e " ${GREEN}0.${PLAIN} 退出脚本"
    echo -e ""
    read -p " 请输入数字 [0-9]: " num < /dev/tty

    case "$num" in
        1) install_base; install_caddy ;;
        2) install_base; configure_caddy ;;
        3) delete_config ;;
        4) cat /etc/caddy/Caddyfile ;;
        5) systemctl stop caddy; log "服务已停止" ;;
        6) restart_caddy ;;
        7) install_base; check_port ;;
        8) install_base; kill_port ;;
        9) apt remove caddy -y 2>/dev/null; yum remove caddy -y 2>/dev/null; rm -rf /etc/caddy; log "已卸载" ;;
        0) exit 0 ;;
        *) error "请输入正确的数字" ;;
    esac
}

# 主循环
while true; do
    show_menu
    echo -e "\n${GREEN}按回车键返回主菜单...${PLAIN}"
    read temp < /dev/tty
done
