#!/bin/bash

# Unified entrypoint for vast.ai zkwasm deployment
# This script manages FTP server, SSH server, and zkwasm prover in a single container

set -e

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] UNIFIED: $1"
}

log "🚀 Starting ZKWasm Unified Container for vast.ai"

# Create necessary directories for supervisor
sudo mkdir -p /var/log/supervisor
sudo mkdir -p /var/run

# Download and setup parameter files before starting services
log "📦 Setting up parameter files..."
if [ -f "/home/zkwasm/download_params.sh" ]; then
    chmod +x /home/zkwasm/download_params.sh
    /home/zkwasm/download_params.sh
else
    log "⚠️  Parameter download script not found, skipping automatic setup"
fi

# Start supervisor to manage SSH and FTP services
log "📡 Starting supervisor to manage SSH and FTP services..."
sudo /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf &

# Wait a moment for services to start
sleep 5

# Check if FTP server is running
if pgrep -f "pure-ftpd" > /dev/null; then
    log "✅ FTP server started successfully"
    # Test FTP connectivity
    if timeout 5 bash -c "</dev/tcp/localhost/21" 2>/dev/null; then
        log "✅ FTP server is accepting connections on port 21"
    else
        log "⚠️  FTP server started but not accepting connections yet"
    fi
else
    log "❌ FTP server failed to start"
fi

# Check if SSH server is running  
if pgrep -f "sshd" > /dev/null; then
    log "✅ SSH server started successfully"
else
    log "❌ SSH server failed to start"
fi

# Copy any existing params to FTP directory if available
if [ -d "/home/zkwasm/prover-node-release/workspace/static/params" ]; then
    log "📦 Copying existing params to FTP directory..."
    sudo cp -r /home/zkwasm/prover-node-release/workspace/static/params/* /home/ftpuser/params/ 2>/dev/null || true
    sudo chown -R ftpuser:ftpuser /home/ftpuser/params/
fi

# Show parameter file status
log "📋 Parameter file status:"
if [ -f "/home/ftpuser/params/K22.params" ]; then
    log "✅ K22.params found: $(ls -lh /home/ftpuser/params/K22.params | awk '{print $5}')"
else
    log "⚠️  K22.params not found"
    log "📂 Available parameter files:"
    sudo find /home/ftpuser/params -name "*.params" -exec ls -lh {} \; 2>/dev/null || log "   No .params files found"
fi

# Now start the zkwasm prover logic
log "🎯 Starting ZKWasm prover..."

# Check if we should use the vast.ai launcher or smart entrypoint
if [ -n "$USE_VAST_AI_LAUNCHER" ]; then
    log "Using vast.ai launcher..."
    exec /home/zkwasm/vast_ai_launcher.sh
else
    log "Using smart entrypoint..."
    exec /home/zkwasm/smart_entrypoint.sh
fi 