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

# 安全读取配置
source_secret_utils() {
    if [ -f "$SCRIPT_DIR/secret-utils.sh" ]; then
        source "$SCRIPT_DIR/secret-utils.sh"
        export_secrets
    fi
}

# 生成FRPS配置（使用安全的密钥管理）
generate_frps_config() {
    local frps_domain=$1
    local frps_token=""
    local dashboard_user=${3:-admin}
    local dashboard_pwd=""
    
    # 使用安全的配置管理
    source_secret_utils
    
    if [ -n "$FRPS_TOKEN" ]; then
        frps_token="$FRPS_TOKEN"
    else
        frps_token=${2:-"Mercury123*"}
    fi
    
    if [ -n "$ADMIN_PASSWORD" ]; then
        dashboard_pwd="$ADMIN_PASSWORD"
    else
        dashboard_pwd=${4:-$(openssl rand -base64 24)}
    fi
    
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

# HTTP虚拟主机配置
vhostHTTPPort = 8880
vhostHTTPSPort = 8843

# 子域名配置
subdomainHost = "$frps_domain"

# 端口白名单，允许客户端绑定的端口范围
allowPorts = [
  { start = 2000, end = 3000 },
  { start = 3001, end = 4000 },
  { start = 4001, end = 50000 }
]
EOF
    
    log_info "FRPS配置生成完成"
    # 安全显示配置信息（隐藏敏感部分）
    log_info "Token: ${frps_token:0:8}...${frps_token: -4}"
    log_info "Dashboard: $dashboard_user / ${dashboard_pwd:0:4}...${dashboard_pwd: -4}"
    log_info "完整配置信息已安全存储在 .secrets/ 目录中"
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

# 生成域名HTTP配置 (用于证书申请)
generate_domain_http_config() {
    local domain=$1
    
    log_info "生成域名 $domain 的临时HTTP配置..."
    
    cat > "$SCRIPT_DIR/nginx/conf/conf.d/${domain}.conf" << EOF
# 临时HTTP配置用于SSL证书申请
server {
    listen 80;
    server_name $domain;

    location /.well-known/acme-challenge/ {
        root /usr/share/nginx/html;
    }

    location / {
        return 200 'SSL certificate setup in progress...';
        add_header Content-Type text/plain;
    }
}
EOF
    
    log_info "域名 $domain 临时HTTP配置生成完成"
}

# 生成域名SSL配置
generate_domain_ssl_config() {
    local domain=$1
    local service_name=$2
    local service_port=$3
    local config_type=${4:-web}  # web, frps-web, frps-api
    
    log_info "生成域名 $domain 的SSL配置..."
    
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
            # FRPS HTTP 代理 + Dashboard (通过端口访问)
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
    listen 443 ssl;
    http2 on;
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

# 检查SSL证书是否有效
check_ssl_certificate() {
    local domain=$1
    local cert_file="$SCRIPT_DIR/certbot/data/live/$domain/cert.pem"
    
    # 检查证书文件是否存在
    if [ ! -f "$cert_file" ]; then
        log_info "域名 $domain 证书不存在，需要申请"
        return 1
    fi
    
    # 检查证书是否在30天内过期
    local expiry_date=$(openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | cut -d= -f2)
    if [ -z "$expiry_date" ]; then
        log_warn "无法读取证书过期时间，重新申请证书"
        return 1
    fi
    
    local expiry_timestamp=$(date -d "$expiry_date" +%s 2>/dev/null || date -j -f "%b %d %H:%M:%S %Y %Z" "$expiry_date" +%s 2>/dev/null)
    local current_timestamp=$(date +%s)
    local thirty_days=$((30 * 24 * 3600))
    
    if [ $((expiry_timestamp - current_timestamp)) -lt $thirty_days ]; then
        log_warn "域名 $domain 证书将在30天内过期，需要续签"
        return 1
    else
        log_info "域名 $domain 证书有效，有效期至: $(date -d "$expiry_date" 2>/dev/null || date -j -f "%b %d %H:%M:%S %Y %Z" "$expiry_date" +"%Y-%m-%d" 2>/dev/null)"
        return 0
    fi
}

# 申请多域名SSL证书 (SAN证书)
request_ssl_certificate() {
    local email=$1
    shift 1
    local domains=("$@")
    
    if [ ${#domains[@]} -eq 0 ]; then
        log_error "没有提供域名"
        return 1
    fi
    
    local primary_domain="${domains[0]}"
    
    # 检查主域名证书是否有效
    if check_ssl_certificate "$primary_domain"; then
        log_info "主域名 $primary_domain 证书仍然有效，检查是否包含所有域名..."
        
        # 检查证书是否包含所有所需域名
        local cert_file="$SCRIPT_DIR/certbot/data/live/$primary_domain/cert.pem"
        local cert_domains=$(openssl x509 -in "$cert_file" -noout -text 2>/dev/null | grep -A1 "Subject Alternative Name" | tail -1 | tr ',' '\n' | grep "DNS:" | sed 's/.*DNS://' | tr -d ' ')
        
        local all_covered=true
        for domain in "${domains[@]}"; do
            if ! echo "$cert_domains" | grep -q "^$domain$"; then
                log_warn "证书不包含域名: $domain"
                all_covered=false
                break
            fi
        done
        
        if [ "$all_covered" = true ]; then
            log_info "现有证书已包含所有域名，跳过申请"
            return 0
        fi
    fi
    
    log_info "申请多域名SSL证书，包含域名: ${domains[*]}"
    
    # 构建certbot命令参数
    local certbot_args=""
    for domain in "${domains[@]}"; do
        certbot_args="$certbot_args -d $domain"
    done
    
    docker run --rm \
        -v "$SCRIPT_DIR/certbot/data:/etc/letsencrypt" \
        -v "$SCRIPT_DIR/nginx/html:/var/www/html" \
        certbot/certbot certonly \
        --webroot \
        --webroot-path=/var/www/html \
        --email "$email" \
        --agree-tos \
        --no-eff-email \
        --non-interactive \
        $certbot_args
    
    if [ $? -eq 0 ]; then
        log_info "多域名SSL证书申请成功: ${domains[*]}"
        return 0
    else
        log_error "多域名SSL证书申请失败: ${domains[*]}"
        return 1
    fi
}

# 初始化部署环境
init_deployment() {
    log_info "初始化部署环境..."
    
    # 创建日志目录
    mkdir -p "$SCRIPT_DIR/logs"
    touch "$SCRIPT_DIR/logs/deploy.log"
    
    # 初始化安全配置
    if [ -f "$SCRIPT_DIR/security-enhancements.sh" ]; then
        log_info "初始化安全配置..."
        "$SCRIPT_DIR/security-enhancements.sh" config >/dev/null 2>&1
    fi
    
    # 生成基础配置
    generate_nginx_config
    
    log_info "环境初始化完成"
}

# 多域名部署
deploy_multiple_domains() {
    local domains=("$@")
    local admin_email="${domains[-1]}"
    unset 'domains[-1]'  # 移除最后一个元素（邮箱）
    
    if [ ${#domains[@]} -eq 0 ] || [ -z "$admin_email" ]; then
        log_error "参数不完整"
        show_usage
        exit 1
    fi
    
    local frps_domain="${domains[0]}"
    local frps_dashboard_domain=""
    
    # 如果有第二个域名，作为dashboard域名
    if [ ${#domains[@]} -gt 1 ]; then
        frps_dashboard_domain="${domains[1]}"
    fi
    
    log_info "开始多域名部署..."
    log_info "FRPS域名: $frps_domain"
    if [ -n "$frps_dashboard_domain" ]; then
        log_info "Dashboard域名: $frps_dashboard_domain"
    fi
    log_info "其他域名: ${domains[@]:2}"
    log_info "邮箱: $admin_email"
    
    # 1. 生成服务配置
    local frps_token="Mercury123*"
    local dashboard_user="admin"
    local dashboard_pwd=$(openssl rand -hex 12)
    
    generate_frps_config "$frps_domain" "$frps_token" "$dashboard_user" "$dashboard_pwd"
    
    # 2. 为所有域名生成HTTP配置用于证书申请
    for domain in "${domains[@]}"; do
        generate_domain_http_config "$domain"
    done
    
    # 3. 启动基础服务
    log_info "启动基础服务..."
    docker-compose -f "$SCRIPT_DIR/docker-compose.yml" up -d nginx frps
    
    # 等待服务启动
    sleep 10
    
    # 4. 申请多域名SSL证书
    if request_ssl_certificate "$admin_email" "${domains[@]}"; then
        log_info "多域名SSL证书申请成功"
    else
        log_error "多域名SSL证书申请失败"
        return 1
    fi
    
    # 5. 为每个域名生成SSL配置
    for i in "${!domains[@]}"; do
        local domain="${domains[$i]}"
        log_info "生成域名 $domain 的SSL配置..."
        
        if [ "$domain" = "$frps_dashboard_domain" ]; then
            generate_domain_ssl_config "$domain" "frps" "7001" "frps-web"
        elif [ "$domain" = "$frps_domain" ]; then
            generate_domain_ssl_config "$domain" "frps" "8880" "frps-api"
        else
            # 其他域名也代理到FRPS
            generate_domain_ssl_config "$domain" "frps" "8880" "frps-api"
        fi
    done
    
    # 6. 重新加载nginx应用所有SSL配置
    docker exec nginx-proxy nginx -s reload
    log_info "所有域名配置完成"
    
    # 7. 最终重启所有服务
    log_info "重启所有服务以应用SSL配置..."
    docker-compose -f "$SCRIPT_DIR/docker-compose.yml" restart
    
    # 8. 显示部署结果
    echo ""
    echo -e "${GREEN}🎉 多域名部署完成！${NC}"
    echo ""
    echo -e "${CYAN}服务访问地址:${NC}"
    for domain in "${domains[@]}"; do
        if [ "$domain" = "$frps_dashboard_domain" ]; then
            echo -e "  FRPS管理: ${YELLOW}https://$domain${NC} (${dashboard_user}/${dashboard_pwd})"
        elif [ "$domain" = "$frps_domain" ]; then
            echo -e "  FRPS服务: ${YELLOW}https://$domain${NC}"
        else
            echo -e "  其他域名: ${YELLOW}https://$domain${NC}"
        fi
    done
    echo ""
    echo -e "${CYAN}FRPS配置信息:${NC}"
    echo -e "  Token: ${YELLOW}${frps_token:0:8}...${frps_token: -4}${NC}"
    echo -e "  服务器: ${YELLOW}$frps_domain:7000${NC}"
    echo ""
}

# 部署服务
deploy_services() {
    local frps_domain=$1
    local frps_dashboard_domain=$2
    local admin_email=$3
    local frps_token=${4:-"Mercury123*"}
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
    
    # 检查是否需要申请证书
    local need_cert=false
    local primary_domain="${domains[0]}"
    
    if ! check_ssl_certificate "$primary_domain"; then
        need_cert=true
    else
        # 检查证书是否包含所有域名
        local cert_file="$SCRIPT_DIR/certbot/data/live/$primary_domain/cert.pem"
        if [ -f "$cert_file" ]; then
            local cert_domains=$(openssl x509 -in "$cert_file" -noout -text 2>/dev/null | grep -A1 "Subject Alternative Name" | tail -1 | tr ',' '\n' | grep "DNS:" | sed 's/.*DNS://' | tr -d ' ')
            
            for domain in "${domains[@]}"; do
                if ! echo "$cert_domains" | grep -q "^$domain$"; then
                    log_info "证书不包含域名 $domain，需要重新申请"
                    need_cert=true
                    break
                fi
            done
        else
            need_cert=true
        fi
    fi
    
    if [ "$need_cert" = true ]; then
        log_info "准备申请多域名SSL证书..."
        
        # 为所有域名生成HTTP配置
        for domain in "${domains[@]}"; do
            generate_domain_http_config "$domain"
        done
        
        # 重新加载nginx
        docker exec nginx-proxy nginx -s reload
        sleep 5
        
        # 申请多域名证书
        if request_ssl_certificate "$admin_email" "${domains[@]}"; then
            log_info "多域名SSL证书申请成功"
        else
            log_error "多域名SSL证书申请失败"
            return 1
        fi
    else
        log_info "现有证书已包含所有域名，跳过申请"
    fi
    
    # 为每个域名生成SSL配置
    for domain in "${domains[@]}"; do
        log_info "生成域名 $domain 的SSL配置..."
        
        case "$domain" in
            "$frps_dashboard_domain")
                generate_domain_ssl_config "$domain" "frps" "7001" "frps-web"
                ;;
            "$frps_domain")
                generate_domain_ssl_config "$domain" "frps" "8880" "frps-api"
                ;;
        esac
    done
    
    # 重新加载nginx应用所有SSL配置
    docker exec nginx-proxy nginx -s reload
    log_info "所有域名配置完成"
    
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
    else
        echo -e "${YELLOW}⚠️  管理界面未配置独立域名${NC}"
        echo -e "   推荐重新部署并添加管理域名："
        echo -e "   ${CYAN}./deploy.sh deploy $frps_domain admin-$frps_domain admin@example.com${NC}"
        echo -e ""
        echo -e "   或临时访问: ${YELLOW}http://$frps_domain:7000${NC} (通过客户端API)"
    fi
    echo ""
    echo -e "${CYAN}FRPS配置信息:${NC}"
    echo -e "  Token: ${YELLOW}${frps_token:0:8}...${frps_token: -4}${NC}"
    echo -e "  服务器: ${YELLOW}$frps_domain:7000${NC}"
    echo -e "  完整配置: ${YELLOW}./secret-utils.sh info${NC}"
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
    $0 deploy <frps域名> <邮箱>              部署FRPS服务
    $0 deploy <frps域名> <dashboard域名> <邮箱>  部署包含独立管理界面
    $0 deploy <域名1> <域名2> <域名3>... <邮箱>  部署多个域名
    $0 wildcard <主域名> <邮箱> <dns-provider>  部署泛域名SSL方案
    $0 renew                                续签证书
    $0 setup-cron                           设置自动续签
    $0 status                               显示状态
    $0 security [选项]                      安全检查和增强
    $0 health                               服务健康检查

${CYAN}示例:${NC}
    $0 init
    $0 deploy frps.example.com admin@example.com
    $0 deploy frps.example.com admin-frps.example.com admin@example.com
    $0 deploy frps.example.com admin.example.com dev.example.com admin@example.com
    $0 wildcard flowbytes.cn admin@example.com cloudflare
    $0 wildcard flowbytes.cn admin@example.com aliyun
    $0 wildcard flowbytes.cn admin@example.com tencent
    $0 renew
    $0 status
    $0 security all    # 执行所有安全增强
    $0 health          # 检查服务健康状态

${CYAN}说明:${NC}
    - frps域名: FRPS服务访问域名
    - dashboard域名: FRPS管理界面独立域名 (推荐使用二级域名)
    - 主域名: 用于泛域名证书的根域名
    - dns-provider: DNS提供商 (cloudflare/aliyun/tencent)
    - 邮箱: Let's Encrypt注册邮箱

${CYAN}SSL证书方案:${NC}
    📋 SAN证书 (默认): 指定域名，配置简单
    🌟 泛域名证书: 无限子域名，frpc subdomain自动SSL
    
    详细说明: docs/wildcard-ssl.md

${CYAN}推荐配置:${NC}
    ✅ 小规模/固定域名: 使用SAN证书
    ✅ 大规模/动态域名: 使用泛域名证书
    ✅ frpc subdomain自动SSL: 配置泛域名方案
EOF
}

# DNS API配置验证
validate_dns_credentials() {
    local dns_provider=$1
    
    case "$dns_provider" in
        "cloudflare")
            if [ -z "$CLOUDFLARE_EMAIL" ] || [ -z "$CLOUDFLARE_API_KEY" ]; then
                log_error "Cloudflare DNS API配置不完整"
                echo ""
                echo -e "${YELLOW}请设置以下环境变量:${NC}"
                echo -e "  ${CYAN}export CLOUDFLARE_EMAIL=\"your-email@example.com\"${NC}"
                echo -e "  ${CYAN}export CLOUDFLARE_API_KEY=\"your-api-key\"${NC}"
                echo ""
                echo -e "${YELLOW}或者在 .env 文件中配置:${NC}"
                echo -e "  ${CYAN}CLOUDFLARE_EMAIL=your-email@example.com${NC}"
                echo -e "  ${CYAN}CLOUDFLARE_API_KEY=your-api-key${NC}"
                return 1
            fi
            ;;
        "aliyun")
            if [ -z "$ALIBABA_CLOUD_ACCESS_KEY_ID" ] || [ -z "$ALIBABA_CLOUD_ACCESS_KEY_SECRET" ]; then
                log_error "阿里云DNS API配置不完整"
                echo ""
                echo -e "${YELLOW}请设置以下环境变量:${NC}"
                echo -e "  ${CYAN}export ALIBABA_CLOUD_ACCESS_KEY_ID=\"your-access-key\"${NC}"
                echo -e "  ${CYAN}export ALIBABA_CLOUD_ACCESS_KEY_SECRET=\"your-secret-key\"${NC}"
                echo ""
                echo -e "${YELLOW}或者在 .env 文件中配置:${NC}"
                echo -e "  ${CYAN}ALIBABA_CLOUD_ACCESS_KEY_ID=your-access-key${NC}"
                echo -e "  ${CYAN}ALIBABA_CLOUD_ACCESS_KEY_SECRET=your-secret-key${NC}"
                return 1
            fi
            ;;
        "tencent")
            if [ -z "$TENCENTCLOUD_SECRET_ID" ] || [ -z "$TENCENTCLOUD_SECRET_KEY" ]; then
                log_error "腾讯云DNS API配置不完整"
                echo ""
                echo -e "${YELLOW}请设置以下环境变量:${NC}"
                echo -e "  ${CYAN}export TENCENTCLOUD_SECRET_ID=\"your-secret-id\"${NC}"
                echo -e "  ${CYAN}export TENCENTCLOUD_SECRET_KEY=\"your-secret-key\"${NC}"
                echo ""
                echo -e "${YELLOW}或者在 .env 文件中配置:${NC}"
                echo -e "  ${CYAN}TENCENTCLOUD_SECRET_ID=your-secret-id${NC}"
                echo -e "  ${CYAN}TENCENTCLOUD_SECRET_KEY=your-secret-key${NC}"
                return 1
            fi
            ;;
        *)
            log_error "不支持的DNS提供商: $dns_provider"
            echo -e "${YELLOW}支持的DNS提供商: cloudflare, aliyun, tencent${NC}"
            return 1
            ;;
    esac
    
    log_info "DNS API配置验证通过: $dns_provider"
    return 0
}

# 加载环境变量
load_env_file() {
    if [ -f "$SCRIPT_DIR/.env" ]; then
        log_info "加载环境变量文件: .env"
        set -a
        source "$SCRIPT_DIR/.env"
        set +a
    fi
}

# 申请泛域名SSL证书
request_wildcard_certificate() {
    local root_domain=$1
    local admin_email=$2
    local dns_provider=$3
    
    log_info "开始申请泛域名SSL证书: *.$root_domain"
    
    local docker_env_args=""
    local certbot_plugin=""
    
    case "$dns_provider" in
        "cloudflare")
            certbot_plugin="dns-cloudflare"
            docker_env_args="-e CLOUDFLARE_EMAIL=$CLOUDFLARE_EMAIL -e CLOUDFLARE_API_KEY=$CLOUDFLARE_API_KEY"
            
            # 创建Cloudflare凭据文件
            mkdir -p "$SCRIPT_DIR/certbot/credentials"
            cat > "$SCRIPT_DIR/certbot/credentials/cloudflare.ini" << EOF
dns_cloudflare_email = $CLOUDFLARE_EMAIL
dns_cloudflare_api_key = $CLOUDFLARE_API_KEY
EOF
            chmod 600 "$SCRIPT_DIR/certbot/credentials/cloudflare.ini"
            ;;
        "aliyun")
            certbot_plugin="dns-aliyun"
            docker_env_args="-e ALIBABA_CLOUD_ACCESS_KEY_ID=$ALIBABA_CLOUD_ACCESS_KEY_ID -e ALIBABA_CLOUD_ACCESS_KEY_SECRET=$ALIBABA_CLOUD_ACCESS_KEY_SECRET"
            
            # 创建阿里云凭据文件
            mkdir -p "$SCRIPT_DIR/certbot/credentials"
            cat > "$SCRIPT_DIR/certbot/credentials/aliyun.ini" << EOF
dns_aliyun_access_key_id = $ALIBABA_CLOUD_ACCESS_KEY_ID
dns_aliyun_access_key_secret = $ALIBABA_CLOUD_ACCESS_KEY_SECRET
EOF
            chmod 600 "$SCRIPT_DIR/certbot/credentials/aliyun.ini"
            ;;
        "tencent")
            certbot_plugin="dns-tencentcloud"
            docker_env_args="-e TENCENTCLOUD_SECRET_ID=$TENCENTCLOUD_SECRET_ID -e TENCENTCLOUD_SECRET_KEY=$TENCENTCLOUD_SECRET_KEY"
            
            # 创建腾讯云凭据文件
            mkdir -p "$SCRIPT_DIR/certbot/credentials"
            cat > "$SCRIPT_DIR/certbot/credentials/tencent.ini" << EOF
