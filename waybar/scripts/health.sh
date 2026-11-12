#!/usr/bin/env bash
# Status text for the waybar `custom/health` module.
# State file is written by eye-break.sh (kill -USR1 eye-break.sh toggles).
# HEALTH_PGREP overrides the daemon-detection pattern (used by tests).

STATE="${XDG_STATE_HOME:-$HOME/.local/state}/health-rules.state"
PGREP_PATTERN="${HEALTH_PGREP:-eye-break\.sh}"
RULES="20min eye break / 30min walk break"

if [[ "$(cat "$STATE" 2>/dev/null)" == off ]]; then
    echo '{"text":"⏸","tooltip":"Health rule ('"$RULES"'): OFF\nClick to enable"}'
elif pgrep -f "$PGREP_PATTERN" >/dev/null 2>&1; then
    echo '{"text":"👀","tooltip":"Health rule ('"$RULES"'): ON\nClick to disable"}'
else
    echo '{"text":"⚠","tooltip":"eye-break daemon NOT running!\nRestart it (or keep state off)"}'
fi
