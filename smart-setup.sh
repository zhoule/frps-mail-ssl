#!/bin/bash

# FRPS 智能配置向导
# 提供交互式配置和智能建议

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# 配置变量
SETUP_CONFIG=()
DEPLOYMENT_TYPE=""
DOMAIN_CONFIG=()
SSL_TYPE=""
MONITORING_ENABLED=false
SECURITY_LEVEL=""

# 输出函数
print_header() {
    clear
    echo -e "${CYAN}"
    cat << 'EOF'
╔════════════════════════════════════════════════════════════╗
║                                                            ║
║               FRPS 智能部署向导 v2.0                      ║
║                                                            ║
║  🧠 智能推荐 | 🔧 自动配置 | ⚡ 一键部署 | 📊 监控集成     ║
║                                                            ║
╚════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

print_step() {
    echo -e "\n${PURPLE}=== $1 ===${NC}\n"
}

print_info() {
    echo -e "${BLUE}💡 $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# 输入验证函数
validate_domain() {
    local domain="$1"
    if [[ $domain =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        return 0
    else
        return 1
    fi
}

validate_email() {
    local email="$1"
    if [[ $email =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        return 0
    else
        return 1
    fi
}

check_dns_resolution() {
    local domain="$1"
    if host "$domain" >/dev/null 2>&1 || nslookup "$domain" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# 系统环境检测
detect_environment() {
    print_step "环境检测"
    
    local os_info=""
    local memory_gb=""
    local cpu_cores=""
    local disk_space=""
    local public_ip=""
    
    # 检测操作系统
    if [ -f /etc/os-release ]; then
        source /etc/os-release
        os_info="$NAME $VERSION"
    else
        os_info=$(uname -s)
    fi
    
    # 检测硬件资源
    memory_gb=$(free -g | awk '/^Mem:/ {print $2}')
    cpu_cores=$(nproc)
    disk_space=$(df -h . | awk 'NR==2{print $4}')
    
    # 获取公网IP
    public_ip=$(curl -s ifconfig.me 2>/dev/null || curl -s ipinfo.io/ip 2>/dev/null || echo "未知")
    
    echo -e "${WHITE}系统信息：${NC}"
    echo "  操作系统: $os_info"
    echo "  CPU核心: $cpu_cores"
    echo "  内存: ${memory_gb}GB"
    echo "  可用磁盘: $disk_space"
    echo "  公网IP: $public_ip"
    echo ""
    
    # 根据环境给出建议
    if [ "$memory_gb" -lt 2 ]; then
        print_warning "内存不足2GB，建议升级服务器配置"
    fi
    
    if [ "$cpu_cores" -lt 2 ]; then
        print_warning "CPU核心数较少，可能影响并发性能"
    fi
    
    print_info "环境检测完成，系统满足部署要求"
}

# 部署类型选择
choose_deployment_type() {
    print_step "选择部署类型"
    
    echo -e "${WHITE}请选择适合您的部署类型：${NC}"
    echo ""
    echo "1. 🏠 个人/小团队 (单域名，简单配置)"
    echo "2. 🏢 企业/多项目 (多域名，高可用)"
    echo "3. 🌟 泛域名方案 (无限子域名，自动SSL)"
    echo "4. 🔧 自定义配置 (高级用户)"
    echo ""
    
    while true; do
        read -p "请选择 [1-4]: " choice
        case $choice in
            1)
                DEPLOYMENT_TYPE="personal"
                print_success "已选择：个人/小团队部署"
                break
                ;;
            2)
                DEPLOYMENT_TYPE="enterprise"
                print_success "已选择：企业/多项目部署"
                break
                ;;
            3)
                DEPLOYMENT_TYPE="wildcard"
                print_success "已选择：泛域名方案"
                break
                ;;
            4)
                DEPLOYMENT_TYPE="custom"
                print_success "已选择：自定义配置"
                break
                ;;
            *)
                print_error "请输入有效选项 [1-4]"
                ;;
        esac
    done
}

# 域名配置
configure_domains() {
    print_step "域名配置"
    
    case $DEPLOYMENT_TYPE in
        "personal")
            configure_personal_domain
            ;;
        "enterprise")
            configure_enterprise_domains
            ;;
        "wildcard")
            configure_wildcard_domain
            ;;
        "custom")
            configure_custom_domains
            ;;
    esac
}

