# Git 版本管理指南

## 🎯 为什么需要 .gitkeep 文件？

Git 不会跟踪空目录，但我们的部署系统需要特定的目录结构。通过在每个重要的空目录中放置 `.gitkeep` 文件，我们确保了：

1. **📁 目录结构完整**: 克隆仓库后所有必要目录都存在
2. **🚀 部署顺畅**: 不需要手动创建目录
3. **🔧 自动化友好**: CI/CD 可以直接使用

## 📋 .gitkeep 文件列表

我们在以下目录添加了 `.gitkeep` 文件：

```
📁 certbot/data/                 # SSL证书存储目录
📁 frps/config/                  # FRPS配置文件目录
📁 logs/nginx/                   # Nginx日志目录
📁 logs/frps/                    # FRPS日志目录
📁 nginx/conf/conf.d/            # 域名配置目录
📁 stalwart-mail/config/         # 邮件服务器配置目录
📁 stalwart-mail/data/           # 邮件数据目录
📁 stalwart-mail/logs/           # 邮件服务器日志目录
```

## 🔒 .gitignore 规则说明

我们的 `.gitignore` 文件包含以下规则：

### 日志文件
```gitignore
logs/*.log
logs/**/*.log
```
- **原因**: 日志文件会动态生成，不应该被版本控制
- **效果**: 保留日志目录结构，但忽略日志内容

### SSL证书
```gitignore
certbot/data/live/
certbot/data/archive/
certbot/data/renewal/
certbot/data/accounts/
```
- **原因**: SSL证书是敏感信息，不应该被提交到代码仓库
- **效果**: 保留证书存储目录，但忽略证书文件

### 配置文件
```gitignore
frps/config/*.toml
stalwart-mail/config/*.toml
nginx/conf/conf.d/*.conf
```
- **原因**: 这些配置文件是运行时自动生成的
- **效果**: 保留配置目录，但忽略生成的配置文件

### 数据文件
```gitignore
stalwart-mail/data/*
!stalwart-mail/data/.gitkeep
```
- **原因**: 邮件数据包含用户隐私信息
- **效果**: 忽略所有数据文件，但保留 `.gitkeep`

## 🚀 Git 操作指南

### 初始设置

```bash
# 1. 初始化 Git 仓库
git init

# 2. 添加所有文件
git add .

# 3. 提交初始版本
git commit -m "Initial commit: FRPS + Mail + SSL Deploy System"

# 4. 添加远程仓库
git remote add origin <your-repository-url>

# 5. 推送到远程仓库
git push -u origin main
```

### 部署到服务器

```bash
# 1. 克隆仓库
git clone <your-repository-url>
cd frps-mail-ssl-deploy

# 2. 检查目录结构 (所有目录都应该存在)
ls -la */

# 3. 直接运行部署
./deploy.sh init
./deploy.sh deploy your-domain.com admin.your-domain.com mail.your-domain.com admin@your-domain.com
```

### 更新部署包

```bash
# 1. 拉取最新代码
git pull origin main

# 2. 重启服务应用更新
docker-compose restart

# 3. 检查服务状态
./deploy.sh status
```

## 🛡️ 安全最佳实践

### 敏感信息处理

1. **永远不要提交**:
   - SSL 证书和私钥
   - 邮件数据库文件
   - 用户邮件内容
   - 生成的密码和token

2. **使用环境变量**:
   ```bash
   # 可以通过环境变量传递敏感配置
   export FRPS_TOKEN="your-secret-token"
   export MAIL_ADMIN_PASSWORD="your-admin-password"
   ./deploy.sh deploy ...
   ```

3. **定期备份**:
   ```bash
   # 备份重要数据(不包含在Git中)
   tar -czf backup-$(date +%Y%m%d).tar.gz \
     certbot/data/ \
     stalwart-mail/data/ \
     logs/
   ```

### 分支管理策略

```bash
# 开发分支
git checkout -b feature/new-feature
# ... 做修改 ...
git commit -m "Add new feature"
git push origin feature/new-feature

# 生产分支
git checkout main
git merge feature/new-feature
git tag v1.1.0
git push origin main --tags
```

## 🔄 自动化部署

### GitHub Actions 示例

```yaml
name: Deploy FRPS + Mail + SSL
on:
  push:
    branches: [ main ]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v2
    
    - name: Deploy to server
      uses: appleboy/ssh-action@v0.1.5
      with:
        host: ${{ secrets.HOST }}
        username: ${{ secrets.USERNAME }}
        key: ${{ secrets.KEY }}
        script: |
          cd /opt/frps-mail-ssl-deploy
          git pull origin main
          ./deploy.sh status
```

### 服务器端自动更新

```bash
# 添加到 crontab
0 3 * * 1 cd /opt/frps-mail-ssl-deploy && git pull origin main
```

## 📊 监控和维护

### 检查Git状态

```bash
# 查看哪些文件被修改(运行时)
git status

# 查看被忽略的文件
git status --ignored

# 检查目录结构完整性
find . -name ".gitkeep" -type f
```

### 清理和维护

```bash
# 清理Git历史中的大文件
git filter-branch --tree-filter 'rm -f large-file.dat' HEAD

# 检查仓库大小
git count-objects -vH

# 垃圾回收
git gc --aggressive
```

## 🆘 常见问题

### Q: 克隆后缺少目录怎么办？

A: 检查是否所有 `.gitkeep` 文件都被正确提交：
```bash
find . -name ".gitkeep" -type f | wc -l
# 应该显示 8 (我们添加了8个.gitkeep文件)
```

### Q: 敏感文件被意外提交了怎么办？

A: 立即从历史中移除：
```bash
git filter-branch --tree-filter 'rm -f sensitive-file' HEAD
git push origin --force-with-lease
```

### Q: 如何在不同环境间同步配置？

A: 使用模板文件和环境变量：
```bash
# config.template.toml
server_name = "${DOMAIN_NAME}"
admin_password = "${ADMIN_PASSWORD}"

# 部署时替换
envsubst < config.template.toml > config.toml
```

---

**💡 提示**: 遵循这些Git管理实践，能让你的部署更安全、更可靠！