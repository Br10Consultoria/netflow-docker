#!/bin/bash

# Auto-Configuration Script for NetFlow ELK Stack
# Detects system resources and configures optimal settings

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[AUTO-CONFIG]${NC} $1"
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
    TOTAL_RAM_MB=$((TOTAL_RAM_KB / 1024))
    
    # CPU detection
    CPU_CORES=$(nproc)
    CPU_THREADS=$(grep -c ^processor /proc/cpuinfo)
    
    # Disk detection
    ROOT_DISK=$(df / | tail -1 | awk '{print $1}')
    DISK_TYPE="unknown"
    
    # Check if it's SSD or HDD
    if [[ $ROOT_DISK == /dev/nvme* ]]; then
        DISK_TYPE="nvme"
    elif [[ $ROOT_DISK == /dev/sd* ]]; then
        DISK_DEV=$(echo $ROOT_DISK | sed 's/[0-9]*//g')
        if [ -f "/sys/block/$(basename $DISK_DEV)/queue/rotational" ]; then
            ROTATIONAL=$(cat /sys/block/$(basename $DISK_DEV)/queue/rotational 2>/dev/null || echo "1")
            if [ "$ROTATIONAL" = "0" ]; then
                DISK_TYPE="ssd"
            else
                DISK_TYPE="hdd"
            fi
        fi
    fi
    
    # Available disk space
    AVAILABLE_SPACE_GB=$(df / | tail -1 | awk '{print int($4/1024/1024)}')
    
    # Get server IP (primary interface)
    SERVER_IP=$(ip route get 8.8.8.8 | grep -oP 'src \K\S+' 2>/dev/null || echo "127.0.0.1")
    
    # Detect if running in container
    IS_CONTAINER=false
    if [ -f /.dockerenv ] || grep -q docker /proc/1/cgroup 2>/dev/null; then
        IS_CONTAINER=true
    fi
    
    log_success "System Resources Detected:"
    echo "  💾 RAM: ${TOTAL_RAM_GB}GB (${TOTAL_RAM_MB}MB)"
    echo "  🖥️  CPU: ${CPU_CORES} cores / ${CPU_THREADS} threads"
    echo "  💿 Disk: ${DISK_TYPE} storage"
    echo "  📁 Available Space: ${AVAILABLE_SPACE_GB}GB"
    echo "  🌐 Server IP: ${SERVER_IP}"
    echo "  🐳 Container Environment: ${IS_CONTAINER}"
    echo ""
}