configure_personal_domain() {
    echo -e "${WHITE}个人/小团队配置：${NC}"
    echo "只需要一个主域名，系统会自动为管理界面创建子域名"
    echo ""
    
    while true; do
        read -p "请输入您的域名 (例如: frps.example.com): " main_domain
        
        if validate_domain "$main_domain"; then
            if check_dns_resolution "$main_domain"; then
                print_success "域名 $main_domain 解析正常"
                DOMAIN_CONFIG=("$main_domain" "admin-$main_domain")
                break
            else
                print_warning "域名 $main_domain 无法解析"
                echo "请确保已添加 A 记录指向您的服务器IP"
                read -p "是否继续？(y/N): " continue_anyway
                if [[ $continue_anyway =~ ^[Yy]$ ]]; then
                    DOMAIN_CONFIG=("$main_domain" "admin-$main_domain")
                    break
                fi
            fi
        else
            print_error "域名格式不正确，请重新输入"
        fi
    done
    
    print_info "将使用以下域名配置："
    echo "  FRPS服务: ${DOMAIN_CONFIG[0]}"
    echo "  管理界面: ${DOMAIN_CONFIG[1]}"
}

configure_enterprise_domains() {
    echo -e "${WHITE}企业/多项目配置：${NC}"
    echo "支持多个独立域名，每个项目都有独立的访问地址"
    echo ""
    
    DOMAIN_CONFIG=()
    
    # 主服务域名
    while true; do
        read -p "请输入FRPS主服务域名: " main_domain
        if validate_domain "$main_domain"; then
            DOMAIN_CONFIG+=("$main_domain")
            break
        else
            print_error "域名格式不正确"
        fi
    done
    
    # 管理界面域名
    while true; do
        read -p "请输入管理界面域名 (留空使用子域名): " admin_domain
        if [ -z "$admin_domain" ]; then
            admin_domain="admin-$main_domain"
            break
        elif validate_domain "$admin_domain"; then
            break
        else
            print_error "域名格式不正确"
        fi
    done
    DOMAIN_CONFIG+=("$admin_domain")
    
    # 额外的项目域名
    echo ""
    echo "您可以添加额外的项目域名（可选）:"
    while true; do
        read -p "输入项目域名 (留空结束): " project_domain
        if [ -z "$project_domain" ]; then
            break
        elif validate_domain "$project_domain"; then
            DOMAIN_CONFIG+=("$project_domain")
            print_success "已添加: $project_domain"
        else
            print_error "域名格式不正确"
        fi
    done
    
    print_info "企业域名配置："
    for i in "${!DOMAIN_CONFIG[@]}"; do
        echo "  域名 $((i+1)): ${DOMAIN_CONFIG[$i]}"
    done
}

configure_wildcard_domain() {
    echo -e "${WHITE}泛域名配置：${NC}"
    echo "使用泛域名证书，支持无限子域名自动SSL"
    echo ""
    
    while true; do
        read -p "请输入根域名 (例如: example.com): " root_domain
        
        if validate_domain "$root_domain"; then
            DOMAIN_CONFIG=("$root_domain")
            print_success "根域名设置为: $root_domain"
            print_info "将支持所有 *.${root_domain} 子域名"
            break
        else
            print_error "域名格式不正确"
        fi
    done
    
    echo ""
    echo -e "${YELLOW}重要提醒：${NC}"
    echo "1. 需要配置DNS泛域名解析: *.${root_domain} -> 服务器IP"
    echo "2. 需要支持DNS-01验证的证书申请方式"
    echo "3. 建议使用 Cloudflare 或阿里云 DNS 服务"
}

