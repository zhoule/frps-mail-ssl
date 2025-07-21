#!/bin/bash
# 修复已存在证书的部署问题

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}[INFO]${NC} 检查并安装已存在的证书..."

# 安装现有证书
~/.acme.sh/acme.sh --install-cert \
    -d "flowbytes.cn" \
    --key-file "/home/jack/frps/frps/certbot/data/live/flowbytes.cn/privkey.pem" \
    --fullchain-file "/home/jack/frps/frps/certbot/data/live/flowbytes.cn/fullchain.pem" \
    --cert-file "/home/jack/frps/frps/certbot/data/live/flowbytes.cn/cert.pem" \
    --ca-file "/home/jack/frps/frps/certbot/data/live/flowbytes.cn/chain.pem" \
    --reloadcmd "docker exec nginx-proxy nginx -s reload 2>/dev/null || true"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}[INFO]${NC} 证书安装成功"
    
    # 生成 HTTPS 配置
    echo -e "${GREEN}[INFO]${NC} 生成泛域名 HTTPS 配置..."
    
    # 创建 HTTPS 配置文件
    cat > /home/jack/frps/frps/nginx/conf/conf.d/wildcard-ssl.conf << 'EOF'
# 泛域名 HTTPS 配置
server {
    listen 443 ssl;
    http2 on;
    server_name *.flowbytes.cn flowbytes.cn;

    # SSL证书
    ssl_certificate /etc/letsencrypt/live/flowbytes.cn/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/flowbytes.cn/privkey.pem;

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

    # FRPS 代理
    location / {
        proxy_pass http://frps:8880;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # WebSocket 支持
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $http_connection;
    }
}
EOF

    # 重启 nginx
    echo -e "${GREEN}[INFO]${NC} 重启 Nginx..."
    docker restart nginx-proxy
    
    echo -e "${GREEN}[SUCCESS]${NC} 部署完成！"
    echo ""
    echo -e "${YELLOW}访问地址：${NC}"
    echo -e "  主域名: https://flowbytes.cn"
    echo -e "  泛域名: https://*.flowbytes.cn"
    echo ""
    echo -e "${YELLOW}FRPS 客户端配置示例：${NC}"
    echo "[common]"
    echo "server_addr = flowbytes.cn"
    echo "server_port = 7000"
    echo "token = 查看 .secrets/frps-credentials.txt"
    echo ""
    echo "[web]"
    echo "type = http"
    echo "local_ip = 127.0.0.1"
    echo "local_port = 8080"
    echo "subdomain = test"
    echo "# 访问: https://test.flowbytes.cn"
else
    echo -e "${RED}[ERROR]${NC} 证书安装失败"
    exit 1
fi