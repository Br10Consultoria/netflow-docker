#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[SETUP]${NC} $1"
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

# Detect script location and set proper paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Change to project root directory
cd "$PROJECT_ROOT"

echo "🚀 Setting up NetFlow ELK Stack with Auto-Configuration..."
echo "=========================================================="
echo "Project Root: $PROJECT_ROOT"
echo "Script Directory: $SCRIPT_DIR"

# Normalize line endings (CRLF -> LF) and strip BOM in all scripts to avoid execution errors
for f in scripts/*.sh; do
    if [ -f "$f" ]; then
        # Remove CR characters if present
        if grep -q $'\r' "$f" 2>/dev/null; then
            sed -i 's/\r$//' "$f"
        fi
        # Strip UTF-8 BOM if present
        sed -i '1s/^\xEF\xBB\xBF//' "$f" 2>/dev/null || true
        chmod +x "$f" 2>/dev/null || true
    fi
done

# Check if running as root for system optimizations
if [ "$EUID" -eq 0 ]; then
    log_warning "Running as root - will apply system optimizations"
    APPLY_SYSTEM_OPTS=true
else
    log "Running as regular user - system optimizations will be skipped"
    APPLY_SYSTEM_OPTS=false
fi

# Step 1: Auto-configure based on system resources
log "🔧 Step 1: Auto-configuring based on system resources..."
if [ ! -f "scripts/auto-configure.sh" ]; then
    log_error "auto-configure.sh not found! Please ensure all scripts are in place."
    log "Current directory: $(pwd)"
    log "Looking for: $(pwd)/scripts/auto-configure.sh"
    ls -la scripts/
    exit 1
fi

chmod +x scripts/auto-configure.sh
bash ./scripts/auto-configure.sh

# Step 2: Apply system optimizations if running as root
if [ "$APPLY_SYSTEM_OPTS" = true ]; then
    log "⚡ Step 2: Applying system optimizations..."
    
    if [ -f "scripts/debian_smart_optimization.sh" ]; then
        # Normalize potential Windows CRLF line endings to avoid execution errors
        if grep -q $'\r' "scripts/debian_smart_optimization.sh" 2>/dev/null; then
            sed -i 's/\r$//' "scripts/debian_smart_optimization.sh"
        fi
        chmod +x scripts/debian_smart_optimization.sh
        log "Running smart system optimization (this may take a few minutes)..."
        bash ./scripts/debian_smart_optimization.sh
    else
        log_warning "debian_smart_optimization.sh not found - skipping system optimizations"
    fi
else
    log "⚠️  Step 2: Skipping system optimizations (not running as root)"
    echo "   To apply system optimizations later, run:"
    echo "   sudo $PROJECT_ROOT/scripts/debian_smart_optimization.sh"
fi

# Step 3: Create necessary directories and set permissions
log "📁 Step 3: Creating directories and setting permissions..."
mkdir -p data/{elasticsearch,kibana,filebeat}
mkdir -p logs

# Set proper permissions for Elasticsearch
if command -v docker &> /dev/null; then
    # For Docker, we need to set ownership for the elasticsearch user (UID 1000)
    chown -R 1000:1000 data/elasticsearch 2>/dev/null || log_warning "Could not set elasticsearch permissions"
    chown -R 1000:1000 data/kibana 2>/dev/null || log_warning "Could not set kibana permissions"
    chown -R root:root data/filebeat 2>/dev/null || log_warning "Could not set filebeat permissions"
else
    log_error "Docker not found! Please install Docker first."
    exit 1
fi

# Step 4: Validate Docker Compose
log "🐳 Step 4: Validating Docker Compose configuration..."
if ! docker-compose config > /dev/null 2>&1; then
    log_error "Docker Compose configuration is invalid!"
    docker-compose config
    exit 1
fi

log_success "Docker Compose configuration is valid"

# Step 5: Load environment variables and display configuration
log "📋 Step 5: Loading configuration..."
if [ -f ".env" ]; then
    source .env
    echo ""
    echo "🖥️  DETECTED SYSTEM:"
    echo "   RAM: ${TOTAL_RAM_GB}GB"
    echo "   CPU: ${CPU_CORES} cores"
    echo "   Storage: ${DISK_TYPE}"
    echo ""
    echo "⚙️  APPLIED CONFIGURATION:"
    echo "   Elasticsearch Heap: ${ES_HEAP_SIZE}"
    echo "   Elasticsearch Memory Limit: ${ES_MEMORY_LIMIT}"
    echo "   Kibana Memory Limit: ${KIBANA_MEMORY_LIMIT}"
    echo "   Filebeat Memory Limit: ${FILEBEAT_MEMORY_LIMIT}"
    echo "   Data Retention: ${RETENTION_DAYS} days"
    echo ""
else
    log_error ".env file not found! Auto-configuration may have failed."
    exit 1
fi

# Ask for confirmation before starting
echo ""
read -p "Start the NetFlow ELK stack with these settings? (y/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log "Setup cancelled by user"
    exit 0
fi

# Step 6: Start the stack
log "🚀 Step 6: Starting Docker containers..."
docker-compose down 2>/dev/null || true  # Stop any existing containers
docker-compose up -d

# Step 7: Wait for services to be ready
log "⏳ Step 7: Waiting for services to start..."
log "This may take a few minutes on first startup..."

# Function to wait for a service
wait_for_service() {
    local service_name=$1
    local health_url=$2
    local max_attempts=30
    local attempt=1
    
    echo -n "Waiting for $service_name"
    while [ $attempt -le $max_attempts ]; do
        if curl -s --connect-timeout 5 "$health_url" > /dev/null 2>&1; then
            echo ""
            log_success "$service_name is ready!"
            return 0
        fi
        
        echo -n "."
        sleep 10
        attempt=$((attempt + 1))
    done
    
    echo ""
    log_error "$service_name failed to start within $((max_attempts * 10)) seconds"
    return 1
fi

# Wait for Elasticsearch
wait_for_service "Elasticsearch" "http://localhost:${ELASTICSEARCH_PORT}/_cluster/health"

# Apply NetFlow index template for dynamic configuration
log "📋 Applying NetFlow index template..."
if [ -f "configs/elasticsearch/index-template.json" ]; then
    curl -X PUT "localhost:${ELASTICSEARCH_PORT}/_index_template/netflow-template" \
         -H "Content-Type: application/json" \
         -d @configs/elasticsearch/index-template.json > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        log_success "NetFlow index template applied successfully"
    else
        log_warning "Failed to apply index template - will use defaults"
    fi
fi

# Wait for Kibana
wait_for_service "Kibana" "http://localhost:${KIBANA_PORT}/api/status"

# Step 8: Setup Filebeat dashboards
log "📊 Step 8: Setting up Filebeat dashboards..."
sleep 10  # Give services a moment to fully initialize

if docker-compose exec -T filebeat filebeat setup --dashboards 2>/dev/null; then
    log_success "Filebeat dashboards installed successfully"
else
    log_warning "Filebeat dashboard setup failed - will retry later"
    # Try again in background
    (sleep 30 && docker-compose exec -T filebeat filebeat setup --dashboards > /dev/null 2>&1) &
fi

# Step 9: Verify installation
log "✅ Step 9: Verifying installation..."

# Check container status
log "Checking container status..."
if docker-compose ps | grep -q "Up"; then
    running_containers=$(docker-compose ps --services --filter "status=running")
    echo "Running containers: $running_containers"
    docker-compose ps
else
    log_error "No containers are running!"
    echo "Container logs:"
    docker-compose logs --tail=20
    exit 1
fi

# Test connectivity
log "Testing service connectivity..."

# Test Elasticsearch
if curl -s "localhost:${ELASTICSEARCH_PORT}/_cluster/health" | grep -q "green\|yellow"; then
    log_success "Elasticsearch is responding"
else
    log_warning "Elasticsearch may not be fully ready yet"
fi

# Test Kibana
if curl -s "localhost:${KIBANA_PORT}/api/status" > /dev/null 2>&1; then
    log_success "Kibana is responding"
else
    log_warning "Kibana may not be fully ready yet"
fi

# Test NetFlow port
if netstat -ulnp 2>/dev/null | grep -q ":${NETFLOW_PORT}"; then
    log_success "NetFlow port ${NETFLOW_PORT} is listening"
else
    log_warning "NetFlow port may not be ready yet"
fi

# Step 10: Setup monitoring and cleanup
log "🔧 Step 10: Setting up monitoring and cleanup..."

# Make scripts executable
chmod +x scripts/*.sh

# Setup monitoring cron job
if command -v crontab &> /dev/null; then
    # Add monitoring to crontab if not already present
    if ! crontab -l 2>/dev/null | grep -q "netflow-monitor.sh"; then
        (crontab -l 2>/dev/null; echo "*/5 * * * * $SCRIPT_DIR/netflow-monitor.sh >> $PROJECT_ROOT/logs/monitor.log 2>&1") | crontab -
        log_success "Monitoring scheduled every 5 minutes"
    fi
    
    # Add cleanup to crontab if not already present
    if ! crontab -l 2>/dev/null | grep -q "cleanup-data.sh"; then
        (crontab -l 2>/dev/null; echo "0 2 * * * $SCRIPT_DIR/cleanup-data.sh >> $PROJECT_ROOT/logs/cleanup.log 2>&1") | crontab -
        log_success "Daily cleanup scheduled at 2 AM"
    fi
