#!/usr/bin/env fish

if test "$argv[1]" = '-g'
    set group
    set -e $argv[1]
end

if test (count $argv) -ne 2
    echo 'Wrong number of arguments. Usage: ./wsaction.fish [-g] <dispatcher> <workspace>'
    exit 1
end

set -l active_ws (hyprctl activeworkspace -j | jq -r '.id')

set -l target
if set -q group
    # Move to group
    set target (math "($argv[2] - 1) * 10 + $active_ws % 10")
else
    # Move to ws in group
    set target (math "floor(($active_ws - 1) / 10) * 10 + $argv[2]")
end

# Hyprland 0.57 parses `hyprctl dispatch` args as Lua; the legacy
# `dispatch workspace N` form is a syntax error now. Mapped to the hl.dsp API
# (see 0.57 src/config/lua/bindings/LuaBindingsDispatchers.cpp):
#   workspace              -> hl.dsp.focus({workspace = N})
#   movetoworkspace        -> hl.dsp.window.move({workspace = N, follow = true})
#   movetoworkspacesilent  -> hl.dsp.window.move({workspace = N, follow = false})
switch $argv[1]
    case workspace
        hyprctl dispatch "hl.dsp.focus({workspace = $target})"
    case movetoworkspace
        hyprctl dispatch "hl.dsp.window.move({workspace = $target, follow = true})"
    case movetoworkspacesilent
        hyprctl dispatch "hl.dsp.window.move({workspace = $target, follow = false})"
    case '*'
        echo "wsaction.fish: no 0.57 Lua mapping for dispatcher '$argv[1]'" >&2
        exit 1
end
