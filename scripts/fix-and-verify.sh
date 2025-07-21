#!/bin/bash
# 完整修复和验证 FRPS 部署

DOMAIN=${1:-jzhou.fun}
SCRIPT_DIR="/home/jack/frps/frps"
cd "$SCRIPT_DIR"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${BLUE}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║           FRPS 泛域名部署修复和验证工具                  ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

# 1. 检查并修复 FRPS 配置
echo -e "${YELLOW}[1/6] 检查 FRPS 配置...${NC}"
VHOST_HTTP_PORT=$(grep "vhostHTTPPort" frps/config/frps.toml | cut -d'=' -f2 | tr -d ' ')
VHOST_HTTPS_PORT=$(grep "vhostHTTPSPort" frps/config/frps.toml | cut -d'=' -f2 | tr -d ' ')
TOKEN=$(grep "^token" frps/config/frps.toml | cut -d'"' -f2)
DASHBOARD_USER=$(grep "webServer.user" frps/config/frps.toml | cut -d'"' -f2)
DASHBOARD_PWD=$(grep "webServer.password" frps/config/frps.toml | cut -d'"' -f2)

echo -e "  vhostHTTPPort: ${GREEN}${VHOST_HTTP_PORT:-8880}${NC}"
echo -e "  vhostHTTPSPort: ${GREEN}${VHOST_HTTPS_PORT:-8843}${NC}"

# 如果端口配置不存在，添加它们
if [ -z "$VHOST_HTTP_PORT" ]; then
    echo -e "${YELLOW}  添加 vhostHTTPPort 配置...${NC}"
    sed -i '/\[common\]/a vhostHTTPPort = 8880' frps/config/frps.toml
    VHOST_HTTP_PORT=8880
fi

# 2. 创建正确的 Nginx 配置
echo -e "${YELLOW}[2/6] 创建 Nginx 配置...${NC}"
cat > nginx/conf/conf.d/${DOMAIN}.conf << EOF
# HTTP 到 HTTPS 重定向
server {
    listen 80;
    server_name ${DOMAIN} *.${DOMAIN};
    
    location /.well-known/acme-challenge/ {
        root /usr/share/nginx/html;
    }
    
    location / {
        return 301 https://\$server_name\$request_uri;
    }
}

# HTTPS 配置 - 泛域名代理
server {
    listen 443 ssl;
    http2 on;
    server_name *.${DOMAIN};  # 注意：只匹配子域名

    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    
    # SSL 安全配置
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    
    # 安全头
    add_header Strict-Transport-Security "max-age=63072000" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;

    # 代理到 FRPS HTTP 端口
    location / {
        proxy_pass http://frps:${VHOST_HTTP_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # WebSocket 支持
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        
        # 超时设置
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        # 错误处理
        proxy_intercept_errors on;
        error_page 404 502 503 504 /error.html;
    }
    
    location = /error.html {
        internal;
        root /usr/share/nginx/html;
        try_files /404.html =404;
    }
}

# HTTPS 配置 - 主域名
server {
    listen 443 ssl;
    http2 on;
    server_name ${DOMAIN};  # 只匹配主域名

    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    
    # 主域名显示欢迎页面
    location / {
        root /usr/share/nginx/html;
        index index.html;
    }
}

# WebSocket 连接升级映射
map \$http_upgrade \$connection_upgrade {
    default upgrade;
    ''      close;
}
EOF