# Function to calculate optimal configurations
calculate_configurations() {
    log "⚡ Calculating optimal configurations..."
    
    # Elasticsearch Heap Size Calculation
    # Rule: Never more than 50% of RAM, never more than 31GB
    if [ $TOTAL_RAM_GB -le 1 ]; then
        ES_HEAP_SIZE="400m"
        ES_MEMORY_LIMIT="600m"
        ES_MEMORY_RESERVATION="400m"
        log_warning "Very low RAM (${TOTAL_RAM_GB}GB) - using minimal heap"
    elif [ $TOTAL_RAM_GB -le 2 ]; then
        ES_HEAP_SIZE="800m"
        ES_MEMORY_LIMIT="1200m"
        ES_MEMORY_RESERVATION="800m"
    elif [ $TOTAL_RAM_GB -le 4 ]; then
        ES_HEAP_SIZE="1536m"
        ES_MEMORY_LIMIT="2g"
        ES_MEMORY_RESERVATION="1536m"
    elif [ $TOTAL_RAM_GB -le 8 ]; then
        ES_HEAP_SIZE="3g"
        ES_MEMORY_LIMIT="4g"
        ES_MEMORY_RESERVATION="3g"
    elif [ $TOTAL_RAM_GB -le 16 ]; then
        ES_HEAP_SIZE="6g"
        ES_MEMORY_LIMIT="8g"
        ES_MEMORY_RESERVATION="6g"
    elif [ $TOTAL_RAM_GB -le 32 ]; then
        ES_HEAP_SIZE="12g"
        ES_MEMORY_LIMIT="16g"
        ES_MEMORY_RESERVATION="12g"
    elif [ $TOTAL_RAM_GB -le 64 ]; then
        ES_HEAP_SIZE="26g"
        ES_MEMORY_LIMIT="32g"
        ES_MEMORY_RESERVATION="26g"
    else
        # Never exceed 31GB for heap (compressed OOPs)
        ES_HEAP_SIZE="31g"
        ES_MEMORY_LIMIT="40g"
        ES_MEMORY_RESERVATION="31g"
        log_success "High RAM detected (${TOTAL_RAM_GB}GB) - using maximum safe heap (31GB)"
    fi
    
    # Kibana Memory Configuration
    if [ $TOTAL_RAM_GB -le 2 ]; then
        KIBANA_MEMORY_LIMIT="300m"
        KIBANA_MEMORY_RESERVATION="200m"
        KIBANA_NODE_OPTIONS="--max-old-space-size=200"
    elif [ $TOTAL_RAM_GB -le 4 ]; then
        KIBANA_MEMORY_LIMIT="512m"
        KIBANA_MEMORY_RESERVATION="300m"
        KIBANA_NODE_OPTIONS="--max-old-space-size=300"
    elif [ $TOTAL_RAM_GB -le 8 ]; then
        KIBANA_MEMORY_LIMIT="1g"
        KIBANA_MEMORY_RESERVATION="512m"
        KIBANA_NODE_OPTIONS="--max-old-space-size=512"
    else
        KIBANA_MEMORY_LIMIT="2g"
        KIBANA_MEMORY_RESERVATION="1g"
        KIBANA_NODE_OPTIONS="--max-old-space-size=1024"
    fi
    
    # Filebeat Memory Configuration
    if [ $TOTAL_RAM_GB -le 2 ]; then
        FILEBEAT_MEMORY_LIMIT="150m"
        FILEBEAT_MEMORY_RESERVATION="100m"
    elif [ $TOTAL_RAM_GB -le 4 ]; then
        FILEBEAT_MEMORY_LIMIT="256m"
        FILEBEAT_MEMORY_RESERVATION="150m"
    else
        FILEBEAT_MEMORY_LIMIT="512m"
        FILEBEAT_MEMORY_RESERVATION="256m"
    fi
    
    # CPU Configuration
    if [ $CPU_CORES -le 2 ]; then
        ES_PROCESSORS=1
        GOMAXPROCS=1
        log_warning "Low CPU cores (${CPU_CORES}) - limiting processors"
    elif [ $CPU_CORES -le 4 ]; then
        ES_PROCESSORS=2
        GOMAXPROCS=2
    else
        ES_PROCESSORS=$((CPU_CORES > 8 ? 8 : CPU_CORES))  # Cap at 8 for ES
        GOMAXPROCS=$CPU_CORES
    fi
    
    # Storage-based optimizations
    if [ "$DISK_TYPE" = "nvme" ] || [ "$DISK_TYPE" = "ssd" ]; then
        INDEX_REFRESH_INTERVAL="5s"
        INDEX_TRANSLOG_SYNC_INTERVAL="5s"
        BULK_TIMEOUT="60s"
    else
        INDEX_REFRESH_INTERVAL="30s"
        INDEX_TRANSLOG_SYNC_INTERVAL="30s"
        BULK_TIMEOUT="120s"
    fi
    
    # Network optimizations based on expected load
    if [ $TOTAL_RAM_GB -ge 8 ]; then
        NETFLOW_QUEUE_SIZE=10000
        BULK_SIZE=1000
    elif [ $TOTAL_RAM_GB -ge 4 ]; then
        NETFLOW_QUEUE_SIZE=5000
        BULK_SIZE=500
    else
        NETFLOW_QUEUE_SIZE=1000
        BULK_SIZE=100
    fi
    
    # Calculate retention policy based on available space
    if [ $AVAILABLE_SPACE_GB -lt 20 ]; then
        RETENTION_DAYS=7
        log_warning "Low disk space (${AVAILABLE_SPACE_GB}GB) - using 7 days retention"
    elif [ $AVAILABLE_SPACE_GB -lt 50 ]; then
        RETENTION_DAYS=15
    elif [ $AVAILABLE_SPACE_GB -lt 100 ]; then
        RETENTION_DAYS=30
    else
        RETENTION_DAYS=60
    fi
    
    log_success "Configurations calculated:"
    echo "  🧠 Elasticsearch Heap: ${ES_HEAP_SIZE}"
    echo "  📊 Kibana Memory Limit: ${KIBANA_MEMORY_LIMIT}"
    echo "  📡 Filebeat Memory Limit: ${FILEBEAT_MEMORY_LIMIT}"
    echo "  🖥️  ES Processors: ${ES_PROCESSORS}"
    echo "  💿 Index Refresh: ${INDEX_REFRESH_INTERVAL}"
    echo "  📅 Retention Days: ${RETENTION_DAYS}"
    echo ""
}

