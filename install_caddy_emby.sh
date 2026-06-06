#!/bin/bash

# ====================================================
#  Caddy Reverse Proxy for Emby - V5 (Multi-Site Manager)
#  Author: AiLi1337
# ====================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
SKYBLUE='\033[0;36m'
PLAIN='\033[0m'

SCRIPT_URL="https://raw.githubusercontent.com/AiLi1337/install_caddy_emby/main/install_caddy_emby.sh"
SCRIPT_DEST="/usr/local/bin/caddy_emby.sh"
SHORTCUT="/usr/local/bin/c"

[[ $EUID -ne 0 ]] && echo -e "${RED}错误：${PLAIN} 必须使用 root 用户运行！\n" && exit 1

log()  { echo -e "${GREEN}[Info]${PLAIN} $1"; }
warn() { echo -e "${YELLOW}[Warning]${PLAIN} $1"; }
error(){ echo -e "${RED}[Error]${PLAIN} $1"; }


# 注册全局快捷命令 c
register_shortcut() {
    local SRC="${BASH_SOURCE[0]}"

    # 情况1：通过真实文件运行（如 bash install_caddy_emby.sh）
    if [[ -f "$SRC" && "$SRC" != /proc/* ]]; then
        cp "$SRC" "$SCRIPT_DEST"
        chmod +x "$SCRIPT_DEST"
        log "脚本已保存到 $SCRIPT_DEST"

    # 情况2：通过管道运行（如 bash <(curl ...)），从 URL 重新下载完整脚本
    else
        log "检测到管道运行，正在从远程下载脚本到 $SCRIPT_DEST ..."
        if curl -sL "$SCRIPT_URL" -o "$SCRIPT_DEST"; then
            chmod +x "$SCRIPT_DEST"
            log "下载成功！"
        else
            error "下载失败，请检查网络或手动保存脚本到 $SCRIPT_DEST"
            return
        fi
    fi

    # 创建 /usr/local/bin/c 快捷命令
    if [[ ! -f "$SHORTCUT" ]]; then
        printf '#!/bin/bash\nbash "%s"\n' "$SCRIPT_DEST" > "$SHORTCUT"
        chmod +x "$SHORTCUT"
        log "已注册快捷命令：下次直接输入 c 即可启动本脚本"
    fi

    # 双保险：写 alias 到 /root/.bashrc
    if ! grep -q "alias c=" /root/.bashrc 2>/dev/null; then
        echo "alias c='bash $SCRIPT_DEST'" >> /root/.bashrc
        log "已写入 alias，重新登录后也可用 c 唤出脚本"
    fi
}


# 1. 安装基础环境
install_base() {
    log "正在检查基础组件..."
    
    local packages=("curl" "wget" "sudo" "socat" "net-tools" "psmisc" "sed" "grep")
    local to_install=()
    
    if [ -f /etc/debian_version ]; then
        for pkg in "${packages[@]}"; do
            if ! dpkg -s "$pkg" 2>/dev/null | grep -q "^Status: install ok installed"; then
                to_install+=("$pkg")
            else
                log "$pkg 已安装，跳过"
            fi
        done
        if [ ${#to_install[@]} -gt 0 ]; then
            log "正在安装缺失的包: ${to_install[*]}"
            apt update -y && apt install -y "${to_install[@]}"
        else
            log "所有基础组件已安装"
        fi
    elif [ -f /etc/redhat-release ]; then
        for pkg in "${packages[@]}"; do
            if ! rpm -q "$pkg" &>/dev/null; then
                to_install+=("$pkg")
            else
                log "$pkg 已安装，跳过"
            fi
        done
        if [ ${#to_install[@]} -gt 0 ]; then
            log "正在安装缺失的包: ${to_install[*]}"
            yum install -y "${to_install[@]}"
        else
            log "所有基础组件已安装"
        fi
    else
        warn "未检测到支持的 Linux 发行版 (Debian/Ubuntu/CentOS/RHEL)"
        log "请手动安装依赖: curl wget sudo socat net-tools psmisc sed grep"
    fi
}


# 验证域名格式
validate_domain() {
    local domain="$1"
    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)+$ ]]; then
        return 1
    fi
    return 0
}


# 验证后端地址格式
validate_backend() {
    local backend="$1"
    if [[ "$backend" =~ ^https?://[a-zA-Z0-9.-]+:[0-9]+$ ]]; then
        return 0
    fi
    if [[ "$backend" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}:[0-9]+$ ]]; then
        local ip="${backend%:*}"
        local valid=true
        IFS='.' read -ra OCTETS <<< "$ip"
        for octet in "${OCTETS[@]}"; do
            if [ "$octet" -gt 255 ] 2>/dev/null; then
                valid=false
                break
            fi
        done
        if $valid; then
            return 0
        fi
    fi
    if [[ "$backend" =~ ^[a-zA-Z0-9.-]+:[0-9]+$ ]]; then
        return 0
    fi
    return 1
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
        
        if command -v caddy &> /dev/null; then
            systemctl enable caddy
            log "Caddy 安装完成！"
        else
            error "Caddy 安装失败，请检查网络或手动安装"
            return 1
        fi
    fi
}


# 5. 配置向导（支持追加）
configure_caddy() {
    echo -e "------------------------------------------------"
    echo -e "${SKYBLUE}Caddy 反代配置 (支持多站点)${PLAIN}"
    echo -e "------------------------------------------------"

    MODE="new"
    if [ -f /etc/caddy/Caddyfile ] && [ -s /etc/caddy/Caddyfile ]; then
        echo -e "检测到已有配置文件。"
        echo -e " ${GREEN}1.${PLAIN} 覆盖 (清空旧配置，仅保留这一个)"
        echo -e " ${GREEN}2.${PLAIN} 追加 (保留旧配置，添加新域名)"
        read -p "请选择模式 [1-2]: " config_mode < /dev/tty
        if [[ "$config_mode" == "2" ]]; then
            MODE="append"
        elif [[ "$config_mode" != "1" ]]; then
            warn "无效选择，将使用覆盖模式"
            MODE="new"
        fi
    fi

    read -p "请输入新域名 (例如 emby2.my.com): " DOMAIN < /dev/tty
    if [[ -z "$DOMAIN" ]]; then error "域名不能为空"; return; fi
    if ! validate_domain "$DOMAIN"; then
        error "域名格式无效，请输入正确的域名（如 emby.my.com）"
        return
    fi

    read -p "请输入后端地址 (如 https://remote.com:443 或 127.0.0.1:8096): " EMBY_ADDRESS < /dev/tty
    [[ -z "$EMBY_ADDRESS" ]] && EMBY_ADDRESS="127.0.0.1:8096"
    if ! validate_backend "$EMBY_ADDRESS"; then
        error "后端地址格式无效，请输入正确的地址（如 127.0.0.1:8096 或 https://remote.com:443）"
        return
    fi

    if [ ! -d /etc/caddy ]; then
        mkdir -p /etc/caddy
    fi
    
    cp /etc/caddy/Caddyfile /etc/caddy/Caddyfile.bak.$(date +%F_%H%M%S) 2>/dev/null

    backup_count=$(ls -1 /etc/caddy/Caddyfile.bak.* 2>/dev/null | wc -l)
    if [ "$backup_count" -gt 5 ]; then
        ls -1t /etc/caddy/Caddyfile.bak.* | tail -n +6 | xargs rm -f 2>/dev/null
        log "已清理旧备份文件"
    fi

    if [[ "$MODE" == "append" ]]; then
        if grep -q "^$DOMAIN {" /etc/caddy/Caddyfile; then
            warn "域名 $DOMAIN 已存在！正在删除旧配置块，写入新配置..."
            sed -i "/^$DOMAIN {/,/^}/d" /etc/caddy/Caddyfile
            sed -i '/^\s*$/d' /etc/caddy/Caddyfile
        fi
    fi

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
        echo "" >> /etc/caddy/Caddyfile
        echo "$CONFIG_BLOCK" >> /etc/caddy/Caddyfile
    fi

    restart_caddy
}


# 6. 删除指定配置
delete_config() {
    echo -e "------------------------------------------------"
    echo -e "${SKYBLUE}删除指定站点配置${PLAIN}"
    echo -e "------------------------------------------------"

    if [ ! -f /etc/caddy/Caddyfile ]; then
        error "未找到配置文件！"
        return
    fi

    echo -e "当前已配置的域名："
    grep -E "^[a-zA-Z0-9.-]+ \{" /etc/caddy/Caddyfile | awk '{print $1}' > /tmp/caddy_domains.txt

    if [ ! -s /tmp/caddy_domains.txt ]; then
        warn "配置文件中未找到有效域名块。"
        return
    fi

    i=1
    domains=()
    while read line; do
        echo -e " ${GREEN}$i.${PLAIN} $line"
        domains+=("$line")
        ((i++))
    done < /tmp/caddy_domains.txt

    echo -e "------------------------------------------------"
    echo -e "请输入要删除的域名编号或完整域名:"
    read -p "请输入数字或域名: " DEL_DOMAIN < /dev/tty
    
    if [[ -z "$DEL_DOMAIN" ]]; then return; fi
    
    if [[ "$DEL_DOMAIN" =~ ^[0-9]+$ ]]; then
        idx=$((DEL_DOMAIN - 1))
        if [[ $idx -ge 0 && $idx -lt ${#domains[@]} ]]; then
            DEL_DOMAIN="${domains[$idx]}"
        else
            error "无效的编号"
            return
        fi
    fi

    echo -e ""
    read -p "确定要删除域名 $DEL_DOMAIN 吗? (y/n): " confirm < /dev/tty
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        log "已取消删除操作"
        return
    fi

    if grep -q "^$DEL_DOMAIN {" /etc/caddy/Caddyfile; then
        cp /etc/caddy/Caddyfile /etc/caddy/Caddyfile.bak.del
        sed -i "/^$DEL_DOMAIN {/,/^}/d" /etc/caddy/Caddyfile
        sed -i '/^\s*$/d' /etc/caddy/Caddyfile
        log "域名 $DEL_DOMAIN 配置已删除。"
        
        if grep -qE "^[a-zA-Z0-9.-]+ \{" /etc/caddy/Caddyfile; then
            restart_caddy
        else
            warn "已删除最后一个域名配置，Caddyfile 已清空。"
            log "正在停止 Caddy 服务..."
            systemctl stop caddy
            if ! systemctl is-active --quiet caddy; then
                echo -e "\n${GREEN}=========================================="
                echo -e " 操作成功！Caddy 服务已停止。"
                echo -e "==========================================${PLAIN}"
            else
                error "停止 Caddy 服务失败！"
            fi
        fi
    else
        error "未找到域名 $DEL_DOMAIN 的配置！请检查拼写。"
    fi
}


restart_caddy() {
    if [ ! -f /etc/caddy/Caddyfile ]; then
        error "Caddyfile 配置文件不存在！"
        return
    fi
    
    if [ ! -s /etc/caddy/Caddyfile ]; then
        warn "Caddyfile 配置文件为空，无法启动 Caddy。"
        log "请先添加域名配置（选项 2）"
        return
    fi
    
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


# 主菜单
show_menu() {
    clear
    echo -e "##########################################################"
    echo -e "#    Caddy + Emby 多站点管理脚本 (V5 Pro) (快捷键c唤出)  #"
    echo -e "##########################################################"
    echo -e " ${GREEN}1.${PLAIN} 安装环境 & Caddy"
    echo -e " ${GREEN}2.${PLAIN} 添加/覆盖 反代配置 (支持多站)"
    echo -e " ${GREEN}3.${PLAIN} 删除指定站点配置"
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
    
    if [[ ! "$num" =~ ^[0-9]$ ]]; then
        error "请输入有效的数字 (0-9)"
        echo -e "\n${GREEN}按回车键返回主菜单...${PLAIN}"
        read temp < /dev/tty
        return
    fi

    case "$num" in
        1) install_base; install_caddy ;;
        2) install_base; configure_caddy ;;
        3) delete_config ;;
        4) cat /etc/caddy/Caddyfile ;;
        5) if systemctl is-active --quiet caddy; then
            systemctl stop caddy
            log "服务已停止"
        else
            warn "Caddy 服务未运行"
        fi ;;
        6) restart_caddy ;;
        7) install_base; check_port ;;
        8) install_base; kill_port ;;
        9) if systemctl is-active --quiet caddy; then
            systemctl stop caddy
           fi
           apt remove caddy -y 2>/dev/null; yum remove caddy -y 2>/dev/null
           rm -rf /etc/caddy
           log "已卸载" ;;
        0) exit 0 ;;
        *) error "请输入正确的数字" ;;
    esac
}


# ===== 入口 =====
register_shortcut

while true; do
    show_menu
    echo -e "\n${GREEN}按回车键返回主菜单...${PLAIN}"
    read temp < /dev/tty
done
