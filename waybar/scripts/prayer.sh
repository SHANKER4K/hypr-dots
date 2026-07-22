#!/bin/bash
# Prayer times for Waybar — uses aladhan.com API (free, no key)

CONFIG="$HOME/.config/waybar/prayer.conf"
CACHE="/tmp/prayer-times.json"

# Defaults (Egypt)
LAT=30.0444
LON=31.2357
METHOD=5
LOCK_DURATION=30

[[ -f "$CONFIG" ]] && while IFS='=' read -r k v; do
    case "$k" in
        latitude) LAT="$v" ;;
        longitude) LON="$v" ;;
        method) METHOD="$v" ;;
        lock_duration) LOCK_DURATION="$v" ;;
    esac
done < "$CONFIG"

# Fetch if cache is stale (>6h) or missing
if [[ ! -f "$CACHE" ]] || [[ $(($(date +%s) - $(stat -c %Y "$CACHE" 2>/dev/null || echo 0))) -gt 21600 ]]; then
    TODAY=$(date +%d-%m-%Y)
    DATA=$(curl -sf "https://api.aladhan.com/v1/timings/$TODAY?latitude=$LAT&longitude=$LON&method=$METHOD" 2>/dev/null)
    [[ -n "$DATA" ]] && echo "$DATA" > "$CACHE"
fi

if [[ ! -f "$CACHE" ]]; then
    echo '{"text":"﮲ ??:??","tooltip":"Offline","class":"prayer"}'
    exit 0
fi

# Extract prayer timings (strip seconds)
get_time() { jq -r ".data.timings.$1" "$CACHE" 2>/dev/null | cut -d: -f1-2; }
FAJR=$(get_time Fajr)
DHUHR=$(get_time Dhuhr)
ASR=$(get_time Asr)
MAGHRIB=$(get_time Maghrib)
ISHA=$(get_time Isha)

# ── Notifications ────────────────────────────────────────
NOTIFIED_FILE="/tmp/waybar-prayer-notified"
NOW=$(date +%s)
TODAY_DATE=$(date +%Y-%m-%d)

# Init or rotate state at midnight
if [[ ! -f "$NOTIFIED_FILE" ]] || [[ "$(head -1 "$NOTIFIED_FILE" 2>/dev/null)" != "$TODAY_DATE" ]]; then
    echo "$TODAY_DATE" > "$NOTIFIED_FILE"
fi

notify_prayer() {
    local name=$1 time_str=$2
    local epoch=$(date -d "$TODAY_DATE $time_str" +%s 2>/dev/null) || return
    local diff=$((epoch - NOW))

    # 10 min before
    if [[ "$diff" -gt 0 && "$diff" -le 600 ]]; then
        if ! grep -qx "${name}-10m" "$NOTIFIED_FILE" 2>/dev/null; then
            notify-send -t 5000 "🕌 $name" "Adhan in $((diff / 60)) minutes" 2>/dev/null || true
            echo "${name}-10m" >> "$NOTIFIED_FILE"
        fi
    fi

    # At prayer time (within 5 min window)
    if [[ "$diff" -le 0 && "$diff" -gt -300 ]]; then
        if ! grep -qx "${name}" "$NOTIFIED_FILE" 2>/dev/null; then
            notify-send -u critical -t 10000 "🕌 $name" "Prayer time now ﷽" 2>/dev/null || true
            echo "${name}" >> "$NOTIFIED_FILE"
            # Lock screen as a reminder (same SIGUSR1 unlock as eye-break)
            killall -q hyprlock 2>/dev/null || true
            (
                sleep 1
                hyprlock -c "$HOME/.config/hypr/prayer-lock.conf" &>/dev/null &
                HPID=$!
                sleep "$LOCK_DURATION"
                kill -SIGUSR1 "$HPID" 2>/dev/null || true
                wait "$HPID" 2>/dev/null || true
            ) &>/dev/null &
        fi
    fi
}