# Function to generate .env file
generate_env_file() {
    log "📝 Generating optimized .env file..."
    
    cat > .env << EOF
# NetFlow ELK Stack Configuration
# Auto-generated on $(date)
# System: ${TOTAL_RAM_GB}GB RAM, ${CPU_CORES} cores, ${DISK_TYPE} storage

# Elastic Stack Version
ELASTIC_VERSION=8.15.0

# Network Configuration
ELASTICSEARCH_PORT=9200
KIBANA_PORT=5601
NETFLOW_PORT=2055
SERVER_IP=${SERVER_IP}

# System Resources (Auto-detected)
TOTAL_RAM_GB=${TOTAL_RAM_GB}
TOTAL_RAM_MB=${TOTAL_RAM_MB}
CPU_CORES=${CPU_CORES}
DISK_TYPE=${DISK_TYPE}

# Elasticsearch Configuration (Auto-calculated)
ES_HEAP_SIZE=${ES_HEAP_SIZE}
ES_MEMORY_LIMIT=${ES_MEMORY_LIMIT}
ES_MEMORY_RESERVATION=${ES_MEMORY_RESERVATION}
ES_PROCESSORS=${ES_PROCESSORS}

# Kibana Configuration (Auto-calculated)
KIBANA_MEMORY_LIMIT=${KIBANA_MEMORY_LIMIT}
KIBANA_MEMORY_RESERVATION=${KIBANA_MEMORY_RESERVATION}
KIBANA_NODE_OPTIONS=${KIBANA_NODE_OPTIONS}

# Filebeat Configuration (Auto-calculated)
FILEBEAT_MEMORY_LIMIT=${FILEBEAT_MEMORY_LIMIT}
FILEBEAT_MEMORY_RESERVATION=${FILEBEAT_MEMORY_RESERVATION}
GOMAXPROCS=${GOMAXPROCS}

# Performance Tuning (Based on hardware)
INDEX_REFRESH_INTERVAL=${INDEX_REFRESH_INTERVAL}
INDEX_TRANSLOG_SYNC_INTERVAL=${INDEX_TRANSLOG_SYNC_INTERVAL}
BULK_TIMEOUT=${BULK_TIMEOUT}
NETFLOW_QUEUE_SIZE=${NETFLOW_QUEUE_SIZE}
BULK_SIZE=${BULK_SIZE}

# Data Retention (Based on available space)
RETENTION_DAYS=${RETENTION_DAYS}
DISK_THRESHOLD_WARNING=80
DISK_THRESHOLD_CRITICAL=90

# Internal Networks (Adjust as needed)
INTERNAL_NETWORKS=private
EOF

    log_success ".env file generated successfully!"
}

