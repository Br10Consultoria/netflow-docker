#!/bin/bash

# Debian 12 Smart Optimization Script for NetFlow ELK Stack
# Analyzes system resources and applies optimizations accordingly

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to detect system resources
detect_system_resources() {
    log "🔍 Detecting system resources..."
    
    # RAM detection
    TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    TOTAL_RAM_GB=$((TOTAL_RAM_KB / 1024 / 1024))
    
    # CPU detection
    CPU_CORES=$(nproc)
    
    # Disk detection
    ROOT_DISK=$(df / | tail -1 | awk '{print $1}')
    DISK_TYPE="unknown"
    
    # Check if it's SSD or HDD
    if [[ $ROOT_DISK == /dev/nvme* ]]; then
        DISK_TYPE="nvme"
    elif [[ $ROOT_DISK == /dev/sd* ]]; then
        DISK_NUM=$(echo $ROOT_DISK | sed 's/[^0-9]*//g' | cut -c1)
        DISK_DEV=$(echo $ROOT_DISK | sed 's/[0-9]*//g')
        if [ -f "/sys/block/$(basename $DISK_DEV)/queue/rotational" ]; then
            ROTATIONAL=$(cat /sys/block/$(basename $DISK_DEV)/queue/rotational)
            if [ "$ROTATIONAL" = "0" ]; then
                DISK_TYPE="ssd"
            else
                DISK_TYPE="hdd"
            fi
        fi
    fi
    
    # Available disk space
    AVAILABLE_SPACE_GB=$(df / | tail -1 | awk '{print int($4/1024/1024)}')
    
    # Network interfaces
    NETWORK_INTERFACES=$(ip -o link show | awk -F': ' '{print $2}' | grep -v lo | head -5)
    
    # Display detected resources
    log_success "System Resources Detected:"
    echo "  💾 RAM: ${TOTAL_RAM_GB}GB"
    echo "  🖥️  CPU Cores: ${CPU_CORES}"
    echo "  💿 Disk Type: ${DISK_TYPE}"
    echo "  📁 Available Space: ${AVAILABLE_SPACE_GB}GB"
    echo "  🌐 Network Interfaces: $(echo $NETWORK_INTERFACES | tr '\n' ' ')"
    echo ""
}

# Function to calculate optimized values based on system resources
calculate_optimizations() {
    log "⚡ Calculating optimizations based on system resources..."
    
    # Memory-based optimizations
    if [ $TOTAL_RAM_GB -lt 4 ]; then
        VM_MAX_MAP_COUNT=65536
        ES_HEAP_SIZE="1g"
        NETWORK_BUFFER_SIZE=67108864  # 64MB
        UDP_MEM="51200 436900 8388608"
        NETDEV_BACKLOG=1000
        log_warning "Low RAM detected (${TOTAL_RAM_GB}GB) - applying conservative settings"
    elif [ $TOTAL_RAM_GB -lt 8 ]; then
        VM_MAX_MAP_COUNT=131072
        ES_HEAP_SIZE="2g"
        NETWORK_BUFFER_SIZE=134217728  # 128MB
        UDP_MEM="102400 873800 16777216"
        NETDEV_BACKLOG=5000
    elif [ $TOTAL_RAM_GB -lt 16 ]; then
        VM_MAX_MAP_COUNT=262144
        ES_HEAP_SIZE="4g"
        NETWORK_BUFFER_SIZE=268435456  # 256MB
        UDP_MEM="204800 1747600 33554432"
        NETDEV_BACKLOG=10000
    else
        VM_MAX_MAP_COUNT=262144
        ES_HEAP_SIZE="8g"
        NETWORK_BUFFER_SIZE=536870912  # 512MB
        UDP_MEM="409600 3495200 67108864"
        NETDEV_BACKLOG=30000
        log_success "High RAM detected (${TOTAL_RAM_GB}GB) - applying aggressive settings"
    fi
    
    # CPU-based optimizations
    if [ $CPU_CORES -lt 2 ]; then
        WORKER_PROCESSES=1
        ES_PROCESSORS=1
        log_warning "Low CPU cores (${CPU_CORES}) - limiting worker processes"
    elif [ $CPU_CORES -lt 4 ]; then
        WORKER_PROCESSES=2
        ES_PROCESSORS=2
    else
        WORKER_PROCESSES=$((CPU_CORES - 1))
        ES_PROCESSORS=$CPU_CORES
    fi
    
    # File descriptor limits based on expected load
    if [ $TOTAL_RAM_GB -lt 8 ]; then
        FILE_MAX=500000
        NOFILE_LIMIT=100000
    else
        FILE_MAX=1000000
        NOFILE_LIMIT=1000000
    fi
    
    # Process limits
    PID_MAX=$((CPU_CORES * 32768))
    THREADS_MAX=$((CPU_CORES * 65536))
    
    log_success "Optimizations calculated:"
    echo "  📊 VM Max Map Count: ${VM_MAX_MAP_COUNT}"
    echo "  🧠 Elasticsearch Heap: ${ES_HEAP_SIZE}"
    echo "  🌐 Network Buffer Size: $((NETWORK_BUFFER_SIZE / 1024 / 1024))MB"
    echo "  👥 Worker Processes: ${WORKER_PROCESSES}"
    echo "  📁 File Descriptor Limit: ${NOFILE_LIMIT}"
    echo ""
}

