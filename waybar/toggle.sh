#!/usr/bin/env bash
# Toggle Waybar visibility
# Uses state file to track visibility

STATE_FILE="/tmp/waybar_toggle_state"

if ! pgrep -x waybar > /dev/null; then
    waybar &
    exit 0
fi

if [[ -f "$STATE_FILE" ]]; then
    rm -f "$STATE_FILE"
    pkill -SIGUSR1 waybar  # hide
else
    touch "$STATE_FILE"
    pkill -SIGUSR2 waybar  # show
fi
