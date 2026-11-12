#!/usr/bin/env bash
# eye-break.sh — 20-20-20 & 30-5 Health Break Daemon
#
# Two break rules sharing one active-time tracker (polls Hyprland idle):
#   20-20: after 20 min active -> pause media, lock 20 s ("rest your eyes")
#   30-5 : after 30 min active -> pause media, lock 5 min ("get up and walk")
# Each rule resets only its own timer: with both on, eyes fires @20m,
# walk @30m, eyes @40m, ...
#
# Smart behaviour (unchanged):
# - Only counts time when actively using the PC (not idle)
# - Resets counters if you step away for 2+ minutes
# - Pauses media, silences notifications during a break
# - Never crashes: error-checked commands, outer restart loop
#
# Toggle: kill -USR1 <pid> flips BOTH rules on/off, resets both timers,
# and persists the state to HEALTH_STATE (absent file = on). The waybar
# "custom/health" button just sends this signal and reads the file.
#
# Lock release strategy (unchanged):
#   1. SIGUSR1 -> hyprlock unlocks the session + exits
#   2. Poll up to 5 s
#   3. SIGKILL only if hyprlock hangs (never happens in testing)
#
# We only ever signal hyprlock processes WE started (tracked PIDs), never
# another session's lock (caelestia lock, prayer lock). If a foreign
# hyprlock session is active when a break is due, the break is deferred
# until it clears or skipped -- never force-unlocked.

set -o pipefail
IFS=$'\n\t'

# ---- Configuration (env-overridable for testing) ----
: "${BREAK_INTERVAL:=1200}"    # 20 minutes active -> eye break
: "${BREAK_DURATION:=20}"      # eye break length, seconds
: "${WALK_INTERVAL:=1800}"     # 30 minutes active -> walk break
: "${WALK_DURATION:=300}"      # walk break length, seconds
: "${IDLE_RESET:=120}"         # reset counters if idle this many seconds
: "${CHECK_INTERVAL:=1}"
: "${LOCK_CONFIG:=$HOME/.config/hypr/eye-break-lock.conf}"
: "${HEALTH_STATE:=${XDG_STATE_HOME:-$HOME/.local/state}/health-rules.state}"
: "${LOG_FILE:=${XDG_STATE_HOME:-$HOME/.local/state}/eye-break.log}"
: "${PID_FILE:=${XDG_STATE_HOME:-$HOME/.local/state}/eye-break.pid}"
readonly RECOVERY_LOCK_SECS=1.5

# ---- State ----
EYE_SECONDS=0
WALK_SECONDS=0
SILENCED=false
LOCK_PID=""
ABORT_BREAK=false

# ---- Logging ----
log() {
    local level="${1:-INFO}"
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" >> "$LOG_FILE"
}

rules_on() {
    [[ "$(cat "$HEALTH_STATE" 2>/dev/null)" != off ]]
}

# Interruptible sleep: a plain `sleep` would delay trap handlers (the waybar
# toggle) until it finishes -- up to 5 min during a walk break.
nap() {
    sleep "$1" &
    wait $! 2>/dev/null
}

cleanup() {
    log "INFO" "Daemon shutting down"
    rm -f "$PID_FILE"
    [[ -n "$LOCK_PID" ]] && kill -SIGUSR1 "$LOCK_PID" 2>/dev/null
    command -v makoctl &>/dev/null && makoctl mode -r focus 2>/dev/null || true
    exit 0
}
trap cleanup SIGINT SIGTERM SIGHUP

toggle() {
    if rules_on; then
        echo off > "$HEALTH_STATE"
        log "INFO" "Rules DISABLED (toggle) -- timers wiped"
    else
        echo on > "$HEALTH_STATE"
        log "INFO" "Rules ENABLED (toggle) -- timers wiped"
    fi
    EYE_SECONDS=0
    WALK_SECONDS=0
    ABORT_BREAK=true    # toggling mid-break ends it immediately
}
trap toggle SIGUSR1

# ---- Lock Helpers ----

start_lock() {
    local conf="${1:-$LOCK_CONFIG}"
    hyprlock -c "$conf" &>/dev/null &
    echo $!
}

