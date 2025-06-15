#!/bin/bash

# FRPS + Nginx SSL 一键部署脚本
# 支持零配置部署 nginx + frps 服务

set -e

SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"

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
    echo -e "${GREEN}[INFO]${NC} $1" | tee -a "$SCRIPT_DIR/logs/deploy.log"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$SCRIPT_DIR/logs/deploy.log"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$SCRIPT_DIR/logs/deploy.log"
}

log_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1" | tee -a "$SCRIPT_DIR/logs/deploy.log"
}

# 显示横幅
show_banner() {
    echo -e "${CYAN}"
    cat << 'EOF'
╔══════════════════════════════════════════════════════════╗
║            FRPS + Nginx SSL 一键部署系统                  ║
║                                                          ║
║  🚀 FRPS内网穿透服务 + SSL                               ║
║  🌐 Nginx反向代理 + 自动SSL证书                          ║
║  🔄 Let's Encrypt自动续签                                ║
║  🎨 自定义404错误页面                                    ║
╚══════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    echo -e "${PURPLE}Version: $SCRIPT_VERSION${NC}"
    echo ""
}

# 检查依赖
check_dependencies() {
    log_info "检查系统依赖..."
    
    local missing_deps=()
    local need_install=false
    
    # 检查Docker
    if ! command -v docker &> /dev/null; then
        missing_deps+=("docker")
        need_install=true
    fi
    
    # 检查Docker Compose
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        missing_deps+=("docker-compose")
        need_install=true
    fi
    
    # 检查其他必要工具
    for tool in curl wget openssl; do
        if ! command -v $tool &> /dev/null; then
            missing_deps+=("$tool")
            need_install=true
        fi
    done
    
    if [ "$need_install" = true ]; then
        log_warn "缺少以下依赖: ${missing_deps[*]}"
        echo ""
        echo -e "${YELLOW}是否自动安装缺少的依赖？${NC}"
        echo -e "${BLUE}提示: 安装脚本支持 Ubuntu/Debian/CentOS/RHEL${NC}"
        echo ""
        read -p "自动安装依赖? (Y/n) " -n 1 -r
        echo
        
        if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
            log_info "开始自动安装依赖..."
            if [ -x "$SCRIPT_DIR/install-dependencies.sh" ]; then
                "$SCRIPT_DIR/install-dependencies.sh" --quick
                
                # 重新检查
                if ! command -v docker &> /dev/null || ! docker info &> /dev/null; then
                    log_error "依赖安装可能未完成，请手动检查"
                    exit 1
                fi
                
                log_info "依赖安装完成，继续部署..."
            else
                log_error "找不到依赖安装脚本"
                exit 1
            fi
        else
            log_error "请手动安装依赖后重新运行"
            echo ""
            echo "您可以运行以下命令安装依赖:"
            echo "  ./install-dependencies.sh"
            echo ""
            echo "或手动安装:"
            echo "  Ubuntu/Debian: sudo apt install -y docker.io docker-compose curl wget openssl"
            echo "  CentOS/RHEL: sudo yum install -y docker docker-compose curl wget openssl"
            echo ""
            exit 1
        fi
    else
        # 检查Docker服务状态
        if ! docker info &> /dev/null; then
            log_warn "Docker服务未运行"
            echo ""
            read -p "是否启动Docker服务? (Y/n) " -n 1 -r
            echo
            
            if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
                if command -v systemctl &> /dev/null; then
                    sudo systemctl start docker
                    sudo systemctl enable docker
                    log_info "Docker服务已启动"
                else
                    log_error "无法自动启动Docker服务，请手动启动"
                    exit 1
                fi
            else
                log_error "Docker服务未运行，无法继续"
                exit 1
            fi
        fi
        
        log_info "依赖检查通过"
    fi
}