dns_tencentcloud_secret_id = $TENCENTCLOUD_SECRET_ID
dns_tencentcloud_secret_key = $TENCENTCLOUD_SECRET_KEY
EOF
            chmod 600 "$SCRIPT_DIR/certbot/credentials/tencent.ini"
            ;;
    esac
    
    # 使用自定义certbot镜像（包含DNS插件）
    local certbot_image="certbot/dns-$dns_provider"
    if [ "$dns_provider" = "aliyun" ]; then
        certbot_image="soulteary/certbot-dns-aliyun"
    elif [ "$dns_provider" = "tencent" ]; then
        certbot_image="certbot/dns-tencentcloud"
    fi
    
    docker run --rm \
        -v "$SCRIPT_DIR/certbot/data:/etc/letsencrypt" \
        -v "$SCRIPT_DIR/certbot/credentials:/etc/letsencrypt/credentials" \
        $docker_env_args \
        $certbot_image certonly \
        --$certbot_plugin \
        --${certbot_plugin}-credentials /etc/letsencrypt/credentials/${dns_provider}.ini \
        --email "$admin_email" \
        --agree-tos \
        --no-eff-email \
        --non-interactive \
        -d "$root_domain" \
        -d "*.$root_domain"
    
    if [ $? -eq 0 ]; then
        log_info "泛域名SSL证书申请成功: *.$root_domain"
        return 0
    else
        log_error "泛域名SSL证书申请失败: *.$root_domain"
        return 1
    fi
}