# Kill hyprlock gracefully using SIGUSR1 (hyprlock's unlock signal).
# Polls for exit, only uses SIGKILL as absolute last resort.
# Returns 0 if clean, 1 if SIGKILL was used.
kill_lock() {
    local PID=$1
    local USED_SIGKILL=false

    # Step 1: Send SIGUSR1 -- hyprlock explicitly unlocks the session then exits
    kill -SIGUSR1 "$PID" 2>/dev/null || true

    # Step 2: Poll up to 5 seconds (25 x 0.2s)
    local waited=0
    while kill -0 "$PID" 2>/dev/null && [[ "$waited" -lt 25 ]]; do
        sleep 0.2
        waited=$((waited + 1))
    done

    # Step 3: Retry SIGUSR1 once
    if kill -0 "$PID" 2>/dev/null; then
        log "WARN" "hyprlock not exiting after SIGUSR1 (waited ${waited}s) -- retrying"
        kill -SIGUSR1 "$PID" 2>/dev/null || true
        sleep 1
    fi

    # Step 4: Last resort -- SIGKILL (this can corrupt ext-session-lock state)
    if kill -0 "$PID" 2>/dev/null; then
        log "WARN" "hyprlock ignoring SIGUSR1 -- forcing SIGKILL"
        kill -9 "$PID" 2>/dev/null || true
        USED_SIGKILL=true
    fi

    wait "$PID" 2>/dev/null || true

    $USED_SIGKILL && return 1 || return 0
}

# Runs if SIGKILL was used. Spawns hyprlock again, sends SIGUSR1 to
# cleanly reset the ext-session-lock state. Only uses SIGUSR1, never SIGKILL.
# ponytail: killall here is untracked-PID collateral we accept -- it only
# ever runs after WE had to SIGKILL our own lock; a foreign lock starting
# exactly in that window is vanishingly rare.
recover_lock_state() {
    log "WARN" "Running session lock recovery (allow_session_lock_restore=true required)"
    killall -q hyprlock 2>/dev/null || true
    sleep 0.3

    local RECOVER_PID
    RECOVER_PID=$(start_lock)
    sleep "$RECOVERY_LOCK_SECS"

    # Only SIGUSR1 -- this cleanup must be clean
    kill -SIGUSR1 "$RECOVER_PID" 2>/dev/null || true
    sleep 1

    local waited=0
    while kill -0 "$RECOVER_PID" 2>/dev/null && [[ "$waited" -lt 15 ]]; do
        sleep 0.2
        waited=$((waited + 1))
    done

    if kill -0 "$RECOVER_PID" 2>/dev/null; then
        log "ERROR" "Recovery hyprlock also hung -- manual recovery may be needed"
    fi

    wait "$RECOVER_PID" 2>/dev/null || true
    killall -q hyprlock 2>/dev/null || true
    log "INFO" "Recovery complete"
}

# Should we start our own lock right now? A foreign hyprlock session
# (caelestia lock, prayer lock) means breaking would be pointless or rude --
# defer up to 3 min, then give up (skip this break).
# ponytail: poll-and-give-up instead of a proper interlock; ceiling is a
# 3-min stall of the daemon loop while you're intentionally locked.
wait_lock_clear() {
    local waited=0
    while pgrep -x hyprlock >/dev/null 2>&1 && [[ $waited -lt 180 ]]; do
        log "INFO" "Another hyprlock session is active -- break deferred"
        nap 30
        waited=$((waited + 30))
    done
    ! pgrep -x hyprlock >/dev/null 2>&1
}

# ---- Break Logic ----
# take_break DURATION TITLE SUBTITLE -- pauses media, silences notifs,
# notifies, locks. Does NOT touch any rule timer.

take_break() {
    local DURATION=$1 TITLE=$2 SUBTITLE=$3
    local LOCK_CONF="${4:-$LOCK_CONFIG}"
    ABORT_BREAK=false
    log "INFO" "=== ${TITLE} ==="

    # 1. Pause media
    if command -v playerctl &>/dev/null; then
        playerctl pause --all-players 2>/dev/null || true
        log "INFO" "Paused media players"
    fi

    # 2. Silence notifications during break (only if not already silenced)
    if command -v makoctl &>/dev/null && ! $SILENCED; then
        makoctl mode -a focus 2>/dev/null || true
        SILENCED=true
        log "INFO" "Enabled focus mode (notifications silenced)"
    fi

    # 3. Show notification
    notify-send -u critical -t "$((DURATION * 1000))" "$TITLE" "$SUBTITLE" \
        2>/dev/null || true

    # 4. Lock screen (only our own hyprlock instance is ever signalled)
    if command -v hyprlock &>/dev/null && wait_lock_clear; then
        log "INFO" "Locking screen for ${DURATION}s"
        LOCK_PID=$(start_lock "$LOCK_CONF")
        local end=$((SECONDS + DURATION))
        while [[ $SECONDS -lt $end ]] && ! $ABORT_BREAK; do nap 1; done

        if kill_lock "$LOCK_PID"; then
            log "INFO" "Lock released (SIGUSR1 -- graceful)"
        else
            log "WARN" "SIGKILL was needed -- running recovery"
            recover_lock_state
        fi
        LOCK_PID=""
    else
        log "WARN" "hyprlock missing or foreign lock stuck -- notification-only"
        local end=$((SECONDS + DURATION))
        while [[ $SECONDS -lt $end ]] && ! $ABORT_BREAK; do nap 1; done
    fi

    # 5. Restore notifications (only if we were the ones who silenced them)
    if $SILENCED && command -v makoctl &>/dev/null; then
        makoctl mode -r focus 2>/dev/null || true
        SILENCED=false
    fi

    log "INFO" "Break finished"
}

