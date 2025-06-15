#!/bin/bash

# 快速开始脚本
# 一键安装依赖并开始部署

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# 显示欢迎信息
show_welcome() {
    clear
    echo -e "${CYAN}"
    cat << 'EOF'
╔════════════════════════════════════════════════════════╗
║                                                        ║
║        FRPS + SSL 快速部署向导                        ║
║                                                        ║
║  🚀 一键部署完整的服务器环境                           ║
║  📦 自动安装所有依赖                                   ║
║  🔐 自动配置SSL证书                                    ║
║  ⚡ 5分钟完成部署                                      ║
║                                                        ║
╚════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    echo -e "${PURPLE}欢迎使用快速部署向导！${NC}"
    echo ""
}

# 收集部署信息
collect_deployment_info() {
    echo -e "${BLUE}=== 第一步：收集部署信息 ===${NC}"
    echo ""
    
    # FRPS域名
    read -p "请输入FRPS服务域名 (例如: frps.example.com): " FRPS_DOMAIN
    while [ -z "$FRPS_DOMAIN" ]; do
        echo -e "${RED}域名不能为空${NC}"
        read -p "请输入FRPS服务域名: " FRPS_DOMAIN
    done
    
    # FRPS管理界面域名
    read -p "请输入FRPS管理界面域名 (例如: admin.example.com，留空跳过): " ADMIN_DOMAIN
    
    
    # 管理员邮箱
    read -p "请输入管理员邮箱 (用于Let's Encrypt): " ADMIN_EMAIL
    while [ -z "$ADMIN_EMAIL" ]; do
        echo -e "${RED}邮箱不能为空${NC}"
        read -p "请输入管理员邮箱: " ADMIN_EMAIL
    done
    
    echo ""
    echo -e "${GREEN}=== 确认部署信息 ===${NC}"
    echo -e "FRPS服务域名: ${YELLOW}$FRPS_DOMAIN${NC}"
    [ -n "$ADMIN_DOMAIN" ] && echo -e "FRPS管理域名: ${YELLOW}$ADMIN_DOMAIN${NC}"
    echo -e "管理员邮箱: ${YELLOW}$ADMIN_EMAIL${NC}"
    echo ""
    
    read -p "确认以上信息正确? (Y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]] && [[ -n $REPLY ]]; then
        echo -e "${YELLOW}请重新运行脚本${NC}"
        exit 1
    fi
}

# 检查DNS解析
check_dns() {
    echo ""
    echo -e "${BLUE}=== 第二步：检查DNS解析 ===${NC}"
    echo ""
    
    local all_good=true
    
    for domain in "$FRPS_DOMAIN" "$ADMIN_DOMAIN"; do
        [ -z "$domain" ] && continue
        
        echo -n "检查 $domain ... "
        if host "$domain" > /dev/null 2>&1 || nslookup "$domain" > /dev/null 2>&1; then
            echo -e "${GREEN}✓ 解析正常${NC}"
        else
            echo -e "${RED}✗ 无法解析${NC}"
            all_good=false
        fi
    done
    
    if [ "$all_good" = false ]; then
        echo ""
        echo -e "${YELLOW}警告: 部分域名无法解析${NC}"
        echo -e "${YELLOW}请确保已添加以下DNS记录:${NC}"
        echo ""
        echo "  A记录: $FRPS_DOMAIN → 您的服务器IP"
        [ -n "$ADMIN_DOMAIN" ] && echo "  A记录: $ADMIN_DOMAIN → 您的服务器IP"
        echo ""
        read -p "是否继续部署? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}请先配置DNS后再运行${NC}"
            exit 1
        fi
    else
        echo -e "${GREEN}所有域名解析正常！${NC}"
    fi
}

# 安装依赖
install_dependencies() {
    echo ""
    echo -e "${BLUE}=== 第三步：安装依赖 ===${NC}"
    echo ""
    
    if [ -x "$SCRIPT_DIR/install-dependencies.sh" ]; then
        "$SCRIPT_DIR/install-dependencies.sh" --quick
    else
        echo -e "${RED}找不到依赖安装脚本${NC}"
        exit 1
    fi
}

# 开始部署
start_deployment() {
    echo ""
    echo -e "${BLUE}=== 第四步：开始部署服务 ===${NC}"
    echo ""
    
    if [ -x "$SCRIPT_DIR/deploy.sh" ]; then
        if [ -n "$ADMIN_DOMAIN" ]; then
            "$SCRIPT_DIR/deploy.sh" deploy "$FRPS_DOMAIN" "$ADMIN_DOMAIN" "$ADMIN_EMAIL"
        else
            "$SCRIPT_DIR/deploy.sh" deploy "$FRPS_DOMAIN" "$ADMIN_EMAIL"
        fi
    else
        echo -e "${RED}找不到部署脚本${NC}"
        exit 1
    fi
}

# 部署后设置
post_deployment() {
    echo ""
    echo -e "${BLUE}=== 第五步：部署后设置 ===${NC}"
    echo ""
    
    # 设置自动续签
    echo -e "${YELLOW}是否设置SSL证书自动续签？${NC}"
    read -p "设置自动续签? (Y/n) " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
        "$SCRIPT_DIR/deploy.sh" setup-cron
    fi
    
    # 显示下一步操作
    echo ""
    echo -e "${GREEN}=== 🎉 部署完成！===${NC}"
    echo ""
    echo -e "${BLUE}下一步操作:${NC}"
    echo ""
    echo "1. 配置FRPS客户端连接到服务器"
    echo "   服务器地址: $FRPS_DOMAIN:7000"
    echo ""
    echo "2. 查看服务状态"
    echo "   运行: ./deploy.sh status"
    echo ""
    echo -e "${YELLOW}需要帮助？查看 README.md 或运行 ./deploy.sh help${NC}"
}

# 主函数
main() {
    show_welcome
    
    # 检查是否在正确的目录
    if [ ! -f "$SCRIPT_DIR/deploy.sh" ]; then
        echo -e "${RED}错误: 请在项目根目录运行此脚本${NC}"
        exit 1
    fi
    
    # 执行部署流程
    collect_deployment_info
    check_dns
    install_dependencies
    start_deployment
    post_deployment
}

# 执行主函数
main