# Function to create optimized Elasticsearch config
generate_elasticsearch_config() {
    log "⚙️ Generating optimized Elasticsearch configuration..."
    
    mkdir -p configs/elasticsearch
    
    cat > configs/elasticsearch/elasticsearch.yml << EOF
# Elasticsearch Configuration
# Auto-generated for ${TOTAL_RAM_GB}GB RAM, ${CPU_CORES} cores, ${DISK_TYPE} storage

# Cluster settings
cluster.name: "netflow-cluster"
node.name: "netflow-node-01"
network.host: 0.0.0.0
http.port: 9200
discovery.type: single-node

# Security (disabled for simplicity)
xpack.security.enabled: false
xpack.security.enrollment.enabled: false
xpack.ml.enabled: false
xpack.monitoring.enabled: false
xpack.watcher.enabled: false

# Memory locking disabled for compatibility
bootstrap.memory_lock: false

# Performance tuning based on system resources
indices.memory.index_buffer_size: $([ $TOTAL_RAM_GB -le 4 ] && echo "10%" || echo "20%")
indices.memory.min_index_buffer_size: $([ $TOTAL_RAM_GB -le 2 ] && echo "48mb" || echo "96mb")
indices.fielddata.cache.size: $([ $TOTAL_RAM_GB -le 4 ] && echo "20%" || echo "30%")
indices.queries.cache.size: $([ $TOTAL_RAM_GB -le 4 ] && echo "10%" || echo "15%")

# Thread pools based on CPU cores
thread_pool.write.queue_size: $((CPU_CORES * 200))
thread_pool.search.queue_size: $((CPU_CORES * 1000))
thread_pool.get.queue_size: $((CPU_CORES * 1000))

# Index settings optimized for NetFlow
action.auto_create_index: true
action.destructive_requires_name: true

# Disk allocation thresholds
cluster.routing.allocation.disk.threshold_enabled: true
cluster.routing.allocation.disk.watermark.low: 85%
cluster.routing.allocation.disk.watermark.high: 90%
cluster.routing.allocation.disk.watermark.flood_stage: 95%

# Recovery settings based on disk type
cluster.routing.allocation.node_concurrent_recoveries: $([ "$DISK_TYPE" = "hdd" ] && echo "1" || echo "2")
indices.recovery.max_bytes_per_sec: $([ "$DISK_TYPE" = "hdd" ] && echo "20mb" || echo "100mb")

# Processor configuration
processors: ${ES_PROCESSORS}

# NOTE: Index-level settings are configured via index templates, not in elasticsearch.yml
# This avoids the "node settings must not contain any index level settings" error
EOF

    log_success "Elasticsearch configuration generated!"
}

# Function to create optimized Filebeat config
generate_filebeat_config() {
    log "📡 Generating optimized Filebeat configuration..."
    
    mkdir -p configs/filebeat/modules.d
    
    cat > configs/filebeat/filebeat.yml << EOF
# Filebeat Configuration
# Auto-generated for ${TOTAL_RAM_GB}GB RAM, ${CPU_CORES} cores

filebeat.modules:
  - module: netflow
    log:
      enabled: true
      var.netflow_host: 0.0.0.0
      var.netflow_port: 2055
      var.internal_networks:
        - private
        - 10.0.0.0/8
        - 172.16.0.0/12
        - 192.168.0.0/16

# Output to Elasticsearch with optimized settings
output.elasticsearch:
  hosts: ["elasticsearch:9200"]
  index: "netflow-%{+yyyy.MM.dd}"
  bulk_max_size: ${BULK_SIZE}
  timeout: ${BULK_TIMEOUT}
  worker: $([ $CPU_CORES -le 2 ] && echo "1" || echo "2")

# Setup Kibana
setup.kibana:
  host: "kibana:5601"

# Template settings optimized for system resources
setup.template.settings:
  index.number_of_shards: 1
  index.number_of_replicas: 0
  index.refresh_interval: "${INDEX_REFRESH_INTERVAL}"
  index.codec: "best_compression"

# ILM Policy for automatic cleanup
setup.ilm.enabled: true
setup.ilm.rollover_alias: "netflow"
setup.ilm.pattern: "netflow-*"
setup.ilm.policy: "netflow-policy"

# Logging configuration
logging.level: info
logging.to_files: true
logging.files:
  path: /usr/share/filebeat/logs
  name: filebeat
  keepfiles: 7
  permissions: 0644

# Performance processors
processors:
  - add_host_metadata:
      when.not.contains.tags: forwarded
  - drop_fields:
      fields: ["agent", "ecs", "host.architecture", "host.os.family"]
      ignore_missing: true

# Queue settings based on available memory
queue.mem:
  events: ${NETFLOW_QUEUE_SIZE}
  flush.min_events: $([ $TOTAL_RAM_GB -le 2 ] && echo "100" || echo "512")
  flush.timeout: 5s
EOF

    cat > configs/filebeat/modules.d/netflow.yml << EOF
- module: netflow
  log:
    enabled: true
    var:
      netflow_host: 0.0.0.0
      netflow_port: 2055
      internal_networks:
        - private
        - 10.0.0.0/8
        - 172.16.0.0/12
        - 192.168.0.0/16
EOF

    log_success "Filebeat configuration generated!"
}

