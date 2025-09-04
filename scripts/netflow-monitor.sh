#!/bin/bash

# NetFlow ELK Stack Smart Monitoring Script
# Adapts based on system configuration

# Load environment variables if available
if [ -f "$(dirname "$0")/../.env" ]; then
    source "$(dirname "$0")/../.env"
elif [ -f ".env" ]; then
    source ".env"
fi

# Default values if not set
TOTAL_RAM_GB=${TOTAL_RAM_GB:-"Unknown"}
CPU_CORES=${CPU_CORES:-$(nproc)}
DISK_TYPE=${DISK_TYPE:-"Unknown"}
ES_HEAP_SIZE=${ES_HEAP_SIZE:-"Unknown"}
ELASTICSEARCH_PORT=${ELASTICSEARCH_PORT:-9200}
KIBANA_PORT=${KIBANA_PORT:-5601}
NETFLOW_PORT=${NETFLOW_PORT:-2055}
RETENTION_DAYS=${RETENTION_DAYS:-30}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Configuration thresholds based on system resources
if [ "$TOTAL_RAM_GB" != "Unknown" ] && [ "$TOTAL_RAM_GB" -le 2 ]; then
    MEMORY_WARNING_THRESHOLD=90
    CPU_WARNING_THRESHOLD=85
    DISK_WARNING_THRESHOLD=85
    DISK_CRITICAL_THRESHOLD=92
else
    MEMORY_WARNING_THRESHOLD=85
    CPU_WARNING_THRESHOLD=80
    DISK_WARNING_THRESHOLD=80
    DISK_CRITICAL_THRESHOLD=90
fi

# Header with system info
echo "========================================================"
echo "=== NetFlow ELK Stack Monitoring - $(hostname) ==="
echo "========================================================"
echo "System: ${TOTAL_RAM_GB}GB RAM, ${CPU_CORES} cores, ${DISK_TYPE} storage"
echo "ES Heap: ${ES_HEAP_SIZE} | Retention: ${RETENTION_DAYS} days"
echo "Date: $(date '+%Y-%m-%d %H:%M:%S')"
echo "Uptime: $(uptime -p)"
echo "========================================================"
echo ""

# 1. SYSTEM OVERVIEW
echo "🖥️  === SYSTEM OVERVIEW ==="
echo "Hostname: $(hostname)"
echo "Kernel: $(uname -r)"
echo "Architecture: $(uname -m)"
echo "Load Average: $(uptime | awk -F'load average:' '{print $2}')"
echo ""

# 2. MEMORY USAGE with adaptive warnings
echo "💾 === MEMORY USAGE ==="
memory_info=$(free -h)
echo "$memory_info"

memory_used=$(free | grep Mem | awk '{printf("%.1f"), ($3/$2) * 100.0}')
memory_available=$(free -h | grep Mem | awk '{print $7}')

echo "Memory Usage: ${memory_used}% (Available: ${memory_available})"

# Smart memory warnings based on system size
if (( $(echo "$memory_used > $MEMORY_WARNING_THRESHOLD" | bc -l) )); then
    if [ "$TOTAL_RAM_GB" != "Unknown" ] && [ "$TOTAL_RAM_GB" -le 2 ]; then
        log_warning "High memory usage for low-RAM system: ${memory_used}%"
        echo "   Recommendation: Consider reducing Elasticsearch heap or add more RAM"
    else
        log_warning "High memory usage detected: ${memory_used}%"
    fi
fi

# Show memory usage by major processes
echo "Top memory consumers:"
ps aux --sort=-%mem | head -6 | awk 'NR==1{print $0} NR>1{printf "  %-15s %6s %6s %s\n", $11, $4"%", $6/1024"MB", $2}'
echo ""

# 3. CPU USAGE with context
echo "🔥 === CPU USAGE ==="
cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{printf("%.1f"), 100 - $1}')
echo "CPU Usage: ${cpu_usage}%"

# Context-aware CPU warnings
if (( $(echo "$cpu_usage > $CPU_WARNING_THRESHOLD" | bc -l) )); then
    if [ "$CPU_CORES" -le 2 ]; then
        log_warning "High CPU usage for ${CPU_CORES}-core system: ${cpu_usage}%"
    else
        log_warning "High CPU usage detected: ${cpu_usage}%"
    fi
fi

# CPU details
echo "CPU Details:"
echo "  Cores/Threads: $(nproc) / $(grep -c ^processor /proc/cpuinfo)"
echo "  CPU Model: $(grep 'model name' /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)"

