#!/bin/bash

# Node Exporter 自动安装脚本
# 作者: jerry
# 版本: 1.0
# 描述: 自动检测最新版本，下载安装并配置 Node Exporter

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# 检查是否以 root 身份运行
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要以 root 身份运行"
        echo "请使用: sudo $0"
        exit 1
    fi
}

# 获取最新版本信息
get_latest_version() {
    log_step "获取 Node Exporter 最新版本信息..."
    
    # 尝试从 GitHub API 获取最新版本
    if command -v curl >/dev/null 2>&1; then
        LATEST_VERSION=$(curl -s https://api.github.com/repos/prometheus/node_exporter/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' | sed 's/v//')
    elif command -v wget >/dev/null 2>&1; then
        LATEST_VERSION=$(wget -qO- https://api.github.com/repos/prometheus/node_exporter/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' | sed 's/v//')
    else
        log_warn "未找到 curl 或 wget，使用默认版本"
        LATEST_VERSION="1.9.1"
    fi
    
    # 如果获取失败，使用默认版本
    if [[ -z "$LATEST_VERSION" ]]; then
        log_warn "无法获取最新版本，使用默认版本 1.9.1"
        LATEST_VERSION="1.9.1"
    fi
    
    FILENAME="node_exporter-${LATEST_VERSION}.linux-amd64"
    DOWNLOAD_URL="https://github.com/prometheus/node_exporter/releases/download/v${LATEST_VERSION}/${FILENAME}.tar.gz"
    
    log_info "检测到最新版本: ${LATEST_VERSION}"
}

# 检查并安装依赖
install_dependencies() {
    log_step "检查系统依赖..."
    
    # 检查系统类型
    if command -v apt-get >/dev/null 2>&1; then
        PKG_MANAGER="apt-get"
        if ! command -v wget >/dev/null 2>&1 && ! command -v curl >/dev/null 2>&1; then
            log_info "安装下载工具..."
            apt-get update -qq
            apt-get install -y wget curl
        fi
    elif command -v yum >/dev/null 2>&1; then
        PKG_MANAGER="yum"
        if ! command -v wget >/dev/null 2>&1 && ! command -v curl >/dev/null 2>&1; then
            log_info "安装下载工具..."
            yum install -y wget curl
        fi
    elif command -v dnf >/dev/null 2>&1; then
        PKG_MANAGER="dnf"
        if ! command -v wget >/dev/null 2>&1 && ! command -v curl >/dev/null 2>&1; then
            log_info "安装下载工具..."
            dnf install -y wget curl
        fi
    else
        log_warn "未识别的包管理器，请确保已安装 wget 或 curl"
    fi
}

# 检查文件是否已存在
check_existing_file() {
    log_step "检查已存在的文件..."
    
    cd /tmp
    
    if [[ -f "${FILENAME}.tar.gz" ]]; then
        log_info "发现已下载的文件: ${FILENAME}.tar.gz"
        echo -n "是否重新下载？(y/N): "
        read -r REDOWNLOAD
        if [[ $REDOWNLOAD =~ ^[Yy]$ ]]; then
            rm -f "${FILENAME}.tar.gz"
            NEED_DOWNLOAD=true
        else
            NEED_DOWNLOAD=false
        fi
    else
        NEED_DOWNLOAD=true
    fi
    
    if [[ -d "$FILENAME" ]]; then
        log_info "发现已解压的目录: $FILENAME"
        echo -n "是否重新解压？(y/N): "
        read -r REEXTRACT
        if [[ $REEXTRACT =~ ^[Yy]$ ]]; then
            rm -rf "$FILENAME"
            NEED_EXTRACT=true
        else
            NEED_EXTRACT=false
        fi
    else
        NEED_EXTRACT=true
    fi
}

# 下载 Node Exporter
download_node_exporter() {
    if [[ $NEED_DOWNLOAD == true ]]; then
        log_step "下载 Node Exporter ${LATEST_VERSION}..."
        
        if command -v wget >/dev/null 2>&1; then
            wget -O "${FILENAME}.tar.gz" "$DOWNLOAD_URL"
        elif command -v curl >/dev/null 2>&1; then
            curl -L -o "${FILENAME}.tar.gz" "$DOWNLOAD_URL"
        else
            log_error "未找到下载工具 (wget 或 curl)"
            exit 1
        fi
        
        # 验证下载是否成功
        if [[ ! -f "${FILENAME}.tar.gz" ]] || [[ ! -s "${FILENAME}.tar.gz" ]]; then
            log_error "下载失败或文件为空"
            exit 1
        fi
        
        log_info "下载完成"
    else
        log_info "跳过下载，使用已存在的文件"
    fi
}

# 解压文件
extract_file() {
    if [[ $NEED_EXTRACT == true ]]; then
        log_step "解压文件..."
        tar xzf "${FILENAME}.tar.gz"
        
        if [[ ! -d "$FILENAME" ]]; then
            log_error "解压失败，未找到目录 $FILENAME"
            exit 1
        fi
        
        log_info "解压完成"
    else
        log_info "跳过解压，使用已存在的目录"
    fi
}

# 创建用户
create_user() {
    log_step "配置运行用户..."
    
    echo -e "\n${BLUE}用户配置选项:${NC}"
    echo "1. 使用专用用户 node_exporter (推荐，无登录权限)"
    echo "2. 使用 root 用户 (简单但不安全)"
    echo "3. 创建自定义用户"
    echo -n "请选择 [1-3]: "
    read -r USER_CHOICE
    
    case $USER_CHOICE in
        1)
            SERVICE_USER="node_exporter"
            if id "$SERVICE_USER" &>/dev/null; then
                log_info "用户 $SERVICE_USER 已存在"
            else
                log_info "创建专用用户: $SERVICE_USER"
                useradd --no-create-home --shell /bin/false "$SERVICE_USER"
            fi
            ;;
        2)
            SERVICE_USER="root"
            log_warn "使用 root 用户运行 (不推荐用于生产环境)"
            ;;
        3)
            echo -n "请输入用户名: "
            read -r SERVICE_USER
            
            if id "$SERVICE_USER" &>/dev/null; then
                log_info "用户 $SERVICE_USER 已存在"
            else
                echo -n "是否创建为系统用户 (无登录权限)? (Y/n): "
                read -r IS_SYSTEM_USER
                
                if [[ $IS_SYSTEM_USER =~ ^[Nn]$ ]]; then
                    # 创建普通用户
                    log_info "创建普通用户: $SERVICE_USER"
                    echo -n "请输入密码: "
                    read -s USER_PASSWORD
                    echo
                    useradd -m -s /bin/bash "$SERVICE_USER"
                    echo "$SERVICE_USER:$USER_PASSWORD" | chpasswd
                    log_info "用户 $SERVICE_USER 创建完成"
                else
                    # 创建系统用户
                    log_info "创建系统用户: $SERVICE_USER"
                    useradd --no-create-home --shell /bin/false "$SERVICE_USER"
                fi
            fi
            ;;
        *)
            log_error "无效选择，使用默认用户 node_exporter"
            SERVICE_USER="node_exporter"
            if ! id "$SERVICE_USER" &>/dev/null; then
                useradd --no-create-home --shell /bin/false "$SERVICE_USER"
            fi
            ;;
    esac
    
    SERVICE_GROUP="$SERVICE_USER"
}