# Function to check disk space requirements
check_disk_space() {
    log "💿 Checking disk space requirements..."
    
    REQUIRED_SPACE=10  # Minimum 10GB required
    
    if [ $AVAILABLE_SPACE_GB -lt $REQUIRED_SPACE ]; then
        log_error "Insufficient disk space! Available: ${AVAILABLE_SPACE_GB}GB, Required: ${REQUIRED_SPACE}GB"
        exit 1
    else
        log_success "Sufficient disk space available: ${AVAILABLE_SPACE_GB}GB"
    fi
}

# Main optimization function
apply_optimizations() {
    log "🚀 Applying optimizations to Debian 12 for NetFlow ELK Stack..."
    
    # Backup original configurations
    BACKUP_DIR="/etc/sysctl.d/backup-$(date +%Y%m%d-%H%M%S)"
    sudo mkdir -p "$BACKUP_DIR"
    log "📁 Backup directory created: $BACKUP_DIR"
    
    # Backup existing files
    for file in /etc/sysctl.d/99-elasticsearch.conf /etc/sysctl.d/99-network-buffers.conf; do
        if [ -f "$file" ]; then
            sudo cp "$file" "$BACKUP_DIR/"
        fi
    done
    
    # Elasticsearch optimizations
    log "⚡ Applying Elasticsearch optimizations..."
    sudo tee /etc/sysctl.d/99-elasticsearch.conf > /dev/null <<EOF
# Elasticsearch optimizations - Auto-generated based on system resources
# System: ${TOTAL_RAM_GB}GB RAM, ${CPU_CORES} CPU cores, ${DISK_TYPE} storage
vm.max_map_count=${VM_MAX_MAP_COUNT}
vm.swappiness=1
vm.dirty_ratio=15
vm.dirty_background_ratio=5

# Network optimizations for NetFlow
net.core.rmem_max=${NETWORK_BUFFER_SIZE}
net.core.rmem_default=65536
net.core.wmem_max=${NETWORK_BUFFER_SIZE}
net.core.wmem_default=65536
net.core.netdev_max_backlog=${NETDEV_BACKLOG}
net.ipv4.udp_mem=${UDP_MEM}
net.ipv4.udp_rmem_min=8192
net.ipv4.udp_wmem_min=8192

# File system optimizations
fs.file-max=${FILE_MAX}
fs.nr_open=${FILE_MAX}

# Process limits
kernel.pid_max=${PID_MAX}
kernel.threads-max=${THREADS_MAX}
EOF

    # Network buffer optimizations
    log "🌐 Optimizing network buffers..."
    sudo tee /etc/sysctl.d/99-network-buffers.conf > /dev/null <<EOF
# Network buffer optimizations for high-volume NetFlow
# Auto-generated based on ${TOTAL_RAM_GB}GB RAM system
net.core.rmem_max=${NETWORK_BUFFER_SIZE}
net.core.wmem_max=${NETWORK_BUFFER_SIZE}
net.core.rmem_default=262144
net.core.wmem_default=262144
net.core.optmem_max=40960
net.core.netdev_max_backlog=${NETDEV_BACKLOG}
net.core.netdev_budget=600

# UDP optimizations
net.ipv4.udp_rmem_min=131072
net.ipv4.udp_wmem_min=131072
net.ipv4.udp_mem=${UDP_MEM}

# TCP optimizations
net.ipv4.tcp_rmem=4096 87380 ${NETWORK_BUFFER_SIZE}
net.ipv4.tcp_wmem=4096 65536 ${NETWORK_BUFFER_SIZE}
net.ipv4.tcp_congestion_control=bbr
EOF

    # Security and limits
    log "🔒 Setting up security limits..."
    sudo tee /etc/security/limits.d/99-elasticsearch.conf > /dev/null <<EOF
# Limits for elasticsearch user - Auto-generated for ${TOTAL_RAM_GB}GB system
elasticsearch soft memlock unlimited
elasticsearch hard memlock unlimited
elasticsearch soft nofile ${NOFILE_LIMIT}
elasticsearch hard nofile ${NOFILE_LIMIT}
elasticsearch soft nproc 4096
elasticsearch hard nproc 4096

# Limits for root (Docker)
root soft memlock unlimited
root hard memlock unlimited
root soft nofile ${NOFILE_LIMIT}
root hard nofile ${NOFILE_LIMIT}
EOF

    # Systemd optimizations
    log "⚙️ Optimizing systemd..."
    sudo mkdir -p /etc/systemd/system.conf.d
    sudo tee /etc/systemd/system.conf.d/limits.conf > /dev/null <<EOF
[Manager]
DefaultLimitNOFILE=${NOFILE_LIMIT}
DefaultLimitMEMLOCK=infinity
EOF

    # I/O scheduler optimization based on detected disk type
    log "💾 Optimizing I/O scheduler for ${DISK_TYPE} storage..."
    if [ "$DISK_TYPE" = "nvme" ] || [ "$DISK_TYPE" = "ssd" ]; then
        SCHEDULER="none"
        log_success "Detected SSD/NVMe - using 'none' scheduler"
    else
        SCHEDULER="mq-deadline"
        log "Detected HDD or unknown type - using 'mq-deadline' scheduler"
    fi
    
    sudo tee /etc/udev/rules.d/60-io-scheduler.rules > /dev/null <<EOF
# Set I/O scheduler based on detected disk type: ${DISK_TYPE}
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="none"
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="mq-deadline"
ACTION=="add|change", KERNEL=="nvme*", ATTR{queue/scheduler}="none"
EOF

    # Docker optimizations
    log "🐳 Optimizing Docker..."
    sudo mkdir -p /etc/docker
    sudo tee /etc/docker/daemon.json > /dev/null <<EOF
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "100m",
        "max-file": "3"
    },
    "storage-driver": "overlay2",
    "default-ulimits": {
        "nofile": {
            "Name": "nofile",
            "Hard": ${NOFILE_LIMIT},
            "Soft": ${NOFILE_LIMIT}
        },
        "memlock": {
            "Name": "memlock",
            "Hard": -1,
            "Soft": -1
        }
    }
}
EOF

    # Apply sysctl settings
    log "🔄 Applying sysctl settings..."
    sudo sysctl -p /etc/sysctl.d/99-elasticsearch.conf
    sudo sysctl -p /etc/sysctl.d/99-network-buffers.conf
    
    # Install performance monitoring tools
    log "📊 Installing monitoring tools..."
    sudo apt update -qq
    sudo apt install -y htop iotop nethogs tcpdump sysstat dstat
    
    # Create smart monitoring script
    sudo tee /usr/local/bin/netflow-monitor.sh > /dev/null <<EOF
