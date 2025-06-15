# DNS 配置指南

## 🎯 推荐的DNS配置

为了获得最佳的安全性和用户体验，推荐使用以下DNS配置：

### 主要域名记录

假设你的主域名为 `example.com`，服务器IP为 `1.2.3.4`：

```dns
# A记录 - 指向服务器IP
frps.example.com.       IN  A     1.2.3.4
admin-frps.example.com. IN  A     1.2.3.4
```

### 部署命令

```bash
./deploy.sh deploy frps.example.com admin-frps.example.com admin@example.com
```

## 🔒 访问地址

部署完成后的访问地址：

- **FRPS服务**: `https://frps.example.com` (客户端连接)
- **管理界面**: `https://admin-frps.example.com` (Web管理)

## 🌟 优势

### 使用独立二级域名的好处：

1. **🔐 SSL加密**: 管理界面也有SSL保护
2. **🚫 无端口暴露**: 不需要开放7001端口
3. **👥 专业外观**: 更专业的访问地址
4. **🛡️ 安全隔离**: 可以单独配置访问控制
5. **📱 移动友好**: 更容易记忆和分享

### 与端口访问方式对比：

| 方式 | 地址 | SSL | 端口暴露 | 专业度 |
|------|------|-----|----------|--------|
| 二级域名 | `https://admin-frps.example.com` | ✅ | ❌ | ⭐⭐⭐⭐⭐ |
| 端口访问 | `http://frps.example.com:7001` | ❌ | ✅ | ⭐⭐ |

## 🔧 其他DNS配置方案

### 方案1: 同级子域名（推荐）
```dns
frps.example.com.       IN  A     1.2.3.4
admin-frps.example.com. IN  A     1.2.3.4
```

### 方案2: 嵌套子域名
```dns
frps.example.com.       IN  A     1.2.3.4
admin.frps.example.com. IN  A     1.2.3.4
```

### 方案3: 完全独立域名
```dns
myfrps.com.           IN  A     1.2.3.4
admin.myfrps.com.     IN  A     1.2.3.4
```

## 🛠️ DNS验证

部署前验证DNS解析：

```bash
# 检查主域名
nslookup frps.example.com

# 检查管理域名  
nslookup admin-frps.example.com

# 测试连通性
ping frps.example.com
ping admin-frps.example.com
```

## 📋 部署检查清单

- [ ] DNS记录已添加并生效
- [ ] 服务器防火墙开放端口80, 443, 7000
- [ ] 域名能正常解析到服务器IP
- [ ] 服务器有足够磁盘空间(建议10GB+)
- [ ] 已准备好Let's Encrypt注册邮箱

## 🆘 常见问题

### Q: 我只有一个域名，可以用二级域名吗？
A: 可以！只要你能添加A记录，就可以创建二级域名。

### Q: DNS解析需要多久生效？
A: 通常5-30分钟，最长可能需要24小时。

### Q: 可以使用免费域名吗？
A: 可以，但建议使用可信的域名提供商，确保稳定性。

### Q: 内网部署需要真实域名吗？
A: 内网可以使用hosts文件配置本地解析，但无法申请Let's Encrypt证书。

---

**💡 提示**: 使用独立的管理域名是最佳实践，既安全又专业！