else
    log_warning "crontab not available - manual monitoring required"
fi

# Create management scripts in project root
cat > start-netflow.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
echo "Starting NetFlow ELK Stack..."
docker-compose up -d
echo "Stack started! Access Kibana at: http://localhost:5601"
EOF

cat > stop-netflow.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
echo "Stopping NetFlow ELK Stack..."
docker-compose down
echo "Stack stopped!"
EOF

chmod +x start-netflow.sh stop-netflow.sh

# Final summary
echo ""
echo "=========================================================="
log_success "✅ NetFlow ELK Stack setup completed successfully!"
echo "=========================================================="
echo ""
echo "🌐 ACCESS INFORMATION:"
echo "   Kibana Web Interface: http://${SERVER_IP:-localhost}:${KIBANA_PORT}"
echo "   Elasticsearch API: http://${SERVER_IP:-localhost}:${ELASTICSEARCH_PORT}"
echo "   NetFlow Listener: UDP port ${NETFLOW_PORT}"
echo ""
echo "📊 SYSTEM CONFIGURATION:"
echo "   System RAM: ${TOTAL_RAM_GB}GB"
echo "   Elasticsearch Heap: ${ES_HEAP_SIZE}"
echo "   Data Retention: ${RETENTION_DAYS} days"
echo "   Disk Type: ${DISK_TYPE}"
echo ""
echo "🔧 MANAGEMENT COMMANDS:"
echo "   Start stack: ./start-netflow.sh"
echo "   Stop stack: ./stop-netflow.sh"
echo "   View logs: docker-compose logs -f"
echo "   Monitor system: $SCRIPT_DIR/netflow-monitor.sh"
echo "   Cleanup data: $SCRIPT_DIR/cleanup-data.sh"
echo ""
echo "📡 CONFIGURE YOUR ROUTERS:"
echo "   Point NetFlow/sFlow exports to: ${SERVER_IP:-<your-server-ip>}:${NETFLOW_PORT}"
echo ""

# Display router configuration examples
cat << 'EOF'
📋 ROUTER CONFIGURATION EXAMPLES:

Cisco IOS:
  ip flow-export destination <SERVER_IP> 2055
  ip flow-export version 9
  interface GigabitEthernet0/1
    ip flow ingress

Huawei:
  ip netstream export host <SERVER_IP> 2055
  ip netstream export version 9
  interface GigabitEthernet0/0/1
    ip netstream inbound
    ip netstream outbound

Mikrotik:
  /ip traffic-flow
  set enabled=yes interfaces=ether1
  /ip traffic-flow target
  add address=<SERVER_IP> port=2055 version=9

EOF

echo "🎉 Setup complete! Your NetFlow ELK stack is ready to receive data."
echo ""
echo "📖 Quick Start:"
echo "   1. Configure your routers to send NetFlow to ${SERVER_IP:-<your-server-ip>}:${NETFLOW_PORT}"
echo "   2. Access Kibana at http://${SERVER_IP:-localhost}:${KIBANA_PORT}"
echo "   3. Monitor system: $SCRIPT_DIR/netflow-monitor.sh"
echo ""
