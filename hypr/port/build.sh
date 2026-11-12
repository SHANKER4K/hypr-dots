#!/usr/bin/env bash
# Regenerate + install hyprland.lua from the hyprlang rice (Hyprland 0.57+).
#   build.sh            regenerate, verify, install, reload
#   build.sh --dry-run  regenerate + verify only
set -euo pipefail
cd "$(dirname "$0")"

if [[ "${1:-}" == "--dry-run" ]]; then
    exec python3 build.py
fi

python3 build.py --install
exec hyprctl reload