# 生成FRPS配置
generate_frps_config() {
    local frps_domain=$1
    local frps_token=${2:-$(openssl rand -hex 16)}
    local dashboard_user=${3:-admin}
    local dashboard_pwd=${4:-$(openssl rand -hex 12)}
    
    log_info "生成FRPS配置..."
    
    cat > "$SCRIPT_DIR/frps/config/frps.toml" << EOF
# FRPS 配置文件

# 基础配置
bindPort = 7000
bindAddr = "0.0.0.0"

# Dashboard 配置
webServer.addr = "0.0.0.0"
webServer.port = 7001
webServer.user = "$dashboard_user"
webServer.password = "$dashboard_pwd"

# 自定义404错误页面
custom404Page = "/etc/frp/custom_errors/404.html"

# 日志配置
log.to = "/var/log/frps/frps.log"
log.level = "info"
log.maxDays = 3

# 认证配置
auth.method = "token"
auth.token = "$frps_token"

# 连接池
transport.maxPoolCount = 5

# 心跳配置
transport.heartbeatTimeout = 90

# 端口白名单，允许客户端绑定的端口范围
allowPorts = [
  { start = 2000, end = 3000 },
  { start = 3001, end = 4000 },
  { start = 4001, end = 50000 }
]
EOF
    
    log_info "FRPS配置生成完成"
    log_info "Token: $frps_token"
    log_info "Dashboard: $dashboard_user / $dashboard_pwd"
}


