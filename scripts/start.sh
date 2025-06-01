#!/bin/bash

# Set `RUN_MONITOR` to skip if `ALERT_POST_URL` is empty. This disables monitoring if the url is not set.
if [ ! -e "scripts/.env" ]; then
    echo "scripts/.env does not exist! Required for start up."
    exit 1
fi
. scripts/.env
if [ "$ALERT_POST_URL" = "" ]; then
    export RUN_MONITOR="skip"
else
    export RUN_MONITOR=""
fi

docker compose down  # Stop any existing services

# Check zkwasm (prover node) image exists, if not ask the user to build it.
if docker images | grep "^zkwasm[[:space:]]" &> /dev/null; then
    echo "OK: Prover node image found"
else
    echo "ERR: prover node image not found. please build it using 'bash scripts/build_image.sh'"
    exit 1
fi

# Start all services (no more FTP dependency)
echo "Starting ZKWasm prover node..."
docker compose up
