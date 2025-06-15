# SSL证书配置选项

## 🔒 证书类型说明

### 1. SAN证书（当前默认）
**Subject Alternative Name** - 多域名证书

```bash
# 系统会自动为所有域名申请一张证书
./deploy.sh deploy frps.flowbytes.cn admin-frps.flowbytes.cn admin@example.com
```

**特点**：
- ✅ 一张证书包含多个域名
- ✅ 管理简单，续签方便
- ✅ Let's Encrypt免费支持
- ✅ 自动检测域名覆盖

### 2. 泛域名证书（手动配置）
**Wildcard Certificate** - `*.flowbytes.cn`

```bash
# 需要DNS验证，暂不支持自动化
# 可以手动申请后放入 certbot/data/live/ 目录
```

**特点**：
- ✅ 覆盖所有子域名
- ✅ 无需为新子域名重新申请
- ❌ 需要DNS API支持
- ❌ 配置复杂

## 🚀 推荐配置方案

### 方案1: SAN证书（推荐）

**适用场景**: 域名数量少（≤5个）

```bash
# 示例：2个域名一张证书
./deploy.sh deploy frps.flowbytes.cn admin-frps.flowbytes.cn admin@example.com
```

**优势**：
- 🎯 配置简单
- 🔄 自动续签
- 💰 完全免费
- 🛡️ 安全可靠

### 方案2: 泛域名证书

**适用场景**: 需要大量子域名

```bash
# 手动申请泛域名证书（需要DNS API）
certbot certonly --dns-cloudflare --dns-cloudflare-credentials ~/.secrets/cloudflare.ini -d "*.flowbytes.cn"
```

**优势**：
- 🌟 一证全覆盖
- 🚀 扩展性强
- 📈 适合大规模部署

## 📊 证书方案对比

| 方案 | 域名覆盖 | 配置难度 | 续签方式 | 成本 | 推荐度 |
|------|----------|----------|----------|------|--------|
| **SAN证书** | 指定域名 | ⭐ | 自动 | 免费 | ⭐⭐⭐⭐⭐ |
| 泛域名证书 | 所有子域名 | ⭐⭐⭐⭐ | 手动/API | 免费 | ⭐⭐⭐ |
| 单域名证书 | 单个域名 | ⭐ | 自动 | 免费 | ⭐⭐ |

## 🔧 当前系统特性

### 自动优化

1. **智能检测**: 自动检查现有证书是否包含所有域名
2. **避免重复**: 有效证书不会重新申请
3. **统一管理**: 多个域名使用同一张证书
4. **自动续签**: 接近过期时自动续签

### 证书文件结构

```
certbot/data/live/frps.flowbytes.cn/
├── cert.pem        # 证书文件
├── chain.pem       # 证书链
├── fullchain.pem   # 完整证书链
└── privkey.pem     # 私钥
```

### 域名覆盖检查

```bash
# 查看证书包含的域名
openssl x509 -in certbot/data/live/frps.flowbytes.cn/cert.pem -noout -text | grep "DNS:"
```

## 🛠️ 手动配置泛域名证书

如果你有大量子域名需求，可以手动配置泛域名证书：

### 1. 申请泛域名证书

```bash
# 使用DNS验证方式（需要DNS API支持）
certbot certonly \
  --dns-cloudflare \
  --dns-cloudflare-credentials ~/.secrets/cloudflare.ini \
  -d "*.flowbytes.cn" \
  -d "flowbytes.cn"
```

### 2. 修改nginx配置

```nginx
# 所有子域名使用同一证书
ssl_certificate /etc/letsencrypt/live/flowbytes.cn/fullchain.pem;
ssl_certificate_key /etc/letsencrypt/live/flowbytes.cn/privkey.pem;
```

### 3. 支持的DNS提供商

- Cloudflare
- AWS Route53
- Google Cloud DNS
- 阿里云DNS
- 腾讯云DNS

## 🔄 证书续签

### SAN证书续签

```bash
# 自动续签（系统已配置）
./deploy.sh renew

# 手动续签
certbot renew
```

### 泛域名证书续签

```bash
# 需要DNS API
certbot renew --dns-cloudflare --dns-cloudflare-credentials ~/.secrets/cloudflare.ini
```

## 💡 最佳实践

1. **小规模部署**: 使用SAN证书（≤5个域名）
2. **大规模部署**: 考虑泛域名证书（>10个子域名）
3. **混合部署**: 主要服务用SAN，其他用泛域名
4. **定期检查**: 监控证书过期时间
5. **备份证书**: 定期备份证书文件

## 🆘 常见问题

### Q: SAN证书最多支持多少个域名？
A: Let's Encrypt支持最多100个域名，但建议不超过10个。

### Q: 可以混合使用不同证书吗？
A: 可以，不同域名可以使用不同的证书。

### Q: 泛域名证书是否覆盖主域名？
A: 不覆盖，需要同时申请 `*.example.com` 和 `example.com`。

### Q: 如何查看当前证书信息？
A: 使用 `./deploy.sh status` 或 `openssl x509 -in cert.pem -noout -text`。

---

**🔒 推荐**: 对于大多数用户，SAN证书是最佳选择！