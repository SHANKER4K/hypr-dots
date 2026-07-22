#!/usr/bin/env bash
# eye-break.sh — 20-20-20 Smart Eye Break Daemon
#
# Tracks cumulative active usage. After 20 minutes of active computer use,
# pauses all media and locks the screen for 20 seconds to enforce an eye break.
#
# Smart behaviour:
# - Only counts time when you're actively using the PC (not idle)
# - Resets counter if you step away for 2+ minutes (you already rested)
# - Pauses videos/music via playerctl
# - Locks screen with hyprlock (falls back to a notification if unavailable)
# - Never crashes: every command is error-checked, outer restart loop
#
# Lock release strategy:
#   1. Send SIGUSR1 → hyprlock explicitly unlocks session + exits (~5ms)
#   2. Poll up to 5s for process exit
#   3. SIGKILL only if hyprlock hangs (never happens in testing)
#   4. If SIGKILL was used: recovery cycle to reset ext-session-lock state

set -o pipefail
IFS=$'\n\t'

# ---- Configuration ----
readonly BREAK_INTERVAL=1200   # 20 minutes in seconds
readonly BREAK_DURATION=20     # Break duration in seconds
readonly IDLE_RESET=120        # Reset counter if idle this many seconds
readonly CHECK_INTERVAL=1      # Check every second
readonly LOCK_CONFIG="$HOME/.config/hypr/eye-break-lock.conf"
readonly LOG_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/eye-break.log"
readonly RECOVERY_LOCK_SECS=1.5

# ---- State ----
ACTIVE_SECONDS=0

# ---- Logging ----
log() {
    local level="${1:-INFO}"
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" >> "$LOG_FILE"
}

cleanup() {
    log "INFO" "Daemon shutting down"
    killall -q hyprlock 2>/dev/null || true
    command -v makoctl &>/dev/null && makoctl mode -r focus 2>/dev/null || true
    exit 0
}
trap cleanup SIGINT SIGTERM SIGHUP

# ---- Lock Helpers ----

start_lock() {
    hyprlock -c "$LOCK_CONFIG" &>/dev/null &
    echo $!
}

# Kill hyprlock gracefully using SIGUSR1 (hyprlock's unlock signal).
# Polls for exit, only uses SIGKILL as absolute last resort.
# Returns 0 if clean, 1 if SIGKILL was used.
kill_lock() {
    local PID=$1
    local USED_SIGKILL=false

    # Step 1: Send SIGUSR1 — hyprlock explicitly unlocks the session then exits
    kill -SIGUSR1 "$PID" 2>/dev/null || true

    # Step 2: Poll up to 5 seconds (25 × 0.2s)
    local waited=0
    while kill -0 "$PID" 2>/dev/null && [[ "$waited" -lt 25 ]]; do
        sleep 0.2
        waited=$((waited + 1))
    done

    # Step 3: Retry SIGUSR1 once
    if kill -0 "$PID" 2>/dev/null; then
        log "WARN" "hyprlock not exiting after SIGUSR1 (waited ${waited}s) — retrying"
        kill -SIGUSR1 "$PID" 2>/dev/null || true
        sleep 1
    fi

    # Step 4: Last resort — SIGKILL (this can corrupt ext-session-lock state)
    if kill -0 "$PID" 2>/dev/null; then
        log "WARN" "hyprlock ignoring SIGUSR1 — forcing SIGKILL"
        kill -9 "$PID" 2>/dev/null || true
        USED_SIGKILL=true
    fi

    wait "$PID" 2>/dev/null || true

    $USED_SIGKILL && return 1 || return 0
}

