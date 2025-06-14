#!/bin/bash

# FRPS + Mail + SSL 一键部署脚本
# 支持零配置部署 nginx + frps + stalwart-mail 服务

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
║            FRPS + Mail + SSL 一键部署系统                ║
║                                                          ║
║  🚀 FRPS内网穿透服务 + SSL                               ║
║  📧 Stalwart邮件服务器 + SSL                             ║
║  🌐 Nginx反向代理 + 自动SSL证书                          ║
║  🔄 Let's Encrypt自动续签                                ║
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
    
    if ! command -v docker &> /dev/null; then
        missing_deps+=("docker")
    fi
    
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        missing_deps+=("docker-compose")
    fi
    
    if ! command -v openssl &> /dev/null; then
        missing_deps+=("openssl")
    fi
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        log_error "缺少依赖: ${missing_deps[*]}"
        echo ""
        echo "Ubuntu/Debian 安装命令:"
        echo "  sudo apt update && sudo apt install -y docker.io docker-compose openssl"
        echo ""
        echo "CentOS/RHEL 安装命令:"
        echo "  sudo yum install -y docker docker-compose openssl"
        echo ""
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        log_error "Docker服务未运行，请启动Docker"
        echo "启动命令: sudo systemctl start docker"
        exit 1
    fi
    
    log_info "依赖检查通过"
}

# 生成FRPS配置
generate_frps_config() {
    local frps_domain=$1
    local frps_token=${2:-$(openssl rand -hex 16)}
    local dashboard_user=${3:-admin}
    local dashboard_pwd=${4:-$(openssl rand -hex 12)}
    
    log_info "生成FRPS配置..."
    
    cat > "$SCRIPT_DIR/frps/config/frps.toml" << EOF
# FRPS 服务器配置
bindPort = 7000
token = "$frps_token"

# HTTP 代理配置
vhostHTTPPort = 8880
vhostHTTPSPort = 8843

# Dashboard 配置
webServer.addr = "0.0.0.0"
webServer.port = 7001
webServer.user = "$dashboard_user"
webServer.password = "$dashboard_pwd"

# 性能优化
transport.maxPoolSize = 50
transport.tcpMux = true
transport.tcpMuxKeepaliveInterval = 60

# 域名配置
subDomainHost = "$frps_domain"

# 日志配置
log.to = "/var/log/frps/frps.log"
log.level = "info"
log.maxDays = 7
EOF
    
    log_info "FRPS配置生成完成"
    log_info "Token: $frps_token"
    log_info "Dashboard: $dashboard_user / $dashboard_pwd"
}

