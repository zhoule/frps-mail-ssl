# 使用 acme.sh 申请泛域名证书

## 🚀 优势

- ✅ **支持所有主流 DNS 提供商**（100+ 个）
- ✅ **无需 Docker 镜像**，纯 Shell 脚本
- ✅ **自动续期**更可靠
- ✅ **更轻量**，安装速度快

## 📋 支持的 DNS 提供商

### 国内提供商
- **腾讯云**: `tencent`
- **阿里云**: `aliyun` 或 `ali`
- **DNSPod**: `dnspod`
- **华为云**: `huaweicloud`

### 国际提供商
- **Cloudflare**: `cloudflare`
- **AWS Route53**: `aws`
- **Google Cloud**: `gcloud`
- **Azure**: `azure`
- 更多请查看：https://github.com/acmesh-official/acme.sh/wiki/dnsapi

## 🔧 使用方法

### 1. 设置环境变量

在 `.env` 文件中配置你的 DNS API 凭据：

#### 腾讯云
```bash
TENCENTCLOUD_SECRET_ID=your-secret-id
TENCENTCLOUD_SECRET_KEY=your-secret-key
```

#### 阿里云
```bash
ALIBABA_CLOUD_ACCESS_KEY_ID=your-access-key
ALIBABA_CLOUD_ACCESS_KEY_SECRET=your-secret-key
```

#### Cloudflare
```bash
CLOUDFLARE_EMAIL=your-email@example.com
CLOUDFLARE_API_KEY=your-api-key
```

#### DNSPod
```bash
DNSPOD_ID=your-id
DNSPOD_KEY=your-key
```

### 2. 申请证书

部署脚本会自动使用 acme.sh：

```bash
# 腾讯云
./deploy.sh wildcard flowbytes.cn admin@flowbytes.cn tencent

# 阿里云
./deploy.sh wildcard example.com admin@example.com aliyun

# Cloudflare
./deploy.sh wildcard example.com admin@example.com cloudflare
```

### 3. 手动使用 acme.sh

如果需要手动操作：

```bash
# 申请新证书
./scripts/acme-wildcard.sh issue example.com admin@example.com tencent

# 续期证书
./scripts/acme-wildcard.sh renew example.com

# 列出所有证书
./scripts/acme-wildcard.sh list
```

## 🔄 工作原理

1. **自动检测**：脚本会优先尝试使用 acme.sh
2. **回退机制**：如果 acme.sh 失败，对于 Cloudflare 和阿里云会尝试使用 certbot
3. **自动安装**：如果系统没有 acme.sh，会自动下载安装
4. **凭据管理**：自动从环境变量读取 API 凭据

## 📝 故障排除

### 问题：提示 DNS API 配置不完整
**解决**：检查 `.env` 文件中是否正确设置了 API 凭据

### 问题：证书申请失败
**解决**：
1. 确认 DNS 解析已生效：`nslookup *.example.com`
2. 检查 API 凭据是否正确
3. 查看详细日志：`~/.acme.sh/acme.sh --debug --issue ...`

### 问题：续期失败
**解决**：
1. 手动续期：`./scripts/acme-wildcard.sh renew example.com`
2. 检查 cron 任务：`crontab -l`
3. 查看 acme.sh 日志：`tail -f ~/.acme.sh/acme.sh.log`

## 🎯 最佳实践

1. **使用 .env 文件**管理 API 凭据，不要硬编码
2. **定期检查**证书状态：`./scripts/acme-wildcard.sh list`
3. **测试续期**：`./scripts/acme-wildcard.sh renew example.com --force`
4. **备份证书**：定期备份 `certbot/data` 目录

## 🔗 相关链接

- [acme.sh 官方文档](https://github.com/acmesh-official/acme.sh)
- [DNS API 列表](https://github.com/acmesh-official/acme.sh/wiki/dnsapi)
- [Let's Encrypt 文档](https://letsencrypt.org/docs/)