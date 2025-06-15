# WebSocket 配置指南

本指南介绍如何在FRPS内网穿透服务中配置WebSocket支持。

## 🚀 快速开始

### 1. 服务端已配置支持

FRPS服务端已经配置了WebSocket支持：
- HTTP虚拟主机端口：8080
- HTTPS虚拟主机端口：8443
- 支持的协议包括：tcp, http, https, stcp, sudp, tcpmux

### 2. 客户端配置示例

创建 `frpc.toml` 配置文件：

```toml
# 服务器配置
serverAddr = "frps.yourdomain.com"
serverPort = 7000

# 认证配置
auth.method = "token"
auth.token = "your_secure_token"  # 从部署时获取的token

# WebSocket应用
[[proxies]]
name = "my_websocket"
type = "http"
localIP = "127.0.0.1"
localPort = 3000  # 你的WebSocket服务端口
customDomains = ["ws.yourdomain.com"]
```

### 3. Nginx配置

如果需要通过Nginx代理WebSocket，使用提供的示例配置：

```bash
# 复制示例配置
cp nginx/conf/conf.d/websocket-proxy.conf.example nginx/conf/conf.d/ws.yourdomain.com.conf

# 编辑配置，修改域名
vim nginx/conf/conf.d/ws.yourdomain.com.conf
```

### 4. 申请SSL证书

```bash
./deploy.sh renew
```

## 📋 WebSocket测试

### 使用wscat测试

```bash
# 安装wscat
npm install -g wscat

# 测试WebSocket连接
wscat -c wss://ws.yourdomain.com/
```

### 使用JavaScript测试

```javascript
const ws = new WebSocket('wss://ws.yourdomain.com/');

ws.onopen = function() {
    console.log('WebSocket连接已建立');
    ws.send('Hello Server!');
};

ws.onmessage = function(event) {
    console.log('收到消息:', event.data);
};

ws.onerror = function(error) {
    console.error('WebSocket错误:', error);
};

ws.onclose = function() {
    console.log('WebSocket连接已关闭');
};
```

## 🔧 高级配置

### 1. 多个WebSocket服务

```toml
# WebSocket服务1
[[proxies]]
name = "ws_app1"
type = "http"
localIP = "127.0.0.1"
localPort = 3001
customDomains = ["ws1.yourdomain.com"]

# WebSocket服务2
[[proxies]]
name = "ws_app2"
type = "http"
localIP = "127.0.0.1"
localPort = 3002
customDomains = ["ws2.yourdomain.com"]
```

### 2. 使用子域名

```toml
[[proxies]]
name = "ws_subdomain"
type = "http"
localIP = "127.0.0.1"
localPort = 3000
subdomain = "ws"  # 将使用 ws.frps.yourdomain.com
```

### 3. 负载均衡配置

如果有多个WebSocket后端服务器，可以在frpc中配置负载均衡：

```toml
[[proxies]]
name = "ws_lb"
type = "http"
localIP = "127.0.0.1"
localPort = 3000
customDomains = ["ws.yourdomain.com"]
loadBalancer.group = "ws_group"
loadBalancer.groupKey = "ws_key_123"
```

## 🛠️ 故障排查

### 1. 连接失败

检查防火墙规则：
```bash
# 检查端口是否开放
sudo iptables -L -n | grep 8080
sudo iptables -L -n | grep 8443
```

### 2. 握手失败

检查Nginx日志：
```bash
tail -f logs/nginx/error.log
tail -f logs/nginx/access.log
```

### 3. 连接频繁断开

调整超时设置：
- Nginx: `proxy_read_timeout`, `proxy_send_timeout`
- FRPS: `transport.heartbeatTimeout`

### 4. 调试模式

启用FRPS调试日志：
```toml
log.level = "debug"
```

## 📊 性能优化

### 1. 增加连接数限制

在 `nginx.conf` 中：
```nginx
events {
    worker_connections 10240;
}
```

### 2. 优化内核参数

```bash
# 增加文件描述符限制
echo "* soft nofile 65535" >> /etc/security/limits.conf
echo "* hard nofile 65535" >> /etc/security/limits.conf

# 优化网络参数
sysctl -w net.core.somaxconn=65535
sysctl -w net.ipv4.tcp_max_syn_backlog=65535
```

### 3. 使用连接池

在FRPS配置中已启用：
```toml
transport.maxPoolCount = 5
```

## 🔒 安全建议

1. **使用WSS（WebSocket Secure）**
   - 始终使用HTTPS/WSS而不是HTTP/WS
   - 确保SSL证书有效且及时更新

2. **限制访问**
   - 使用防火墙规则限制访问源
   - 在应用层实现认证机制

3. **监控和日志**
   - 定期检查连接日志
   - 监控异常连接模式

## 📚 参考资源

- [FRPS官方文档](https://gofrp.org/)
- [WebSocket协议规范](https://tools.ietf.org/html/rfc6455)
- [Nginx WebSocket代理](https://nginx.org/en/docs/http/websocket.html)