# 安装二进制文件
install_binary() {
    log_step "安装 Node Exporter 二进制文件..."
    
    # 复制二进制文件
    cp "${FILENAME}/node_exporter" /usr/local/bin/
    chown root:root /usr/local/bin/node_exporter
    chmod +x /usr/local/bin/node_exporter
    
    # 验证安装
    if /usr/local/bin/node_exporter --version >/dev/null 2>&1; then
        log_info "Node Exporter 安装成功"
        /usr/local/bin/node_exporter --version
    else
        log_error "Node Exporter 安装失败"
        exit 1
    fi
}

# 创建 systemd 服务
create_service() {
    log_step "创建 systemd 服务..."
    
    cat > /etc/systemd/system/node_exporter.service << EOF
[Unit]
Description=Node Exporter
Documentation=https://prometheus.io/docs/guides/node-exporter/
Wants=network-online.target
After=network-online.target

[Service]
User=$SERVICE_USER
Group=$SERVICE_GROUP
Type=simple
Restart=on-failure
RestartSec=5s
ExecStart=/usr/local/bin/node_exporter \\
    --web.listen-address=:9100 \\
    --path.procfs=/proc \\
    --path.sysfs=/sys \\
    --collector.filesystem.mount-points-exclude='^/(sys|proc|dev|host|etc|rootfs/var/lib/docker/containers|rootfs/var/lib/docker/overlay2|rootfs/run/docker/netns|rootfs/var/lib/docker/aufs)($$|/)'

[Install]
WantedBy=multi-user.target
EOF
    
    log_info "systemd 服务文件创建完成"
}