configure_custom_domains() {
    echo -e "${WHITE}自定义配置：${NC}"
    echo "高级用户可以完全自定义域名配置"
    echo ""
    
    DOMAIN_CONFIG=()
    
    echo "请逐个输入需要配置的域名："
    while true; do
        read -p "输入域名 (留空结束): " domain
        if [ -z "$domain" ]; then
            break
        elif validate_domain "$domain"; then
            DOMAIN_CONFIG+=("$domain")
            print_success "已添加: $domain"
        else
            print_error "域名格式不正确"
        fi
    done
    
    if [ ${#DOMAIN_CONFIG[@]} -eq 0 ]; then
        print_error "至少需要一个域名"
        configure_custom_domains
        return
    fi
    
    print_info "自定义域名配置："
    for i in "${!DOMAIN_CONFIG[@]}"; do
        echo "  域名 $((i+1)): ${DOMAIN_CONFIG[$i]}"
    done
}

# SSL证书类型选择
choose_ssl_type() {
    print_step "SSL证书配置"
    
    case $DEPLOYMENT_TYPE in
        "personal"|"enterprise")
            echo -e "${WHITE}为您推荐：SAN多域名证书${NC}"
            echo "✅ 配置简单，一个证书支持多个域名"
            echo "✅ 适合固定域名数量的场景"
            SSL_TYPE="san"
            print_success "已选择：SAN多域名证书"
            ;;
        "wildcard")
            echo -e "${WHITE}泛域名方案必须使用：泛域名证书${NC}"
            echo "✅ 支持无限子域名"
            echo "✅ frpc客户端subdomain自动SSL"
            SSL_TYPE="wildcard"
            print_success "已选择：泛域名证书"
            ;;
        "custom")
            echo -e "${WHITE}请选择SSL证书类型：${NC}"
            echo ""
            echo "1. SAN多域名证书 (适合固定域名)"
            echo "2. 泛域名证书 (支持无限子域名)"
            echo ""
            
            while true; do
                read -p "请选择 [1-2]: " choice
                case $choice in
                    1)
                        SSL_TYPE="san"
                        print_success "已选择：SAN多域名证书"
                        break
                        ;;
                    2)
                        SSL_TYPE="wildcard"
                        print_success "已选择：泛域名证书"
                        break
                        ;;
                    *)
                        print_error "请输入有效选项 [1-2]"
                        ;;
                esac
            done
            ;;
    esac
    
    # 获取邮箱地址
    while true; do
        read -p "请输入Let's Encrypt注册邮箱: " email
        if validate_email "$email"; then
            LETSENCRYPT_EMAIL="$email"
            print_success "邮箱设置为: $email"
            break
        else
            print_error "邮箱格式不正确"
        fi
    done
}

# 安全级别配置
configure_security() {
    print_step "安全级别配置"
    
    echo -e "${WHITE}请选择安全级别：${NC}"
    echo ""
    echo "1. 🔒 基础安全 (默认配置)"
    echo "2. 🛡️  增强安全 (推荐)"
    echo "3. 🏰 最高安全 (企业级)"
    echo ""
    
    while true; do
        read -p "请选择 [1-3]: " choice
        case $choice in
            1)
                SECURITY_LEVEL="basic"
                print_success "已选择：基础安全级别"
                break
                ;;
            2)
                SECURITY_LEVEL="enhanced"
                print_success "已选择：增强安全级别"
                break
                ;;
            3)
                SECURITY_LEVEL="maximum"
                print_success "已选择：最高安全级别"
                break
                ;;
            *)
                print_error "请输入有效选项 [1-3]"
                ;;
        esac
    done
    
    case $SECURITY_LEVEL in
        "basic")
            echo "  ✅ SSL/TLS加密"
            echo "  ✅ 基础防火墙规则"
            ;;
        "enhanced")
            echo "  ✅ SSL/TLS加密"
            echo "  ✅ 增强防火墙规则"
            echo "  ✅ 请求频率限制"
            echo "  ✅ 安全头设置"
            ;;
        "maximum")
            echo "  ✅ SSL/TLS加密"
            echo "  ✅ 最严格防火墙规则"
            echo "  ✅ 请求频率限制"
            echo "  ✅ 完整安全头设置"
            echo "  ✅ 容器安全加固"
            echo "  ✅ 文件权限严格控制"
            ;;
    esac
}