# Show CPU usage per core if available
if command -v mpstat &> /dev/null; then
    echo "  Per-core usage:"
    mpstat -P ALL 1 1 | grep -E "Average.*[0-9]" | awk '{printf "    Core %s: %.1f%%\n", $2, 100-$12}'
fi
echo ""

# 4. DISK USAGE with intelligent warnings
echo "💿 === DISK USAGE ==="
df_output=$(df -h | grep -E '^/dev|^Filesystem')
echo "$df_output"

# Check critical disk usage with context
while read -r line; do
    if [[ $line == /dev* ]]; then
        usage=$(echo "$line" | awk '{print $5}' | sed 's/%//')
        mount=$(echo "$line" | awk '{print $6}')
        size=$(echo "$line" | awk '{print $2}')
        
        if [ "$usage" -gt "$DISK_CRITICAL_THRESHOLD" ]; then
            log_error "Critical disk usage on $mount: ${usage}% (${size} total)"
            echo "   🚨 Immediate action required! Run cleanup script."
        elif [ "$usage" -gt "$DISK_WARNING_THRESHOLD" ]; then
            log_warning "High disk usage on $mount: ${usage}% (${size} total)"
            if [ "$RETENTION_DAYS" -gt 7 ]; then
                echo "   💡 Consider reducing retention from ${RETENTION_DAYS} to 7-14 days"
            fi
        fi
    fi
done <<< "$df_output"

# Elasticsearch data size
if [ -d "data/elasticsearch" ]; then
    es_size=$(du -sh data/elasticsearch 2>/dev/null | awk '{print $1}' || echo "N/A")
    echo "Elasticsearch data: $es_size"
fi

# Docker storage usage
if [ -d "/var/lib/docker" ]; then
    docker_size=$(du -sh /var/lib/docker 2>/dev/null | awk '{print $1}' || echo "N/A")
    echo "Docker storage: $docker_size"
fi
echo ""

# 5. I/O STATISTICS with context
echo "📊 === I/O STATISTICS ==="
if command -v iostat &> /dev/null; then
    echo "Current I/O stats (${DISK_TYPE} storage):"
    iostat -x 1 1 | tail -n +4 | head -10
    
    # I/O wait analysis
    io_wait=$(iostat -c 1 1 | tail -1 | awk '{print $4}')
    if (( $(echo "$io_wait > 10" | bc -l) )); then
        if [ "$DISK_TYPE" = "hdd" ]; then
            log_warning "High I/O wait for HDD storage: ${io_wait}%"
            echo "   💡 Consider upgrading to SSD for better performance"
        else
            log_warning "High I/O wait detected: ${io_wait}%"
        fi
    fi
else
    echo "iostat not available - showing basic disk I/O:"
    if [ -f /proc/diskstats ]; then
        awk '$3 ~ /^(sd|nvme|hd)/ {print $3 ": reads=" $4 " writes=" $8}' /proc/diskstats | head -5
    fi
fi
echo ""

# 6. NETWORK STATISTICS
echo "🌐 === NETWORK STATISTICS ==="
echo "Active interfaces:"
ip -s link show | grep -E '^[0-9]+:|RX:|TX:' | paste - - - | awk '
    /^[0-9]+:/ {
        interface = $2
        gsub(/:/, "", interface)
    }
    /RX:/ {
        rx_bytes = $3
        rx_packets = $2
        getline
        tx_bytes = $3
        tx_packets = $2
        printf "  %-12s RX: %10.2f MB (%s packets)  TX: %10.2f MB (%s packets)\n", 
               interface, rx_bytes/1024/1024, rx_packets, tx_bytes/1024/1024, tx_packets
    }
'

# Network errors
echo ""
echo "Network errors (if any):"
netstat -i | awk 'NR>2 && ($4>0 || $8>0) {printf "  %s: RX errors=%s, TX errors=%s\n", $1, $4, $8}' || echo "  No network errors detected"
echo ""

# 7. DOCKER STATUS with resource usage
echo "🐳 === DOCKER CONTAINER STATUS ==="
if command -v docker &> /dev/null && docker info &>/dev/null; then
    echo "Container overview:"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null
    
    echo ""
    echo "Resource usage by container:"
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}" 2>/dev/null
    
    # Health check status
    echo ""
    echo "Health status:"
    for container in netflow-elasticsearch netflow-kibana netflow-filebeat; do
        if docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
            health=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "no-healthcheck")
            status=$(docker inspect --format='{{.State.Status}}' "$container" 2>/dev/null || echo "unknown")
            
            if [ "$health" = "healthy" ] || [ "$status" = "running" ]; then
                log_success "$container: $status ($health)"
            else
                log_warning "$container: $status ($health)"
                # Show recent logs for problematic containers
                echo "    Recent logs:"
                docker logs --tail=3 "$container" 2>&1 | sed 's/^/      /'
            fi
        else
            log_error "$container: not found"
        fi
    done
