#!/usr/bin/env fish
# Post-hook for Caelestia — updates swaybg when wallpaper changes
set WALLPAPER (cat ~/.local/state/caelestia/wallpaper/path.txt 2>/dev/null)
if test -n "$WALLPAPER" -a -f "$WALLPAPER"
    # Kill old swaybg gracefully
    pkill swaybg 2>/dev/null
    # Start new one
    swaybg -i "$WALLPAPER" -m fill &
    disown
end
