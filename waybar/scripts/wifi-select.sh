#!/bin/bash
# WiFi network selector using fuzzel + nmcli

IFACE=$(ip route | awk '/default/ {print $5; exit}')
[[ -z "$IFACE" ]] && exit 0

# Check WiFi radio state
WIFI_ON=$(nmcli radio wifi 2>/dev/null)

# Get current SSID from active connection
CURRENT_SSID=$(nmcli -t connection show --active 2>/dev/null | awk -F: "/:${IFACE}$/ {print \$1}")

# Build menu
MENU=""
if [[ "$WIFI_ON" == "enabled" ]]; then
    MENU="睊  Turn WiFi off"
    [[ -n "$CURRENT_SSID" ]] && MENU="$MENU\nDisconnect from $CURRENT_SSID"
else
    MENU="  Turn WiFi on"
fi

while IFS=: read -r ssid signal security; do
    [[ -z "$ssid" || "$ssid" == "SSID" ]] && continue
    if   (( signal >= 80 )); then ICON="󰤨"
    elif (( signal >= 60 )); then ICON="󰤥"
    elif (( signal >= 40 )); then ICON="󰤢"
    elif (( signal >= 20 )); then ICON="󰤟"
    else ICON="󰤫"
    fi
    [[ "$ssid" == "$CURRENT_SSID" ]] && ICON="󰤪"
    MENU="$MENU\n$ICON $ssid ($signal%)"
done < <(nmcli -t -f SSID,SIGNAL,SECURITY device wifi list 2>/dev/null)

SELECTED=$(echo -e "$MENU" | sed '1{/^$/d;}' | fuzzel -d -p "WiFi > " --lines 15 2>/dev/null)
[[ -z "$SELECTED" ]] && exit 0

# Handle toggle / disconnect
if echo "$SELECTED" | grep -q "Turn WiFi off"; then
    nmcli radio wifi off
    notify-send -t 3000 "WiFi" "WiFi turned off"
    exit 0
fi
if echo "$SELECTED" | grep -q "Turn WiFi on"; then
    nmcli radio wifi on
    notify-send -t 3000 "WiFi" "WiFi turned on"
    exit 0
fi
if echo "$SELECTED" | grep -q "^Disconnect"; then
    nmcli connection down "$CURRENT_SSID" 2>/dev/null
    notify-send -t 3000 "WiFi" "Disconnected from $CURRENT_SSID"
    exit 0
fi

# Extract SSID
SELECTED_SSID=$(echo "$SELECTED" | sed 's/.* \([^ ]*\) (.*/\1/')

notify-send -t 5000 "WiFi" "Connecting to $SELECTED_SSID..."
if nmcli device wifi connect "$SELECTED_SSID" 2>/tmp/wifi-err.log; then
    notify-send -t 3000 "WiFi" "Connected to $SELECTED_SSID"
else
    ERR=$(cat /tmp/wifi-err.log)
    PASSWORD=$(echo "" | fuzzel -d -p "Password for $SELECTED_SSID > " 2>/dev/null)
    if [[ -n "$PASSWORD" ]]; then
        nmcli device wifi connect "$SELECTED_SSID" password "$PASSWORD" && \
            notify-send -t 3000 "WiFi" "Connected to $SELECTED_SSID" || \
            notify-send -u critical -t 5000 "WiFi" "Wrong password?"
    else
        notify-send -u critical -t 5000 "WiFi" "Failed: $(echo "$ERR" | head -1)"
    fi
fi