# ---- Idle Detection ----
get_idle_seconds() {
    local idle_ms=0
    local monitor_data
    monitor_data=$(hyprctl monitors -j 2>/dev/null) || return 1
    idle_ms=$(echo "$monitor_data" | jq -r '.[0].idleTime // 0' 2>/dev/null) || return 1
    [[ "$idle_ms" =~ ^[0-9]+$ ]] || idle_ms=0
    echo $(( (idle_ms + 999) / 1000 ))
    return 0
}

# ---- Main Loop ----
main() {
    mkdir -p "$(dirname "$HEALTH_STATE")"
    [[ -f "$HEALTH_STATE" ]] || echo on > "$HEALTH_STATE"

    log "INFO" "=== Daemon Started ==="
    log "INFO" "Eye: ${BREAK_INTERVAL}s->${BREAK_DURATION}s | Walk: ${WALK_INTERVAL}s->${WALK_DURATION}s | Idle reset: ${IDLE_RESET}s | Rules: $(rules_on && echo on || echo off)"

    local idle_s=0
    local last_idle_s=0

    while true; do
        if ! idle_s=$(get_idle_seconds); then
            log "WARN" "Cannot get idle time (Hyprland not responding); retry in 5s"
            nap 5
            continue
        fi

        if [[ "$idle_s" -ge "$IDLE_RESET" ]]; then
            if [[ $((EYE_SECONDS + WALK_SECONDS)) -gt 0 ]]; then
                log "INFO" "Idle ${idle_s}s -- reset (eye ${EYE_SECONDS}s, walk ${WALK_SECONDS}s)"
            fi
            EYE_SECONDS=0
            WALK_SECONDS=0
        elif [[ "$last_idle_s" -lt "$IDLE_RESET" ]] && rules_on; then
            EYE_SECONDS=$((EYE_SECONDS + CHECK_INTERVAL))
            WALK_SECONDS=$((WALK_SECONDS + CHECK_INTERVAL))
        fi
        last_idle_s="$idle_s"

        [[ $((WALK_SECONDS % 300)) -eq 0 ]] && [[ "$WALK_SECONDS" -gt 0 ]] && \
            log "INFO" "Active: eye $((EYE_SECONDS / 60))m | walk $((WALK_SECONDS / 60))m"

        if [[ "$WALK_SECONDS" -ge "$WALK_INTERVAL" ]]; then
            take_break "$WALK_DURATION" "🚶 وقت المشي" "انهض وامشِ لمدة 5 دقائق" "$HOME/.config/hypr/walk-break-lock.conf"
            WALK_SECONDS=0
            nap 2
        elif [[ "$EYE_SECONDS" -ge "$BREAK_INTERVAL" ]]; then
            take_break "$BREAK_DURATION" "👀 وقت راحة العين" "ارح عينيك انظر بعيدا لمدة 20 ثانية، لا تنسى ذكر الله"
            EYE_SECONDS=0
            nap 2
        fi

        nap "$CHECK_INTERVAL"
    done
}

# Single instance + pidfile (waybar's click handler signals this PID; matching
# `pkill -f eye-break.sh` also hit the click handler's own shell).
if [[ -r "$PID_FILE" ]] && old=$(<"$PID_FILE") && [[ -n "$old" ]] && \
   [[ "$old" != "$$" ]] && grep -qa 'eye-break' "/proc/$old/cmdline" 2>/dev/null; then
    echo "eye-break.sh already running (pid $old)" >&2
    exit 0
fi
mkdir -p "$(dirname "$PID_FILE")"
echo $$ > "$PID_FILE"

# Outer restart loop
while true; do
    main
    log "ERROR" "Main loop exited unexpectedly -- restarting in 5s"
    nap 5
done
