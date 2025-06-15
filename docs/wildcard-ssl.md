# 泛域名SSL证书配置指南

## 🌟 泛域名证书的优势

使用泛域名证书（`*.flowbytes.cn`）可以实现：

- ✅ **自动SSL**: frpc客户端设置`subdomain`后自动获得SSL
- ✅ **无限子域名**: 不需要为新子域名重新申请证书
- ✅ **零配置**: DNS泛域名解析 + SSL泛域名证书 = 全自动

## 🔧 配置步骤

### 1. DNS泛域名解析

在DNS管理面板添加：

```dns
# 主域名
flowbytes.cn.        IN  A     your-server-ip

# 泛域名解析（关键！）
*.flowbytes.cn.      IN  A     your-server-ip
```

### 2. 申请泛域名SSL证书

泛域名证书需要DNS验证，支持以下DNS提供商：

#### Cloudflare (推荐)

```bash
# 1. 安装certbot-dns-cloudflare插件
pip install certbot-dns-cloudflare

# 2. 创建Cloudflare API凭据文件
mkdir -p ~/.secrets
cat > ~/.secrets/cloudflare.ini << EOF
dns_cloudflare_email = your-email@example.com
dns_cloudflare_api_key = your-global-api-key
EOF
chmod 600 ~/.secrets/cloudflare.ini

# 3. 申请泛域名证书
certbot certonly \
  --dns-cloudflare \
  --dns-cloudflare-credentials ~/.secrets/cloudflare.ini \
  -d "flowbytes.cn" \
  -d "*.flowbytes.cn"
```

#### 阿里云DNS

```bash
# 1. 安装阿里云插件
pip install certbot-dns-aliyun

# 2. 配置API凭据
cat > ~/.secrets/aliyun.ini << EOF
dns_aliyun_access_key_id = your-access-key-id
dns_aliyun_access_key_secret = your-access-key-secret
EOF

# 3. 申请证书
certbot certonly \
  --dns-aliyun \
  --dns-aliyun-credentials ~/.secrets/aliyun.ini \
  -d "flowbytes.cn" \
  -d "*.flowbytes.cn"
```

### 3. 配置nginx使用泛域名证书

创建泛域名nginx配置：

```nginx
# /nginx/conf/conf.d/wildcard.conf
server {
    listen 80;
    server_name *.flowbytes.cn flowbytes.cn;

    location /.well-known/acme-challenge/ {
        root /usr/share/nginx/html;
    }

    location / {
        return 301 https://$server_name$request_uri;
    }
}

server {
    listen 443 ssl;
    http2 on;
    server_name *.flowbytes.cn flowbytes.cn;

    # 泛域名SSL证书
    ssl_certificate /etc/letsencrypt/live/flowbytes.cn/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/flowbytes.cn/privkey.pem;

    # HSTS
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;

    # FRPS管理界面专用
    location ~ ^/admin {
        if ($host != "admin-frps.flowbytes.cn") {
            return 404;
        }
        proxy_pass http://frps:7001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # 所有其他子域名代理到frps HTTP虚拟主机
    location / {
        proxy_pass http://frps:8880;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $http_connection;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

## 🚀 客户端配置示例

配置完成后，frpc客户端可以这样使用：

```toml
# frpc.toml
[common]
server_addr = flowbytes.cn
server_port = 7000
token = your-token

# Web应用 - 自动获得SSL
[webapp]
type = http
local_ip = 127.0.0.1
local_port = 3000
subdomain = webapp
# 访问地址: https://webapp.flowbytes.cn (自动SSL!)

# API服务 - 自动获得SSL  
[api]
type = http
local_ip = 127.0.0.1
local_port = 8080
subdomain = api
# 访问地址: https://api.flowbytes.cn (自动SSL!)

# 测试环境 - 自动获得SSL
[test]
type = http
local_ip = 127.0.0.1
local_port = 9000
subdomain = test
# 访问地址: https://test.flowbytes.cn (自动SSL!)
```

## 📊 对比：SAN证书 vs 泛域名证书

| 特性 | SAN证书 | 泛域名证书 |
|------|---------|------------|
| **域名数量** | 有限(≤100) | 无限子域名 |
| **动态子域名** | ❌ 需重新申请 | ✅ 自动支持 |
| **配置复杂度** | ⭐ 简单 | ⭐⭐⭐ 中等 |
| **DNS要求** | A记录 | A记录 + API |
| **frpc体验** | 预配置域名 | 🚀 随意subdomain |

## 🔄 自动续签配置

```bash
# 创建续签脚本
cat > /opt/renew-wildcard.sh << 'EOF'
#!/bin/bash
certbot renew \
  --dns-cloudflare \
  --dns-cloudflare-credentials ~/.secrets/cloudflare.ini \
  --quiet

# 重新加载nginx
docker exec nginx-proxy nginx -s reload
EOF

chmod +x /opt/renew-wildcard.sh

# 添加到crontab
echo "0 3 * * 0 /opt/renew-wildcard.sh" | crontab -
```

## 🎯 推荐方案选择

### 选择SAN证书（当前默认）
✅ **适合场景**：
- 域名数量固定且较少（≤5个）
- 不需要动态子域名
- 希望配置简单

### 选择泛域名证书
✅ **适合场景**：
- 需要大量子域名
- frpc客户端频繁使用`subdomain`
- 希望完全的自动化SSL体验

## 💡 最佳实践

1. **小团队**: 使用SAN证书，简单可靠
2. **企业/多项目**: 使用泛域名证书，扩展性强
3. **混合使用**: 核心服务用SAN，动态服务用泛域名

## 🛠️ 实现泛域名自动化

如果你想要真正的"设置subdomain就自动SSL"，需要：

1. ✅ DNS泛域名解析：`*.flowbytes.cn → server-ip`
2. ✅ SSL泛域名证书：`*.flowbytes.cn`
3. ✅ nginx泛域名配置：匹配所有子域名
4. ✅ frps虚拟主机：处理HTTP/HTTPS代理

这样配置后，任何`subdomain`都能自动获得SSL保护！

---

**🎉 想要实现完全自动化？按照本指南配置泛域名证书！**