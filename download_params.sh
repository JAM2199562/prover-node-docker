#!/bin/bash

# Download and extract zkwasm params from the official params image
# This script replicates the functionality of the params-ftp container

set -e

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] PARAMS: $1"
}

log "🔄 Setting up zkwasm parameter files..."

# Check if params already exist
if [ -f "/home/ftpuser/params/K22.params" ]; then
    log "✅ K22.params already exists, skipping download"
    exit 0
fi

# Create temp directory for extraction
TEMP_DIR="/tmp/zkwasm_params_extract"
sudo mkdir -p "$TEMP_DIR"

log "📦 Pulling zkwasm/params Docker image..."
# Pull the official params image (but don't run it)
if sudo docker pull zkwasm/params; then
    log "✅ Successfully pulled zkwasm/params image"
else
    log "❌ Failed to pull zkwasm/params image"
    exit 1
fi

log "📂 Extracting parameter files from image..."
# Create a temporary container and copy files from it
CONTAINER_ID=$(sudo docker create zkwasm/params)

# Try common locations where params might be stored in the image
PARAM_PATHS=(
    "/home/ftpuser/params"
    "/home/ftpuser"
    "/params"
    "/data"
    "/app/params"
    "/usr/local/params"
)

found_params=false
for path in "${PARAM_PATHS[@]}"; do
    log "🔍 Checking path: $path"
    if sudo docker cp "$CONTAINER_ID:$path" "$TEMP_DIR/" 2>/dev/null; then
        log "✅ Found params at: $path"
        found_params=true
        break
    fi
done

# Clean up the temporary container
sudo docker rm "$CONTAINER_ID" >/dev/null

if [ "$found_params" = false ]; then
    log "❌ No parameter files found in zkwasm/params image"
    log "🔧 Trying alternative approach: running params container to generate files..."
    
    # Try running the params container briefly to let it initialize
    PARAMS_CONTAINER=$(sudo docker run -d --name zkwasm_params_temp zkwasm/params)
    sleep 10
    
    # Try to copy from the running container
    for path in "${PARAM_PATHS[@]}"; do
        log "🔍 Checking running container path: $path"
        if sudo docker cp "$PARAMS_CONTAINER:$path" "$TEMP_DIR/" 2>/dev/null; then
            log "✅ Found params from running container at: $path"
            found_params=true
            break
        fi
    done
    
    # Clean up
    sudo docker stop "$PARAMS_CONTAINER" >/dev/null 2>&1 || true
    sudo docker rm "$PARAMS_CONTAINER" >/dev/null 2>&1 || true
fi

if [ "$found_params" = false ]; then
    log "❌ Could not extract parameter files from zkwasm/params image"
    log "💡 You may need to generate them manually using zkwasm CLI"
    log "💡 Or contact DelphinusLab for parameter file download instructions"
    exit 1
fi

log "📋 Copying parameter files to FTP directory..."
# Copy extracted params to FTP directory
sudo mkdir -p /home/ftpuser/params
sudo cp -r "$TEMP_DIR"/*/* /home/ftpuser/params/ 2>/dev/null || \
sudo cp -r "$TEMP_DIR"/* /home/ftpuser/params/ 2>/dev/null || true

# Set proper ownership
sudo chown -R ftpuser:ftpuser /home/ftpuser/params/

# Clean up temp directory
sudo rm -rf "$TEMP_DIR"

# Check if K22.params exists now
if [ -f "/home/ftpuser/params/K22.params" ]; then
    log "✅ Successfully set up K22.params file"
    log "📏 File size: $(ls -lh /home/ftpuser/params/K22.params | awk '{print $5}')"
else
    log "⚠️  K22.params not found, but other parameter files may be available:"
    sudo find /home/ftpuser/params -name "*.params" -exec ls -lh {} \; 2>/dev/null || true
fi

log "🎯 Parameter setup completed!" 