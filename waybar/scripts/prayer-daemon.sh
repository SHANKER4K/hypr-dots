#!/bin/bash
# Prayer notification daemon — runs prayer.sh every 60s for notifications + lock
while true; do
    "$(dirname "$0")/prayer.sh" >/dev/null 2>&1
    sleep 60
done