#!/bin/bash
echo "=== NetFlow ELK Stack Monitoring - $(hostname) ==="
echo "System: ${TOTAL_RAM_GB}GB RAM, ${CPU_CORES} cores, ${DISK_TYPE} storage"
echo "Date: \$(date)"
echo ""
echo "=== Memory Usage ==="
free -h
echo ""
echo "=== CPU Usage ==="
top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print "CPU Usage: " 100 - \$1 "%"}'
echo ""
echo "=== Disk Usage ==="
df -h | grep -E '^/dev|^Filesystem'
echo ""
echo "=== I/O Stats ==="
iostat -x 1 1 | tail -n +4
echo ""
echo "=== Docker Container Status ==="
if command -v docker &> /dev/null; then
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "Docker not running or no containers"
else
    echo "Docker not installed"
fi
echo ""
echo "=== NetFlow UDP Traffic ==="
netstat -nu | grep :2055 || echo "No NetFlow traffic detected on port 2055"
echo ""
echo "=== Elasticsearch Cluster Health ==="
curl -s localhost:9200/_cluster/health?pretty 2>/dev/null || echo "Elasticsearch not accessible"
echo ""
echo "=== System Load ==="
uptime
EOF

    sudo chmod +x /usr/local/bin/netflow-monitor.sh
    
    # Create optimization summary
    sudo tee /usr/local/bin/optimization-summary.sh > /dev/null <<EOF
