#!/bin/bash

# NetFlow Data Cleanup Script
# Removes data older than 30 days or when disk usage exceeds 90%

ELASTICSEARCH_HOST="localhost:9200"
DISK_THRESHOLD=90
RETENTION_DAYS=30
LOG_FILE="/var/log/netflow-cleanup.log"

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

check_disk_usage() {
    df / | awk 'NR==2 {print $5}' | sed 's/%//'
}

cleanup_old_indices() {
    local days_old=$1
    local cutoff_date=$(date -d "$days_old days ago" +%Y.%m.%d)
    
    log_message "Cleaning up indices older than $days_old days (before $cutoff_date)"
    
    # Get list of indices older than cutoff date
    indices=$(curl -s "$ELASTICSEARCH_HOST/_cat/indices/netflow-*?h=index" | \
              awk -v cutoff="$cutoff_date" '$1 ~ /netflow-/ {
                  split($1, parts, "-"); 
                  if (parts[2] < cutoff) print $1
              }')
    
    if [ -n "$indices" ]; then
        for index in $indices; do
            log_message "Deleting index: $index"
            curl -X DELETE "$ELASTICSEARCH_HOST/$index" >/dev/null 2>&1
        done
    else
        log_message "No old indices found for cleanup"
    fi
}

cleanup_by_disk_usage() {
    local current_usage=$(check_disk_usage)
    log_message "Current disk usage: ${current_usage}%"
    
    if [ "$current_usage" -ge "$DISK_THRESHOLD" ]; then
        log_message "Disk usage ($current_usage%) exceeds threshold ($DISK_THRESHOLD%). Starting aggressive cleanup..."
        
        # Start with 7 days and increase if needed
        local cleanup_days=7
        while [ $(check_disk_usage) -ge $DISK_THRESHOLD ] && [ $cleanup_days -le 30 ]; do
            cleanup_old_indices $cleanup_days
            sleep 5
            cleanup_days=$((cleanup_days + 7))
        done
        
        # Force optimize remaining indices
        log_message "Optimizing remaining indices..."
        curl -X POST "$ELASTICSEARCH_HOST/netflow-*/_forcemerge?max_num_segments=1" >/dev/null 2>&1
    fi
}

main() {
    log_message "Starting NetFlow data cleanup"
    
    # Regular cleanup (30 days)
    cleanup_old_indices $RETENTION_DAYS
    
    # Emergency cleanup if disk is full
    cleanup_by_disk_usage
    
    log_message "Cleanup completed"
}

main "$@"