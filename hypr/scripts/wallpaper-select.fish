#!/usr/bin/env fish
# Wallpaper Selector — uses fuzzel + caelestia
# Shows wallpaper list, lets you pick one, applies it

set WALLPAPER_DIR $HOME/.local/share/backgrounds

# Find all image files in wallpaper directory
set files (find "$WALLPAPER_DIR" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" -o -iname "*.bmp" \) | sort)

if test (count $files) -eq 0
    exit 1
end

# Show fuzzel menu with filenames
set selected (for f in $files
    set basename (basename "$f")
    if test (string length "$basename") -gt 50
        set basename (string sub -l 47 "$basename")"..."
    end
    echo "$basename"
end | fuzzel --dmenu --prompt "Wallpaper: " --lines 10 --width 60)

if test -z "$selected"
    exit 0
end

# Find the full path matching the selection
set full_path (string join \n $files | grep -F "$selected" | head -1)

if test -z "$full_path"
    exit 1
end

# Apply wallpaper
caelestia wallpaper -f "$full_path"