# 生成Nginx主配置
generate_nginx_config() {
    log_info "生成Nginx配置..."
    
    cat > "$SCRIPT_DIR/nginx/conf/nginx.conf" << 'EOF'
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log notice;
pid /run/nginx.pid;

events {
    worker_connections 1024;
    use epoll;
    multi_accept on;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';

    access_log /var/log/nginx/access.log main;

    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    client_max_body_size 64m;

    # Gzip 压缩
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_comp_level 6;
    gzip_types
        text/plain
        text/css
        text/xml
        text/javascript
        application/json
        application/javascript
        application/xml+rss
        application/atom+xml;

    # SSL 优化配置
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;

    # 安全头
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;

    include /etc/nginx/conf.d/*.conf;
}
EOF

    # 生成默认配置
    cat > "$SCRIPT_DIR/nginx/conf/conf.d/default.conf" << 'EOF'
server {
    listen 80 default_server;
    server_name _;

    location /.well-known/acme-challenge/ {
        root /usr/share/nginx/html;
    }

    location / {
        return 404;
    }
}
EOF
    
    log_info "Nginx配置生成完成"
}

# 生成域名SSL配置
generate_domain_ssl_config() {
    local domain=$1
    local service_name=$2
    local service_port=$3
    local config_type=${4:-web}  # web, frps-web, frps-api, mail-web
    
    log_info "生成域名 $domain 的SSL配置..."
    
    local upstream_config=""
    local location_config=""
    
    case "$config_type" in
        "frps-web")
            # FRPS Dashboard
            location_config='
    location / {
        proxy_pass http://frps:7001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }'
            ;;
        "frps-api")
            # FRPS HTTP 代理
            location_config='
    location / {
        proxy_pass http://frps:8880;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $http_connection;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }'
            ;;
        *)
            # 通用Web服务
            location_config="
    location / {
        proxy_pass http://$service_name:$service_port;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }"
            ;;
    esac
    
    cat > "$SCRIPT_DIR/nginx/conf/conf.d/${domain}.conf" << EOF
# HTTP -> HTTPS 重定向
server {
    listen 80;
    server_name $domain;

    location /.well-known/acme-challenge/ {
        root /usr/share/nginx/html;
    }

    location / {
        return 301 https://\$server_name\$request_uri;
    }
}

# HTTPS 服务器
server {
    listen 443 ssl http2;
    server_name $domain;

    # SSL 证书
    ssl_certificate /etc/letsencrypt/live/$domain/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$domain/privkey.pem;

    # HSTS
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;

    # 日志
    access_log /var/log/nginx/${domain}.access.log main;
    error_log /var/log/nginx/${domain}.error.log;

$location_config
}
EOF
    
    log_info "域名 $domain 配置生成完成"
}

# 申请SSL证书
request_ssl_certificate() {
    local domain=$1
    local email=$2
    
    log_info "为域名 $domain 申请SSL证书..."
    
    docker run --rm \
        -v "$SCRIPT_DIR/certbot/data:/etc/letsencrypt" \
        -v "$SCRIPT_DIR/nginx/html:/var/www/html" \
        certbot/certbot certonly \
        --webroot \
        --webroot-path=/var/www/html \
        --email "$email" \
        --agree-tos \
        --no-eff-email \
        --force-renewal \
        --non-interactive \
        -d "$domain"
    
    if [ $? -eq 0 ]; then
        log_info "SSL证书申请成功: $domain"
        return 0
    else
        log_error "SSL证书申请失败: $domain"
        return 1
    fi
}

# 初始化部署环境
init_deployment() {
    log_info "初始化部署环境..."
    
    # 创建日志目录
    mkdir -p "$SCRIPT_DIR/logs"
    touch "$SCRIPT_DIR/logs/deploy.log"
    
    # 生成基础配置
    generate_nginx_config
    
    log_info "环境初始化完成"
}

# 部署服务
deploy_services() {
    local frps_domain=$1
    local frps_dashboard_domain=$2
    local admin_email=$3
    local frps_token=${4:-$(openssl rand -hex 16)}
    local dashboard_user=${5:-admin}
    local dashboard_pwd=${6:-$(openssl rand -hex 12)}
    
    if [ -z "$frps_domain" ] || [ -z "$admin_email" ]; then
        log_error "参数不完整"
        show_usage
        exit 1
    fi
    
    log_info "开始部署服务..."
    
    # 1. 生成服务配置
    generate_frps_config "$frps_domain" "$frps_token" "$dashboard_user" "$dashboard_pwd"
    
    # 2. 启动基础服务
    log_info "启动基础服务..."
    docker-compose -f "$SCRIPT_DIR/docker-compose.yml" up -d nginx frps
    
    # 等待服务启动
    sleep 10
    
    # 3. 配置域名和申请证书
    local domains=("$frps_domain")
    if [ -n "$frps_dashboard_domain" ]; then
        domains+=("$frps_dashboard_domain")
    fi
    
    for domain in "${domains[@]}"; do
        log_info "配置域名: $domain"
        
        # 生成nginx配置
        case "$domain" in
            "$frps_dashboard_domain")
                generate_domain_ssl_config "$domain" "frps" "7001" "frps-web"
                ;;
            "$frps_domain")
                generate_domain_ssl_config "$domain" "frps" "8880" "frps-api"
                ;;
        esac
        
        # 重新加载nginx
        docker exec nginx-proxy nginx -s reload
        
        # 申请证书
        if request_ssl_certificate "$domain" "$admin_email"; then
            log_info "域名 $domain 配置完成"
        else
            log_error "域名 $domain 证书申请失败"
        fi
        
        sleep 5
    done
    
    # 4. 最终重启所有服务
    log_info "重启所有服务以应用SSL配置..."
    docker-compose -f "$SCRIPT_DIR/docker-compose.yml" restart
    
    # 5. 显示部署结果
    echo ""
    echo -e "${GREEN}🎉 部署完成！${NC}"
    echo ""
    echo -e "${CYAN}服务访问地址:${NC}"
    echo -e "  FRPS服务: ${YELLOW}https://$frps_domain${NC}"
    if [ -n "$frps_dashboard_domain" ]; then
        echo -e "  FRPS管理: ${YELLOW}https://$frps_dashboard_domain${NC} (${dashboard_user}/${dashboard_pwd})"
    fi
    echo ""
    echo -e "${CYAN}FRPS配置信息:${NC}"
    echo -e "  Token: ${YELLOW}$frps_token${NC}"
    echo -e "  服务器: ${YELLOW}$frps_domain:7000${NC}"
    echo ""
}

# 续签证书
renew_certificates() {
    log_info "续签SSL证书..."
    
    docker run --rm \
        -v "$SCRIPT_DIR/certbot/data:/etc/letsencrypt" \
        -v "$SCRIPT_DIR/nginx/html:/var/www/html" \
        certbot/certbot renew \
        --quiet \
        --no-random-sleep-on-renew
    
    if [ $? -eq 0 ]; then
        log_info "证书续签完成"
        if docker ps | grep -q nginx-proxy; then
            docker exec nginx-proxy nginx -s reload
            log_info "Nginx已重新加载"
        fi
    else
        log_error "证书续签失败"
    fi
}

# 设置自动续签
setup_auto_renew() {
    log_info "设置自动续签..."
    
    cat > "$SCRIPT_DIR/renew.sh" << EOF
#!/bin/bash
cd "$SCRIPT_DIR"
./deploy.sh renew >> logs/ssl-renew.log 2>&1
EOF
    
    chmod +x "$SCRIPT_DIR/renew.sh"
    
    echo ""
    echo -e "${YELLOW}请添加以下crontab任务启用自动续签:${NC}"
    echo -e "${CYAN}0 2 * * 0 $SCRIPT_DIR/renew.sh${NC}"
    echo ""
    echo -e "${YELLOW}或运行命令自动添加:${NC}"
    echo -e "${CYAN}echo '0 2 * * 0 $SCRIPT_DIR/renew.sh' | crontab -${NC}"
    echo ""
}

# 显示状态
show_status() {
    echo ""
    echo -e "${CYAN}=== 服务状态 ===${NC}"
    echo ""
    
    # Docker服务状态
    if docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "(nginx-proxy|frps-server|NAMES)"; then
        echo ""
    else
        echo "  没有运行的服务"
        echo ""
    fi
    
    # 证书状态
    echo -e "${CYAN}=== SSL证书状态 ===${NC}"
    if [ -d "$SCRIPT_DIR/certbot/data/live" ] && [ "$(ls -A $SCRIPT_DIR/certbot/data/live 2>/dev/null)" ]; then
        for cert_dir in "$SCRIPT_DIR/certbot/data/live"/*; do
            if [ -d "$cert_dir" ]; then
                domain=$(basename "$cert_dir")
                if [ "$domain" != "README" ]; then
                    expiry=$(openssl x509 -in "$cert_dir/cert.pem" -noout -enddate 2>/dev/null | cut -d= -f2)
                    echo "  $domain: $expiry"
                fi
            fi
        done
    else
        echo "  没有SSL证书"
    fi
    echo ""
}

# 显示用法
show_usage() {
    cat << EOF
${CYAN}FRPS + Nginx SSL 一键部署系统${NC}

${CYAN}用法:${NC}
    $0 init                                 初始化环境
    $0 deploy <frps域名> <邮箱>              部署所有服务
    $0 deploy <frps域名> <dashboard域名> <邮箱>  部署包含dashboard
    $0 renew                                续签证书
    $0 setup-cron                           设置自动续签
    $0 status                               显示状态

${CYAN}示例:${NC}
    $0 init
    $0 deploy frps.example.com admin@example.com
    $0 deploy frps.example.com admin.example.com admin@example.com
    $0 renew
    $0 status

${CYAN}说明:${NC}
    - frps域名: FRPS服务访问域名
    - dashboard域名: FRPS管理界面域名 (可选)
    - 邮箱: Let's Encrypt注册邮箱
EOF
}

# 主函数
main() {
    show_banner
    
    case "${1:-help}" in
        "init")
            check_dependencies
            init_deployment
            log_info "🎉 初始化完成! 现在可以使用 deploy 命令部署服务"
            ;;
        "deploy")
            check_dependencies
            init_deployment
            # 判断参数个数
            if [ $# -eq 3 ]; then
                # deploy frps.example.com admin@example.com
                deploy_services "$2" "" "$3"
            elif [ $# -eq 4 ]; then
                # deploy frps.example.com admin.example.com admin@example.com
                deploy_services "$2" "$3" "$4"
            else
                log_error "参数不正确"
                show_usage
                exit 1
            fi
            ;;
        "renew")
            renew_certificates
            ;;
        "setup-cron")
            setup_auto_renew
            ;;
        "status")
            show_status
            ;;
        "help"|*)
            show_usage
            ;;
    esac
}

main "$@"