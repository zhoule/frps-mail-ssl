#!/bin/bash

# FRPS 安全性增强脚本
# 提供安全配置检查和强化功能

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[SECURITY]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 设置SSL证书权限
secure_ssl_certificates() {
    log_info "设置SSL证书安全权限..."
    
    if [ -d "$SCRIPT_DIR/certbot/data" ]; then
        # 设置证书目录权限
        find "$SCRIPT_DIR/certbot/data" -type d -exec chmod 750 {} \;
        find "$SCRIPT_DIR/certbot/data" -name "*.pem" -exec chmod 600 {} \;
        find "$SCRIPT_DIR/certbot/data" -name "*.key" -exec chmod 600 {} \;
        
        log_info "SSL证书权限已设置"
    else
        log_warn "SSL证书目录不存在，跳过权限设置"
    fi
}

# 创建安全的配置文件管理
create_secure_config() {
    log_info "创建安全配置管理..."
    
    # 创建secrets目录
    mkdir -p "$SCRIPT_DIR/.secrets"
    chmod 700 "$SCRIPT_DIR/.secrets"
    
    # 生成secure token
    if [ ! -f "$SCRIPT_DIR/.secrets/frps_token" ]; then
        openssl rand -hex 32 > "$SCRIPT_DIR/.secrets/frps_token"
        chmod 600 "$SCRIPT_DIR/.secrets/frps_token"
        log_info "FRPS token已生成并安全存储"
    fi
    
    # 生成admin密码
    if [ ! -f "$SCRIPT_DIR/.secrets/admin_password" ]; then
        openssl rand -base64 24 > "$SCRIPT_DIR/.secrets/admin_password"
        chmod 600 "$SCRIPT_DIR/.secrets/admin_password"
        log_info "管理员密码已生成并安全存储"
    fi
}

# 检查Docker安全配置
check_docker_security() {
    log_info "检查Docker安全配置..."
    
    # 检查Docker守护进程是否使用TLS
    if docker info 2>/dev/null | grep -q "Server Version"; then
        log_info "Docker守护进程运行正常"
        
        # 检查是否有不必要的权限
        if docker info 2>/dev/null | grep -q "Rootless"; then
            log_info "Docker运行在Rootless模式（推荐）"
        else
            log_warn "Docker运行在Root模式，建议考虑Rootless模式"
        fi
    else
        log_error "无法连接到Docker守护进程"
        return 1
    fi
}

# 强化防火墙配置
setup_firewall_rules() {
    log_info "检查防火墙配置..."
    
    # 检查UFW是否可用
    if command -v ufw >/dev/null 2>&1; then
        log_info "检测到UFW防火墙"
        echo ""
        echo "建议的防火墙规则："
        echo "  sudo ufw allow 22/tcp    # SSH"
        echo "  sudo ufw allow 80/tcp    # HTTP"
        echo "  sudo ufw allow 443/tcp   # HTTPS"  
        echo "  sudo ufw allow 7000/tcp  # FRPS"
        echo "  sudo ufw --force enable"
        echo ""
        
        read -p "是否自动配置防火墙规则? (y/N) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            sudo ufw allow 22/tcp
            sudo ufw allow 80/tcp
            sudo ufw allow 443/tcp
            sudo ufw allow 7000/tcp
            sudo ufw --force enable
            log_info "防火墙规则已配置"
        fi
    elif command -v firewall-cmd >/dev/null 2>&1; then
        log_info "检测到firewalld防火墙"
        echo ""
        echo "建议的防火墙规则："
        echo "  sudo firewall-cmd --permanent --add-service=ssh"
        echo "  sudo firewall-cmd --permanent --add-service=http"
        echo "  sudo firewall-cmd --permanent --add-service=https"
        echo "  sudo firewall-cmd --permanent --add-port=7000/tcp"
        echo "  sudo firewall-cmd --reload"
    else
        log_warn "未检测到防火墙，建议手动配置iptables规则"
    fi
}

