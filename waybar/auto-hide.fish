#!/usr/bin/env fish
# Auto-hide for Waybar (bottom bar) — fixed scope
# Shows when cursor is near bottom edge, hides after 2s away

set -g HIDE_DELAY 0
set -g TRIGGER_PX 8
set -g POLL_INTERVAL 0.5
set -g DEBOUNCE_MS 500
set -g BUFFER_ZONE 30

set -g shown true
set -g last_move (date +%s%3N)
set -g screen_h 768
set -g last_toggle 0

function update_height
    set -g screen_h (hyprctl monitors -j 2>/dev/null | jq -r '.[0].height' 2>/dev/null)
    if test -z "$screen_h" -o "$screen_h" = "null"
        set -g screen_h 768
    end
end

function do_show
    set -l now (date +%s%3N)
    if test (math "$now - $last_toggle") -lt $DEBOUNCE_MS
        return
    end
    pkill -SIGUSR2 waybar 2>/dev/null; or true
    set -g shown true
    set -g last_toggle $now
end

function do_hide
    set -l now (date +%s%3N)
    if test (math "$now - $last_toggle") -lt $DEBOUNCE_MS
        return
    end
    pkill -SIGUSR1 waybar 2>/dev/null; or true
    set -g shown false
    set -g last_toggle $now
end

update_height

while true
    set -l pos (hyprctl cursorpos 2>/dev/null)
    if test -n "$pos"
        set -l y (echo $pos | cut -d',' -f2 | string trim)
        set -l dist (math "$screen_h - $y")

        if test "$dist" -le "$TRIGGER_PX"
            # Near bottom edge → show
            if not $shown
                do_show
            end
            set -g last_move (date +%s%3N)
        else if test "$dist" -le (math "$TRIGGER_PX + $BUFFER_ZONE")
            # In buffer zone → still near, update timer
            set -g last_move (date +%s%3N)
        else
            # Far from edge → hide after delay
            set -l now (date +%s%3N)
            if test (math "$now - $last_move") -ge "$HIDE_DELAY"
                if $shown
                    do_hide
                end
            end
        end
    end
    sleep $POLL_INTERVAL
end
