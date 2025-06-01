#!/bin/bash

# Smart entrypoint for zkwasm prover
# Checks configuration and parameters before starting

set -e

CONFIG_FILE="/home/zkwasm/prover-node-release/prover_config.json"
LOG_FILE="/home/zkwasm/prover-node-release/logs/entrypoint.log"
PID_FILE="/home/zkwasm/prover-node-release/prover.pid"

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

# Function to verify parameter files (built-in at build time)
verify_params() {
    log "📦 Verifying parameter files (copied during build)..."
    
    # Change to the working directory
    cd /home/zkwasm/prover-node-release
    
    # Check if parameter files exist
    if [ ! -d "workspace/static/params" ]; then
        log "❌ Parameter directory not found: workspace/static/params"
        log "💡 This should have been created during Docker build. Rebuild the image."
        return 1
    fi
    
    # Check if parameter files exist and are not empty
    local param_files_found=0
    for param_file in "workspace/static/params"/*; do
        if [ -f "$param_file" ] && [ -s "$param_file" ]; then
            param_files_found=$((param_files_found + 1))
            local file_size=$(ls -lh "$param_file" | awk '{print $5}')
            log "✅ Found: $(basename "$param_file") ($file_size)"
        fi
    done
    
    if [ $param_files_found -eq 0 ]; then
        log "❌ No parameter files found in workspace/static/params/"
        log "💡 The zkwasm/params image should contain K22.params, K23.params, etc."
        log "💡 Please rebuild the Docker image to copy parameter files during build."
        return 1
    fi
    
    log "✅ Found $param_files_found parameter file(s)"
    log "✅ Parameter files verification completed"
    return 0
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

# Verify parameter files
if ! verify_params; then
    log "❌ Failed to verify parameter files"
    exit 1
fi

# Start the prover
start_prover 