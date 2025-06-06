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

echo "Starting services in detached mode..."
echo "If you want to attach to the logs, run 'docker compose logs -f --tail 100'"
echo "Alternatively for each service, run 'docker compose logs -f <service_name> --tail 100'"

docker compose up -d