else
    log_error "Docker not accessible"
fi
echo ""

# 8. NETFLOW TRAFFIC ANALYSIS
echo "📡 === NETFLOW TRAFFIC ANALYSIS ==="
netflow_listening=$(netstat -ulnp 2>/dev/null | grep ":$NETFLOW_PORT" || echo "")
if [ -n "$netflow_listening" ]; then
    log_success "NetFlow listener active on port $NETFLOW_PORT"
    echo "$netflow_listening"
    
    # Traffic analysis
    echo ""
    echo "NetFlow traffic analysis:"
    
    # Check for recent traffic using tcpdump if available
    if command -v tcpdump &> /dev/null; then
        echo "  Testing for NetFlow packets (5 second sample):"
        timeout 5 tcpdump -c 5 -i any "udp port $NETFLOW_PORT" 2>/dev/null | wc -l | awk '{print "    Packets received: " $1}'
    fi
    
    # Check UDP buffer usage
    if [ -f /proc/net/udp ]; then
        udp_buffer=$(awk -v port=$(printf "%04X" $NETFLOW_PORT) '$2 ~ port {print $4}' /proc/net/udp | head -1)
        if [ -n "$udp_buffer" ]; then
            echo "    UDP buffer queue: $udp_buffer"
        fi
    fi
else
    log_warning "NetFlow listener not detected on port $NETFLOW_PORT"
    echo "    Check if filebeat container is running"
fi
echo ""