# Runs if SIGKILL was used. Spawns hyprlock again, sends SIGUSR1 to
# cleanly reset the ext-session-lock state. Only uses SIGUSR1, never SIGKILL.
recover_lock_state() {
    log "WARN" "Running session lock recovery (allow_session_lock_restore=true required)"
    killall -q hyprlock 2>/dev/null || true
    sleep 0.3

    local RECOVER_PID
    RECOVER_PID=$(start_lock)
    sleep "$RECOVERY_LOCK_SECS"

    # Only SIGUSR1 — this cleanup must be clean
    kill -SIGUSR1 "$RECOVER_PID" 2>/dev/null || true
    sleep 1

    local waited=0
    while kill -0 "$RECOVER_PID" 2>/dev/null && [[ "$waited" -lt 15 ]]; do
        sleep 0.2
        waited=$((waited + 1))
    done

    if kill -0 "$RECOVER_PID" 2>/dev/null; then
        log "ERROR" "Recovery hyprlock also hung — manual recovery may be needed"
    fi

    wait "$RECOVER_PID" 2>/dev/null || true
    killall -q hyprlock 2>/dev/null || true
    log "INFO" "Recovery complete"
}

# ---- Break Logic ----
take_break() {
    log "INFO" "=== 20-20-20 BREAK ==="

    # 1. Pause media
    if command -v playerctl &>/dev/null; then
        playerctl pause --all-players 2>/dev/null || true
        log "INFO" "Paused media players"
    fi

    # 2. Silence notifications during break
    local had_focus_mode=false
    if command -v makoctl &>/dev/null; then
        if makoctl mode 2>/dev/null | grep -q 'focus'; then
            had_focus_mode=true
        else
            makoctl mode -a focus 2>/dev/null || true
            log "INFO" "Enabled focus mode (notifications silenced)"
        fi
    fi

    # 3. Show notification
    notify-send -u critical -t "$((BREAK_DURATION * 1000))" \
        "👀 20-20-20 Eye Break" \
        "Look at something 20 feet (6m) away for ${BREAK_DURATION} seconds!" \
        2>/dev/null || true

    # 4. Lock screen
    if command -v hyprlock &>/dev/null; then
        log "INFO" "Locking screen for ${BREAK_DURATION}s"

        killall -q hyprlock 2>/dev/null || true

        local HPID
        HPID=$(start_lock)
        sleep "$BREAK_DURATION"

        if kill_lock "$HPID"; then
            log "INFO" "Lock released (SIGUSR1 — graceful)"
        else
            log "WARN" "SIGKILL was needed — running recovery"
            recover_lock_state
        fi

        killall -q hyprlock 2>/dev/null || true
    else
        log "WARN" "hyprlock not installed — notification-only"
        sleep "$BREAK_DURATION"
    fi

    # 5. Restore notifications
    command -v makoctl &>/dev/null && ! $had_focus_mode && \
        makoctl mode -r focus 2>/dev/null || true

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
    log "INFO" "=== Daemon Started ==="
    log "INFO" "Interval: ${BREAK_INTERVAL}s | Duration: ${BREAK_DURATION}s | Idle reset: ${IDLE_RESET}s"

    local idle_s=0
    local last_idle_s=0

    while true; do
        if ! idle_s=$(get_idle_seconds); then
            log "WARN" "Cannot get idle time (Hyprland not responding); retry in 5s"
            sleep 5
            continue
        fi

        if [[ "$idle_s" -lt "$IDLE_RESET" ]] && [[ "$last_idle_s" -lt "$IDLE_RESET" ]]; then
            ACTIVE_SECONDS=$((ACTIVE_SECONDS + CHECK_INTERVAL))
        elif [[ "$idle_s" -ge "$IDLE_RESET" ]]; then
            [[ "$ACTIVE_SECONDS" -gt 0 ]] && \
                log "INFO" "Idle ${idle_s}s — reset (was ${ACTIVE_SECONDS}s)"
            ACTIVE_SECONDS=0
        fi
        last_idle_s="$idle_s"

        [[ $((ACTIVE_SECONDS % 300)) -eq 0 ]] && [[ "$ACTIVE_SECONDS" -gt 0 ]] && \
            log "INFO" "Active: $((ACTIVE_SECONDS / 60))m | Next: $(((BREAK_INTERVAL - ACTIVE_SECONDS) / 60))m"

        if [[ "$ACTIVE_SECONDS" -ge "$BREAK_INTERVAL" ]]; then
            take_break
            ACTIVE_SECONDS=0
            sleep 2
        fi

        sleep "$CHECK_INTERVAL"
    done
}

# Outer restart loop
while true; do
    main
    log "ERROR" "Main loop exited unexpectedly — restarting in 5s"
    sleep 5
done