# 3. 创建管理面板配置
echo -e "${YELLOW}[3/6] 创建管理面板配置...${NC}"
cat > nginx/conf/conf.d/admin-${DOMAIN}.conf << EOF
server {
    listen 443 ssl;
    http2 on;
    server_name admin.${DOMAIN};

    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;

    location / {
        proxy_pass http://frps:7001;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

# 4. 重启服务
echo -e "${YELLOW}[4/6] 重启服务...${NC}"
docker-compose restart frps-server
sleep 3
docker exec nginx-proxy nginx -s reload

# 5. 验证服务
echo -e "${YELLOW}[5/6] 验证服务状态...${NC}"
echo -e "  ${CYAN}容器状态:${NC}"
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "nginx-proxy|frps-server"

echo -e "\n  ${CYAN}端口监听:${NC}"
docker exec frps-server netstat -tlnp 2>/dev/null | grep -E "7000|7001|${VHOST_HTTP_PORT}" || echo "    无法获取端口信息"

echo -e "\n  ${CYAN}网络连通性测试:${NC}"
docker exec nginx-proxy wget -q -O- --timeout=2 http://frps:${VHOST_HTTP_PORT} 2>&1 | head -1 || echo "    FRPS HTTP 端口: ${RED}未响应${NC}"

# 6. 生成配置信息文件
echo -e "${YELLOW}[6/6] 生成配置信息...${NC}"
cat > deployment-info.txt << EOF
╔══════════════════════════════════════════════════════════════════════╗
║                     FRPS 泛域名部署配置信息                          ║
╚══════════════════════════════════════════════════════════════════════╝

部署时间: $(date)
服务器IP: $(curl -s ifconfig.me 2>/dev/null || echo "35.236.190.253")

=== 证书信息 ===
域名: ${DOMAIN}
泛域名: *.${DOMAIN}
证书状态: $([ -f "certbot/data/live/${DOMAIN}/fullchain.pem" ] && echo "✅ 已安装" || echo "❌ 未找到")

=== FRPS 服务配置 ===
服务地址: ${DOMAIN}:7000
Token: ${TOKEN}
HTTP 代理端口: ${VHOST_HTTP_PORT}
HTTPS 代理端口: ${VHOST_HTTPS_PORT}

=== 管理面板 ===
访问地址: https://admin.${DOMAIN}
用户名: ${DASHBOARD_USER:-admin}
密码: ${DASHBOARD_PWD}

=== FRPC 客户端配置示例 ===
创建 frpc.toml 文件：

[common]
server_addr = "${DOMAIN}"
server_port = 7000
token = "${TOKEN}"

[web-demo]
type = "http"
local_ip = "127.0.0.1"
local_port = 8080
subdomain = "demo"
# 访问地址: https://demo.${DOMAIN}

[api-service]
type = "http"  
local_ip = "127.0.0.1"
local_port = 3000
subdomain = "api"
# 访问地址: https://api.${DOMAIN}

=== 测试命令 ===
# 测试证书
curl -I https://${DOMAIN}

# 测试子域名（需要先启动 frpc 客户端）
curl https://demo.${DOMAIN}

# 查看管理面板
访问 https://admin.${DOMAIN}

=== 故障排查 ===
# 查看 FRPS 日志
docker logs frps-server

# 查看 Nginx 日志  
docker logs nginx-proxy

# 测试内部连接
docker exec nginx-proxy curl http://frps:${VHOST_HTTP_PORT}

=== DNS 配置提醒 ===
确保已配置泛域名解析：
*.${DOMAIN} → $(curl -s ifconfig.me 2>/dev/null || echo "服务器IP")

EOF

# 显示配置信息
echo ""
cat deployment-info.txt

# 保存到 .secrets 目录
mkdir -p .secrets
cp deployment-info.txt .secrets/

echo -e "\n${GREEN}✅ 修复完成！配置信息已保存到:${NC}"
echo -e "   ${CYAN}./deployment-info.txt${NC}"
echo -e "   ${CYAN}./.secrets/deployment-info.txt${NC}"

# 测试一下
echo -e "\n${YELLOW}正在测试...${NC}"
echo -e "主域名测试: $(curl -s -o /dev/null -w "%{http_code}" https://${DOMAIN} -k)"
echo -e "管理面板测试: $(curl -s -o /dev/null -w "%{http_code}" https://admin.${DOMAIN} -k)"

echo -e "\n${BLUE}提示：${NC}"
echo -e "1. 启动你的 FRPC 客户端连接到 ${DOMAIN}:7000"
echo -e "2. 访问 https://subdomain.${DOMAIN} 查看效果"
echo -e "3. 管理面板: https://admin.${DOMAIN}"