# FRPS + Nginx SSL 部署方案

🚀 **零配置部署 FRPS内网穿透服务 + 自动SSL证书**

## 🎯 功能特性

- 🌐 **FRPS内网穿透服务**: 完整的内网穿透解决方案
- 🔒 **自动SSL证书**: Let's Encrypt证书自动申请和续签
- 🛡️ **Nginx反向代理**: 高性能反向代理和负载均衡
- 📦 **一键部署**: 零配置，复制即用
- 🔄 **自动续签**: SSL证书自动续签，永不过期
- 🎨 **自定义404页面**: 专业的错误页面展示
- 🔌 **WebSocket支持**: 完整的WebSocket协议支持

## 🚀 快速开始

### 方式一：超级快速开始（推荐新手）

```bash
# 1. 获取部署包
git clone <repository-url> frps-ssl-deploy
cd frps-ssl-deploy

# 2. 运行快速开始向导
./quick-start.sh
```

向导会自动：
- ✅ 检查并安装Docker、Docker Compose等依赖
- ✅ 验证域名DNS解析
- ✅ 配置所有服务
- ✅ 申请SSL证书
- ✅ 设置自动续签

### 方式二：手动部署（高级用户）

```bash
# 1. 获取部署包
scp -r frps-ssl-deploy/ user@your-server:/opt/
cd /opt/frps-ssl-deploy

# 2. 安装依赖（可选，deploy.sh会自动提示）
./install-dependencies.sh

# 3. 初始化环境
./deploy.sh init

# 4. 一键部署
./deploy.sh deploy frps.example.com admin@example.com
```

完成！🎉

## 📋 详细使用指南

### 命令参考

```bash
# 初始化环境
./deploy.sh init

# 部署所有服务
./deploy.sh deploy <FRPS域名> <管理界面域名>

# 续签证书
./deploy.sh renew

# 设置自动续签
./deploy.sh setup-cron

# 查看状态
./deploy.sh status

# 显示帮助
./deploy.sh help
```

### 部署示例

```bash
# 推荐部署（使用独立管理域名）
./deploy.sh deploy frps.mydomain.com admin-frps.mydomain.com admin@mydomain.com

# 简单部署（仅FRPS服务）
./deploy.sh deploy frps.mydomain.com admin@mydomain.com
```

## 🏗️ 服务架构

详细的架构图和系统设计请查看: [📋 架构文档](./architecture.md)

### 快速架构概览

```
                                    Internet
                                       │
                                       │ Port 80/443
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                               Nginx Proxy                                   │
│                           (SSL Termination)                                │
├─────────────────────────────────────────────────────────────────────────────┤
│  HTTPS Proxy Rules:                                                         │
│  • frps.domain.com → frps:8880 (HTTP Tunnel)                              │
│  • admin.domain.com → frps:7001 (Dashboard)                               │
└─────────────────────────────────────────────────────────────────────────────┘
                           │              │              │
                           ▼              ▼              ▼
┌─────────────────────────────┐  ┌─────────────────┐
│         FRPS Server         │  │   FRPS Admin    │
│                             │  │   Dashboard     │
│ Port 7000: Main Service     │  │ Port 7001: Web  │
│ Port 8880: HTTP Proxy       │  │ Management UI   │
│ Port 8843: HTTPS Proxy      │  │                 │
└─────────────────────────────┘  └─────────────────┘
```

## 📁 目录结构

```
frps-ssl-deploy/
├── 📄 deploy.sh                    # 主部署脚本
├── 📄 docker-compose.yml           # Docker服务配置
├── 📄 README.md                    # 说明文档
├── 📄 architecture.md              # 架构图文档
├── 📄 .gitignore                   # Git忽略规则
├── 📁 nginx/                       # Nginx配置
│   ├── 📁 conf/
│   │   ├── 📄 nginx.conf          # 主配置文件(自动生成)
│   │   └── 📁 conf.d/             # 域名配置目录
│   │       └── 📄 .gitkeep        # 保持目录结构
│   └── 📁 html/                   # Web根目录
│       └── 📄 index.html          # 欢迎页面
├── 📁 frps/
│   ├── 📁 config/
│   │   └── 📄 frps.toml           # FRPS配置文件(自动生成)
│   └── 📁 custom_errors/
│       └── 📄 404.html            # 自定义404页面
├── 📁 certbot/
│   └── 📁 data/                   # SSL证书存储
│       └── 📄 .gitkeep            # 保持目录结构
└── 📁 logs/                       # 系统日志
    ├── 📁 nginx/                  # Nginx日志
    │   └── 📄 .gitkeep            # 保持目录结构
    └── 📁 frps/                   # FRPS日志
        └── 📄 .gitkeep            # 保持目录结构
```

### 📋 Git管理说明

项目使用 `.gitkeep` 文件来保持必要的目录结构，因为Git不会跟踪空目录。

- **📄 .gitkeep**: 确保空目录被Git跟踪和保存
- **📄 .gitignore**: 忽略运行时生成的文件，但保留目录结构
- **🔒 数据安全**: 敏感数据(SSL证书)不会被提交到Git

## 🔧 服务配置

### FRPS 配置

部署后自动生成的FRPS配置包括：

- **主服务端口**: 7000
- **HTTP虚拟主机端口**: 8080
- **HTTPS虚拟主机端口**: 8443
- **管理界面端口**: 7001
- **自动Token生成**: 16字节随机token
- **WebSocket支持**: 完整支持WebSocket协议
- **自定义404页面**: 专业的错误页面展示
- **性能优化**: 连接池、心跳检测等