# Function to create optimized Kibana config
generate_kibana_config() {
    log "📊 Generating optimized Kibana configuration..."
    
    mkdir -p configs/kibana
    
    cat > configs/kibana/kibana.yml << EOF
# Kibana Configuration
# Auto-generated for ${TOTAL_RAM_GB}GB RAM system

server.host: 0.0.0.0
server.port: 5601
server.name: "netflow-kibana"

elasticsearch.hosts: ["http://elasticsearch:9200"]

# Security
xpack.security.enabled: false
xpack.encryptedSavedObjects.encryptionKey: "netflow_elk_stack_$(date +%s)_key_32_chars"

# Performance tuning based on available memory
server.maxPayload: $([ $TOTAL_RAM_GB -le 4 ] && echo "1048576" || echo "2097152")
elasticsearch.requestTimeout: $([ $TOTAL_RAM_GB -le 4 ] && echo "60000" || echo "30000")
elasticsearch.shardTimeout: $([ $TOTAL_RAM_GB -le 4 ] && echo "60000" || echo "30000")

# Logging
logging.quiet: $([ $TOTAL_RAM_GB -le 2 ] && echo "true" || echo "false")
EOF

    log_success "Kibana configuration generated!"
}

# Function to display configuration summary
display_summary() {
    log "📋 Configuration Summary:"
    echo ""
    echo "🖥️  SYSTEM DETECTED:"
    echo "   RAM: ${TOTAL_RAM_GB}GB (${TOTAL_RAM_MB}MB)"
    echo "   CPU: ${CPU_CORES} cores"
    echo "   Storage: ${DISK_TYPE}"
    echo "   Available Space: ${AVAILABLE_SPACE_GB}GB"
    echo ""
    echo "⚡ ELASTICSEARCH:"
    echo "   Heap Size: ${ES_HEAP_SIZE}"
    echo "   Memory Limit: ${ES_MEMORY_LIMIT}"
    echo "   Processors: ${ES_PROCESSORS}"
    echo ""
    echo "📊 KIBANA:"
    echo "   Memory Limit: ${KIBANA_MEMORY_LIMIT}"
    echo "   Node Options: ${KIBANA_NODE_OPTIONS}"
    echo ""
    echo "📡 FILEBEAT:"
    echo "   Memory Limit: ${FILEBEAT_MEMORY_LIMIT}"
    echo "   Queue Size: ${NETFLOW_QUEUE_SIZE}"
    echo "   Bulk Size: ${BULK_SIZE}"
    echo ""
    echo "💿 PERFORMANCE:"
    echo "   Index Refresh: ${INDEX_REFRESH_INTERVAL}"
    echo "   Storage Type: ${DISK_TYPE}"
    echo "   Retention: ${RETENTION_DAYS} days"
    echo ""
    echo "🌐 NETWORK:"
    echo "   Server IP: ${SERVER_IP}"
    echo "   NetFlow Port: 2055"
    echo ""
}

# Main execution function
main() {
    echo ""
    log "🚀 Starting Auto-Configuration for NetFlow ELK Stack"
    echo "=================================================="
    
    # Create necessary directories
    mkdir -p {data/{elasticsearch,kibana,filebeat},configs/{elasticsearch,kibana,filebeat/modules.d}}
    
    # Detect system and calculate configurations
    detect_system_resources
    calculate_configurations
    
    # Generate all configuration files
    generate_env_file
    generate_elasticsearch_config
    generate_kibana_config
    generate_filebeat_config
    
    # Display summary
    display_summary
    
    log_success "✅ Auto-configuration completed successfully!"
    echo ""
    echo "📝 Generated files:"
    echo "   • .env (environment variables)"
    echo "   • configs/elasticsearch/elasticsearch.yml"
    echo "   • configs/kibana/kibana.yml"
    echo "   • configs/filebeat/filebeat.yml"
    echo ""
    echo "🚀 Next steps:"
    echo "   1. Review the generated .env file"
    echo "   2. Run: ./scripts/setup.sh"
    echo "   3. Access Kibana at http://${SERVER_IP}:5601"
    echo ""
}

# Execute main function
main "$@"