# 生成Stalwart Mail配置
generate_mail_config() {
    local mail_domain=$1
    local admin_password=${2:-$(openssl rand -base64 32)}
    
    log_info "生成邮件服务器配置..."
    
    # 生成管理员密码哈希
    local password_hash=$(openssl passwd -6 "$admin_password")
    
    cat > "$SCRIPT_DIR/stalwart-mail/config/config.toml" << EOF
# Stalwart 邮件服务器配置

# 认证配置
[authentication.fallback-admin]
user = "admin"
secret = "$password_hash"

# 服务器配置
[server]
hostname = "$mail_domain"
max-connections = 8192

# HTTP 管理界面
[server.listener.http]
bind = "[::]:8080"
protocol = "http"

# SMTP 配置
[server.listener.smtp]
bind = "[::]:25"
protocol = "smtp"

[server.listener.submission]
bind = "[::]:587"  
protocol = "smtp"

[server.listener.submissions]
bind = "[::]:465"
protocol = "smtp"
tls.implicit = true

# IMAP 配置  
[server.listener.imap]
bind = "[::]:143"
protocol = "imap"

[server.listener.imaptls]
bind = "[::]:993"
protocol = "imap"
tls.implicit = true

# POP3 配置
[server.listener.pop3]
bind = "[::]:110"
protocol = "pop3"

[server.listener.pop3s]
bind = "[::]:995"
protocol = "pop3"
tls.implicit = true

# ManageSieve 配置
[server.listener.sieve]
bind = "[::]:4190"
protocol = "managesieve"

# SSL证书配置 (通过volume挂载)
[certificate.default]
cert = "file:///opt/stalwart-mail/certs/$mail_domain/fullchain.pem"
private-key = "file:///opt/stalwart-mail/certs/$mail_domain/privkey.pem"
default = true

# 存储配置
[storage]
data = "rocksdb"
blob = "rocksdb" 
lookup = "rocksdb"
fts = "rocksdb"
directory = "internal"

[store.rocksdb]
type = "rocksdb"
path = "/opt/stalwart-mail/data"
compression = "lz4"

[directory.internal]
type = "internal"
store = "rocksdb"

# 日志配置
[tracer.log]
type = "log"
level = "info"
enable = true
path = "/opt/stalwart-mail/logs"
prefix = "stalwart.log"
rotate = "daily"
ansi = false

# Web管理界面
[webadmin]
resource = "file:///opt/stalwart-mail/etc/webadmin.zip"
EOF
    
    log_info "邮件服务器配置生成完成"
    log_info "管理员密码: $admin_password"
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
        "mail-web")
            # 邮件管理界面
            location_config='
    location / {
        proxy_pass http://stalwart-mail:8080;
        proxy_http_version 1.1;
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
    local mail_domain=$3
    local admin_email=$4
    local frps_token=${5:-$(openssl rand -hex 16)}
    local dashboard_user=${6:-admin}
    local dashboard_pwd=${7:-$(openssl rand -hex 12)}
    local mail_admin_pwd=${8:-$(openssl rand -base64 32)}
    
    if [ -z "$frps_domain" ] || [ -z "$mail_domain" ] || [ -z "$admin_email" ]; then
        log_error "参数不完整"
        show_usage
        exit 1
    fi
    
    log_info "开始部署服务..."
    
    # 1. 生成服务配置
    generate_frps_config "$frps_domain" "$frps_token" "$dashboard_user" "$dashboard_pwd"
    generate_mail_config "$mail_domain" "$mail_admin_pwd"
    
    # 2. 启动基础服务
    log_info "启动基础服务..."
    docker-compose -f "$SCRIPT_DIR/docker-compose.yml" up -d nginx frps stalwart-mail
    
    # 等待服务启动
    sleep 10
    
    # 3. 配置域名和申请证书
    local domains=("$frps_domain" "$mail_domain")
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
            "$mail_domain")
                generate_domain_ssl_config "$domain" "stalwart-mail" "8080" "mail-web"
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
    echo -e "  邮件管理: ${YELLOW}https://$mail_domain${NC} (admin/${mail_admin_pwd})"
    echo ""
    echo -e "${CYAN}FRPS配置信息:${NC}"
    echo -e "  Token: ${YELLOW}$frps_token${NC}"
    echo -e "  服务器: ${YELLOW}$frps_domain:7000${NC}"
    echo ""
    echo -e "${CYAN}邮件服务信息:${NC}"
    echo -e "  SMTP: ${YELLOW}$mail_domain:587 (TLS)${NC}"
    echo -e "  IMAP: ${YELLOW}$mail_domain:993 (SSL)${NC}"
    echo -e "  管理: ${YELLOW}admin/$mail_admin_pwd${NC}"
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
    if docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "(nginx-proxy|frps-server|stalwart-mail-server|NAMES)"; then
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
${CYAN}FRPS + Mail + SSL 一键部署系统${NC}

${CYAN}用法:${NC}
    $0 init                                               初始化环境
    $0 deploy <frps域名> <dashboard域名> <邮件域名> <邮箱>   部署所有服务
    $0 renew                                              续签证书
    $0 setup-cron                                         设置自动续签
    $0 status                                             显示状态

${CYAN}示例:${NC}
    $0 init
    $0 deploy frps.example.com admin.example.com mail.example.com admin@example.com
    $0 renew
    $0 status

${CYAN}说明:${NC}
    - frps域名: FRPS服务访问域名
    - dashboard域名: FRPS管理界面域名 (可选，留空则不部署)
    - 邮件域名: 邮件服务器域名
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
            deploy_services "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9"
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