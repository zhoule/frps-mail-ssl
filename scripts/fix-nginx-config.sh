#!/bin/bash
# 修复 Nginx 配置问题

SCRIPT_DIR="/home/jack/frps/frps"
cd "$SCRIPT_DIR"

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}[INFO]${NC} 修复 Nginx 配置问题..."

# 1. 查找包含错误证书路径的配置文件
echo -e "${GREEN}[INFO]${NC} 查找错误的配置文件..."
grep -l "frps.yourdomain.com" nginx/conf/conf.d/*.conf 2>/dev/null | while read file; do
    echo -e "${YELLOW}[WARN]${NC} 发现错误配置: $file"
    # 删除或注释掉这个文件
    if [[ "$file" == *"frps.conf"* ]]; then
        echo -e "${GREEN}[INFO]${NC} 删除默认示例配置: $file"
        rm -f "$file"
    fi
done

# 2. 修复 http2 指令问题
echo -e "${GREEN}[INFO]${NC} 修复 http2 指令..."
find nginx/conf/conf.d/ -name "*.conf" -type f | while read file; do
    # 将 "listen 443 ssl http2;" 改为 "listen 443 ssl;" + "http2 on;"
    if grep -q "listen.*ssl.*http2" "$file"; then
        echo -e "${GREEN}[INFO]${NC} 更新 $file 中的 http2 指令..."
        sed -i.bak 's/listen\(.*\)ssl http2;/listen\1ssl;/' "$file"
        # 在 server 块中添加 http2 on; (如果还没有的话)
        if ! grep -q "http2 on;" "$file"; then
            sed -i '/listen.*ssl;/a\    http2 on;' "$file"
        fi
    fi
done

# 3. 创建一个基础的 default.conf
echo -e "${GREEN}[INFO]${NC} 创建默认配置..."
cat > nginx/conf/conf.d/default.conf << 'EOF'
# 默认服务器配置
server {
    listen 80 default_server;
    server_name _;

    # 健康检查端点
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }

    # 默认返回 404
    location / {
        return 404;
    }
}

# 处理未知 HTTPS 请求
server {
    listen 443 ssl default_server;
    http2 on;
    server_name _;

    # 使用自签名证书作为默认证书
    ssl_certificate /etc/nginx/ssl/default.crt;
    ssl_certificate_key /etc/nginx/ssl/default.key;

    return 444;
}
EOF

# 4. 生成自签名证书（用于默认 SSL）
echo -e "${GREEN}[INFO]${NC} 生成默认自签名证书..."
mkdir -p nginx/ssl
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout nginx/ssl/default.key \
    -out nginx/ssl/default.crt \
    -subj "/C=US/ST=State/L=City/O=Organization/CN=default"

# 5. 检查现有的泛域名配置
echo -e "${GREEN}[INFO]${NC} 检查泛域名配置..."
for domain in flowbytes.cn jzhou.fun; do
    if [ -f "certbot/data/live/$domain/fullchain.pem" ]; then
        echo -e "${GREEN}[✓]${NC} $domain 证书存在"
        if [ ! -f "nginx/conf/conf.d/${domain}-wildcard.conf" ]; then
            echo -e "${YELLOW}[!]${NC} 缺少 $domain 的 Nginx 配置，正在创建..."
            ~/tmp/complete-wildcard-deploy.sh "$domain"
        fi
    fi
done

# 6. 更新 docker-compose.yml 挂载 ssl 目录
echo -e "${GREEN}[INFO]${NC} 更新 docker-compose.yml..."
if ! grep -q "/nginx/ssl" docker-compose.yml; then
    sed -i '/nginx\/conf:/a\      - ./nginx/ssl:/etc/nginx/ssl:ro' docker-compose.yml
fi

# 7. 重启 Nginx
echo -e "${GREEN}[INFO]${NC} 重启 Nginx..."
docker-compose down nginx-proxy
docker-compose up -d nginx-proxy

# 8. 等待并检查状态
sleep 5
echo -e "${GREEN}[INFO]${NC} 检查 Nginx 状态..."
if docker ps | grep -q nginx-proxy; then
    echo -e "${GREEN}[✓]${NC} Nginx 正在运行"
    docker logs --tail 20 nginx-proxy
else
    echo -e "${RED}[✗]${NC} Nginx 启动失败"
    echo -e "${YELLOW}查看日志：${NC}"
    docker logs nginx-proxy
fi

echo ""
echo -e "${GREEN}========== 修复完成 ==========${NC}"
echo ""
echo -e "${YELLOW}验证命令：${NC}"
echo "  docker exec nginx-proxy nginx -t"
echo "  docker logs nginx-proxy"
echo "  curl -I http://localhost/health"