# 生成安全的nginx配置
generate_secure_nginx_config() {
    log_info "生成安全增强的Nginx配置..."
    
    cat > "$SCRIPT_DIR/nginx/conf/security.conf" << 'EOF'
# 安全性增强配置
# 隐藏Nginx版本
server_tokens off;

# 安全头配置
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-Content-Type-Options "nosniff" always;
add_header X-XSS-Protection "1; mode=block" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline';" always;

# 限制请求大小
client_max_body_size 64m;
client_body_buffer_size 16k;
client_header_buffer_size 1k;
large_client_header_buffers 2 1k;

# Rate limiting
limit_req_zone $binary_remote_addr zone=login:10m rate=5r/m;
limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;

# 超时设置
client_body_timeout 12;
client_header_timeout 12;
keepalive_timeout 15;
send_timeout 10;

# 禁用不必要的HTTP方法
map $request_method $not_allowed_method {
    default 0;
    ~^(TRACE|DELETE|PUT)$ 1;
}

# 隐藏敏感路径
location ~ /\. {
    deny all;
    access_log off;
    log_not_found off;
}

location ~ \.(ini|conf|config|sql|bak)$ {
    deny all;
    access_log off;
    log_not_found off;
}
EOF

    log_info "安全配置已生成: nginx/conf/security.conf"
}

