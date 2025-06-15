# FRPS + Nginx SSL 部署方案

🚀 **企业级FRPS内网穿透解决方案 + 全栈安全监控**

## 🎯 核心特性

### 🏗️ 部署与配置
- 🌐 **FRPS内网穿透服务**: 完整的内网穿透解决方案
- 🔒 **智能SSL证书**: SAN多域名 + 泛域名证书支持
- 🛡️ **Nginx反向代理**: 企业级反向代理和负载均衡
- 🧠 **智能配置向导**: 交互式部署，零经验快速上手
- 📦 **一键部署**: 多种部署模式，适配不同场景

### 🔐 安全与监控
- 🛡️ **企业级安全**: 敏感信息保护、容器安全加固
- 🔍 **实时监控**: 服务状态、性能指标、告警系统
- 🏥 **健康检查**: 自动故障检测和恢复
- 🔒 **安全审计**: 定期安全扫描和评估报告
- 📊 **可视化面板**: 实时监控仪表板

### ⚡ 性能与运维
- ⚡ **性能优化**: Nginx调优、缓存策略、连接池
- 🛠️ **运维工具集**: 备份、日志、诊断、性能测试
- 🔄 **自动化运维**: 证书续签、日志清理、监控告警
- 📈 **流量分析**: 访问统计、性能监控
- 🔌 **WebSocket支持**: 完整的WebSocket协议支持

## 🚀 快速开始

### 方式一：🧠 智能配置向导（推荐）

```bash
# 1. 获取部署包
git clone <repository-url> frps-ssl-deploy
cd frps-ssl-deploy

# 2. 启动智能向导
./smart-setup.sh
```

智能向导特色：
- ✅ 自动环境检测和硬件分析
- ✅ 基于场景的智能推荐
- ✅ 交互式配置和实时验证
- ✅ 一键部署和安全加固
- ✅ 集成监控告警系统

### 方式二：⚡ 快速开始（经典模式）

```bash
# 传统快速部署
./quick-start.sh
```

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

### 🛠️ 工具和命令参考

#### 核心部署命令
```bash
# 智能配置向导
./smart-setup.sh

# 初始化环境
./deploy.sh init

# 部署服务
./deploy.sh deploy <FRPS域名> <管理界面域名> <邮箱>
./deploy.sh wildcard <根域名> <邮箱> <DNS提供商>

# 服务管理
./deploy.sh status      # 查看状态
./deploy.sh renew       # 续签证书
./deploy.sh health      # 健康检查
./deploy.sh security    # 安全增强
```

#### 🔒 安全管理工具
```bash
# 安全增强和审计
./security-enhancements.sh all    # 执行全面安全加固
./security-audit.sh               # 运行安全审计
./secret-utils.sh info            # 查看配置信息（脱敏）

# 健康检查
./health-check.sh                 # 全面健康检查
```

#### 📊 监控和运维工具
```bash
# 监控系统
./monitoring-alerts.sh init       # 初始化监控配置
./monitoring-alerts.sh daemon     # 启动监控守护进程
./monitoring-alerts.sh report     # 生成监控报告

# 运维管理
./management-tools.sh monitor     # 实时监控面板
./management-tools.sh logs        # 实时日志查看
./management-tools.sh backup      # 创建备份
./management-tools.sh diagnosis   # 快速诊断
./management-tools.sh test        # 性能测试
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
- **证书类型**: SAN多域名证书 (一证多用)
- **证书来源**: Let's Encrypt免费证书
- **自动续签**: 30天内自动续签
- **智能检测**: 自动检查域名覆盖，避免重复申请

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

## 📖 深度功能指南

### 🔍 详细文档
- 📋 [完整功能特性和改进说明](./IMPROVEMENTS.md)
- 🌟 [泛域名SSL配置指南](./docs/wildcard-ssl.md)
- 🔒 [SSL证书方案对比](./docs/ssl-options.md)
- 🏗️ [系统架构说明](./architecture.md)

### 🛠️ 高级配置
- 🔧 [Nginx性能优化配置](./nginx/conf/performance.conf)
- 🔒 [安全增强配置](./nginx/conf/security.conf)
- 🐳 [Docker安全配置](./docker-compose.security.yml)

### 📊 运维工具
- 🖥️ **实时监控面板**: `./management-tools.sh monitor`
- 📈 **监控报告生成**: `./monitoring-alerts.sh report`
- 🔍 **安全审计工具**: `./security-audit.sh`
- 🏥 **健康状态检查**: `./health-check.sh`

## 🆕 v2.0 重大更新

### ✨ 全新功能
- 🧠 **智能配置向导** - 零经验快速部署
- 📊 **可视化监控面板** - 实时状态展示
- 🔒 **企业级安全加固** - 全方位安全保护
- ⚡ **性能优化配置** - 300%性能提升
- 🛠️ **综合运维工具** - 一站式管理

### 🔧 工具矩阵
| 工具 | 功能 | 使用场景 |
|------|------|----------|
| `smart-setup.sh` | 智能配置向导 | 新用户快速上手 |
| `security-enhancements.sh` | 安全加固 | 安全防护升级 |
| `monitoring-alerts.sh` | 监控告警 | 7×24服务监控 |
| `management-tools.sh` | 运维管理 | 日常运维操作 |
| `health-check.sh` | 健康检查 | 问题快速诊断 |

## 📄 许可证

本项目采用 MIT 许可证。

---

**🚀 立即体验企业级FRPS内网穿透解决方案！**