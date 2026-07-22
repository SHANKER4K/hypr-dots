#!/bin/bash
# 20-20-20 eye break lock

hyprlock -c ~/.config/hypr/eye-break-lock.conf &
LOCK_PID=$!

sleep 20

kill -SIGUSR1 $LOCK_PID 2>/dev/null