# 监控配置
configure_monitoring() {
    print_step "监控和告警配置"
    
    echo -e "${WHITE}是否启用服务监控？${NC}"
    echo "监控功能可以实时检查服务状态，并在异常时发送告警"
    echo ""
    
    read -p "启用监控？(Y/n): " enable_monitoring
    if [[ $enable_monitoring =~ ^[Nn]$ ]]; then
        MONITORING_ENABLED=false
        print_info "已跳过监控配置"
        return
    fi
    
    MONITORING_ENABLED=true
    print_success "已启用监控功能"
    
    echo ""
    echo "配置告警方式 (可选):"
    
    # 邮件告警
    read -p "邮件告警地址 (留空跳过): " alert_email
    if [ -n "$alert_email" ] && validate_email "$alert_email"; then
        ALERT_EMAIL="$alert_email"
        print_success "邮件告警已配置"
    fi
    
    # Webhook告警
    read -p "Webhook URL (Slack/Discord等，留空跳过): " webhook_url
    if [ -n "$webhook_url" ]; then
        WEBHOOK_URL="$webhook_url"
        print_success "Webhook告警已配置"
    fi
}

# 配置确认
confirm_configuration() {
    print_step "配置确认"
    
    echo -e "${WHITE}请确认您的配置：${NC}"
    echo ""
    echo "部署类型: $DEPLOYMENT_TYPE"
    echo "域名配置:"
    for domain in "${DOMAIN_CONFIG[@]}"; do
        echo "  - $domain"
    done
    echo "SSL类型: $SSL_TYPE"
    echo "安全级别: $SECURITY_LEVEL"
    echo "监控功能: $([ "$MONITORING_ENABLED" = true ] && echo "启用" || echo "禁用")"
    echo ""
    
    read -p "确认配置并开始部署？(Y/n): " confirm
    if [[ $confirm =~ ^[Nn]$ ]]; then
        print_warning "部署已取消"
        exit 0
    fi
    
    print_success "配置确认完成，开始部署..."
}

# 执行部署
execute_deployment() {
    print_step "执行部署"
    
    # 创建部署命令
    local deploy_cmd="./deploy.sh"
    
    case $DEPLOYMENT_TYPE in
        "personal")
            deploy_cmd="$deploy_cmd deploy ${DOMAIN_CONFIG[0]} ${DOMAIN_CONFIG[1]} $LETSENCRYPT_EMAIL"
            ;;
        "enterprise")
            if [ ${#DOMAIN_CONFIG[@]} -eq 2 ]; then
                deploy_cmd="$deploy_cmd deploy ${DOMAIN_CONFIG[0]} ${DOMAIN_CONFIG[1]} $LETSENCRYPT_EMAIL"
            else
                deploy_cmd="$deploy_cmd deploy ${DOMAIN_CONFIG[0]} $LETSENCRYPT_EMAIL"
            fi
            ;;
        "wildcard")
            deploy_cmd="$deploy_cmd wildcard ${DOMAIN_CONFIG[0]} $LETSENCRYPT_EMAIL cloudflare"
            ;;
        "custom")
            deploy_cmd="$deploy_cmd deploy ${DOMAIN_CONFIG[0]} $LETSENCRYPT_EMAIL"
            ;;
    esac
    
    print_info "执行命令: $deploy_cmd"
    echo ""
    
    # 执行部署
    if eval "$deploy_cmd"; then
        print_success "部署完成！"
    else
        print_error "部署失败，请检查错误信息"
        return 1
    fi
    
    # 应用安全配置
    if [ "$SECURITY_LEVEL" != "basic" ]; then
        print_info "应用安全配置..."
        if [ -f "$SCRIPT_DIR/security-enhancements.sh" ]; then
            "$SCRIPT_DIR/security-enhancements.sh" all
            print_success "安全配置已应用"
        fi
    fi
    
    # 启用监控
    if [ "$MONITORING_ENABLED" = true ]; then
        print_info "配置监控系统..."
        if [ -f "$SCRIPT_DIR/monitoring-alerts.sh" ]; then
            "$SCRIPT_DIR/monitoring-alerts.sh" init
            
            # 写入告警配置
            if [ -n "$ALERT_EMAIL" ]; then
                sed -i "s/ALERT_EMAIL=\"\"/ALERT_EMAIL=\"$ALERT_EMAIL\"/" "$SCRIPT_DIR/monitoring.conf"
            fi
            
            if [ -n "$WEBHOOK_URL" ]; then
                sed -i "s|WEBHOOK_URL=\"\"|WEBHOOK_URL=\"$WEBHOOK_URL\"|" "$SCRIPT_DIR/monitoring.conf"
            fi
            
            print_success "监控系统已配置"
        fi
    fi
}