#!/bin/bash
echo "=== Debian Optimization Summary ==="
echo "Applied on: \$(date)"
echo "System Resources:"
echo "  RAM: ${TOTAL_RAM_GB}GB"
echo "  CPU Cores: ${CPU_CORES}"
echo "  Disk Type: ${DISK_TYPE}"
echo ""
echo "Applied Optimizations:"
echo "  VM Max Map Count: ${VM_MAX_MAP_COUNT}"
echo "  Network Buffer Size: $((NETWORK_BUFFER_SIZE / 1024 / 1024))MB"
echo "  File Descriptor Limit: ${NOFILE_LIMIT}"
echo "  UDP Memory: ${UDP_MEM}"
echo "  I/O Scheduler: ${SCHEDULER}"
echo ""
echo "Backup Location: ${BACKUP_DIR}"
EOF

    sudo chmod +x /usr/local/bin/optimization-summary.sh
}

# Function to validate applied settings
validate_settings() {
    log "✅ Validating applied settings..."
    
    # Check sysctl values
    CURRENT_VM_MAP=$(sysctl -n vm.max_map_count)
    CURRENT_FILE_MAX=$(sysctl -n fs.file-max)
    
    if [ "$CURRENT_VM_MAP" = "$VM_MAX_MAP_COUNT" ]; then
        log_success "VM max map count: $CURRENT_VM_MAP ✓"
    else
        log_warning "VM max map count mismatch: expected $VM_MAX_MAP_COUNT, got $CURRENT_VM_MAP"
    fi
    
    if [ "$CURRENT_FILE_MAX" = "$FILE_MAX" ]; then
        log_success "File max: $CURRENT_FILE_MAX ✓"
    else
        log_warning "File max mismatch: expected $FILE_MAX, got $CURRENT_FILE_MAX"
    fi
}

# Main execution
main() {
    echo ""
    log "🚀 Starting Debian 12 Smart Optimization for NetFlow ELK Stack"
    echo "=================================================="
    
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
    
    detect_system_resources
    calculate_optimizations
    check_disk_space
    
    # Ask for confirmation
    echo ""
    read -p "Apply these optimizations? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Optimization cancelled by user"
        exit 0
    fi
    
    apply_optimizations
    validate_settings
    
    log_success "✅ Debian optimization complete!"
    echo ""
    echo "📋 Summary:"
    echo "  • Optimizations applied based on ${TOTAL_RAM_GB}GB RAM and ${CPU_CORES} CPU cores"
    echo "  • I/O scheduler optimized for ${DISK_TYPE} storage"
    echo "  • Network buffers sized at $((NETWORK_BUFFER_SIZE / 1024 / 1024))MB"
    echo "  • File descriptor limit set to ${NOFILE_LIMIT}"
    echo ""
    echo "🔄 Please reboot the system to apply all changes:"
    echo "sudo reboot"
    echo ""
    echo "📊 After reboot, monitor your system with:"
    echo "/usr/local/bin/netflow-monitor.sh"
    echo ""
    echo "📋 View optimization summary anytime with:"
    echo "/usr/local/bin/optimization-summary.sh"
}

# Execute main function
main "$@"