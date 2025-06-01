#!/bin/bash

# Smart entrypoint for zkwasm prover
# Checks configuration and downloads parameters before starting

set -e

CONFIG_FILE="/home/zkwasm/prover-node-release/prover_config.json"
LOG_FILE="/home/zkwasm/prover-node-release/logs/entrypoint.log"
PID_FILE="/home/zkwasm/prover-node-release/prover.pid"

# FTP Server configuration
FTP_SERVER_IP="${FTP_SERVER_IP:-localhost}"
FTP_USER="ftpuser"
FTP_PASS="ftppassword"

# Ensure log directory exists
mkdir -p /home/zkwasm/prover-node-release/logs

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] SMART: $1" | tee -a "$LOG_FILE"
}

# Function to check if private key is properly configured
check_private_key() {
    if [ ! -f "$CONFIG_FILE" ]; then
        return 1
    fi
    
    # Extract private key from JSON config using jq if available, fallback to grep
    local priv_key
    if command -v jq >/dev/null 2>&1; then
        priv_key=$(jq -r '.priv_key // empty' "$CONFIG_FILE" 2>/dev/null)
    else
        priv_key=$(grep -o '"priv_key"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
    fi
    
    # Check if private key exists and is not placeholder
    if [ -z "$priv_key" ] || [ "$priv_key" = "PRIVATE_KEY" ] || [ "$priv_key" = "" ]; then
        return 1
    fi
    
    # Check if private key looks valid (should be 64 characters without 0x prefix)
    if [[ ${#priv_key} -eq 64 && "$priv_key" =~ ^[0-9a-fA-F]+$ ]]; then
        return 0
    elif [[ ${#priv_key} -eq 66 && "$priv_key" =~ ^0x[0-9a-fA-F]+$ ]]; then
        log "WARNING: Private key should not include '0x' prefix"
        return 1
    fi
    
    return 1
}

# Function to check if server URL is configured
check_server_url() {
    if [ ! -f "$CONFIG_FILE" ]; then
        return 1
    fi
    
    local server_url
    if command -v jq >/dev/null 2>&1; then
        server_url=$(jq -r '.server_url // empty' "$CONFIG_FILE" 2>/dev/null)
    else
        server_url=$(grep -o '"server_url"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
    fi
    
    # Check if server URL is not localhost
    if [ "$server_url" = "http://localhost:8080" ] || [ -z "$server_url" ]; then
        return 1
    fi
    
    return 0
}

# Function to download parameter files from FTP server
download_params() {
    log "📦 Downloading parameter files from FTP server: $FTP_SERVER_IP:21 (Active Mode)"
    log "This may take a while on first run..."
    
    # Check if parameter files already exist
    if [ -d "workspace/static/params" ] && [ -n "$(ls -A workspace/static/params 2>/dev/null)" ]; then
        log "✅ Parameter files already exist, skipping download"
        return 0
    fi
    
    # Create directory structure
    mkdir -p workspace/static
    
    # Try to download from FTP server (wget uses active mode by default)
    if timeout 300s wget -r -nH -nv --cut-dirs=1 --no-parent \
        --user="$FTP_USER" --password="$FTP_PASS" \
        "ftp://$FTP_SERVER_IP/params/" \
        -P workspace/static/ 2>/dev/null; then
        log "✅ Parameter files downloaded successfully from $FTP_SERVER_IP:21"
        return 0
    else
        log "❌ Failed to download parameter files from $FTP_SERVER_IP:21"
        log "💡 Please check:"
        log "   1. FTP server is running at $FTP_SERVER_IP:21"
        log "   2. Network connectivity to the FTP server"
        log "   3. FTP credentials are correct"
        log "   4. Server allows active mode FTP connections"
        return 1
    fi
}

# Function to start the prover
start_prover() {
    log "✓ Configuration validated. Starting prover node..."
    
    # Change to the working directory
    cd /home/zkwasm/prover-node-release
    
    # Ensure proper ownership of files
    sudo chown -R zkwasm:root .
    sudo chown -R zkwasm:root logs/ 2>/dev/null || true
    sudo chown -R zkwasm:root rocksdb/ 2>/dev/null || true
    
    log "Checking system requirements..."
    
    # Check available memory
    mem_available=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
    mem_available_gb=$((mem_available / 1024 / 1024))
    
    log "Available memory: $mem_available_gb GB"
    
    if [ "$mem_available_gb" -lt 60 ]; then
        log "⚠️  Warning: Available memory ($mem_available_gb GB) may be insufficient for optimal performance"
        log "   Recommended: 80+ GB for stable operation"
    fi
    
    # Check GPU
    if command -v nvidia-smi > /dev/null 2>&1; then
        log "GPU status:"
        nvidia-smi --query-gpu=name,memory.total,memory.free --format=csv,noheader 2>/dev/null | head -1 | while read gpu_info; do
            log "  $gpu_info"
        done
    else
        log "⚠️  nvidia-smi not found, GPU may not be available"
    fi
    
    # Set environment variables
    export CUDA_VISIBLE_DEVICES=0
    export RUST_LOG=info
    export RUST_BACKTRACE=1
    
    # Start the prover
    local time=$(date +%Y-%m-%d-%H-%M-%S)
    
    log "🎯 Starting zkwasm-playground..."
    log "📊 Logs will be written to: logs/prover/prover_${time}.log"
    
    # Start the prover process
    nohup ./target/release/zkwasm-playground \
        --config prover_config.json \
        -w workspace \
        --proversystemconfig prover_system_config.json \
        -p \
        --rocksdbworkspace rocksdb \
        > logs/prover/prover_${time}.log 2>&1 &
    
    local prover_pid=$!
    echo $prover_pid > "$PID_FILE"
    
    log "✅ Prover started with PID: $prover_pid"
    log "📄 Monitor logs with: tail -f logs/prover/prover_${time}.log"
    
    # Monitor the process
    while kill -0 $prover_pid 2>/dev/null; do
        sleep 30
        log "📊 Prover (PID: $prover_pid) is running"
    done
    
    log "❌ Prover process stopped"
    exit 1
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

# Main execution
log "🌟 ZKWasm Smart Entrypoint Started"
log "🌐 FTP Server: $FTP_SERVER_IP:21 (Active Mode)"

# Check configuration
if ! check_private_key; then
    log "❌ Private key not configured properly"
    log "💡 Please edit $CONFIG_FILE and set a valid 64-character hex private key"
    exit 1
fi

if ! check_server_url; then
    log "❌ Server URL not configured properly"
    log "💡 Please edit $CONFIG_FILE and set server_url (current: http://localhost:8080)"
    exit 1
fi

log "✅ Configuration validated"

# Download parameter files
if ! download_params; then
    log "❌ Failed to download parameter files"
    exit 1
fi

# Start the prover
start_prover 