# 显示部署后指导
show_post_deployment_guide() {
    print_step "部署完成指导"
    
    echo -e "${GREEN}🎉 恭喜！FRPS服务部署成功！${NC}"
    echo ""
    
    echo -e "${WHITE}访问地址：${NC}"
    for domain in "${DOMAIN_CONFIG[@]}"; do
        echo "  🌐 https://$domain"
    done
    echo ""
    
    echo -e "${WHITE}配置信息：${NC}"
    echo "  🔑 查看完整配置: ./secret-utils.sh info"
    echo "  📊 服务状态: ./deploy.sh status"
    echo "  🏥 健康检查: ./health-check.sh"
    echo ""
    
    echo -e "${WHITE}客户端配置：${NC}"
    if [ "$DEPLOYMENT_TYPE" = "wildcard" ]; then
        echo "  📄 泛域名配置示例: frpc-wildcard-example.toml"
    else
        echo "  📄 标准配置示例: frpc-example.toml"
    fi
    echo ""
    
    if [ "$MONITORING_ENABLED" = true ]; then
        echo -e "${WHITE}监控管理：${NC}"
        echo "  🔍 启动监控: ./monitoring-alerts.sh daemon"
        echo "  📈 查看监控: ./management-tools.sh monitor"
        echo "  📋 生成报告: ./monitoring-alerts.sh report"
        echo ""
    fi
    
    echo -e "${WHITE}日常管理：${NC}"
    echo "  🛠️  管理工具: ./management-tools.sh"
    echo "  🔒 安全审计: ./security-audit.sh"
    echo "  💾 创建备份: ./management-tools.sh backup"
    echo ""
    
    echo -e "${YELLOW}重要提醒：${NC}"
    echo "1. 请妥善保管 .secrets/ 目录中的密钥文件"
    echo "2. 定期运行健康检查和安全审计"
    echo "3. 建议启用自动备份和监控"
    echo ""
    
    read -p "是否现在启动监控守护进程？(Y/n): " start_monitoring
    if [[ ! $start_monitoring =~ ^[Nn]$ ]] && [ "$MONITORING_ENABLED" = true ]; then
        if [ -f "$SCRIPT_DIR/monitoring-alerts.sh" ]; then
            "$SCRIPT_DIR/monitoring-alerts.sh" daemon
            print_success "监控守护进程已启动"
        fi
    fi
}

# 主函数
main() {
    print_header
    
    echo -e "${WHITE}欢迎使用 FRPS 智能部署向导！${NC}"
    echo "本向导将帮助您快速配置和部署 FRPS 内网穿透服务"
    echo ""
    
    read -p "按回车键开始配置... "
    
    # 执行配置步骤
    detect_environment
    choose_deployment_type
    configure_domains
    choose_ssl_type
    configure_security
    configure_monitoring
    confirm_configuration
    execute_deployment
    show_post_deployment_guide
    
    echo ""
    print_success "智能部署向导完成！"
    echo -e "${CYAN}感谢使用 FRPS 部署方案！${NC}"
}

# 显示使用说明
show_usage() {
    cat << EOF
FRPS 智能配置向导

这是一个交互式的配置向导，将引导您完成以下步骤：
1. 环境检测和硬件信息分析
2. 部署类型选择和智能推荐
3. 域名配置和DNS检查
4. SSL证书类型选择
5. 安全级别设置
6. 监控和告警配置
7. 自动部署和后配置

用法:
    $0              # 启动交互式向导
    $0 --help       # 显示帮助信息

支持的部署类型：
- 个人/小团队：简单配置，适合个人使用
- 企业/多项目：多域名配置，适合企业部署
- 泛域名方案：支持无限子域名的高级配置
- 自定义配置：完全自定义的高级选项

特色功能：
- 🧠 智能环境检测和配置推荐
- 🔧 自动化安全配置和优化
- 📊 集成监控和告警系统
- ⚡ 一键部署和后期管理工具
EOF
}

# 处理命令行参数
case "${1:-}" in
    "--help"|"-h"|"help")
        show_usage
        ;;
    *)
        main
        ;;
esac