#!/bin/bash

# 依赖安装脚本
# 自动检测并安装 Docker 和 Docker Compose

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

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

# 显示横幅
show_banner() {
    echo -e "${CYAN}"
    cat << 'EOF'
╔════════════════════════════════════════╗
║          依赖安装检查工具              ║
║                                        ║
║  自动检测并安装:                       ║
║  • Docker                              ║
║  • Docker Compose                      ║
║  • 其他必要工具                        ║
╚════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

# 检测操作系统
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
        DISTRO=$ID
    elif type lsb_release >/dev/null 2>&1; then
        OS=$(lsb_release -si)
        VER=$(lsb_release -sr)
        DISTRO=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
    elif [ -f /etc/lsb-release ]; then
        . /etc/lsb-release
        OS=$DISTRIB_ID
        VER=$DISTRIB_RELEASE
        DISTRO=$(echo $DISTRIB_ID | tr '[:upper:]' '[:lower:]')
    elif [ -f /etc/debian_version ]; then
        OS=Debian
        VER=$(cat /etc/debian_version)
        DISTRO=debian
    elif [ -f /etc/redhat-release ]; then
        OS=RedHat
        DISTRO=centos
    else
        OS=$(uname -s)
        VER=$(uname -r)
        DISTRO=unknown
    fi
    
    log_info "检测到操作系统: $OS $VER ($DISTRO)"
}

# 检查是否有 sudo 权限
check_sudo() {
    if [ "$EUID" -ne 0 ]; then 
        if ! command -v sudo &> /dev/null; then
            log_error "需要 root 权限安装依赖，但系统没有 sudo"
            log_error "请以 root 用户运行此脚本"
            exit 1
        fi
        SUDO="sudo"
    else
        SUDO=""
    fi
}

# 安装 Docker - Ubuntu/Debian
install_docker_debian() {
    log_info "在 Debian/Ubuntu 上安装 Docker..."
    
    # 更新包索引
    $SUDO apt-get update
    
    # 安装必要的包
    $SUDO apt-get install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release
    
    # 添加 Docker 官方 GPG 密钥
    curl -fsSL https://download.docker.com/linux/$DISTRO/gpg | $SUDO gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    
    # 设置稳定版仓库
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/$DISTRO \
        $(lsb_release -cs) stable" | $SUDO tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # 安装 Docker Engine
    $SUDO apt-get update
    $SUDO apt-get install -y docker-ce docker-ce-cli containerd.io
    
    # 启动 Docker
    $SUDO systemctl start docker
    $SUDO systemctl enable docker
    
    log_info "Docker 安装完成"
}

# 安装 Docker - CentOS/RHEL
install_docker_centos() {
    log_info "在 CentOS/RHEL 上安装 Docker..."
    
    # 移除旧版本
    $SUDO yum remove -y docker \
                        docker-client \
                        docker-client-latest \
                        docker-common \
                        docker-latest \
                        docker-latest-logrotate \
                        docker-logrotate \
                        docker-engine
    
    # 安装必要的包
    $SUDO yum install -y yum-utils
    
    # 添加 Docker 仓库
    $SUDO yum-config-manager \
        --add-repo \
        https://download.docker.com/linux/centos/docker-ce.repo
    
    # 安装 Docker Engine
    $SUDO yum install -y docker-ce docker-ce-cli containerd.io
    
    # 启动 Docker
    $SUDO systemctl start docker
    $SUDO systemctl enable docker
    
    log_info "Docker 安装完成"
}

# 安装 Docker Compose
install_docker_compose() {
    log_info "安装 Docker Compose..."
    
    # 获取最新版本
    COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep -Po '"tag_name": "\K.*?(?=")' || echo "v2.23.0")
    
    # 下载 Docker Compose
    $SUDO curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    
    # 添加执行权限
    $SUDO chmod +x /usr/local/bin/docker-compose
    
    # 创建软链接
    $SUDO ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
    
    log_info "Docker Compose 安装完成"
}

# 安装其他必要工具
install_other_tools() {
    log_info "安装其他必要工具..."
    
    case "$DISTRO" in
        ubuntu|debian)
            $SUDO apt-get install -y \
                curl \
                wget \
                openssl \
                git \
                htop \
                net-tools
            ;;
        centos|rhel|fedora)
            $SUDO yum install -y \
                curl \
                wget \
                openssl \
                git \
                htop \
                net-tools
            ;;
        *)
            log_warn "未知的发行版，跳过额外工具安装"
            ;;
    esac
}

# 配置 Docker 用户组
configure_docker_group() {
    if [ "$EUID" -ne 0 ]; then
        log_info "将当前用户添加到 docker 组..."
        $SUDO usermod -aG docker $USER
        log_warn "请注销并重新登录以使组权限生效"
        log_warn "或运行: newgrp docker"
    fi
}

