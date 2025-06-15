#!/bin/bash

# Stalwart Mail 初始化脚本
# 用于首次启动后配置Stalwart

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# 颜色输出
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# 读取配置
if [ -f "$PROJECT_DIR/stalwart-mail/.env" ]; then
    source "$PROJECT_DIR/stalwart-mail/.env"
else
    log_error "配置文件不存在，请先运行部署脚本"
    exit 1
fi

log_info "等待Stalwart启动..."
sleep 10

# 获取初始管理员密码
log_info "获取Stalwart初始管理员凭据..."
INITIAL_CREDS=$(docker logs stalwart-mail-server 2>&1 | grep -A2 "administrator" || true)

if [ -n "$INITIAL_CREDS" ]; then
    echo ""
    echo -e "${BLUE}=== Stalwart Mail 初始凭据 ===${NC}"
    echo "$INITIAL_CREDS"
    echo ""
    echo -e "${YELLOW}请使用这些凭据登录管理界面并完成配置${NC}"
    echo -e "管理界面地址: ${BLUE}https://$STALWART_DOMAIN${NC}"
    echo ""
else
    log_warn "未找到初始凭据，Stalwart可能已经配置过"
fi

# 配置SSL证书
if [ -d "$PROJECT_DIR/certbot/data/live/$STALWART_DOMAIN" ]; then
    log_info "配置SSL证书..."
    
    # 创建证书链接
    mkdir -p "$PROJECT_DIR/stalwart-mail/etc/certs"
    ln -sf "/etc/letsencrypt/live/$STALWART_DOMAIN/fullchain.pem" \
           "$PROJECT_DIR/stalwart-mail/etc/certs/cert.pem"
    ln -sf "/etc/letsencrypt/live/$STALWART_DOMAIN/privkey.pem" \
           "$PROJECT_DIR/stalwart-mail/etc/certs/key.pem"
    
    log_info "SSL证书配置完成"
fi

# 配置建议
echo ""
echo -e "${BLUE}=== 配置建议 ===${NC}"
echo "1. 登录管理界面完成初始设置"
echo "2. 配置邮件域名为: $STALWART_DOMAIN"
echo "3. 创建邮箱账户"
echo "4. 配置DKIM、SPF、DMARC记录"
echo ""
echo -e "${BLUE}=== DNS 记录配置 ===${NC}"
echo "MX记录:     @ → mail.$STALWART_DOMAIN (优先级: 10)"
echo "A记录:      mail → 您的服务器IP"
echo "SPF记录:    @ → v=spf1 mx ~all"
echo "DMARC记录:  _dmarc → v=DMARC1; p=quarantine"
echo ""

# 删除首次运行标记
rm -f "$PROJECT_DIR/stalwart-mail/.first-run"

log_info "Stalwart Mail 初始化完成！"