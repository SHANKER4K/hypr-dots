#!/usr/bin/env bash
# Toggle Waybar visibility
# Uses SIGUSR2 (show) and SIGUSR1 (hide)

if pgrep -x waybar > /dev/null; then
    # Waybar exists — check if visible (toggle)
    # Just alternate: if we send SIGUSR2 it shows, SIGUSR1 it hides
    # Simple approach: always toggle between states
    # Since we can't easily check visibility, just send SIGUSR2 to show
    # and rely on the user pressing again to hide via SIGUSR1
    # Better: use a simple state file
    STATE_FILE="/tmp/waybar_toggle_state"
    if [[ -f "$STATE_FILE" ]]; then
        rm -f "$STATE_FILE"
        pkill -SIGUSR1 waybar  # hide
    else
        touch "$STATE_FILE"
        pkill -SIGUSR2 waybar  # show
    fi
else
    waybar &
fi
