#!/bin/bash

# Vast.ai compatible launcher for zkwasm prover node
# This script should be run manually or via cron/systemd in vast.ai environment

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROVER_DIR="/home/zkwasm/prover-node-release"
SMART_ENTRYPOINT="/home/zkwasm/smart_entrypoint.sh"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "🚀 ZKWasm Vast.ai Launcher Started"

# Check if we're running as root and switch to zkwasm user if needed
if [ "$EUID" -eq 0 ]; then
    log "Running as root, switching to zkwasm user..."
    
    # Ensure proper ownership
    chown -R zkwasm:root /home/zkwasm/ 2>/dev/null || true
    
    # Run smart entrypoint as zkwasm user
    exec su - zkwasm -c "$SMART_ENTRYPOINT"
else
    log "Running as user: $(whoami)"
    
    # Check if smart entrypoint exists
    if [ -f "$SMART_ENTRYPOINT" ]; then
        log "Starting smart entrypoint script..."
        exec "$SMART_ENTRYPOINT"
    else
        log "Smart entrypoint not found, trying manual setup..."
        
        # Fallback: run prover directly if configured
        if [ -f "$PROVER_DIR/prover_config.json" ]; then
            cd "$PROVER_DIR"
            
            # Check configuration
            server_url=$(grep -o '"server_url"[[:space:]]*:[[:space:]]*"[^"]*"' prover_config.json | cut -d'"' -f4)
            priv_key=$(grep -o '"priv_key"[[:space:]]*:[[:space:]]*"[^"]*"' prover_config.json | cut -d'"' -f4)
            
            log "Configuration check:"
            log "  Server URL: $server_url"
            log "  Private Key: ${priv_key:0:20}..."
            
            if [ "$priv_key" != "PRIVATE_KEY" ] && [ ${#priv_key} -eq 64 ]; then
                log "✅ Configuration looks good, preparing to start prover..."
                
                mkdir -p logs/prover
                mkdir -p workspace/static
                
                # Download parameter files if not exist
                if [ ! -d "workspace/static/params" ] || [ -z "$(ls -A workspace/static/params 2>/dev/null)" ]; then
                    log "📦 Downloading parameter files (required for K=22)..."
                    log "This may take a while on first run..."
                    
                    # Try to download from localhost FTP (if running with docker-compose)
                    if timeout 60s wget -r -nH -nv --cut-dirs=1 --no-parent \
                        --user=ftpuser --password=ftppassword \
                        ftp://localhost/params/ \
                        -P workspace/static/ 2>/dev/null; then
                        log "✅ Parameter files downloaded from localhost FTP"
                    else
                        log "⚠️  Local FTP not available, this is expected in vast.ai environment"
                        log "❌ Missing parameter files for K=22"
                        log ""
                        log "🔧 SOLUTION: You need to obtain parameter files from:"
                        log "   1. Run the official docker-compose setup once to download params"
                        log "   2. Copy the workspace/static/params directory to this container"
                        log "   3. Or contact zkwasm team for parameter file access"
                        log ""
                        log "📝 Quick fix for testing:"
                        log "   mkdir -p workspace/static/params"
                        log "   # Then copy actual param files to that directory"
                        log ""
                        log "❌ Cannot start prover without parameter files"
                        exit 1
                    fi
                else
                    log "✅ Parameter files already exist"
                fi
                
                log "🚀 Starting zkwasm prover..."
                export CUDA_VISIBLE_DEVICES=0
                export RUST_LOG=info
                export RUST_BACKTRACE=1
                
                time=$(date +%Y-%m-%d-%H-%M-%S)
                log_file="logs/prover/prover_${time}.log"
                
                nohup ./target/release/zkwasm-playground \
                    --config prover_config.json \
                    -w workspace \
                    --proversystemconfig prover_system_config.json \
                    -p \
                    --rocksdbworkspace rocksdb \
                    > "$log_file" 2>&1 &
                
                prover_pid=$!
                log "🎯 Prover started with PID: $prover_pid"
                log "📄 Log file: $log_file"
                
                # Monitor the process
                while kill -0 $prover_pid 2>/dev/null; do
                    sleep 60
                    log "📊 Prover process (PID: $prover_pid) is running"
                done
                
                log "❌ Prover process stopped"
            else
                log "❌ Please configure private key in $PROVER_DIR/prover_config.json"
                log "📝 Edit the file and set priv_key to your 64-character hex private key"
                log "🔄 Then run this script again"
                exit 1
            fi
        else
            log "❌ Configuration file not found: $PROVER_DIR/prover_config.json"
            exit 1
        fi
    fi
fi 