#!/usr/bin/env fish
# notification.fish — Manage mako notifications
# Usage:
#   notification.fish dnd     Toggle Do-Not-Disturb (silence all)
#   notification.fish focus   Toggle Focus mode (only critical)
#   notification.fish history Show last dismissed notification
#   notification.fish status  Output JSON for waybar

set -g MODE_DND "dnd"
set -g MODE_FOCUS "focus"

function _get_state
    set modes (makoctl mode 2>/dev/null || echo "")
    if string match -q "*$MODE_DND*" -- $modes
        echo "dnd"
    else if string match -q "*$MODE_FOCUS*" -- $modes
        echo "focus"
    else
        echo "normal"
    end
end

switch $argv[1]
    case dnd
        # Toggle Do-Not-Disturb
        if test (_get_state) = dnd
            makoctl mode -r $MODE_DND
            notify-send -u low -i dialog-information \
                "🔔 Notifications: ON" "Do Not Disturb disabled"
        else
            makoctl mode -a $MODE_DND
            notify-send -u low -i dialog-information \
                "🔕 Notifications: OFF" "Do Not Disturb enabled"
        end

    case focus
        # Toggle Focus mode (only critical notifications through)
        if test (_get_state) = focus
            makoctl mode -r $MODE_FOCUS
            notify-send -u low -i dialog-information \
                "🔔 Focus: OFF" "All notifications restored"
        else
            # Remove DND if active, set focus mode
            makoctl mode -r $MODE_DND
            makoctl mode -a $MODE_FOCUS
            notify-send -u low -i dialog-information \
                "🧘 Focus: ON" "Only critical notifications"
        end

    case history
        # Restore the most recently dismissed notification
        makoctl restore 2>/dev/null
        or notify-send -u low -i dialog-information \
            "📋 Notification history" "No dismissed notifications"

    case status
        # JSON output for waybar
        set state (_get_state)
        switch $state
            case dnd
                echo '{"text": "🔕", "tooltip": "Do Not Disturb (all muted)", "class": "dnd"}'
            case focus
                echo '{"text": "🧘", "tooltip": "Focus mode (critical only)", "class": "focus"}'
            case normal
                echo '{"text": "🔔", "tooltip": "Notifications active", "class": "normal"}'
        end

    case '*'
        echo "Usage: $argv[0] {dnd|focus|history|status}"
        exit 1
end