# 泛域名部署
deploy_wildcard() {
    local root_domain=$1
    local admin_email=$2
    local dns_provider=$3
    
    if [ -z "$root_domain" ] || [ -z "$admin_email" ] || [ -z "$dns_provider" ]; then
        log_error "参数不完整"
        show_usage
        exit 1
    fi
    
    # 加载环境变量
    load_env_file
    
    # 验证DNS API配置
    if ! validate_dns_credentials "$dns_provider"; then
        exit 1
    fi
    
    log_info "开始部署泛域名SSL方案..."
    log_info "根域名: $root_domain"
    log_info "DNS提供商: $dns_provider"
    
    # 1. 生成FRPS配置
    local frps_token="Mercury123*"
    local dashboard_user="admin"
    local dashboard_pwd=$(openssl rand -hex 12)
    
    # 使用安全配置管理
    source_secret_utils
    if [ -n "$FRPS_TOKEN" ]; then
        frps_token="$FRPS_TOKEN"
    fi
    if [ -n "$ADMIN_PASSWORD" ]; then
        dashboard_pwd="$ADMIN_PASSWORD"
    fi
    
    generate_frps_config "$root_domain" "$frps_token" "$dashboard_user" "$dashboard_pwd"
    
    # 2. 生成泛域名nginx配置（先生成HTTP版本）
    generate_wildcard_nginx_config_http "$root_domain"
    
    # 3. 启动基础服务
    log_info "启动基础服务..."
    docker-compose -f "$SCRIPT_DIR/docker-compose.yml" up -d nginx frps
    
    # 等待服务启动
    sleep 10
    
    # 4. 申请泛域名SSL证书
    if request_wildcard_certificate "$root_domain" "$admin_email" "$dns_provider"; then
        log_info "泛域名SSL证书申请成功"
    else
        log_error "泛域名SSL证书申请失败"
        return 1
    fi
    
    # 5. 生成SSL配置
    generate_wildcard_nginx_config "$root_domain"
    
    # 6. 重新加载nginx
    docker exec nginx-proxy nginx -s reload
    log_info "泛域名配置完成"
    
    # 7. 最终重启服务
    log_info "重启所有服务以应用SSL配置..."
    docker-compose -f "$SCRIPT_DIR/docker-compose.yml" restart
    
    # 8. 显示部署结果
    echo ""
    echo -e "${GREEN}🎉 泛域名SSL部署完成！${NC}"
    echo ""
    echo -e "${CYAN}服务访问地址:${NC}"
    echo -e "  FRPS服务: ${YELLOW}https://$root_domain${NC}"
    echo -e "  管理界面: ${YELLOW}https://admin.$root_domain${NC} (${dashboard_user}/${dashboard_pwd})"
    echo -e "  任意子域名: ${YELLOW}https://任意名称.$root_domain${NC} (自动SSL)"
    echo ""
    echo -e "${CYAN}FRPS配置信息:${NC}"
    echo -e "  Token: ${YELLOW}${frps_token:0:8}...${frps_token: -4}${NC}"
    echo -e "  服务器: ${YELLOW}$root_domain:7000${NC}"
    echo -e "  完整配置: ${YELLOW}./secret-utils.sh info${NC}"
    echo ""
    echo -e "${GREEN}✅ 现在任何子域名都会自动拥有SSL证书！${NC}"
    echo ""
}