notify_prayer Fajr "$FAJR"
notify_prayer Dhuhr "$DHUHR"
notify_prayer Asr "$ASR"
notify_prayer Maghrib "$MAGHRIB"
notify_prayer Isha "$ISHA"

# ── Find next prayer ─────────────────────────────────────
next_name=""; next_time=""; next_epoch=0

check() {
    local name=$1 t=$2
    local epo=$(date -d "$TODAY_DATE $t" +%s 2>/dev/null)
    [[ -z "$epo" || "$epo" -le "$NOW" ]] && return
    if [[ -z "$next_name" ]] || [[ "$epo" -lt "$next_epoch" ]]; then
        next_name="$name"; next_time="$t"; next_epoch=$epo
    fi
}

check Fajr "$FAJR"
check Dhuhr "$DHUHR"
check Asr "$ASR"
check Maghrib "$MAGHRIB"
check Isha "$ISHA"

# If no next today, show Fajr tomorrow
if [[ -z "$next_name" ]]; then
    next_name="Fajr"; next_time="$FAJR"
    tomorrow=$(date -d "+1 day" +%Y-%m-%d)
    next_epoch=$(date -d "$tomorrow $FAJR" +%s 2>/dev/null)
fi

# Build times display
TIMES="Fajr    $FAJR\nDhuhr   $DHUHR\nAsr     $ASR\nMaghrib $MAGHRIB\nIsha    $ISHA"

# ── menu subcommand ──────────────────────────────────────
if [[ "$1" == "menu" ]]; then
    MENU="$TIMES"
    MENU="$MENU\n──────────────"
    MENU="$MENU\n⚙  Settings"
    CHOICE=$(echo -e "$MENU" | fuzzel -d -p "🕌  Prayer Times > " --lines 10 2>/dev/null)
    [[ -z "$CHOICE" ]] && exit 0
    if echo "$CHOICE" | grep -q "Settings"; then
        exec "$0" config
    fi
    exit 0
fi

# ── config subcommand ────────────────────────────────────
if [[ "$1" == "config" ]]; then
    NEW_LAT=$(echo "$LAT" | fuzzel -d -p "Latitude > " 2>/dev/null)
    [[ -z "$NEW_LAT" ]] && exit 0
    NEW_LON=$(echo "$LON" | fuzzel -d -p "Longitude > " 2>/dev/null)
    [[ -z "$NEW_LON" ]] && exit 0
    NEW_METHOD=$(echo "$METHOD" | fuzzel -d -p "Method (5=Egyptian, 3=MWL, 4=Umm Al-Qura) > " 2>/dev/null)
    [[ -z "$NEW_METHOD" ]] && exit 0
    NEW_LOCK=$(echo "$LOCK_DURATION" | fuzzel -d -p "Lock duration (seconds, 0=off) > " 2>/dev/null)
    [[ -z "$NEW_LOCK" ]] && exit 0
    cat > "$CONFIG" <<EOF
# Prayer times configuration
# Method: 2=ISNA, 3=Muslim World League, 4=Umm Al-Qura, 5=Egyptian, 8=Gulf, 9=Kuwait, 10=Qatar
# lock_duration: how many seconds the screen locks at prayer time (0 to disable)
latitude=$NEW_LAT
longitude=$NEW_LON
method=$NEW_METHOD
lock_duration=$NEW_LOCK
EOF
    rm -f "$CACHE"
    notify-send -t 3000 "Prayer Times" "Settings saved"
    exit 0
fi

# ── Waybar output ───────────────────────────────────────
REMAINING=$((next_epoch - NOW))
MIN=$((REMAINING / 60))
[[ "$MIN" -lt 60 ]] && REMAINING_TXT="${MIN}m" || REMAINING_TXT="$((MIN/60))h $((MIN%60))m"

TEXT="﮲ $next_name $next_time"
TOOLTIP="$TIMES\n──────────────\nNext: $next_name at $next_time (in $REMAINING_TXT)"

jq -cn --arg t "$TEXT" --arg tt "$TOOLTIP" '{"text":$t,"tooltip":$tt}'
