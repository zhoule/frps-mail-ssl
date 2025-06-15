#!/bin/bash

# FRPS 监控和告警系统
# 定期检查服务状态并发送告警

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
CONFIG_FILE="$SCRIPT_DIR/monitoring.conf"

# 默认配置
DEFAULT_CHECK_INTERVAL=300  # 5分钟
DEFAULT_ALERT_EMAIL=""
DEFAULT_WEBHOOK_URL=""
DEFAULT_LOG_FILE="$SCRIPT_DIR/logs/monitoring.log"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    local msg="$(date '+%Y-%m-%d %H:%M:%S') [INFO] $1"
    echo -e "${GREEN}$msg${NC}"
    echo "$msg" >> "$DEFAULT_LOG_FILE"
}

log_warn() {
    local msg="$(date '+%Y-%m-%d %H:%M:%S') [WARN] $1"
    echo -e "${YELLOW}$msg${NC}"
    echo "$msg" >> "$DEFAULT_LOG_FILE"
}

log_error() {
    local msg="$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $1"
    echo -e "${RED}$msg${NC}"
    echo "$msg" >> "$DEFAULT_LOG_FILE"
}

# 加载配置
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    fi
    
    # 设置默认值
    CHECK_INTERVAL=${CHECK_INTERVAL:-$DEFAULT_CHECK_INTERVAL}
    ALERT_EMAIL=${ALERT_EMAIL:-$DEFAULT_ALERT_EMAIL}
    WEBHOOK_URL=${WEBHOOK_URL:-$DEFAULT_WEBHOOK_URL}
    LOG_FILE=${LOG_FILE:-$DEFAULT_LOG_FILE}
    
    # 确保日志目录存在
    mkdir -p "$(dirname "$LOG_FILE")"
}

# 生成配置文件
generate_config() {
    log_info "生成监控配置文件..."
    
    cat > "$CONFIG_FILE" << 'EOF'
# FRPS 监控配置文件

# 检查间隔（秒）
CHECK_INTERVAL=300

# 邮件告警配置
ALERT_EMAIL=""  # 告警邮箱地址
SMTP_SERVER=""  # SMTP服务器
SMTP_PORT=587   # SMTP端口
SMTP_USER=""    # SMTP用户名
SMTP_PASS=""    # SMTP密码

# Webhook告警配置
WEBHOOK_URL=""  # Webhook URL (Slack/Discord/企业微信等)

# 日志配置
LOG_FILE="logs/monitoring.log"

# 告警阈值
CPU_THRESHOLD=80        # CPU使用率阈值(%)
MEMORY_THRESHOLD=80     # 内存使用率阈值(%)
DISK_THRESHOLD=85       # 磁盘使用率阈值(%)
CERT_EXPIRE_DAYS=30     # SSL证书过期告警天数

# 检查项目开关
CHECK_CONTAINERS=true   # 检查容器状态
CHECK_PORTS=true        # 检查端口连通性
CHECK_SSL=true          # 检查SSL证书
CHECK_RESOURCES=true    # 检查系统资源
CHECK_LOGS=true         # 检查错误日志

# 告警静默期（秒，避免重复告警）
ALERT_SILENCE_PERIOD=3600
EOF

    log_info "配置文件已生成: $CONFIG_FILE"
    echo "请编辑配置文件设置告警参数"
}

