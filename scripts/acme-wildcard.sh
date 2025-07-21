#!/bin/bash
# acme.sh 泛域名证书申请脚本
# 支持所有主流 DNS 提供商

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# 安装 acme.sh
install_acme() {
    if [ ! -d "$HOME/.acme.sh" ]; then
        log_info "安装 acme.sh..."
        curl https://get.acme.sh | sh -s email=$1
        source "$HOME/.acme.sh/acme.sh.env"
    else
        log_info "acme.sh 已安装"
    fi
}

# 设置 DNS API 凭据
setup_dns_credentials() {
    local dns_provider=$1
    
    case "$dns_provider" in
        "cloudflare")
            export CF_Email="$CLOUDFLARE_EMAIL"
            export CF_Key="$CLOUDFLARE_API_KEY"
            ;;
        "aliyun"|"ali")
            export Ali_Key="$ALIBABA_CLOUD_ACCESS_KEY_ID"
            export Ali_Secret="$ALIBABA_CLOUD_ACCESS_KEY_SECRET"
            ;;
        "tencent"|"tencentcloud")
            export Tencent_SecretId="$TENCENTCLOUD_SECRET_ID"
            export Tencent_SecretKey="$TENCENTCLOUD_SECRET_KEY"
            ;;
        "dnspod")
            export DP_Id="$DNSPOD_ID"
            export DP_Key="$DNSPOD_KEY"
            ;;
        "huaweicloud")
            export HUAWEICLOUD_Username="$HUAWEICLOUD_USERNAME"
            export HUAWEICLOUD_Password="$HUAWEICLOUD_PASSWORD"
            export HUAWEICLOUD_ProjectID="$HUAWEICLOUD_PROJECT_ID"
            ;;
        "aws")
            export AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID"
            export AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY"
            ;;
        "gcloud")
            export GCLOUD_SERVICE_ACCOUNT_EMAIL="$GCLOUD_SERVICE_ACCOUNT_EMAIL"
            export GCLOUD_SERVICE_ACCOUNT_KEY="$GCLOUD_SERVICE_ACCOUNT_KEY"
            ;;
        "azure")
            export AZUREDNS_SUBSCRIPTIONID="$AZUREDNS_SUBSCRIPTIONID"
            export AZUREDNS_TENANTID="$AZUREDNS_TENANTID"
            export AZUREDNS_APPID="$AZUREDNS_APPID"
            export AZUREDNS_CLIENTSECRET="$AZUREDNS_CLIENTSECRET"
            ;;
        *)
            log_error "不支持的 DNS 提供商: $dns_provider"
            return 1
            ;;
    esac
    
    return 0
}

# 获取 DNS 插件名称
get_dns_plugin() {
    local dns_provider=$1
    
    case "$dns_provider" in
        "cloudflare") echo "dns_cf" ;;
        "aliyun"|"ali") echo "dns_ali" ;;
        "tencent"|"tencentcloud") echo "dns_tencent" ;;
        "dnspod") echo "dns_dp" ;;
        "huaweicloud") echo "dns_huaweicloud" ;;
        "aws") echo "dns_aws" ;;
        "gcloud") echo "dns_gcloud" ;;
        "azure") echo "dns_azure" ;;
        *) echo "" ;;
    esac
}

# 申请泛域名证书
request_wildcard_cert_acme() {
    local domain=$1
    local email=$2
    local dns_provider=$3
    local cert_path=$4
    
    # 安装 acme.sh
    install_acme "$email"
    
    # 设置 DNS 凭据
    setup_dns_credentials "$dns_provider" || return 1
    
    # 获取 DNS 插件名称
    local dns_plugin=$(get_dns_plugin "$dns_provider")
    if [ -z "$dns_plugin" ]; then
        log_error "无法获取 DNS 插件名称"
        return 1
    fi
    
    log_info "使用 $dns_plugin 插件申请证书..."
    
    # 申请证书
    "$HOME/.acme.sh/acme.sh" --issue \
        --dns "$dns_plugin" \
        -d "$domain" \
        -d "*.$domain" \
        --keylength 2048
    
    # 检查返回码
    local issue_result=$?
    
    # acme.sh 返回码说明：
    # 0 - 成功申请新证书
    # 2 - 证书已存在且未到期
    if [ $issue_result -eq 2 ]; then
        log_warning "证书已存在且未到期，继续安装步骤"
    elif [ $issue_result -ne 0 ] && [ $issue_result -ne 2 ]; then
        log_error "证书申请失败 (错误码: $issue_result)"
        return 1
    else
        log_info "新证书申请成功"
    fi
    
    # 安装证书到指定位置
    log_info "安装证书到 $cert_path"
    mkdir -p "$cert_path"
    
    "$HOME/.acme.sh/acme.sh" --install-cert \
        -d "$domain" \
        --key-file "$cert_path/privkey.pem" \
        --fullchain-file "$cert_path/fullchain.pem" \
        --cert-file "$cert_path/cert.pem" \
        --ca-file "$cert_path/chain.pem" \
        --reloadcmd "docker exec nginx-proxy nginx -s reload 2>/dev/null || true"
    
    if [ $? -eq 0 ]; then
        log_info "证书安装成功"
        # 设置自动续期
        "$HOME/.acme.sh/acme.sh" --upgrade --auto-upgrade
        return 0
    else
        log_error "证书安装失败"
        return 1
    fi
}

# 续期证书
renew_wildcard_cert_acme() {
    local domain=$1
    
    log_info "续期证书: $domain"
    "$HOME/.acme.sh/acme.sh" --renew -d "$domain" --force
    
    if [ $? -eq 0 ]; then
        log_info "证书续期成功"
        docker exec nginx-proxy nginx -s reload 2>/dev/null || true
        return 0
    else
        log_error "证书续期失败"
        return 1
    fi
}

# 列出所有证书
list_certs() {
    "$HOME/.acme.sh/acme.sh" --list
}

# 主函数
main() {
    local action=$1
    shift
    
    case "$action" in
        "issue")
            if [ $# -lt 3 ]; then
                echo "用法: $0 issue <domain> <email> <dns-provider> [cert-path]"
                echo "支持的 DNS 提供商: cloudflare, aliyun, tencent, dnspod, huaweicloud, aws, gcloud, azure"
                exit 1
            fi
            request_wildcard_cert_acme "$1" "$2" "$3" "${4:-./certbot/data/live/$1}"
            ;;
        "renew")
            if [ $# -lt 1 ]; then
                echo "用法: $0 renew <domain>"
                exit 1
            fi
            renew_wildcard_cert_acme "$1"
            ;;
        "list")
            list_certs
            ;;
        *)
            echo "用法: $0 {issue|renew|list} ..."
            echo ""
            echo "命令:"
            echo "  issue <domain> <email> <dns-provider> [cert-path]  - 申请新证书"
            echo "  renew <domain>                                      - 续期证书"
            echo "  list                                                - 列出所有证书"
            echo ""
            echo "示例:"
            echo "  $0 issue example.com admin@example.com cloudflare"
            echo "  $0 issue example.com admin@example.com tencent /etc/ssl/certs"
            echo "  $0 renew example.com"
            exit 1
            ;;
    esac
}

# 如果直接运行脚本，执行主函数
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi