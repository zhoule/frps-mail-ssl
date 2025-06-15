# DNS API 配置指南

本指南介绍如何配置各大云服务商的 DNS API，以便使用泛域名SSL证书。

## 支持的DNS提供商

- **Cloudflare** - 全球最受欢迎的DNS服务
- **阿里云** - 阿里云DNS解析服务
- **腾讯云** - 腾讯云DNS解析服务

## 1. Cloudflare DNS API配置

### 获取API密钥
1. 登录 [Cloudflare Dashboard](https://dash.cloudflare.com/)
2. 点击右上角头像 → "My Profile"
3. 选择 "API Tokens" 标签
4. 在 "Global API Key" 部分点击 "View"
5. 复制API Key

### 配置方法
```bash
# 方法1: 设置环境变量
export CLOUDFLARE_EMAIL="your-email@example.com"
export CLOUDFLARE_API_KEY="your-api-key"

# 方法2: 创建.env文件
cat > .env << EOF
CLOUDFLARE_EMAIL=your-email@example.com
CLOUDFLARE_API_KEY=your-api-key
EOF
```

### 使用命令
```bash
./deploy.sh wildcard flowbytes.cn jack.zxzhou@gmail.com cloudflare
```

## 2. 阿里云DNS API配置

### 获取API密钥
1. 登录 [阿里云控制台](https://ecs.console.aliyun.com/)
2. 点击右上角头像 → "AccessKey管理"
3. 创建AccessKey（推荐使用子账号）
4. 复制AccessKey ID和AccessKey Secret

### 权限配置
确保AccessKey具有以下权限：
- `AliyunDNSFullAccess` (DNS解析服务完全访问权限)

### 配置方法
```bash
# 方法1: 设置环境变量
export ALIBABA_CLOUD_ACCESS_KEY_ID="your-access-key"
export ALIBABA_CLOUD_ACCESS_KEY_SECRET="your-secret-key"

# 方法2: 创建.env文件
cat > .env << EOF
ALIBABA_CLOUD_ACCESS_KEY_ID=your-access-key
ALIBABA_CLOUD_ACCESS_KEY_SECRET=your-secret-key
EOF
```

### 使用命令
```bash
./deploy.sh wildcard flowbytes.cn jack.zxzhou@gmail.com aliyun
```

## 3. 腾讯云DNS API配置

### 获取API密钥
1. 登录 [腾讯云控制台](https://console.cloud.tencent.com/)
2. 点击右上角头像 → "访问管理"
3. 选择 "API密钥管理"
4. 创建密钥（推荐使用子账号）
5. 复制SecretId和SecretKey

### 权限配置
确保密钥具有以下权限：
- `QcloudDNSPodFullAccess` (DNS解析服务完全访问权限)

### 配置方法
```bash
# 方法1: 设置环境变量
export TENCENTCLOUD_SECRET_ID="your-secret-id"
export TENCENTCLOUD_SECRET_KEY="your-secret-key"

# 方法2: 创建.env文件
cat > .env << EOF
TENCENTCLOUD_SECRET_ID=your-secret-id
TENCENTCLOUD_SECRET_KEY=your-secret-key
EOF
```

### 使用命令
```bash
./deploy.sh wildcard flowbytes.cn jack.zxzhou@gmail.com tencent
```

## 安全建议

### 1. 使用子账号
- 不要使用主账号的AccessKey
- 为DNS操作创建专用子账号
- 只分配必要的DNS权限

### 2. 密钥管理
- 定期轮换API密钥
- 不要将密钥提交到代码仓库
- 使用环境变量或加密存储

### 3. 权限最小化
- 只分配DNS相关权限
- 不要分配过多的权限
- 定期审核权限设置

## 故障排除

### 常见错误

1. **API密钥无效**
   ```
   [ERROR] DNS API配置不完整
   ```
   - 检查环境变量是否正确设置
   - 验证API密钥是否有效

2. **权限不足**
   ```
   [ERROR] 权限拒绝
   ```
   - 检查API密钥权限
   - 确保域名在对应DNS服务商管理

3. **域名不在DNS服务商**
   ```
   [ERROR] 域名未找到
   ```
   - 确保域名已添加到对应DNS服务商
   - 检查域名拼写是否正确

### 调试方法
```bash
# 检查环境变量
echo $CLOUDFLARE_EMAIL
echo $CLOUDFLARE_API_KEY

# 测试API连接
curl -X GET "https://api.cloudflare.com/client/v4/zones" \
     -H "X-Auth-Email: $CLOUDFLARE_EMAIL" \
     -H "X-Auth-Key: $CLOUDFLARE_API_KEY" \
     -H "Content-Type: application/json"
```

## 泛域名证书优势

1. **一次申请，终身使用** - 覆盖所有子域名
2. **无需HTTP验证** - 绕过防火墙限制
3. **自动化程度高** - DNS-01验证完全自动化
4. **支持内网部署** - 不需要公网80端口
5. **无域名数量限制** - 理论上支持无限子域名

## 部署完成后

部署成功后，你将拥有：
- `https://flowbytes.cn` - 主服务
- `https://admin.flowbytes.cn` - 管理界面
- `https://任意子域名.flowbytes.cn` - 自动SSL

所有子域名都会自动获得SSL证书，无需额外配置！