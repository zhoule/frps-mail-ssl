#!/bin/bash
# 完成泛域名部署的脚本（证书已存在时使用）

DOMAIN=$1
SCRIPT_DIR="/home/jack/frps/frps"

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

if [ -z "$DOMAIN" ]; then
    echo "用法: $0 <domain>"
    echo "示例: $0 jzhou.fun"
    exit 1
fi

echo -e "${GREEN}[INFO]${NC} 完成 $DOMAIN 的泛域名部署..."

# 1. 安装现有证书
echo -e "${GREEN}[INFO]${NC} 安装证书..."
~/.acme.sh/acme.sh --install-cert \
    -d "$DOMAIN" \
    --key-file "$SCRIPT_DIR/certbot/data/live/$DOMAIN/privkey.pem" \
    --fullchain-file "$SCRIPT_DIR/certbot/data/live/$DOMAIN/fullchain.pem" \
    --cert-file "$SCRIPT_DIR/certbot/data/live/$DOMAIN/cert.pem" \
    --ca-file "$SCRIPT_DIR/certbot/data/live/$DOMAIN/chain.pem" \
    --reloadcmd "docker exec nginx-proxy nginx -s reload 2>/dev/null || true"

if [ $? -ne 0 ]; then
    echo -e "${RED}[ERROR]${NC} 证书安装失败"
    exit 1
fi

# 2. 生成泛域名 HTTPS 配置
echo -e "${GREEN}[INFO]${NC} 生成泛域名 HTTPS 配置..."
cat > "$SCRIPT_DIR/nginx/conf/conf.d/${DOMAIN}-wildcard.conf" << EOF
# 泛域名 HTTP 重定向
server {
    listen 80;
    server_name *.${DOMAIN} ${DOMAIN};
    
    location /.well-known/acme-challenge/ {
        root /usr/share/nginx/html;
    }
    
    location / {
        return 301 https://\$server_name\$request_uri;
    }
}

# 泛域名 HTTPS 配置
server {
    listen 443 ssl;
    http2 on;
    server_name *.${DOMAIN} ${DOMAIN};

    # SSL证书
    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;

    # SSL优化
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    # 安全头
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    # 日志
    access_log /var/log/nginx/${DOMAIN}_access.log;
    error_log /var/log/nginx/${DOMAIN}_error.log;

    # 根目录（默认页面）
    location = / {
        root /usr/share/nginx/html;
        try_files /index.html =404;
    }

    # FRPS 代理
    location / {
        proxy_pass http://frps:8880;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # WebSocket 支持
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$http_connection;
        
        # 超时设置
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}
EOF

# 3. 删除旧的 HTTP 配置（如果存在）
if [ -f "$SCRIPT_DIR/nginx/conf/conf.d/${DOMAIN}.conf" ]; then
    echo -e "${GREEN}[INFO]${NC} 删除旧的 HTTP 配置..."
    rm -f "$SCRIPT_DIR/nginx/conf/conf.d/${DOMAIN}.conf"
fi

# 4. 重启 Nginx
echo -e "${GREEN}[INFO]${NC} 重启 Nginx..."
docker restart nginx-proxy

# 等待服务启动
sleep 5

# 5. 检查服务状态
echo -e "${GREEN}[INFO]${NC} 检查服务状态..."
docker ps | grep -E "nginx-proxy|frps-server"

# 6. 设置自动续期
echo -e "${GREEN}[INFO]${NC} 配置自动续期..."
~/.acme.sh/acme.sh --upgrade --auto-upgrade

echo ""
echo -e "${GREEN}========== 部署完成！==========${NC}"
echo ""
echo -e "${YELLOW}访问地址：${NC}"
echo -e "  主域名: https://${DOMAIN}"
echo -e "  泛域名: https://*.${DOMAIN}"
echo ""
echo -e "${YELLOW}测试命令：${NC}"
echo -e "  curl -I https://${DOMAIN}"
echo -e "  curl -I https://test.${DOMAIN}"
echo ""
echo -e "${YELLOW}FRPS 客户端配置示例：${NC}"
echo "[common]"
echo "server_addr = ${DOMAIN}"
echo "server_port = 7000"
echo "token = $(cat $SCRIPT_DIR/.secrets/frps-credentials.txt 2>/dev/null | grep 'Token:' | cut -d' ' -f2 || echo 'check .secrets/frps-credentials.txt')"
echo ""
echo "[web]"
echo "type = http"
echo "local_ip = 127.0.0.1"
echo "local_port = 8080"
echo "subdomain = app"
echo "# 访问: https://app.${DOMAIN}"
echo ""
echo -e "${GREEN}查看日志：${NC}"
echo "  docker logs nginx-proxy"
echo "  docker logs frps-server"