#!/bin/bash

# FRPS 运维管理工具集
# 提供便捷的日常运维命令

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 显示横幅
show_banner() {
    echo -e "${CYAN}"
    cat << 'EOF'
╔═══════════════════════════════════════════╗
║            FRPS 运维管理工具              ║
║                                           ║
║  🔍 监控 | 📊 统计 | 🛠️ 维护 | 📋 日志    ║
╚═══════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

# 实时日志查看
watch_logs() {
    local service=${1:-all}
    
    echo -e "${BLUE}=== 实时日志查看 ===${NC}"
    echo "按 Ctrl+C 停止"
    echo ""
    
    case "$service" in
        "nginx")
            echo "查看 Nginx 日志..."
            tail -f "$SCRIPT_DIR/logs/nginx"/*.log
            ;;
        "frps")
            echo "查看 FRPS 日志..."
            docker logs -f frps-server 2>/dev/null || echo "FRPS容器未运行"
            ;;
        "deploy")
            echo "查看部署日志..."
            tail -f "$SCRIPT_DIR/logs/deploy.log"
            ;;
        "all"|*)
            echo "查看所有服务日志..."
            # 使用多路复用显示所有日志
            {
                echo "=== Nginx Logs ==="
                tail -f "$SCRIPT_DIR/logs/nginx"/*.log 2>/dev/null &
                echo "=== FRPS Logs ==="
                docker logs -f frps-server 2>/dev/null &
                echo "=== Deploy Logs ==="
                tail -f "$SCRIPT_DIR/logs/deploy.log" 2>/dev/null &
                wait
            }
            ;;
    esac
}

# 服务监控面板
monitor_dashboard() {
    clear
    echo -e "${CYAN}FRPS 服务监控面板${NC}"
    echo "按 q 退出，按 r 刷新"
    echo ""
    
    while true; do
        echo -e "\033[3;1H" # 移动光标到第3行
        
        # 显示时间
        echo -e "${PURPLE}更新时间: $(date '+%Y-%m-%d %H:%M:%S')${NC}"
        echo ""
        
        # 容器状态
        echo -e "${BLUE}=== 容器状态 ===${NC}"
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "(nginx-proxy|frps-server|NAMES)" || echo "无容器运行"
        echo ""
        
        # 系统资源
        echo -e "${BLUE}=== 系统资源 ===${NC}"
        echo -n "CPU: "
        top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 | tr -d ' '
        echo "% | 内存: $(free -h | awk '/^Mem:/ {print $3"/"$2}') | 磁盘: $(df -h . | awk 'NR==2{print $5}')"
        echo ""
        
        # 网络连接
        echo -e "${BLUE}=== 活跃连接 ===${NC}"
        echo "端口 80: $(netstat -an | grep ':80 ' | grep ESTABLISHED | wc -l) 连接"
        echo "端口 443: $(netstat -an | grep ':443 ' | grep ESTABLISHED | wc -l) 连接"
        echo "端口 7000: $(netstat -an | grep ':7000 ' | grep ESTABLISHED | wc -l) 连接"
        echo ""
        
        # SSL证书状态
        echo -e "${BLUE}=== SSL证书状态 ===${NC}"
        if [ -d "$SCRIPT_DIR/certbot/data/live" ]; then
            for cert_dir in "$SCRIPT_DIR/certbot/data/live"/*; do
                if [ -d "$cert_dir" ] && [ "$(basename "$cert_dir")" != "README" ]; then
                    domain=$(basename "$cert_dir")
                    if [ -f "$cert_dir/cert.pem" ]; then
                        expiry=$(openssl x509 -in "$cert_dir/cert.pem" -noout -enddate 2>/dev/null | cut -d= -f2)
                        expiry_timestamp=$(date -d "$expiry" +%s 2>/dev/null || echo "0")
                        current_timestamp=$(date +%s)
                        days_left=$(( (expiry_timestamp - current_timestamp) / 86400 ))
                        
                        if [ $days_left -gt 30 ]; then
                            echo -e "✓ $domain: ${GREEN}$days_left 天${NC}"
                        elif [ $days_left -gt 0 ]; then
                            echo -e "⚠ $domain: ${YELLOW}$days_left 天${NC}"
                        else
                            echo -e "✗ $domain: ${RED}已过期${NC}"
                        fi
                    fi
                fi
            done
        else
            echo "未找到SSL证书"
        fi
        echo ""
        
        # 等待用户输入
        echo -e "${YELLOW}按 q 退出，按 r 刷新，或等待10秒自动刷新...${NC}"
        read -t 10 -n 1 key 2>/dev/null || key=""
        
        case "$key" in
            q|Q)
                clear
                break
                ;;
            r|R)
                clear
                echo -e "${CYAN}FRPS 服务监控面板${NC}"
                echo "按 q 退出，按 r 刷新"
                echo ""
                continue
                ;;
            *)
                continue
                ;;
        esac
    done
}

# 流量统计
traffic_stats() {
    echo -e "${BLUE}=== 流量统计 ===${NC}"
    echo ""
    
    # Nginx访问统计
    if [ -f "$SCRIPT_DIR/logs/nginx/access.log" ]; then
        echo "Nginx 访问统计 (最近1000条):"
        echo "----------------------------------------"
        tail -1000 "$SCRIPT_DIR/logs/nginx/access.log" | awk '{print $1}' | sort | uniq -c | sort -nr | head -10 | while read count ip; do
            echo "  $ip: $count 次访问"
        done
        echo ""
        
        echo "状态码统计:"
        echo "----------------------------------------"
        tail -1000 "$SCRIPT_DIR/logs/nginx/access.log" | awk '{print $9}' | sort | uniq -c | sort -nr | while read count code; do
            case "$code" in
                200) echo -e "  $code: ${GREEN}$count${NC}" ;;
                404) echo -e "  $code: ${YELLOW}$count${NC}" ;;
                5*) echo -e "  $code: ${RED}$count${NC}" ;;
                *) echo "  $code: $count" ;;
            esac
        done
        echo ""
    else
        echo "未找到Nginx访问日志"
    fi
    
    # FRPS连接统计
    echo "FRPS 连接统计:"
    echo "----------------------------------------"
    if docker exec frps-server ps aux 2>/dev/null | grep -q frps; then
        echo "FRPS进程运行正常"
        # 通过端口连接数统计
        local frps_connections=$(netstat -an | grep ':7000 ' | grep ESTABLISHED | wc -l)
        echo "当前活跃连接: $frps_connections"
    else
        echo "FRPS进程未运行"
    fi
}

# 自动备份
create_backup() {
    local backup_name=${1:-"backup-$(date +%Y%m%d-%H%M%S)"}
    local backup_dir="$SCRIPT_DIR/backups/$backup_name"
    
    log_info "创建备份: $backup_name"
    
    # 创建备份目录
    mkdir -p "$backup_dir"
    
    # 备份配置文件
    log_info "备份配置文件..."
    tar -czf "$backup_dir/configs.tar.gz" \
        nginx/conf/ \
        frps/config/ \
        docker-compose.yml \
        .env 2>/dev/null || true
    
    # 备份SSL证书
    if [ -d "$SCRIPT_DIR/certbot/data" ]; then
        log_info "备份SSL证书..."
        tar -czf "$backup_dir/ssl-certs.tar.gz" certbot/data/
    fi
    
    # 备份密钥文件
    if [ -d "$SCRIPT_DIR/.secrets" ]; then
        log_info "备份密钥文件..."
        tar -czf "$backup_dir/secrets.tar.gz" .secrets/
    fi
    
    # 生成备份信息
    cat > "$backup_dir/backup-info.txt" << EOF
备份信息
========
备份时间: $(date)
备份位置: $backup_dir
脚本版本: $(grep SCRIPT_VERSION deploy.sh | cut -d'"' -f2)

包含内容:
- configs.tar.gz: 配置文件
- ssl-certs.tar.gz: SSL证书
- secrets.tar.gz: 密钥文件

恢复说明:
1. 停止服务: docker-compose down
2. 解压配置: tar -xzf configs.tar.gz
3. 解压证书: tar -xzf ssl-certs.tar.gz  
4. 解压密钥: tar -xzf secrets.tar.gz
5. 启动服务: docker-compose up -d
EOF
    
    # 计算备份大小
    local backup_size=$(du -sh "$backup_dir" | cut -f1)
    
    log_info "备份完成!"
    echo "  位置: $backup_dir"
    echo "  大小: $backup_size"
    echo "  查看: cat $backup_dir/backup-info.txt"
}

# 清理日志
cleanup_logs() {
    local days=${1:-30}
    
    log_info "清理 $days 天前的日志文件..."
    
    # 清理Nginx日志
    if [ -d "$SCRIPT_DIR/logs/nginx" ]; then
        find "$SCRIPT_DIR/logs/nginx" -name "*.log" -mtime +$days -delete
        log_info "Nginx日志清理完成"
    fi
    
    # 清理部署日志
    if [ -f "$SCRIPT_DIR/logs/deploy.log" ]; then
        # 保留最后1000行
        tail -1000 "$SCRIPT_DIR/logs/deploy.log" > "$SCRIPT_DIR/logs/deploy.log.tmp"
        mv "$SCRIPT_DIR/logs/deploy.log.tmp" "$SCRIPT_DIR/logs/deploy.log"
        log_info "部署日志清理完成"
    fi
    
    # 清理Docker日志
    docker system prune -f >/dev/null 2>&1 || true
    log_info "Docker系统清理完成"
    
    echo ""
    echo "磁盘空间使用情况:"
    df -h "$SCRIPT_DIR"
}

# 性能测试
performance_test() {
    local domain=${1:-"localhost"}
    local test_count=${2:-10}
    
    echo -e "${BLUE}=== 性能测试 ===${NC}"
    echo "测试目标: $domain"
    echo "测试次数: $test_count"
    echo ""
    
    if ! command -v curl >/dev/null 2>&1; then
        log_error "需要安装curl进行性能测试"
        return 1
    fi
    
    # HTTP测试
    echo "HTTP响应时间测试:"
    local total_time=0
    for i in $(seq 1 $test_count); do
        local response_time=$(curl -o /dev/null -s -w "%{time_total}" "http://$domain/" 2>/dev/null || echo "0")
        echo "  测试 $i: ${response_time}s"
        total_time=$(echo "$total_time + $response_time" | bc 2>/dev/null || echo "$total_time")
    done
    
    local avg_time=$(echo "scale=3; $total_time / $test_count" | bc 2>/dev/null || echo "N/A")
    echo "  平均响应时间: ${avg_time}s"
    echo ""
    
    # HTTPS测试（如果支持）
    if curl -s -k "https://$domain/" >/dev/null 2>&1; then
        echo "HTTPS响应时间测试:"
        total_time=0
        for i in $(seq 1 $test_count); do
            local response_time=$(curl -o /dev/null -s -w "%{time_total}" -k "https://$domain/" 2>/dev/null || echo "0")
            echo "  测试 $i: ${response_time}s"
            total_time=$(echo "$total_time + $response_time" | bc 2>/dev/null || echo "$total_time")
        done
        
        avg_time=$(echo "scale=3; $total_time / $test_count" | bc 2>/dev/null || echo "N/A")
        echo "  平均响应时间: ${avg_time}s"
    fi
}

# 快速诊断
quick_diagnosis() {
    echo -e "${BLUE}=== 快速诊断 ===${NC}"
    echo ""
    
    local issues=0
    
    # 检查容器状态
    echo "1. 检查容器状态..."
    if ! docker ps | grep -q "nginx-proxy"; then
        echo -e "   ${RED}✗ Nginx容器未运行${NC}"
        issues=$((issues + 1))
    else
        echo -e "   ${GREEN}✓ Nginx容器运行正常${NC}"
    fi
    
    if ! docker ps | grep -q "frps-server"; then
        echo -e "   ${RED}✗ FRPS容器未运行${NC}"
        issues=$((issues + 1))
    else
        echo -e "   ${GREEN}✓ FRPS容器运行正常${NC}"
    fi
    
    # 检查端口
    echo ""
    echo "2. 检查端口连通性..."
    for port in 80 443 7000; do
        if nc -z localhost $port 2>/dev/null; then
            echo -e "   ${GREEN}✓ 端口 $port 可访问${NC}"
        else
            echo -e "   ${RED}✗ 端口 $port 不可访问${NC}"
            issues=$((issues + 1))
        fi
    done
    
    # 检查SSL证书
    echo ""
    echo "3. 检查SSL证书..."
    if [ -d "$SCRIPT_DIR/certbot/data/live" ] && [ "$(ls -A $SCRIPT_DIR/certbot/data/live 2>/dev/null | grep -v README)" ]; then
        local expired_certs=0
        for cert_dir in "$SCRIPT_DIR/certbot/data/live"/*; do
            if [ -d "$cert_dir" ] && [ "$(basename "$cert_dir")" != "README" ]; then
                domain=$(basename "$cert_dir")
                if [ -f "$cert_dir/cert.pem" ]; then
                    expiry=$(openssl x509 -in "$cert_dir/cert.pem" -noout -enddate 2>/dev/null | cut -d= -f2)
                    expiry_timestamp=$(date -d "$expiry" +%s 2>/dev/null || echo "0")
                    current_timestamp=$(date +%s)
                    days_left=$(( (expiry_timestamp - current_timestamp) / 86400 ))
                    
                    if [ $days_left -le 0 ]; then
                        echo -e "   ${RED}✗ $domain 证书已过期${NC}"
                        expired_certs=$((expired_certs + 1))
                    elif [ $days_left -le 30 ]; then
                        echo -e "   ${YELLOW}⚠ $domain 证书将在 $days_left 天后过期${NC}"
                    else
                        echo -e "   ${GREEN}✓ $domain 证书有效 ($days_left 天)${NC}"
                    fi
                fi
            fi
        done
        issues=$((issues + expired_certs))
    else
        echo -e "   ${YELLOW}⚠ 未找到SSL证书${NC}"
    fi
    
    # 检查磁盘空间
    echo ""
    echo "4. 检查磁盘空间..."
    local disk_usage=$(df "$SCRIPT_DIR" | awk 'NR==2 {print $5}' | sed 's/%//')
    if [ "$disk_usage" -gt 90 ]; then
        echo -e "   ${RED}✗ 磁盘使用率过高: ${disk_usage}%${NC}"
        issues=$((issues + 1))
    elif [ "$disk_usage" -gt 80 ]; then
        echo -e "   ${YELLOW}⚠ 磁盘使用率较高: ${disk_usage}%${NC}"
    else
        echo -e "   ${GREEN}✓ 磁盘使用率正常: ${disk_usage}%${NC}"
    fi
    
    # 总结
    echo ""
    echo "5. 诊断总结:"
    if [ $issues -eq 0 ]; then
        echo -e "   ${GREEN}✓ 所有检查通过，系统运行正常${NC}"
    else
        echo -e "   ${RED}✗ 发现 $issues 个问题，建议检查和修复${NC}"
    fi
}

# 显示使用说明
show_usage() {
    cat << EOF
${CYAN}FRPS 运维管理工具${NC}

${CYAN}用法:${NC}
    $0 monitor              实时监控面板
    $0 logs [service]       查看日志 (nginx/frps/deploy/all)
    $0 stats                流量统计
    $0 backup [name]        创建备份
    $0 cleanup [days]       清理日志 (默认30天)
    $0 test [domain]        性能测试
    $0 diagnosis            快速诊断
    $0 help                 显示帮助

${CYAN}示例:${NC}
    $0 monitor              # 打开监控面板
    $0 logs nginx           # 查看Nginx日志
    $0 backup prod-backup   # 创建生产备份
    $0 cleanup 7            # 清理7天前的日志
    $0 test example.com     # 测试example.com性能
    $0 diagnosis            # 运行系统诊断

${CYAN}高级功能:${NC}
    ./health-check.sh       # 运行健康检查
    ./security-audit.sh     # 运行安全审计
    ./secret-utils.sh info  # 查看配置信息
EOF
}

# 主函数
main() {
    show_banner
    
    case "${1:-help}" in
        "monitor")
            monitor_dashboard
            ;;
        "logs")
            watch_logs "${2:-all}"
            ;;
        "stats")
            traffic_stats
            ;;
        "backup")
            create_backup "$2"
            ;;
        "cleanup")
            cleanup_logs "${2:-30}"
            ;;
        "test")
            performance_test "${2:-localhost}" "${3:-10}"
            ;;
        "diagnosis")
            quick_diagnosis
            ;;
        "help"|*)
            show_usage
            ;;
    esac
}

main "$@"