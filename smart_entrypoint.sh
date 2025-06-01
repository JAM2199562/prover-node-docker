#!/bin/bash

# Smart entrypoint for vast.ai deployment
# This script waits for proper configuration and then starts the prover node

set -e

CONFIG_FILE="/home/zkwasm/prover-node-release/prover_config.json"
LOG_FILE="/home/zkwasm/prover-node-release/logs/entrypoint.log"
CHECK_INTERVAL=30  # Check every 30 seconds
PID_FILE="/home/zkwasm/prover-node-release/prover.pid"

# Ensure log directory exists
mkdir -p /home/zkwasm/prover-node-release/logs

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Function to check if private key is properly configured
check_private_key() {
    if [ ! -f "$CONFIG_FILE" ]; then
        return 1
    fi
    
    # Extract private key from JSON config
    local priv_key=$(grep -o '"priv_key"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
    
    # Check if private key exists and is not placeholder
    if [ -z "$priv_key" ] || [ "$priv_key" = "PRIVATE_KEY" ] || [ "$priv_key" = "" ]; then
        return 1
    fi
    
    # Check if private key looks valid (basic hex check, should be 64 characters without 0x prefix)
    if [[ ${#priv_key} -eq 64 && "$priv_key" =~ ^[0-9a-fA-F]+$ ]]; then
        return 0
    elif [[ ${#priv_key} -eq 66 && "$priv_key" =~ ^0x[0-9a-fA-F]+$ ]]; then
        log "WARNING: Private key should not include '0x' prefix according to documentation"
        return 1
    fi
    
    return 1
}

# Function to check if server URL is configured
check_server_url() {
    if [ ! -f "$CONFIG_FILE" ]; then
        return 1
    fi
    
    local server_url=$(grep -o '"server_url"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
    
    # Check if server URL is not localhost (vast.ai deployment shouldn't use localhost)
    if [ "$server_url" = "http://localhost:8080" ] || [ -z "$server_url" ]; then
        return 1
    fi
    
    return 0
}

# Function to start the prover service
start_prover() {
    log "✓ Configuration validated. Starting prover node..."
    
    # Change to the working directory
    cd /home/zkwasm/prover-node-release
    
    # Ensure proper ownership of files
    sudo chown -R zkwasm:root .
    sudo chown -R zkwasm:root logs/
    sudo chown -R zkwasm:root rocksdb/ 2>/dev/null || true
    
    # Check and download parameter files
    mkdir -p workspace/static
    
    if [ ! -d "workspace/static/params" ] || [ -z "$(ls -A workspace/static/params 2>/dev/null)" ]; then
        log "📦 Checking parameter files (required for K=22)..."
        
        # Try to download from localhost FTP (if available)
        if timeout 60s wget -r -nH -nv --cut-dirs=1 --no-parent \
            --user=ftpuser --password=ftppassword \
            ftp://localhost/params/ \
            -P workspace/static/ 2>/dev/null; then
            log "✅ Parameter files downloaded successfully"
        else
            log "❌ Parameter files not available"
            log "🔧 This container needs parameter files to run the prover"
            log "💡 Run with docker-compose or copy params manually to workspace/static/params/"
            log "⏳ Will retry in 60 seconds..."
            sleep 60
            return 1  # This will cause the main loop to retry
        fi
    else
        log "✅ Parameter files already exist"
    fi
    
    log "Starting FTP server for parameter files..."
    
    # Start params-ftp service in background
    if docker ps --format '{{.Names}}' | grep -q "params-ftp"; then
        log "FTP server already running"
    else
        log "Starting FTP server container..."
        # We need to start this in a way that works in the container
        # For now, we'll skip the FTP server dependency check
    fi
    
    log "Checking system requirements..."
    
    # Check available memory
    mem_available=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
    mem_available_gb=$((mem_available / 1024 / 1024))
    log "Available memory: $mem_available_gb GB"
    
    if [ "$mem_available_gb" -lt 80 ]; then
        log "WARNING: Available memory ($mem_available_gb GB) is less than the recommended 80 GB."
    fi
    
    # Check HugePages if available
    if [ -f /proc/meminfo ]; then
        hugepages_free=$(grep -i hugepages_free /proc/meminfo | awk '{print $2}' 2>/dev/null || echo "0")
        log "HugePages_Free: $hugepages_free"
        
        if [ "$hugepages_free" -lt 15000 ] && [ "$hugepages_free" -gt 0 ]; then
            log "WARNING: HugePages_Free ($hugepages_free) is less than 15000. Performance may be affected."
        fi
    fi
    
    # Check for NVIDIA GPU
    if command -v nvidia-smi > /dev/null 2>&1; then
        log "NVIDIA GPU check:"
        nvidia-smi 2>&1 | tee -a "$LOG_FILE" || log "WARNING: nvidia-smi failed"
    else
        log "WARNING: nvidia-smi not found. GPU acceleration may not be available."
    fi
    
    # Ensure rocksdb directory exists and has proper permissions
    mkdir -p rocksdb
    sudo chown -R zkwasm:root rocksdb/ 2>/dev/null || true
    
    # Start the actual prover process
    log "🚀 Starting zkwasm-playground prover..."
    
    # Create a wrapper script to handle the prover process
    export CUDA_VISIBLE_DEVICES=0
    export RUST_LOG=info
    export RUST_BACKTRACE=1
    
    # Get current timestamp for log file
    time=$(date +%Y-%m-%d-%H-%M-%S)
    
    # Start the prover and save PID
    nohup ./target/release/zkwasm-playground \
        --config prover_config.json \
        -w workspace \
        --proversystemconfig prover_system_config.json \
        -p \
        --rocksdbworkspace rocksdb \
        > logs/prover/prover_${time}.log 2>&1 &
    
    local prover_pid=$!
    echo $prover_pid > "$PID_FILE"
    
    log "✓ Prover started with PID: $prover_pid"
    log "✓ Logs: logs/prover/prover_${time}.log"
    log "🎯 Prover node is now running! Monitor logs for mining progress."
    
    # Monitor the process
    while kill -0 $prover_pid 2>/dev/null; do
        sleep 60
        log "📊 Prover process (PID: $prover_pid) is running"
    done
    
    log "❌ Prover process stopped unexpectedly"
    exit 1
}

# Function to display current configuration status
show_config_status() {
    log "🔍 Configuration Status Check:"
    
    if [ -f "$CONFIG_FILE" ]; then
        log "  ✓ Config file exists: $CONFIG_FILE"
        
        local server_url=$(grep -o '"server_url"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
        local priv_key=$(grep -o '"priv_key"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
        
        log "  Server URL: $server_url"
        
        if check_server_url; then
            log "  ✓ Server URL: Configured"
        else
            log "  ❌ Server URL: Need configuration (currently: $server_url)"
        fi
        
        if check_private_key; then
            log "  ✓ Private Key: Configured and valid"
        else
            log "  ❌ Private Key: Need configuration (currently: ${priv_key:0:20}...)"
        fi
    else
        log "  ❌ Config file missing: $CONFIG_FILE"
    fi
    
    log ""
    log "📝 To configure:"
    log "  1. SSH into this container"
    log "  2. Edit $CONFIG_FILE"
    log "  3. Set 'priv_key' to your 64-character hex private key (no 0x prefix)"
    log "  4. Set 'server_url' to the correct prover server endpoint"
    log "  5. The prover will automatically start once configuration is detected"
}

# Cleanup function
cleanup() {
    log "🛑 Received shutdown signal"
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 $pid 2>/dev/null; then
            log "Stopping prover process (PID: $pid)"
            kill -TERM $pid
            sleep 5
            if kill -0 $pid 2>/dev/null; then
                log "Force killing prover process"
                kill -KILL $pid
            fi
        fi
        rm -f "$PID_FILE"
    fi
    log "👋 Shutdown complete"
    exit 0
}

# Set up signal handlers
trap cleanup SIGTERM SIGINT

# Main loop
log "🌟 ZKWasm Prover Node Smart Entrypoint Started"
log "📍 Deployment: vast.ai compatible"
log "🔄 Check interval: ${CHECK_INTERVAL} seconds"
log ""

# Initial configuration check
show_config_status

# Main monitoring loop
while true; do
    if check_private_key && check_server_url; then
        log "✅ Valid configuration detected!"
        start_prover
        break
    else
        log "⏳ Waiting for configuration... (checked every ${CHECK_INTERVAL}s)"
        show_config_status
    fi
    
    sleep $CHECK_INTERVAL
done

# This point should never be reached under normal circumstances
log "❌ Unexpected exit from main loop"
exit 1 