# 启动服务
start_service() {
    log_step "启动 Node Exporter 服务..."
    
    # 重新加载 systemd
    systemctl daemon-reload
    
    # 启用开机自启
    systemctl enable node_exporter
    
    # 启动服务
    systemctl start node_exporter
    
    # 等待服务启动
    sleep 3
    
    # 检查服务状态
    if systemctl is-active --quiet node_exporter; then
        log_info "Node Exporter 服务启动成功"
        systemctl status node_exporter --no-pager -l
    else
        log_error "Node Exporter 服务启动失败"
        log_error "查看日志: journalctl -u node_exporter -f"
        exit 1
    fi
}

# 验证安装
verify_installation() {
    log_step "验证安装..."
    
    # 检查端口监听
    if ss -tlnp | grep -q ":9100"; then
        log_info "✓ 端口 9100 正在监听"
    else
        log_warn "✗ 端口 9100 未监听"
    fi
    
    # 检查 metrics 端点
    sleep 2
    if curl -s http://localhost:9100/metrics >/dev/null 2>&1; then
        log_info "✓ metrics 端点响应正常"
        echo -e "\n${GREEN}安装完成！${NC}"
        echo -e "Node Exporter 已在端口 9100 上运行"
        echo -e "访问: http://$(hostname -I | awk '{print $1}'):9100/metrics"
    elif wget -q -O /dev/null http://localhost:9100/metrics >/dev/null 2>&1; then
        log_info "✓ metrics 端点响应正常"
        echo -e "\n${GREEN}安装完成！${NC}"
        echo -e "Node Exporter 已在端口 9100 上运行"
        echo -e "访问: http://$(hostname -I | awk '{print $1}'):9100/metrics"
    else
        log_warn "✗ metrics 端点无响应"
        log_warn "请检查服务状态: systemctl status node_exporter"
    fi
    
    echo -e "\n${BLUE}常用命令:${NC}"
    echo "查看状态: systemctl status node_exporter"
    echo "查看日志: journalctl -u node_exporter -f"
    echo "重启服务: systemctl restart node_exporter"
    echo "停止服务: systemctl stop node_exporter"
}

# 清理临时文件
cleanup() {
    log_step "清理临时文件..."
    
    echo -n "是否删除下载的临时文件？(Y/n): "
    read -r CLEANUP_CHOICE
    
    if [[ ! $CLEANUP_CHOICE =~ ^[Nn]$ ]]; then
        cd /tmp
        rm -rf "${FILENAME}" "${FILENAME}.tar.gz"
        log_info "临时文件已清理"
    else
        log_info "保留临时文件在 /tmp/${FILENAME}"
    fi
}

# 主函数
main() {
    echo -e "${GREEN}"
    echo "=================================="
    echo "  Node Exporter 自动安装脚本"
    echo "=================================="
    echo -e "${NC}"
    
    check_root
    install_dependencies
    get_latest_version
    check_existing_file
    download_node_exporter
    extract_file
    create_user
    install_binary
    create_service
    start_service
    verify_installation
    cleanup
    
    echo -e "\n${GREEN}🎉 Node Exporter 安装完成！${NC}"
}

# 脚本入口
main "$@"