#!/bin/bash
# FRPS 泛域名一键部署脚本 v2.0
# 简单、清晰、可靠

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 基础配置
WORK_DIR="$(cd "$(dirname "$0")" && pwd)"
DOMAIN="$1"
EMAIL="$2"
DNS_PROVIDER="${3:-manual}"

# 使用说明
show_usage() {
    echo "使用方法："
    echo "  $0 <域名> <邮箱> [DNS提供商]"
    echo ""
    echo "示例："
    echo "  $0 example.com admin@example.com cloudflare"
    echo "  $0 example.com admin@example.com tencent"
    echo ""
    echo "支持的 DNS 提供商："
    echo "  cloudflare, tencent, aliyun, dnspod, manual(手动)"
    exit 1
}

# 日志函数
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[错误]${NC} $1" >&2
    exit 1
}

# 检查参数
if [ -z "$DOMAIN" ] || [ -z "$EMAIL" ]; then
    show_usage
fi

# 1. 环境检查
check_requirements() {
    log "检查系统环境..."
    
    # 检查 Docker
    if ! command -v docker &> /dev/null; then
        error "请先安装 Docker"
    fi
    
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null 2>&1; then
        error "请先安装 Docker Compose"
    fi
    
    # 检查端口
    for port in 80 443 7000; do
        if lsof -i :$port &> /dev/null; then
            error "端口 $port 已被占用"
        fi
    done
    
    log "环境检查通过 ✓"
}

# 2. 安装 acme.sh
install_acme() {
    if [ ! -d "$HOME/.acme.sh" ]; then
        log "安装 acme.sh..."
        curl https://get.acme.sh | sh -s email=$EMAIL
        source "$HOME/.acme.sh/acme.sh.env"
    fi
    log "acme.sh 已就绪 ✓"
}

# 3. 申请泛域名证书
request_certificate() {
    local cert_path="$WORK_DIR/ssl/$DOMAIN"
    
    # 检查证书是否已存在
    if [ -f "$cert_path/fullchain.pem" ]; then
        log "证书已存在，检查有效性..."
        if openssl x509 -checkend 86400 -noout -in "$cert_path/fullchain.pem" &> /dev/null; then
            log "证书有效，跳过申请 ✓"
            return 0
        fi
    fi
    
    log "申请泛域名证书 *.$DOMAIN..."
    mkdir -p "$cert_path"
    
    # 设置 DNS API 凭据（从环境变量）
    case "$DNS_PROVIDER" in
        cloudflare)
            export CF_Email="$CLOUDFLARE_EMAIL"
            export CF_Key="$CLOUDFLARE_API_KEY"
            ;;
        tencent)
            export Tencent_SecretId="$TENCENTCLOUD_SECRET_ID"
            export Tencent_SecretKey="$TENCENTCLOUD_SECRET_KEY"
            ;;
        aliyun)
            export Ali_Key="$ALIBABA_CLOUD_ACCESS_KEY_ID"
            export Ali_Secret="$ALIBABA_CLOUD_ACCESS_KEY_SECRET"
            ;;
        manual)
            log "使用手动 DNS 验证模式"
            ;;
    esac
    
    # 申请证书
    if [ "$DNS_PROVIDER" = "manual" ]; then
        "$HOME/.acme.sh/acme.sh" --issue -d "$DOMAIN" -d "*.$DOMAIN" --dns --yes-I-know-dns-manual-mode-enough-go-ahead-please
        log "${YELLOW}请按照提示添加 DNS TXT 记录，然后按回车继续...${NC}"
        read -p "按回车继续..."
        "$HOME/.acme.sh/acme.sh" --renew -d "$DOMAIN" --yes-I-know-dns-manual-mode-enough-go-ahead-please
    else
        "$HOME/.acme.sh/acme.sh" --issue -d "$DOMAIN" -d "*.$DOMAIN" --dns "dns_${DNS_PROVIDER}"
    fi
    
    # 安装证书
    "$HOME/.acme.sh/acme.sh" --install-cert -d "$DOMAIN" \
        --key-file "$cert_path/privkey.pem" \
        --fullchain-file "$cert_path/fullchain.pem" \
        --reloadcmd "cd $WORK_DIR && docker-compose restart nginx 2>/dev/null || true"
    
    log "证书申请成功 ✓"
}