# 验证安装
verify_installation() {
    log_info "验证安装..."
    
    echo ""
    echo -e "${BLUE}=== 安装状态 ===${NC}"
    echo ""
    
    # 检查 Docker
    if command -v docker &> /dev/null; then
        DOCKER_VERSION=$(docker --version)
        echo -e "Docker: ${GREEN}✓ 已安装${NC} - $DOCKER_VERSION"
        
        # 检查 Docker 服务状态
        if $SUDO systemctl is-active --quiet docker; then
            echo -e "Docker 服务: ${GREEN}✓ 运行中${NC}"
        else
            echo -e "Docker 服务: ${RED}✗ 未运行${NC}"
            $SUDO systemctl start docker
        fi
    else
        echo -e "Docker: ${RED}✗ 未安装${NC}"
    fi
    
    # 检查 Docker Compose
    if command -v docker-compose &> /dev/null; then
        COMPOSE_VERSION=$(docker-compose --version)
        echo -e "Docker Compose: ${GREEN}✓ 已安装${NC} - $COMPOSE_VERSION"
    elif docker compose version &> /dev/null; then
        COMPOSE_VERSION=$(docker compose version)
        echo -e "Docker Compose (Plugin): ${GREEN}✓ 已安装${NC} - $COMPOSE_VERSION"
    else
        echo -e "Docker Compose: ${RED}✗ 未安装${NC}"
    fi
    
    # 检查其他工具
    for tool in curl wget openssl git; do
        if command -v $tool &> /dev/null; then
            echo -e "$tool: ${GREEN}✓ 已安装${NC}"
        else
            echo -e "$tool: ${RED}✗ 未安装${NC}"
        fi
    done
    
    echo ""
}

# 主安装函数
main_install() {
    local install_docker=false
    local install_compose=false
    
    # 检查 Docker
    if ! command -v docker &> /dev/null; then
        log_warn "Docker 未安装"
        install_docker=true
    else
        log_info "Docker 已安装: $(docker --version)"
    fi
    
    # 检查 Docker Compose
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        log_warn "Docker Compose 未安装"
        install_compose=true
    else
        log_info "Docker Compose 已安装"
    fi
    
    # 如果都已安装，直接返回
    if [ "$install_docker" = false ] && [ "$install_compose" = false ]; then
        log_info "所有依赖已安装"
        verify_installation
        return 0
    fi
    
    # 询问是否安装
    echo ""
    echo -e "${YELLOW}需要安装以下组件:${NC}"
    [ "$install_docker" = true ] && echo "  - Docker"
    [ "$install_compose" = true ] && echo "  - Docker Compose"
    echo ""
    
    read -p "是否继续安装? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_warn "安装已取消"
        exit 1
    fi
    
    # 安装 Docker
    if [ "$install_docker" = true ]; then
        case "$DISTRO" in
            ubuntu|debian)
                install_docker_debian
                ;;
            centos|rhel|fedora)
                install_docker_centos
                ;;
            *)
                log_error "不支持的操作系统: $DISTRO"
                log_error "请手动安装 Docker: https://docs.docker.com/get-docker/"
                exit 1
                ;;
        esac
    fi
    
    # 安装 Docker Compose
    if [ "$install_compose" = true ]; then
        install_docker_compose
    fi
    
    # 安装其他工具
    install_other_tools
    
    # 配置用户组
    configure_docker_group
    
    # 验证安装
    verify_installation
}

# 快速安装模式
quick_install() {
    log_info "快速安装模式 - 自动安装所有依赖"
    
    # 安装 Docker
    if ! command -v docker &> /dev/null; then
        case "$DISTRO" in
            ubuntu|debian)
                install_docker_debian
                ;;
            centos|rhel|fedora)
                install_docker_centos
                ;;
            *)
                log_error "不支持的操作系统，请手动安装"
                exit 1
                ;;
        esac
    fi
    
    # 安装 Docker Compose
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        install_docker_compose
    fi
    
    # 安装其他工具
    install_other_tools
    
    # 配置用户组
    configure_docker_group
    
    # 验证安装
    verify_installation
}

# 显示用法
show_usage() {
    cat << EOF
依赖安装脚本

用法:
    $0 [选项]

选项:
    无参数        交互式安装模式
    --quick      快速安装模式（自动安装所有依赖）
    --check      仅检查依赖状态
    --help       显示帮助

示例:
    $0           # 交互式安装
    $0 --quick   # 自动安装所有依赖
    $0 --check   # 检查安装状态

支持的操作系统:
    - Ubuntu 18.04+
    - Debian 9+
    - CentOS 7+
    - RHEL 7+
    - Fedora 30+
EOF
}

# 主函数
main() {
    show_banner
    detect_os
    check_sudo
    
    case "${1:-}" in
        "--quick")
            quick_install
            ;;
        "--check")
            verify_installation
            ;;
        "--help"|"-h")
            show_usage
            ;;
        *)
            main_install
            ;;
    esac
}

# 执行主函数
main "$@"