### Nginx 配置

自动生成的Nginx配置特性：

- **HTTP到HTTPS重定向**
- **现代化SSL配置** (TLS 1.2/1.3)
- **安全头设置** (HSTS, XSS Protection等)
- **Gzip压缩优化**
- **代理缓冲优化**
- **访问日志分离**

## 🔒 安全特性

### SSL/TLS 安全

- **协议**: TLS 1.2, TLS 1.3
- **密码套件**: 现代化ECDHE密码套件
- **HSTS**: 强制HTTPS访问
- **证书**: Let's Encrypt免费证书
- **自动续签**: 30天内自动续签

### 访问控制

- **防火墙友好**: 只开放必要端口
- **内网隔离**: 服务间通过Docker网络通信
- **管理界面**: 独立域名和认证

### 数据保护

- **日志轮转**: 自动清理旧日志
- **数据持久化**: 重要数据volume挂载
- **配置隔离**: 敏感配置独立存储

## 🛠️ 运维管理

### 日志管理

```bash
# 查看部署日志
tail -f logs/deploy.log

# 查看Nginx日志
tail -f logs/nginx/access.log
tail -f logs/nginx/error.log

# 查看容器日志
docker logs nginx-proxy
docker logs frps-server
```

### 服务管理

```bash
# 查看服务状态
./deploy.sh status

# 重启所有服务
docker-compose restart

# 重启单个服务
docker-compose restart nginx
docker-compose restart frps
```

### 证书管理

```bash
# 手动续签证书
./deploy.sh renew

# 查看证书过期时间
openssl x509 -in certbot/data/live/domain.com/cert.pem -noout -enddate

# 设置自动续签
./deploy.sh setup-cron
```

## 🔌 WebSocket 支持

项目完整支持WebSocket协议，详细配置说明请查看：[📋 WebSocket配置指南](./docs/websocket-guide.md)

### 快速配置

1. **客户端配置示例** (`frpc-example.toml`)
2. **Nginx代理配置** (`nginx/conf/conf.d/websocket-proxy.conf.example`)
3. **完整的WebSocket测试和故障排查指南**

## 📊 监控和维护

### 服务监控

部署完成后，可以通过以下方式监控服务：

1. **FRPS Dashboard**: `https://admin.yourdomain.com`
3. **Nginx状态**: 通过日志文件监控
4. **Docker状态**: `docker ps` 和 `docker stats`

### 定期维护

建议设置以下定期任务：

```bash
# 每周检查服务状态
0 1 * * 1 /opt/frps-ssl-deploy/deploy.sh status

# 每月清理旧日志  
0 0 1 * * find /opt/frps-ssl-deploy/logs -name "*.log" -mtime +30 -delete

# 每周检查磁盘空间
0 2 * * 1 df -h | mail -s "Disk Usage Report" admin@yourdomain.com
```

## 🔧 故障排除

### 常见问题

1. **端口被占用**
   ```bash
   # 检查端口占用
   netstat -tulpn | grep :80
   netstat -tulpn | grep :443
   
   # 停止冲突服务
   sudo systemctl stop apache2
   sudo systemctl stop nginx
   ```

2. **域名解析问题**
   ```bash
   # 检查域名解析
   nslookup yourdomain.com
   dig yourdomain.com
   
   # 测试连通性
   curl -I http://yourdomain.com
   ```

3. **证书申请失败**
   ```bash
   # 检查端口80是否可访问
   curl -I http://yourdomain.com/.well-known/acme-challenge/test
   
   # 查看详细错误
   tail -f logs/deploy.log
   ```

4. **服务启动失败**
   ```bash
   # 查看容器状态
   docker ps -a
   
   # 查看容器日志
   docker logs container-name
   
   # 检查配置文件语法
   docker exec nginx-proxy nginx -t
   ```

### 调试模式

设置环境变量启用详细日志：

```bash
export DEBUG=1
./deploy.sh deploy ...
```

## 🔄 备份和恢复

### 备份重要数据

```bash
# 创建备份脚本
cat > backup.sh << 'EOF'
#!/bin/bash
BACKUP_DIR="/backup/$(date +%Y%m%d)"
mkdir -p "$BACKUP_DIR"

# 备份配置文件
tar -czf "$BACKUP_DIR/configs.tar.gz" nginx/ frps/

# 备份SSL证书
tar -czf "$BACKUP_DIR/certs.tar.gz" certbot/data/


echo "备份完成: $BACKUP_DIR"
EOF

chmod +x backup.sh
```

### 恢复数据

```bash
# 停止服务
docker-compose down

# 恢复配置
tar -xzf backup/configs.tar.gz

# 恢复证书
tar -xzf backup/certs.tar.gz


# 重启服务
docker-compose up -d
```

## 🆘 获取支持

### 检查清单

部署前请确认：

- [ ] 域名已正确解析到服务器IP
- [ ] 服务器80/443端口开放
- [ ] Docker和Docker Compose已安装
- [ ] 服务器有足够磁盘空间(建议10GB+)
- [ ] 服务器内存充足(建议2GB+)

### 日志收集

如遇问题，请收集以下日志：

```bash
# 收集所有日志
tar -czf debug-logs.tar.gz logs/ 
docker logs nginx-proxy > nginx-container.log 2>&1
docker logs frps-server > frps-container.log 2>&1
```

## 📄 许可证

本项目采用 MIT 许可证。

---

**🚀 现在就开始部署你的FRPS内网穿透服务吧！**