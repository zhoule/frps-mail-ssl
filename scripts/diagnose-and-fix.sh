#!/bin/bash
# FRPS 完整链路诊断和修复脚本

DOMAIN=${1:-jzhou.fun}
cd /home/jack/frps/frps

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}          FRPS 代理链路完整诊断                            ${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"

# 1. 检查容器状态
echo -e "\n${YELLOW}[1] 容器状态检查${NC}"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "NAME|nginx-proxy|frps-server"

# 2. 验证 FRPS 配置和监听端口
echo -e "\n${YELLOW}[2] FRPS 配置验证${NC}"
echo "当前 FRPS 配置："
docker exec frps-server cat /etc/frp/frps.toml | grep -E "bindPort|vhostHTTPPort|vhostHTTPSPort|subdomainHost|token" | head -10

echo -e "\nFRPS 监听端口："
docker exec frps-server netstat -tlnp 2>/dev/null | grep -E "LISTEN|frps" || echo "  无法获取端口信息"

# 3. 测试容器间网络连通性
echo -e "\n${YELLOW}[3] 容器网络测试${NC}"
echo "测试 nginx → frps 连通性："
docker exec nginx-proxy ping -c 2 frps 2>&1 | grep -E "bytes from|packet loss"

echo -e "\n测试 nginx → frps:8880 HTTP 连接："
docker exec nginx-proxy wget -qO- --timeout=3 http://frps:8880 2>&1 | head -5 || echo "  连接失败或无响应"

# 4. 检查 Nginx 配置
echo -e "\n${YELLOW}[4] Nginx 配置检查${NC}"
echo "泛域名配置文件："
ls -la nginx/conf/conf.d/*.conf 2>/dev/null | grep -v "total"

echo -e "\n关键配置内容："
if [ -f "nginx/conf/conf.d/${DOMAIN}.conf" ]; then
    grep -E "server_name|proxy_pass|ssl_certificate" "nginx/conf/conf.d/${DOMAIN}.conf" | head -10
else
    echo "  ${RED}未找到 ${DOMAIN}.conf 配置文件${NC}"
fi

# 5. 测试证书
echo -e "\n${YELLOW}[5] SSL 证书状态${NC}"
if [ -f "certbot/data/live/${DOMAIN}/fullchain.pem" ]; then
    echo -e "  ${GREEN}✓${NC} 证书文件存在"
    openssl x509 -in "certbot/data/live/${DOMAIN}/fullchain.pem" -noout -dates | grep -E "notBefore|notAfter"
else
    echo -e "  ${RED}✗${NC} 证书文件不存在"
fi

# 6. 创建测试服务
echo -e "\n${YELLOW}[6] 创建本地测试服务${NC}"
# 停止可能存在的测试服务
pkill -f "python3 -m http.server 8888" 2>/dev/null

# 启动测试 HTTP 服务
echo "测试页面内容" > /tmp/test.html
cd /tmp && python3 -m http.server 8888 >/dev/null 2>&1 &
TEST_PID=$!
cd - >/dev/null
echo "  已启动测试服务 (PID: $TEST_PID)"

# 7. 生成完整的修复配置
echo -e "\n${YELLOW}[7] 生成修复配置${NC}"

# 7.1 确保 FRPS 配置正确
echo "检查 FRPS vhostHTTPPort 配置..."
VHOST_PORT=$(docker exec frps-server cat /etc/frp/frps.toml | grep "vhostHTTPPort" | cut -d'=' -f2 | tr -d ' ')
echo "  当前 vhostHTTPPort: ${VHOST_PORT:-未设置}"

# 7.2 生成正确的 Nginx 配置
cat > nginx/conf/conf.d/${DOMAIN}-fixed.conf << EOF
# HTTP 重定向
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

# 主域名
server {
    listen 443 ssl;
    http2 on;
    server_name ${DOMAIN};

    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;

    location / {
        root /usr/share/nginx/html;
        index index.html;
    }
}

# 管理面板
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

# 泛域名（所有其他子域名）
server {
    listen 443 ssl;
    http2 on;
    server_name *.${DOMAIN};

    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;

    # 代理到 FRPS HTTP 虚拟主机
    location / {
        proxy_pass http://frps:${VHOST_PORT:-8880};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # WebSocket 支持
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        
        # 调试头
        add_header X-Proxy-Pass "frps:${VHOST_PORT:-8880}" always;
    }
}

# WebSocket 升级映射
map \$http_upgrade \$connection_upgrade {
    default upgrade;
    ''      close;
}
EOF

# 8. 应用配置
echo -e "\n${YELLOW}[8] 应用修复${NC}"
echo "备份旧配置..."
mv nginx/conf/conf.d/${DOMAIN}.conf nginx/conf/conf.d/${DOMAIN}.conf.bak 2>/dev/null
mv nginx/conf/conf.d/wildcard.conf nginx/conf/conf.d/wildcard.conf.bak 2>/dev/null

echo "应用新配置..."
mv nginx/conf/conf.d/${DOMAIN}-fixed.conf nginx/conf/conf.d/${DOMAIN}.conf

echo "重载 Nginx..."
docker exec nginx-proxy nginx -t && docker exec nginx-proxy nginx -s reload

# 9. 创建测试 FRPC 配置
echo -e "\n${YELLOW}[9] 创建测试 FRPC 配置${NC}"
cat > test-frpc.toml << EOF
[common]
server_addr = "127.0.0.1"
server_port = 7000
token = "$(docker exec frps-server cat /etc/frp/frps.toml | grep 'auth.token' | cut -d'"' -f2)"

[test]
type = "http"
local_ip = "127.0.0.1"
local_port = 8888
subdomain = "test"
EOF

echo "  已生成 test-frpc.toml"

# 10. 启动测试 FRPC
echo -e "\n${YELLOW}[10] 测试完整链路${NC}"
if command -v frpc >/dev/null 2>&1; then
    echo "启动 FRPC 客户端..."
    frpc -c test-frpc.toml >/tmp/frpc.log 2>&1 &
    FRPC_PID=$!
    sleep 3
    
    echo -e "\n测试访问："
    echo "  本地直接访问: $(curl -s http://localhost:8888/test.html)"
    echo "  通过 FRPS 访问: $(curl -s -k https://test.${DOMAIN}/test.html 2>&1 | head -20)"
    
    # 清理
    kill $FRPC_PID 2>/dev/null
else
    echo "  ${YELLOW}未安装 frpc，跳过链路测试${NC}"
fi

# 11. 清理测试服务
kill $TEST_PID 2>/dev/null

# 12. 输出诊断结果
echo -e "\n${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}                    诊断结果总结                            ${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"

echo -e "\n${CYAN}问题检查清单：${NC}"
echo -n "  1. 容器运行状态: "
docker ps | grep -q "nginx-proxy.*Up" && docker ps | grep -q "frps-server.*Up" && echo -e "${GREEN}✓ 正常${NC}" || echo -e "${RED}✗ 异常${NC}"

echo -n "  2. FRPS 端口监听: "
docker exec frps-server netstat -tlnp 2>/dev/null | grep -q ":8880" && echo -e "${GREEN}✓ 8880 端口正常${NC}" || echo -e "${YELLOW}! 需要检查${NC}"

echo -n "  3. 证书状态: "
[ -f "certbot/data/live/${DOMAIN}/fullchain.pem" ] && echo -e "${GREEN}✓ 证书存在${NC}" || echo -e "${RED}✗ 证书缺失${NC}"

echo -n "  4. Nginx 配置: "
[ -f "nginx/conf/conf.d/${DOMAIN}.conf" ] && echo -e "${GREEN}✓ 已更新${NC}" || echo -e "${RED}✗ 配置缺失${NC}"

echo -e "\n${CYAN}下一步操作：${NC}"
echo "1. 在客户端使用 test-frpc.toml 连接"
echo "2. 访问 https://test.${DOMAIN} 测试"
echo "3. 查看日志: docker logs frps-server"
echo "4. 管理面板: https://admin.${DOMAIN}"

echo -e "\n${GREEN}配置文件已更新，请测试访问！${NC}"