# 生成泛域名HTTP配置（用于证书申请前）
generate_wildcard_nginx_config_http() {
    local root_domain=$1
    
    log_info "生成泛域名HTTP配置..."
    
    cat > "$SCRIPT_DIR/nginx/conf/conf.d/wildcard.conf" << EOF
# 泛域名HTTP配置（用于证书申请）
server {
    listen 80;
    server_name $root_domain *.$root_domain;

    location /.well-known/acme-challenge/ {
        root /usr/share/nginx/html;
    }

    location / {
        return 200 'SSL certificate setup in progress...';
        add_header Content-Type text/plain;
    }
}
EOF
    
    log_info "泛域名HTTP配置生成完成"
}

# 生成泛域名nginx配置
generate_wildcard_nginx_config() {
    local root_domain=$1
    
    log_info "生成泛域名nginx SSL配置..."
    
    cat > "$SCRIPT_DIR/nginx/conf/conf.d/wildcard.conf" << EOF
# 泛域名HTTP -> HTTPS重定向
server {
    listen 80;
    server_name $root_domain *.$root_domain;

    location /.well-known/acme-challenge/ {
        root /usr/share/nginx/html;
    }

    location / {
        return 301 https://\$server_name\$request_uri;
    }
}

# 泛域名HTTPS服务器
server {
    listen 443 ssl;
    http2 on;
    server_name $root_domain *.$root_domain;

    # 泛域名SSL证书 (需要手动申请)
    ssl_certificate /etc/letsencrypt/live/$root_domain/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$root_domain/privkey.pem;

    # HSTS
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;

    # 日志
    access_log /var/log/nginx/wildcard.access.log main;
    error_log /var/log/nginx/wildcard.error.log;

    # FRPS管理界面 (admin-frps子域名)
    location / {
        # 如果是管理子域名
        if (\$host = "admin-frps.$root_domain") {
            proxy_pass http://frps:7001;
            break;
        }
        
        # 所有其他域名和子域名代理到FRPS虚拟主机
        proxy_pass http://frps:8880;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$http_connection;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
    
    log_info "泛域名nginx配置生成完成"
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
            elif [ $# -ge 5 ]; then
                # deploy frps.example.com dashboard.example.com other.example.com ... admin@example.com
                # 提取邮箱（最后一个参数）
                local email="${@: -1}"
                # 提取所有域名（除了最后一个参数）
                local domains=("${@:2:$#-2}")
                deploy_multiple_domains "${domains[@]}" "$email"
            else
                log_error "参数不正确"
                show_usage
                exit 1
            fi
            ;;
        "wildcard")
            check_dependencies
            init_deployment
            if [ $# -eq 4 ]; then
                # wildcard example.com admin@example.com cloudflare
                deploy_wildcard "$2" "$3" "$4"
            else
                log_error "泛域名部署参数不正确"
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
        "security")
            if [ -f "$SCRIPT_DIR/security-enhancements.sh" ]; then
                "$SCRIPT_DIR/security-enhancements.sh" "${2:-all}"
            else
                log_error "安全增强脚本未找到"
                exit 1
            fi
            ;;
        "health")
            if [ -f "$SCRIPT_DIR/health-check.sh" ]; then
                "$SCRIPT_DIR/health-check.sh"
            else
                log_error "健康检查脚本未找到"
                exit 1
            fi
            ;;
        "help"|*)
            show_usage
            ;;
    esac
}

main "$@"