# 创建健康检查脚本
create_health_check() {
    log_info "创建服务健康检查脚本..."
    
    cat > "$SCRIPT_DIR/health-check.sh" << 'EOF'
#!/bin/bash

# 服务健康检查脚本

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"

# 检查Docker容器状态
check_containers() {
    echo "=== Docker容器状态 ==="
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "(nginx-proxy|frps-server|NAMES)"
    
    # 检查容器健康状态
    for container in nginx-proxy frps-server; do
        if docker ps | grep -q "$container"; then
            echo "✓ $container 运行正常"
        else
            echo "✗ $container 未运行"
            return 1
        fi
    done
}

# 检查端口连通性
check_ports() {
    echo ""
    echo "=== 端口连通性检查 ==="
    
    for port in 80 443 7000; do
        if nc -z localhost $port 2>/dev/null; then
            echo "✓ 端口 $port 可访问"
        else
            echo "✗ 端口 $port 不可访问"
        fi
    done
}

# 检查SSL证书
check_ssl_certs() {
    echo ""
    echo "=== SSL证书状态 ==="
    
    if [ -d "$SCRIPT_DIR/certbot/data/live" ]; then
        for cert_dir in "$SCRIPT_DIR/certbot/data/live"/*; do
            if [ -d "$cert_dir" ] && [ "$(basename "$cert_dir")" != "README" ]; then
                domain=$(basename "$cert_dir")
                if [ -f "$cert_dir/cert.pem" ]; then
                    expiry=$(openssl x509 -in "$cert_dir/cert.pem" -noout -enddate 2>/dev/null | cut -d= -f2)
                    expiry_timestamp=$(date -d "$expiry" +%s 2>/dev/null)
                    current_timestamp=$(date +%s)
                    days_left=$(( (expiry_timestamp - current_timestamp) / 86400 ))
                    
                    if [ $days_left -gt 30 ]; then
                        echo "✓ $domain: $days_left 天后过期"
                    elif [ $days_left -gt 0 ]; then
                        echo "⚠ $domain: $days_left 天后过期 (需要续签)"
                    else
                        echo "✗ $domain: 证书已过期"
                    fi
                fi
            fi
        done
    else
        echo "✗ 未找到SSL证书"
    fi
}

# 检查磁盘空间
check_disk_space() {
    echo ""
    echo "=== 磁盘空间检查 ==="
    
    used_percent=$(df "$SCRIPT_DIR" | awk 'NR==2 {print $5}' | sed 's/%//')
    if [ "$used_percent" -gt 85 ]; then
        echo "⚠ 磁盘使用率: ${used_percent}% (建议清理)"
    else
        echo "✓ 磁盘使用率: ${used_percent}%"
    fi
}

# 主检查函数
main() {
    echo "FRPS服务健康检查 - $(date)"
    echo "================================"
    
    check_containers
    check_ports
    check_ssl_certs
    check_disk_space
    
    echo ""
    echo "健康检查完成"
}

main "$@"
EOF

    chmod +x "$SCRIPT_DIR/health-check.sh"
    log_info "健康检查脚本已创建: health-check.sh"
}

# 创建敏感信息读取函数
create_secret_utils() {
    log_info "创建安全的配置读取工具..."
    
    cat > "$SCRIPT_DIR/secret-utils.sh" << 'EOF'
#!/bin/bash

# 安全配置读取工具

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
SECRETS_DIR="$SCRIPT_DIR/.secrets"

# 安全读取token
get_frps_token() {
    if [ -f "$SECRETS_DIR/frps_token" ]; then
        cat "$SECRETS_DIR/frps_token"
    else
        echo "$(openssl rand -hex 32)" | tee "$SECRETS_DIR/frps_token"
        chmod 600 "$SECRETS_DIR/frps_token"
    fi
}

# 安全读取管理员密码
get_admin_password() {
    if [ -f "$SECRETS_DIR/admin_password" ]; then
        cat "$SECRETS_DIR/admin_password"
    else
        echo "$(openssl rand -base64 24)" | tee "$SECRETS_DIR/admin_password"
        chmod 600 "$SECRETS_DIR/admin_password"
    fi
}

# 安全显示配置信息（隐藏敏感部分）
show_config_info() {
    local token=$(get_frps_token)
    local password=$(get_admin_password)
    
    echo "FRPS配置信息:"
    echo "  Token: ${token:0:8}...${token: -4}"
    echo "  Admin Password: ${password:0:4}...${password: -4}"
    echo ""
    echo "完整信息存储在 .secrets/ 目录中"
}

# 导出配置到环境变量（用于脚本内部）
export_secrets() {
    export FRPS_TOKEN=$(get_frps_token)
    export ADMIN_PASSWORD=$(get_admin_password)
}

# 主函数
case "${1:-}" in
    "token")
        get_frps_token
        ;;
    "password")
        get_admin_password
        ;;
    "info")
        show_config_info
        ;;
    "export")
        export_secrets
        ;;
    *)
        echo "用法: $0 {token|password|info|export}"
        ;;
esac
EOF

    chmod +x "$SCRIPT_DIR/secret-utils.sh"
    log_info "安全配置工具已创建: secret-utils.sh"
}

# 增强的docker-compose配置
enhance_docker_compose() {
    log_info "增强Docker Compose配置..."
    
    # 创建增强版本的docker-compose配置
    cat > "$SCRIPT_DIR/docker-compose.security.yml" << 'EOF'
version: '3.8'

services:
  # Nginx 反向代理和SSL终止
  nginx:
    image: nginx:alpine
    container_name: nginx-proxy
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/conf/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./nginx/conf/conf.d:/etc/nginx/conf.d:ro
      - ./nginx/conf/security.conf:/etc/nginx/conf.d/security.conf:ro
      - ./nginx/html:/usr/share/nginx/html
      - ./certbot/data:/etc/letsencrypt:ro
      - ./logs/nginx:/var/log/nginx
    depends_on:
      - frps
    restart: unless-stopped
    networks:
      - app-network
    # 安全增强
    security_opt:
      - no-new-privileges:true
    read_only: true
    tmpfs:
      - /var/cache/nginx:noexec,nosuid,size=100m
      - /var/run:noexec,nosuid,size=100m
    # 资源限制
    deploy:
      resources:
        limits:
          cpus: '1.0'
          memory: 512M
        reservations:
          cpus: '0.25'
          memory: 128M
    # 健康检查
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost/health", "||", "exit", "1"]
      interval: 30s
      timeout: 10s
      retries: 3

  # FRPS 服务器
  frps:
    image: snowdreamtech/frps:latest
    container_name: frps-server
    ports:
      - "7000:7000"       # FRPS 主端口
      # Dashboard 端口7001仅供nginx代理使用，不对外暴露
    volumes:
      - ./frps/config:/etc/frp:ro
      - ./frps/custom_errors:/etc/frp/custom_errors:ro
      - ./logs/frps:/var/log/frps
    restart: unless-stopped
    environment:
      - TZ=Asia/Shanghai
    networks:
      - app-network
    # 安全增强
    security_opt:
      - no-new-privileges:true
    # 资源限制
    deploy:
      resources:
        limits:
          cpus: '2.0'
          memory: 1G
        reservations:
          cpus: '0.5'
          memory: 256M
    # 健康检查
    healthcheck:
      test: ["CMD", "nc", "-z", "localhost", "7000"]
      interval: 30s
      timeout: 10s
      retries: 3

networks:
  app-network:
    driver: bridge
    ipam:
      config:
        - subnet: 172.30.0.0/16
    # 网络安全增强
    driver_opts:
      com.docker.network.bridge.enable_icc: "false"
      com.docker.network.bridge.enable_ip_masquerade: "true"
EOF

    log_info "安全增强的Docker Compose配置已创建: docker-compose.security.yml"
}

# 创建安全审计脚本
create_security_audit() {
    log_info "创建安全审计脚本..."
    
    cat > "$SCRIPT_DIR/security-audit.sh" << 'EOF'
#!/bin/bash

# 安全审计脚本

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"

echo "FRPS 安全审计报告 - $(date)"
echo "================================"

# 检查文件权限
echo ""
echo "=== 文件权限检查 ==="
echo "检查敏感文件权限..."

critical_files=(
    ".secrets/frps_token"
    ".secrets/admin_password"
    "certbot/data"
)

for file in "${critical_files[@]}"; do
    if [ -e "$SCRIPT_DIR/$file" ]; then
        permissions=$(stat -c "%a" "$SCRIPT_DIR/$file" 2>/dev/null || stat -f "%A" "$SCRIPT_DIR/$file" 2>/dev/null)
        if [[ "$file" == *".secrets"* ]] && [[ "$permissions" =~ ^6 ]]; then
            echo "✓ $file: $permissions (安全)"
        elif [[ "$file" == "certbot/data" ]] && [[ "$permissions" =~ ^7 ]]; then
            echo "✓ $file: $permissions (安全)" 
        else
            echo "⚠ $file: $permissions (可能不安全)"
        fi
    else
        echo "- $file: 不存在"
    fi
done

# 检查容器安全配置
echo ""
echo "=== 容器安全检查 ==="
echo "检查容器安全配置..."

for container in nginx-proxy frps-server; do
    if docker ps | grep -q "$container"; then
        # 检查是否以root运行
        user=$(docker exec "$container" whoami 2>/dev/null || echo "unknown")
        if [ "$user" = "root" ]; then
            echo "⚠ $container: 以root用户运行"
        else
            echo "✓ $container: 以非root用户运行 ($user)"
        fi
        
        # 检查安全选项
        security_opts=$(docker inspect "$container" --format '{{.HostConfig.SecurityOpt}}' 2>/dev/null)
        if [[ "$security_opts" == *"no-new-privileges"* ]]; then
            echo "✓ $container: 已启用no-new-privileges"
        else
            echo "⚠ $container: 未启用no-new-privileges"
        fi
    else
        echo "- $container: 未运行"
    fi
done

# 检查网络暴露
echo ""
echo "=== 网络暴露检查 ==="
netstat -tlnp 2>/dev/null | grep -E ':(80|443|7000|7001)' | while read line; do
    port=$(echo "$line" | awk '{print $4}' | cut -d: -f2)
    case "$port" in
        "80"|"443"|"7000")
            echo "✓ 端口 $port: 应该对外开放"
            ;;
        "7001")
            if echo "$line" | grep -q "127.0.0.1"; then
                echo "✓ 端口 7001: 仅本地访问 (安全)"
            else
                echo "⚠ 端口 7001: 对外开放 (管理端口应仅内部访问)"
            fi
            ;;
    esac
done

echo ""
echo "安全审计完成"
EOF

    chmod +x "$SCRIPT_DIR/security-audit.sh"
    log_info "安全审计脚本已创建: security-audit.sh"
}

# 主函数
main() {
    echo "FRPS 安全性增强工具"
    echo "==================="
    echo ""
    
    case "${1:-all}" in
        "ssl")
            secure_ssl_certificates
            ;;
        "config")
            create_secure_config
            ;;
        "docker")
            check_docker_security
            enhance_docker_compose
            ;;
        "firewall")
            setup_firewall_rules
            ;;
        "nginx")
            generate_secure_nginx_config
            ;;
        "health")
            create_health_check
            ;;
        "audit")
            create_security_audit
            ;;
        "all")
            create_secure_config
            secure_ssl_certificates
            check_docker_security
            generate_secure_nginx_config
            enhance_docker_compose
            create_health_check
            create_secret_utils
            create_security_audit
            setup_firewall_rules
            ;;
        *)
            echo "用法: $0 {ssl|config|docker|firewall|nginx|health|audit|all}"
            echo ""
            echo "  ssl      - 设置SSL证书权限"
            echo "  config   - 创建安全配置管理"
            echo "  docker   - Docker安全检查和增强"
            echo "  firewall - 防火墙配置"
            echo "  nginx    - Nginx安全配置"
            echo "  health   - 创建健康检查"
            echo "  audit    - 创建安全审计"
            echo "  all      - 执行所有安全增强"
            ;;
    esac
}

main "$@"