# 4. 生成配置文件
generate_configs() {
    log "生成配置文件..."
    
    # 生成随机密码和 token
    FRPS_TOKEN=$(openssl rand -hex 16)
    ADMIN_PASSWORD=$(openssl rand -base64 12)
    
    # 创建目录结构
    mkdir -p "$WORK_DIR"/{frps,nginx/conf.d,ssl,logs}
    
    # FRPS 配置
    cat > "$WORK_DIR/frps/frps.toml" << EOF
bindPort = 7000
vhostHTTPPort = 8080
vhostHTTPSPort = 8443

# 认证
auth.method = "token"
auth.token = "$FRPS_TOKEN"

# 管理面板
webServer.addr = "0.0.0.0"
webServer.port = 7001
webServer.user = "admin"
webServer.password = "$ADMIN_PASSWORD"

# 日志
log.to = "console"
log.level = "info"

# 允许所有端口
allowPorts = [
  { start = 1, end = 65535 }
]

# 子域名
subdomainHost = "$DOMAIN"
EOF

    # Nginx 配置
    cat > "$WORK_DIR/nginx/nginx.conf" << 'EOF'
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    sendfile on;
    keepalive_timeout 65;
    
    # WebSocket 支持
    map $http_upgrade $connection_upgrade {
        default upgrade;
        ''      close;
    }
    
    include /etc/nginx/conf.d/*.conf;
}
EOF

    # Nginx 站点配置
    cat > "$WORK_DIR/nginx/conf.d/default.conf" << EOF
# HTTP 重定向
server {
    listen 80;
    server_name $DOMAIN *.$DOMAIN;
    return 301 https://\$server_name\$request_uri;
}

# 主域名
server {
    listen 443 ssl http2;
    server_name $DOMAIN;
    
    ssl_certificate /ssl/$DOMAIN/fullchain.pem;
    ssl_certificate_key /ssl/$DOMAIN/privkey.pem;
    
    location / {
        return 200 "FRPS 部署成功！\n\n访问 https://admin.$DOMAIN 查看管理面板\n";
        add_header Content-Type text/plain;
    }
}

# 管理面板
server {
    listen 443 ssl http2;
    server_name admin.$DOMAIN;
    
    ssl_certificate /ssl/$DOMAIN/fullchain.pem;
    ssl_certificate_key /ssl/$DOMAIN/privkey.pem;
    
    location / {
        proxy_pass http://frps:7001;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}

# 泛域名（FRPS 代理）
server {
    listen 443 ssl http2;
    server_name *.$DOMAIN;
    
    ssl_certificate /ssl/$DOMAIN/fullchain.pem;
    ssl_certificate_key /ssl/$DOMAIN/privkey.pem;
    
    location / {
        proxy_pass http://frps:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # WebSocket
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
    }
}
EOF

    # Docker Compose 配置
    cat > "$WORK_DIR/docker-compose.yml" << EOF
version: '3'

services:
  frps:
    image: snowdreamtech/frps:latest
    container_name: frps
    restart: always
    ports:
      - "7000:7000"
    volumes:
      - ./frps/frps.toml:/etc/frp/frps.toml:ro
      - ./logs:/var/log
    networks:
      - frp-net

  nginx:
    image: nginx:alpine
    container_name: nginx
    restart: always
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./nginx/conf.d:/etc/nginx/conf.d:ro
      - ./ssl:/ssl:ro
      - ./logs:/var/log/nginx
    depends_on:
      - frps
    networks:
      - frp-net

networks:
  frp-net:
    driver: bridge
EOF

    log "配置文件生成完成 ✓"
}

# 5. 启动服务
start_services() {
    log "启动服务..."
    cd "$WORK_DIR"
    
    # 使用 docker-compose 或 docker compose
    if command -v docker-compose &> /dev/null; then
        docker-compose up -d
    else
        docker compose up -d
    fi
    
    # 等待服务启动
    sleep 5
    
    # 检查服务状态
    if docker ps | grep -q "frps.*Up" && docker ps | grep -q "nginx.*Up"; then
        log "服务启动成功 ✓"
    else
        error "服务启动失败，请检查日志"
    fi
}

# 6. 输出配置信息
show_info() {
    # 保存配置信息
    cat > "$WORK_DIR/deployment-info.txt" << EOF
====================================
    FRPS 泛域名部署信息
====================================

部署时间: $(date)
域名: $DOMAIN
服务器 IP: $(curl -s ifconfig.me 2>/dev/null || echo "请手动获取")

==== 服务地址 ====
FRPS 端口: 7000
管理面板: https://admin.$DOMAIN
用户名: admin
密码: $ADMIN_PASSWORD

==== FRPC 客户端配置 ====
[common]
server_addr = "$DOMAIN"
server_port = 7000
token = "$FRPS_TOKEN"

[web]
type = "http"
local_ip = "127.0.0.1"
local_port = 8080
subdomain = "demo"
# 访问: https://demo.$DOMAIN

==== 测试命令 ====
curl https://$DOMAIN
curl https://admin.$DOMAIN

==== 查看日志 ====
docker logs frps
docker logs nginx
EOF

    echo ""
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo -e "${GREEN}    🎉 部署成功！${NC}"
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo ""
    cat "$WORK_DIR/deployment-info.txt"
    echo ""
    echo -e "${YELLOW}配置已保存到: $WORK_DIR/deployment-info.txt${NC}"
}

# 主流程
main() {
    echo -e "${BLUE}FRPS 泛域名一键部署 v2.0${NC}"
    echo ""
    
    check_requirements
    install_acme
    request_certificate
    generate_configs
    start_services
    show_info
}

# 执行主流程
main