# 检查容器状态
check_containers() {
    local issues=()
    
    # 检查Nginx容器
    if ! docker ps | grep -q "nginx-proxy"; then
        issues+=("Nginx容器未运行")
    fi
    
    # 检查FRPS容器  
    if ! docker ps | grep -q "frps-server"; then
        issues+=("FRPS容器未运行")
    fi
    
    # 检查容器健康状态
    for container in nginx-proxy frps-server; do
        if docker ps | grep -q "$container"; then
            local health=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "unknown")
            if [ "$health" = "unhealthy" ]; then
                issues+=("$container 容器状态不健康")
            fi
        fi
    done
    
    if [ ${#issues[@]} -gt 0 ]; then
        return 1
    fi
    return 0
}

# 检查端口连通性
check_ports() {
    local issues=()
    local required_ports=(80 443 7000)
    
    for port in "${required_ports[@]}"; do
        if ! nc -z localhost "$port" 2>/dev/null; then
            issues+=("端口 $port 不可访问")
        fi
    done
    
    if [ ${#issues[@]} -gt 0 ]; then
        return 1
    fi
    return 0
}

# 检查SSL证书
check_ssl_certificates() {
    local issues=()
    
    if [ -d "$SCRIPT_DIR/certbot/data/live" ]; then
        for cert_dir in "$SCRIPT_DIR/certbot/data/live"/*; do
            if [ -d "$cert_dir" ] && [ "$(basename "$cert_dir")" != "README" ]; then
                local domain=$(basename "$cert_dir")
                if [ -f "$cert_dir/cert.pem" ]; then
                    local expiry=$(openssl x509 -in "$cert_dir/cert.pem" -noout -enddate 2>/dev/null | cut -d= -f2)
                    local expiry_timestamp=$(date -d "$expiry" +%s 2>/dev/null || echo "0")
                    local current_timestamp=$(date +%s)
                    local days_left=$(( (expiry_timestamp - current_timestamp) / 86400 ))
                    
                    if [ $days_left -le 0 ]; then
                        issues+=("$domain SSL证书已过期")
                    elif [ $days_left -le $CERT_EXPIRE_DAYS ]; then
                        issues+=("$domain SSL证书将在 $days_left 天后过期")
                    fi
                fi
            fi
        done
    fi
    
    if [ ${#issues[@]} -gt 0 ]; then
        return 1
    fi
    return 0
}

# 检查系统资源
check_system_resources() {
    local issues=()
    
    # 检查CPU使用率
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 | tr -d ' ' | cut -d'.' -f1)
    if [ "$cpu_usage" -gt $CPU_THRESHOLD ]; then
        issues+=("CPU使用率过高: ${cpu_usage}%")
    fi
    
    # 检查内存使用率
    local memory_usage=$(free | awk '/^Mem:/ {printf "%.0f", $3/$2 * 100}')
    if [ "$memory_usage" -gt $MEMORY_THRESHOLD ]; then
        issues+=("内存使用率过高: ${memory_usage}%")
    fi
    
    # 检查磁盘使用率
    local disk_usage=$(df "$SCRIPT_DIR" | awk 'NR==2 {print $5}' | sed 's/%//')
    if [ "$disk_usage" -gt $DISK_THRESHOLD ]; then
        issues+=("磁盘使用率过高: ${disk_usage}%")
    fi
    
    if [ ${#issues[@]} -gt 0 ]; then
        return 1
    fi
    return 0
}

# 检查错误日志
check_error_logs() {
    local issues=()
    local time_threshold=$(date -d '5 minutes ago' '+%Y-%m-%d %H:%M:%S')
    
    # 检查Nginx错误日志
    if [ -f "$SCRIPT_DIR/logs/nginx/error.log" ]; then
        local nginx_errors=$(grep "error" "$SCRIPT_DIR/logs/nginx/error.log" | tail -100 | wc -l)
        if [ "$nginx_errors" -gt 10 ]; then
            issues+=("Nginx错误日志过多: $nginx_errors 条")
        fi
    fi
    
    # 检查Docker容器错误
    for container in nginx-proxy frps-server; do
        if docker ps | grep -q "$container"; then
            local container_errors=$(docker logs "$container" --since 5m 2>&1 | grep -i error | wc -l)
            if [ "$container_errors" -gt 5 ]; then
                issues+=("$container 容器错误过多: $container_errors 条")
            fi
        fi
    done
    
    if [ ${#issues[@]} -gt 0 ]; then
        return 1
    fi
    return 0
}

# 发送邮件告警
send_email_alert() {
    local subject="$1"
    local message="$2"
    
    if [ -z "$ALERT_EMAIL" ] || [ -z "$SMTP_SERVER" ]; then
        log_warn "邮件告警未配置，跳过邮件发送"
        return 1
    fi
    
    # 使用sendmail或mail命令发送邮件
    if command -v mail >/dev/null 2>&1; then
        echo "$message" | mail -s "$subject" "$ALERT_EMAIL"
        log_info "告警邮件已发送到: $ALERT_EMAIL"
    elif command -v sendmail >/dev/null 2>&1; then
        {
            echo "To: $ALERT_EMAIL"
            echo "Subject: $subject"
            echo ""
            echo "$message"
        } | sendmail "$ALERT_EMAIL"
        log_info "告警邮件已发送到: $ALERT_EMAIL"
    else
        log_warn "未找到邮件发送工具"
        return 1
    fi
}

# 发送Webhook告警
send_webhook_alert() {
    local title="$1"
    local message="$2"
    
    if [ -z "$WEBHOOK_URL" ]; then
        log_warn "Webhook告警未配置，跳过Webhook发送"
        return 1
    fi
    
    # 构造JSON消息（适用于Slack/Discord等）
    local json_payload=$(cat << EOF
{
    "text": "$title",
    "attachments": [
        {
            "color": "danger",
            "fields": [
                {
                    "title": "详细信息",
                    "value": "$message",
                    "short": false
                },
                {
                    "title": "时间",
                    "value": "$(date '+%Y-%m-%d %H:%M:%S')",
                    "short": true
                },
                {
                    "title": "服务器",
                    "value": "$(hostname)",
                    "short": true
                }
            ]
        }
    ]
}
EOF
)
    
    # 发送Webhook
    if curl -X POST -H "Content-Type: application/json" -d "$json_payload" "$WEBHOOK_URL" >/dev/null 2>&1; then
        log_info "Webhook告警已发送"
    else
        log_warn "Webhook发送失败"
        return 1
    fi
}

# 检查告警静默期
is_alert_silenced() {
    local alert_type="$1"
    local silence_file="$SCRIPT_DIR/.alert_silence_$alert_type"
    
    if [ -f "$silence_file" ]; then
        local last_alert=$(cat "$silence_file")
        local current_time=$(date +%s)
        local time_diff=$((current_time - last_alert))
        
        if [ $time_diff -lt $ALERT_SILENCE_PERIOD ]; then
            return 0  # 在静默期内
        fi
    fi
    
    return 1  # 不在静默期内
}

# 记录告警时间
record_alert_time() {
    local alert_type="$1"
    local silence_file="$SCRIPT_DIR/.alert_silence_$alert_type"
    date +%s > "$silence_file"
}

# 执行监控检查
run_monitoring() {
    log_info "开始监控检查..."
    local overall_status="healthy"
    local alert_messages=()
    
    # 容器状态检查
    if [ "$CHECK_CONTAINERS" = "true" ]; then
        if ! check_containers; then
            overall_status="unhealthy"
            if ! is_alert_silenced "containers"; then
                alert_messages+=("容器状态异常")
                record_alert_time "containers"
            fi
        fi
    fi
    
    # 端口连通性检查
    if [ "$CHECK_PORTS" = "true" ]; then
        if ! check_ports; then
            overall_status="unhealthy"
            if ! is_alert_silenced "ports"; then
                alert_messages+=("端口连通性异常")
                record_alert_time "ports"
            fi
        fi
    fi
    
    # SSL证书检查
    if [ "$CHECK_SSL" = "true" ]; then
        if ! check_ssl_certificates; then
            overall_status="warning"
            if ! is_alert_silenced "ssl"; then
                alert_messages+=("SSL证书即将过期或已过期")
                record_alert_time "ssl"
            fi
        fi
    fi
    
    # 系统资源检查
    if [ "$CHECK_RESOURCES" = "true" ]; then
        if ! check_system_resources; then
            overall_status="warning"
            if ! is_alert_silenced "resources"; then
                alert_messages+=("系统资源使用率过高")
                record_alert_time "resources"
            fi
        fi
    fi
    
    # 错误日志检查
    if [ "$CHECK_LOGS" = "true" ]; then
        if ! check_error_logs; then
            overall_status="warning"
            if ! is_alert_silenced "logs"; then
                alert_messages+=("发现大量错误日志")
                record_alert_time "logs"
            fi
        fi
    fi
    
    # 发送告警
    if [ ${#alert_messages[@]} -gt 0 ]; then
        local alert_title="FRPS服务告警 - $(hostname)"
        local alert_message="检测到以下问题：\n$(printf '%s\n' "${alert_messages[@]}")\n\n请及时检查和处理。"
        
        log_error "发现问题: $(printf '%s; ' "${alert_messages[@]}")"
        
        # 发送邮件告警
        send_email_alert "$alert_title" "$alert_message"
        
        # 发送Webhook告警
        send_webhook_alert "$alert_title" "$alert_message"
    else
        log_info "所有检查通过，服务运行正常"
    fi
    
    # 记录状态
    echo "$(date '+%Y-%m-%d %H:%M:%S'),$overall_status" >> "$SCRIPT_DIR/logs/monitoring-status.csv"
}

# 生成监控报告
generate_report() {
    local days=${1:-7}
    local report_file="$SCRIPT_DIR/monitoring-report-$(date +%Y%m%d).html"
    
    log_info "生成监控报告: $report_file"
    
    cat > "$report_file" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>FRPS监控报告</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background: #f5f5f5; padding: 20px; border-radius: 5px; }
        .section { margin: 20px 0; padding: 15px; border: 1px solid #ddd; border-radius: 5px; }
        .healthy { color: green; }
        .warning { color: orange; }
        .unhealthy { color: red; }
        table { width: 100%; border-collapse: collapse; }
        th, td { padding: 8px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background-color: #f2f2f2; }
    </style>
</head>
<body>
    <div class="header">
        <h1>FRPS监控报告</h1>
        <p>生成时间: $(date '+%Y-%m-%d %H:%M:%S')</p>
        <p>报告周期: 最近 $days 天</p>
        <p>服务器: $(hostname)</p>
    </div>
    
    <div class="section">
        <h2>服务状态概览</h2>
        <table>
            <tr><th>检查项</th><th>状态</th><th>说明</th></tr>
EOF

    # 添加当前状态检查
    if check_containers; then
        echo "            <tr><td>容器状态</td><td class=\"healthy\">正常</td><td>所有容器运行正常</td></tr>" >> "$report_file"
    else
        echo "            <tr><td>容器状态</td><td class=\"unhealthy\">异常</td><td>部分容器未运行</td></tr>" >> "$report_file"
    fi
    
    if check_ports; then
        echo "            <tr><td>端口连通性</td><td class=\"healthy\">正常</td><td>所有端口可访问</td></tr>" >> "$report_file"
    else
        echo "            <tr><td>端口连通性</td><td class=\"unhealthy\">异常</td><td>部分端口不可访问</td></tr>" >> "$report_file"
    fi
    
    if check_ssl_certificates; then
        echo "            <tr><td>SSL证书</td><td class=\"healthy\">正常</td><td>证书有效</td></tr>" >> "$report_file"
    else
        echo "            <tr><td>SSL证书</td><td class=\"warning\">警告</td><td>证书即将过期或已过期</td></tr>" >> "$report_file"
    fi
    
    cat >> "$report_file" << EOF
        </table>
    </div>
    
    <div class="section">
        <h2>历史状态统计</h2>
        <p>基于监控日志的统计信息</p>
EOF

    # 添加历史统计
    if [ -f "$SCRIPT_DIR/logs/monitoring-status.csv" ]; then
        local total_checks=$(tail -$((days * 288)) "$SCRIPT_DIR/logs/monitoring-status.csv" | wc -l)
        local healthy_checks=$(tail -$((days * 288)) "$SCRIPT_DIR/logs/monitoring-status.csv" | grep ",healthy" | wc -l)
        local warning_checks=$(tail -$((days * 288)) "$SCRIPT_DIR/logs/monitoring-status.csv" | grep ",warning" | wc -l)
        local unhealthy_checks=$(tail -$((days * 288)) "$SCRIPT_DIR/logs/monitoring-status.csv" | grep ",unhealthy" | wc -l)
        
        local healthy_percent=$(( healthy_checks * 100 / total_checks ))
        
        cat >> "$report_file" << EOF
        <table>
            <tr><th>状态</th><th>次数</th><th>占比</th></tr>
            <tr><td class="healthy">正常</td><td>$healthy_checks</td><td>${healthy_percent}%</td></tr>
            <tr><td class="warning">警告</td><td>$warning_checks</td><td>$(( warning_checks * 100 / total_checks ))%</td></tr>
            <tr><td class="unhealthy">异常</td><td>$unhealthy_checks</td><td>$(( unhealthy_checks * 100 / total_checks ))%</td></tr>
        </table>
        <p>可用性: <strong>${healthy_percent}%</strong></p>
EOF
    fi
    
    cat >> "$report_file" << EOF
    </div>
    
    <div class="section">
        <h2>建议</h2>
        <ul>
            <li>定期检查SSL证书过期时间，及时续签</li>
            <li>监控系统资源使用情况，及时清理日志</li>
            <li>保持Docker镜像为最新版本</li>
            <li>定期备份重要配置和数据</li>
        </ul>
    </div>
</body>
</html>
EOF

    log_info "监控报告已生成: $report_file"
    echo "在浏览器中打开查看: file://$report_file"
}

# 显示使用说明
show_usage() {
    cat << EOF
FRPS 监控和告警系统

用法:
    $0 init                     初始化配置文件
    $0 check                    执行一次监控检查
    $0 daemon                   启动监控守护进程
    $0 stop                     停止监控守护进程
    $0 status                   查看监控状态
    $0 report [days]            生成监控报告

示例:
    $0 init                     # 初始化配置
    $0 check                    # 手动检查一次
    $0 daemon                   # 启动持续监控
    $0 report 30                # 生成30天报告

配置文件: $CONFIG_FILE
日志文件: $DEFAULT_LOG_FILE
EOF
}

# 启动监控守护进程
start_daemon() {
    local pid_file="$SCRIPT_DIR/.monitoring.pid"
    
    if [ -f "$pid_file" ] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
        log_error "监控进程已在运行 (PID: $(cat "$pid_file"))"
        return 1
    fi
    
    log_info "启动监控守护进程..."
    
    # 后台运行监控循环
    (
        while true; do
            run_monitoring
            sleep "$CHECK_INTERVAL"
        done
    ) &
    
    echo $! > "$pid_file"
    log_info "监控守护进程已启动 (PID: $!)"
    echo "使用 '$0 stop' 停止监控"
}

# 停止监控守护进程
stop_daemon() {
    local pid_file="$SCRIPT_DIR/.monitoring.pid"
    
    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid"
            rm -f "$pid_file"
            log_info "监控守护进程已停止"
        else
            log_warn "监控进程不存在，清理PID文件"
            rm -f "$pid_file"
        fi
    else
        log_warn "未找到监控进程PID文件"
    fi
}

# 查看监控状态
show_monitoring_status() {
    local pid_file="$SCRIPT_DIR/.monitoring.pid"
    
    echo "监控系统状态:"
    echo "============="
    
    if [ -f "$pid_file" ] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
        echo "状态: 运行中"
        echo "PID: $(cat "$pid_file")"
        echo "检查间隔: $CHECK_INTERVAL 秒"
    else
        echo "状态: 未运行"
    fi
    
    echo ""
    echo "配置文件: $CONFIG_FILE"
    echo "日志文件: $LOG_FILE"
    
    if [ -f "$LOG_FILE" ]; then
        echo ""
        echo "最近的日志:"
        tail -5 "$LOG_FILE"
    fi
}

# 主函数
main() {
    load_config
    
    case "${1:-help}" in
        "init")
            generate_config
            ;;
        "check")
            run_monitoring
            ;;
        "daemon")
            start_daemon
            ;;
        "stop")
            stop_daemon
            ;;
        "status")
            show_monitoring_status
            ;;
        "report")
            generate_report "${2:-7}"
            ;;
        "help"|*)
            show_usage
            ;;
    esac
}

main "$@"