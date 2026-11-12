#!/usr/bin/env bash
# Click handler for waybar custom/health: toggle the 20-20 / 30-5 rules.
# Signals the daemon by PID file (never `pkill -f`: that pattern also matches
# this very shell). If the daemon is dead, starts it instead.
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}"
PID_FILE="${PID_FILE:-$STATE_DIR/eye-break.pid}"
pid=$(cat "$PID_FILE" 2>/dev/null)
if [[ -n "$pid" ]] && grep -qa 'eye-break' "/proc/$pid/cmdline" 2>/dev/null; then
    kill -USR1 "$pid"
    sleep 0.3
    if [[ "$(cat "$STATE_DIR/health-rules.state" 2>/dev/null)" == off ]]; then
        notify-send -t 2000 "Health breaks" "Disabled" 2>/dev/null || true
    else
        notify-send -t 2000 "Health breaks" "Enabled" 2>/dev/null || true
    fi
else
    setsid -f "$HOME/.config/hypr/scripts/eye-break.sh" >/dev/null 2>&1
    notify-send -t 2000 "Health breaks" "Started" 2>/dev/null || true
fi
