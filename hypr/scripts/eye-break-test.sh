#!/usr/bin/env bash
# Self-check for eye-break.sh (20-20 & 30-5 rules) + the waybar health.sh module.
# Run directly: ~/.config/hypr/scripts/eye-break-test.sh   (~60s)
#
# Sandboxed: ~8s/18s intervals, stub hyprctl (always "active", idle=0) and a
# stub hyprlock (blocks 60s, killed by our SIGUSR1). The daemon runs from a
# renamed copy ("eye-break-sandbox.sh") so the test's health.sh assertions,
# and the production daemon running in parallel, can't confuse each other.
# Asserts: eye break fires, toggle flips state + wipes timers, break
# disabled-then-re-enabled fires again, health.sh shows on/off/dead states.
# Exits non-zero on failure.

set -euo pipefail
BASE="$HOME/.config/hypr"; export BASE
T="$(mktemp -d /tmp/opencode/eye-break-test.XXXXXX)"
DAEMON=""
trap '[[ -n "$DAEMON" ]] && { kill "$DAEMON" 2>/dev/null; wait "$DAEMON" 2>/dev/null; }; s=$?; [[ $s -eq 0 ]] && rm -rf "$T" || echo "sandbox kept: $T"' EXIT

# --- sandboxes ---
mkdir "$T/bin"
printf '#!/usr/bin/env bash\necho "$*" >> "$STUB_LOG"\nexec sleep 60\n' > "$T/bin/hyprlock"
printf '#!/usr/bin/env bash\necho "[{\\"idleTime\\": 0}]"\n' > "$T/bin/hyprctl"   # never idle -> active ticks
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/bin/makoctl"    # hermetic: don't touch real notif daemon
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/bin/notify-send"
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/bin/playerctl"
chmod +x "$T/bin/hyprlock" "$T/bin/hyprctl" "$T/bin/makoctl" "$T/bin/notify-send" "$T/bin/playerctl"
touch "$T/lock.cfg" "$T/lock-calls.log"
cp "$BASE/scripts/eye-break.sh" "$T/eye-break-sandbox.sh"

export PATH="$T/bin:$PATH" XDG_STATE_HOME="$T"
export LOCK_CONFIG="$T/lock.cfg" STUB_LOG="$T/lock-calls.log"
export BREAK_INTERVAL=8 BREAK_DURATION=1 WALK_INTERVAL=18 WALK_DURATION=1
export IDLE_RESET=9999 CHECK_INTERVAL=1
STATE="$T/health-rules.state" LOG="$T/eye-break.log"

health_text() { HEALTH_PGREP='eye-break-sandbox\.sh' "$HOME/.config/waybar/scripts/health.sh" \
    | grep -oE '"text":"[^"]*"' | head -1; }
fail() { echo "FAIL: $1"; exit 1; }

# daemon (sandbox copy) not yet running -> warning icon
# kill orphans from previous failed runs first — they'd fake the pgrep check
pkill -f 'eye-break-sandbox\.sh' 2>/dev/null || true
[[ "$(health_text)" == '"text":"⚠"' ]] || fail "health.sh should warn when sandbox daemon is dead"

bash "$T/eye-break-sandbox.sh" & DAEMON=$!
sleep 0.3
[[ "$(cat "$STATE" 2>/dev/null)" == "on" ]] || fail "state file should default to on"
[[ "$(health_text)" == '"text":"👀"' ]] || fail "health.sh should show ON while daemon runs"

# eye break at 8s active
sleep 10
grep -q "=== 👀" "$LOG" || fail "eye break never fired"

# toggle OFF via USR1 -> timers wiped; no break in the next ~27s (>= eye interval)
kill -USR1 "$DAEMON"; sleep 2
[[ "$(cat "$STATE")" == "off" ]] || fail "toggle should write 'off'"
[[ "$(health_text)" == '"text":"⏸"' ]] || fail "health.sh should show OFF"
sleep 27
[[ "$(grep -c '=== 👀\|=== 🚶' "$LOG")" -eq 1 ]] || fail "break fired while rules OFF"

# toggle ON -> eye break re-arms within 8s
kill -USR1 "$DAEMON"; sleep 2
[[ "$(cat "$STATE")" == "on" ]] || fail "toggle should write 'on'"
sleep 10
[[ "$(grep -c '=== 👀\|=== 🚶' "$LOG")" -ge 2 ]] || fail "eye break didn't re-fire after enable"

echo "PASS: eye-break-test"
