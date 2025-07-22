#!/bin/bash
# FRPS 泛域名一键部署脚本 - 最终版
# 完整、可靠、无需手动修改

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

# 固定配置
FRPS_HTTP_PORT=8880
FRPS_HTTPS_PORT=8843

# 使用说明
show_usage() {
    echo "使用方法："
    echo "  $0 <域名> <邮箱> [DNS提供商]"
    echo ""
    echo "示例："
    echo "  $0 example.com admin@example.com cloudflare"
    echo "  $0 example.com admin@example.com tencent"
    echo "  $0 example.com admin@example.com manual"
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

# 1. 环境检查和清理
prepare_environment() {
    log "准备环境..."
    
    # 检查 Docker
    if ! command -v docker &> /dev/null; then
        error "请先安装 Docker"
    fi
    
    # 停止可能存在的旧容器
    log "清理旧容器..."
    docker stop nginx-proxy frps-server nginx frps 2>/dev/null || true
    docker rm nginx-proxy frps-server nginx frps 2>/dev/null || true
    
    # 如果有 docker-compose，也停止
    if [ -f "$WORK_DIR/docker-compose.yml" ]; then
        docker-compose down 2>/dev/null || docker compose down 2>/dev/null || true
    fi
    
    # 等待端口释放
    sleep 3
    
    # 创建目录结构
    mkdir -p "$WORK_DIR"/{frps,nginx/conf.d,nginx/html,ssl,logs,data}
    
    log "环境准备完成 ✓"
}

# 2. 安装 acme.sh
install_acme() {
    if [ ! -d "$HOME/.acme.sh" ]; then
        log "安装 acme.sh..."
        curl -s https://get.acme.sh | sh -s email=$EMAIL
    fi
    
    # 确保环境变量可用
    export PATH="$HOME/.acme.sh:$PATH"
    
    log "acme.sh 已就绪 ✓"
}

# 3. 申请证书
request_certificate() {
    local cert_path="$WORK_DIR/ssl/$DOMAIN"
    
    # 检查证书是否已存在且有效
    if [ -f "$cert_path/fullchain.pem" ]; then
        log "检查现有证书..."
        if openssl x509 -checkend 86400 -noout -in "$cert_path/fullchain.pem" &> /dev/null; then
            log "证书有效，跳过申请 ✓"
            return 0
        fi
    fi
    
    log "申请泛域名证书 *.$DOMAIN..."
    mkdir -p "$cert_path"
    
    # 加载 DNS API 凭据
    if [ -f "$WORK_DIR/.env" ]; then
        source "$WORK_DIR/.env"
    fi
    
    # 设置 DNS API
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
    esac
    
    # 申请证书
    "$HOME/.acme.sh/acme.sh" --issue -d "$DOMAIN" -d "*.$DOMAIN" --dns "dns_${DNS_PROVIDER}" || {
        error "证书申请失败，请检查 DNS 配置"
    }
    
    # 安装证书
    "$HOME/.acme.sh/acme.sh" --install-cert -d "$DOMAIN" \
        --key-file "$cert_path/privkey.pem" \
        --fullchain-file "$cert_path/fullchain.pem" \
        --reloadcmd "docker restart nginx 2>/dev/null || true"
    
    log "证书申请成功 ✓"
}

# 4. 生成配置
generate_configs() {
    log "生成配置文件..."
    
    # 生成密码
    FRPS_TOKEN=$(openssl rand -hex 16)
    ADMIN_PASSWORD=$(openssl rand -base64 12)
    
    # FRPS 配置
    cat > "$WORK_DIR/frps/frps.toml" << EOF
bindPort = 7000
vhostHTTPPort = ${FRPS_HTTP_PORT}
vhostHTTPSPort = ${FRPS_HTTPS_PORT}

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

# 子域名
subdomainHost = "$DOMAIN"
EOF

    # Nginx 主配置
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

    # Nginx 站点配置 - 分成多个文件避免冲突
    
    # 1. HTTP 重定向
    cat > "$WORK_DIR/nginx/conf.d/00-redirect.conf" << EOF
server {
    listen 80;
    server_name $DOMAIN *.$DOMAIN;
    return 301 https://\$server_name\$request_uri;
}
EOF

    # 2. 主域名
    cat > "$WORK_DIR/nginx/conf.d/10-main.conf" << EOF
server {
    listen 443 ssl http2;
    server_name $DOMAIN;
    
    ssl_certificate /ssl/$DOMAIN/fullchain.pem;
    ssl_certificate_key /ssl/$DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    
    root /usr/share/nginx/html;
    index index.html;
    
    location / {
        try_files \$uri \$uri/ /index.html;
    }
}
EOF

    # 3. 管理面板
    cat > "$WORK_DIR/nginx/conf.d/20-admin.conf" << EOF
server {
    listen 443 ssl http2;
    server_name admin.$DOMAIN;
    
    ssl_certificate /ssl/$DOMAIN/fullchain.pem;
    ssl_certificate_key /ssl/$DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    
    location / {
        proxy_pass http://frps:7001;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

    # 4. FRPS 代理（所有其他子域名）
    cat > "$WORK_DIR/nginx/conf.d/30-wildcard.conf" << EOF
server {
    listen 443 ssl http2;
    server_name *.$DOMAIN;
    
    ssl_certificate /ssl/$DOMAIN/fullchain.pem;
    ssl_certificate_key /ssl/$DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    
    location / {
        proxy_pass http://frps:${FRPS_HTTP_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        # 错误处理
        proxy_intercept_errors off;
    }
}
EOF

    # 创建主页
    cat > "$WORK_DIR/nginx/html/index.html" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>FRPS - $DOMAIN</title>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { 
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        .container {
            background: white;
            padding: 3rem;
            border-radius: 10px;
            box-shadow: 0 20px 40px rgba(0,0,0,0.1);
            max-width: 600px;
            width: 90%;
        }
        h1 { color: #333; margin-bottom: 1.5rem; }
        .status { 
            background: #f0f0f0; 
            padding: 1rem; 
            border-radius: 5px; 
            margin: 1rem 0;
        }
        .status.success { border-left: 4px solid #4CAF50; }
        a { color: #667eea; text-decoration: none; }
        a:hover { text-decoration: underline; }
        code {
            background: #f5f5f5;
            padding: 2px 6px;
            border-radius: 3px;
            font-family: monospace;
        }
        pre {
            background: #2d2d2d;
            color: #fff;
            padding: 1rem;
            border-radius: 5px;
            overflow-x: auto;
            margin: 1rem 0;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🎉 FRPS 部署成功</h1>
        
        <div class="status success">
            <strong>✅ 服务状态：</strong>运行中
        </div>
        
        <h2>快速访问</h2>
        <ul>
            <li>管理面板：<a href="https://admin.$DOMAIN" target="_blank">https://admin.$DOMAIN</a></li>
            <li>服务地址：<code>$DOMAIN:7000</code></li>
        </ul>
        
        <h2>客户端配置示例</h2>
        <pre>[common]
server_addr = "$DOMAIN"
server_port = 7000
token = "查看 deployment-info.txt"

[web]
type = "http"
local_ip = "127.0.0.1"
local_port = 8080
subdomain = "demo"
# 访问: https://demo.$DOMAIN</pre>
        
        <p style="margin-top: 2rem; color: #666; font-size: 0.9rem;">
            配置详情请查看服务器上的 <code>deployment-info.txt</code> 文件
        </p>
    </div>
</body>
</html>
EOF

    # Docker Compose
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
      - ./nginx/html:/usr/share/nginx/html:ro
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
    
    # 启动服务
    docker-compose up -d || docker compose up -d
    
    # 等待服务完全启动
    log "等待服务启动..."
    sleep 5
    
    # 验证服务
    local retry=0
    while [ $retry -lt 10 ]; do
        if docker ps | grep -q "frps.*Up" && docker ps | grep -q "nginx.*Up"; then
            log "服务启动成功 ✓"
            return 0
        fi
        sleep 2
        retry=$((retry + 1))
    done
    
    error "服务启动失败"
}

# 6. 保存配置信息
save_info() {
    cat > "$WORK_DIR/deployment-info.txt" << EOF
=====================================
     FRPS 泛域名部署信息
=====================================

部署时间: $(date)
服务器: $(hostname -I | awk '{print $1}' || curl -s ifconfig.me)
域名: $DOMAIN

===== 管理信息 =====
管理面板: https://admin.$DOMAIN
用户名: admin
密码: $ADMIN_PASSWORD

===== FRPS 配置 =====
服务端口: 7000
Token: $FRPS_TOKEN

===== FRPC 客户端配置 =====
[common]
server_addr = "$DOMAIN"
server_port = 7000
token = "$FRPS_TOKEN"

[web-demo]
type = "http"
local_ip = "127.0.0.1"
local_port = 8080
subdomain = "demo"
# 访问: https://demo.$DOMAIN

[tcp-ssh]
type = "tcp"
local_ip = "127.0.0.1"
local_port = 22
remote_port = 6022
# SSH: ssh -p 6022 user@$DOMAIN

===== 常用命令 =====
查看日志: docker logs frps
重启服务: docker-compose restart
查看状态: docker ps

===== 测试 =====
curl https://$DOMAIN
curl https://admin.$DOMAIN
EOF

    chmod 600 "$WORK_DIR/deployment-info.txt"
}

# 7. 显示结果
show_result() {
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║        🎉 部署成功！                       ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}域名:${NC} $DOMAIN"
    echo -e "${BLUE}管理面板:${NC} https://admin.$DOMAIN"
    echo -e "${BLUE}用户名:${NC} admin"
    echo -e "${BLUE}密码:${NC} $ADMIN_PASSWORD"
    echo ""
    echo -e "${YELLOW}Token:${NC} $FRPS_TOKEN"
    echo ""
    echo -e "${GREEN}配置已保存到:${NC} $WORK_DIR/deployment-info.txt"
    echo ""
    echo -e "${CYAN}测试命令:${NC}"
    echo "  curl https://$DOMAIN"
    echo "  curl https://admin.$DOMAIN"
}

# 主流程
main() {
    echo -e "${BLUE}═══════════════════════════════════════${NC}"
    echo -e "${BLUE}    FRPS 泛域名一键部署 - 最终版      ${NC}"
    echo -e "${BLUE}═══════════════════════════════════════${NC}"
    echo ""
    
    prepare_environment
    install_acme
    request_certificate
    generate_configs
    start_services
    save_info
    show_result
}

# 运行
main