# 9. ELASTICSEARCH STATUS with detailed analysis
echo "🔍 === ELASTICSEARCH STATUS ==="
es_health=$(curl -s --connect-timeout 10 "localhost:$ELASTICSEARCH_PORT/_cluster/health?pretty" 2>/dev/null)
if [ $? -eq 0 ] && [ -n "$es_health" ]; then
    log_success "Elasticsearch is accessible"
    
    # Parse cluster info
    cluster_status=$(echo "$es_health" | grep '"status"' | awk -F'"' '{print $4}')
    number_of_nodes=$(echo "$es_health" | grep '"number_of_nodes"' | awk '{print $3}' | tr -d ',')
    active_shards=$(echo "$es_health" | grep '"active_shards"' | awk '{print $3}' | tr -d ',')
    
    echo "Cluster Status: $cluster_status"
    echo "Nodes: $number_of_nodes"
    echo "Active Shards: $active_shards"
    
    # Status-specific advice
    case "$cluster_status" in
        "red")
            log_error "Elasticsearch cluster is RED - data loss possible!"
            echo "   🚨 Check logs immediately: docker-compose logs elasticsearch"
            ;;
        "yellow")
            log_warning "Elasticsearch cluster is YELLOW - check replica settings"
            echo "   💡 This is normal for single-node setups"
            ;;
        "green")
            log_success "Elasticsearch cluster is GREEN - all good!"
            ;;
    esac
    
    # Heap usage analysis
    echo ""
    echo "=== ELASTICSEARCH HEAP ANALYSIS ==="
    heap_info=$(curl -s --connect-timeout 10 "localhost:$ELASTICSEARCH_PORT/_nodes/stats/jvm?pretty" 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$heap_info" ]; then
        heap_used_percent=$(echo "$heap_info" | grep '"heap_used_percent"' | head -1 | awk '{print $3}' | tr -d ',')
        heap_max_bytes=$(echo "$heap_info" | grep '"heap_max_in_bytes"' | head -1 | awk '{print $3}' | tr -d ',')
        
        if [ -n "$heap_max_bytes" ] && [ "$heap_max_bytes" -gt 0 ]; then
            heap_max_gb=$(echo "$heap_max_bytes" | awk '{printf "%.1f", $1/1024/1024/1024}')
            
            echo "Heap Usage: ${heap_used_percent}% of ${heap_max_gb}GB"
            
            # Context-aware heap warnings
            if [ "$heap_used_percent" -gt 90 ]; then
                log_error "Critical heap usage: ${heap_used_percent}%"
                echo "   🚨 Risk of OutOfMemoryError - restart recommended"
            elif [ "$heap_used_percent" -gt 75 ]; then
                log_warning "High heap usage: ${heap_used_percent}%"
                if [ "$TOTAL_RAM_GB" != "Unknown" ] && [ "$TOTAL_RAM_GB" -le 4 ]; then
                    echo "   💡 Consider reducing retention period for low-RAM system"
                fi
            else
                log_success "Heap usage is healthy: ${heap_used_percent}%"
            fi
            
            # GC analysis
            gc_collection_count=$(echo "$heap_info" | grep '"collection_count"' | head -1 | awk '{print $3}' | tr -d ',')
            gc_collection_time=$(echo "$heap_info" | grep '"collection_time_in_millis"' | head -1 | awk '{print $3}' | tr -d ',')
            if [ -n "$gc_collection_count" ] && [ "$gc_collection_count" -gt 0 ]; then
                avg_gc_time=$(echo "$gc_collection_time $gc_collection_count" | awk '{printf "%.1f", $1/$2}')
                echo "GC Stats: $gc_collection_count collections, avg ${avg_gc_time}ms"
            fi
        fi
    fi
    
    # Index information with smart analysis
    echo ""
    echo "=== ELASTICSEARCH INDICES ==="
    indices_info=$(curl -s --connect-timeout 10 "localhost:$ELASTICSEARCH_PORT/_cat/indices/netflow-*?h=index,docs.count,store.size,pri.store.size&s=index" 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$indices_info" ]; then
        echo "NetFlow indices (recent first):"
        echo "$indices_info" | tail -10
        
        # Calculate totals
        total_docs=$(echo "$indices_info" | awk '{sum += $2} END {print sum}')
        total_size=$(echo "$indices_info" | awk '{
            for(i=1; i<=NF; i++) {
                if($i ~ /[0-9]+\.?[0-9]*[kmgt]b?$/) {
                    val = $i
                    gsub(/[^0-9.]/, "", val)
                    unit = tolower($i)
                    if(unit ~ /k/) mult = 1024
                    else if(unit ~ /m/) mult = 1024*1024  
                    else if(unit ~ /g/) mult = 1024*1024*1024
                    else if(unit ~ /t/) mult = 1024*1024*1024*1024
                    else mult = 1
                    sum += val * mult
                }
            }
            END {
                if(sum > 1024*1024*1024) printf "%.1fGB", sum/(1024*1024*1024)
                else if(sum > 1024*1024) printf "%.1fMB", sum/(1024*1024)
                else printf "%.1fKB", sum/1024
            }
        }')
        
        echo ""
        echo "Summary: ${total_docs} documents, ${total_size} total size"
        
        # Smart index recommendations
        index_count=$(echo "$indices_info" | wc -l)
        if [ "$index_count" -gt "$RETENTION_DAYS" ]; then
            log_warning "More indices than retention period: $index_count indices vs ${RETENTION_DAYS} days"
            echo "   💡 Run cleanup script to remove old indices"
        fi
    else
        echo "No NetFlow indices found or unable to retrieve information"
        echo "💡 Check if NetFlow data is being received"
    fi
else
    log_error "Elasticsearch not accessible at localhost:$ELASTICSEARCH_PORT"
    echo "   🔧 Check if elasticsearch container is running"
fi
echo ""

# 10. KIBANA STATUS
echo "📊 === KIBANA STATUS ==="
kibana_status=$(curl -s --connect-timeout 10 "localhost:$KIBANA_PORT/api/status" 2>/dev/null)
if [ $? -eq 0 ] && [ -n "$kibana_status" ]; then
    if echo "$kibana_status" | grep -q '"level":"available"'; then
        log_success "Kibana is accessible and available"
        echo "   🌐 Access at: http://localhost:$KIBANA_PORT"
    else
        log_warning "Kibana accessible but may have issues"
        echo "   Status response: $(echo "$kibana_status" | head -c 100)..."
    fi
else
    log_error "Kibana not accessible at localhost:$KIBANA_PORT"
    echo "   🔧 Check if kibana container is running"
fi
echo ""

# 11. INTELLIGENT SYSTEM ALERTS
echo "🚨 === INTELLIGENT SYSTEM ALERTS ==="
alert_count=0

# Memory alerts
if (( $(echo "$memory_used > $MEMORY_WARNING_THRESHOLD" | bc -l) )); then
    log_warning "Memory usage: ${memory_used}% (threshold: ${MEMORY_WARNING_THRESHOLD}%)"
    ((alert_count++))
fi

# CPU alerts
if (( $(echo "$cpu_usage > $CPU_WARNING_THRESHOLD" | bc -l) )); then
    log_warning "CPU usage: ${cpu_usage}% (threshold: ${CPU_WARNING_THRESHOLD}%)"
    ((alert_count++))
fi

# Disk alerts
root_usage=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
if [ "$root_usage" -gt "$DISK_CRITICAL_THRESHOLD" ]; then
    log_error "Critical root disk usage: ${root_usage}%"
    ((alert_count++))
elif [ "$root_usage" -gt "$DISK_WARNING_THRESHOLD" ]; then
    log_warning "High root disk usage: ${root_usage}%"
    ((alert_count++))
fi

# Service alerts
if ! docker ps --format '{{.Names}}' | grep -q netflow-elasticsearch; then
    log_error "Elasticsearch container not running"
    ((alert_count++))
fi

if ! docker ps --format '{{.Names}}' | grep -q netflow-kibana; then
    log_error "Kibana container not running"
    ((alert_count++))
fi

if ! docker ps --format '{{.Names}}' | grep -q netflow-filebeat; then
    log_error "Filebeat container not running"
    ((alert_count++))
fi

if [ $alert_count -eq 0 ]; then
    log_success "No system alerts - all metrics within acceptable ranges"
else
    log_warning "Total system alerts: $alert_count"
fi
echo ""

# 12. SMART RECOMMENDATIONS
echo "💡 === SMART RECOMMENDATIONS ==="

# System-specific recommendations
if [ "$TOTAL_RAM_GB" != "Unknown" ]; then
    if [ "$TOTAL_RAM_GB" -le 2 ]; then
        echo "🔧 Low-RAM System Optimizations:"
        echo "   • Consider upgrading to 4GB+ RAM for better performance"
        echo "   • Reduce retention to 7-14 days: edit RETENTION_DAYS in .env"
        echo "   • Monitor heap usage closely (current: ${ES_HEAP_SIZE})"
    elif [ "$TOTAL_RAM_GB" -ge 16 ]; then
        echo "🚀 High-RAM System Optimizations:"
        echo "   • Your system can handle longer retention periods"
        echo "   • Consider increasing bulk_size for better throughput"
        echo "   • Enable more advanced Elasticsearch features if needed"
    fi
fi

# Disk-specific recommendations
if [ "$DISK_TYPE" = "hdd" ]; then
    echo "💿 HDD Storage Optimizations:"
    echo "   • Consider upgrading to SSD for 10x better I/O performance"
    echo "   • Increase refresh intervals to reduce disk writes"
    echo "   • Monitor I/O wait times (current recommendation: <10%)"
elif [ "$DISK_TYPE" = "ssd" ] || [ "$DISK_TYPE" = "nvme" ]; then
    echo "⚡ SSD/NVMe Optimizations Applied:"
    echo "   • Fast storage detected - using aggressive settings"
    echo "   • Reduced refresh intervals for real-time performance"
fi

# Service-specific recommendations
if (( $(echo "$memory_used > 85" | bc -l) )); then
    echo "🧠 Memory Optimization:"
    echo "   • Run cleanup script: ./scripts/cleanup-data.sh"
    echo "   • Reduce retention period if disk space allows"
    echo "   • Consider restarting services if memory leak suspected"
fi

if [ "$root_usage" -gt 85 ]; then
    echo "💾 Disk Space Optimization:"
    echo "   • Run immediate cleanup: ./scripts/cleanup-data.sh"
    echo "   • Clean Docker: docker system prune -a"
    echo "   • Consider reducing retention from ${RETENTION_DAYS} days"
fi
echo ""

# 13. USEFUL COMMANDS
echo "🔧 === USEFUL COMMANDS ==="
echo "Service Management:"
echo "   • View all logs: docker-compose logs -f"
echo "   • Restart services: docker-compose restart"
echo "   • Stop services: docker-compose down"
echo "   • Update configs: docker-compose up -d"
echo ""
echo "Monitoring & Maintenance:"
echo "   • Manual cleanup: ./scripts/cleanup-data.sh"
echo "   • Check ES indices: curl localhost:$ELASTICSEARCH_PORT/_cat/indices?v"
echo "   • Test NetFlow: sudo tcpdump -i any udp port $NETFLOW_PORT"
echo "   • System optimization: sudo ./scripts/debian_smart_optimization.sh"
echo ""
echo "Troubleshooting:"
echo "   • ES logs: docker-compose logs elasticsearch"
echo "   • Kibana logs: docker-compose logs kibana"
echo "   • Filebeat logs: docker-compose logs filebeat"
echo "   • Container stats: docker stats"
echo ""

# Footer
echo "========================================================"
echo "Monitoring completed at $(date '+%H:%M:%S')"
echo "Next scheduled run: $(date -d '+5 minutes' '+%H:%M:%S') (if automated)"
echo "========================================================"
