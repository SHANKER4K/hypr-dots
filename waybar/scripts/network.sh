#!/bin/bash
# WiFi/ethernet status: icon + SSID, tooltip has traffic + IP
# Click action opens WiFi selector (wifi-select.sh)

IFACE=$(ip route | awk '/default/ {print $5; exit}')
NOW=$(date +%s%N)

RX_NOW=$(cat "/sys/class/net/$IFACE/statistics/rx_bytes" 2>/dev/null || echo 0)
TX_NOW=$(cat "/sys/class/net/$IFACE/statistics/tx_bytes" 2>/dev/null || echo 0)

CACHE=/tmp/.waybar_net_cache
RX_RATE=0; TX_RATE=0
if [[ -f $CACHE ]]; then
    read -r PREV_T PREV_RX PREV_TX < "$CACHE"
    ELAPSED=$(( (NOW - PREV_T) / 1000000000 ))
    (( ELAPSED > 0 )) && { RX_RATE=$(( (RX_NOW - PREV_RX) / ELAPSED )); TX_RATE=$(( (TX_NOW - PREV_TX) / ELAPSED )); }
fi
echo "$NOW $RX_NOW $TX_NOW" > "$CACHE"
(( RX_RATE < 0 )) && RX_RATE=0
(( TX_RATE < 0 )) && TX_RATE=0

fmt() { local b=$1
    (( b >= 1073741824 )) && { echo "$((b/1073741824))G"; return; }
    (( b >= 1048576 )) && { echo "$((b/1048576))M"; return; }
    (( b >= 1024 )) && { echo "$((b/1024))K"; return; }
    echo "${b}B"; }
UP=$(fmt $TX_RATE); DOWN=$(fmt $RX_RATE)

if [[ -z "$IFACE" ]]; then
    jq -cn '{"text":" offline","tooltip":"No network"}'
    exit 0
fi

IP=$(ip -4 addr show "$IFACE" 2>/dev/null | awk '/inet / {print $2; exit}')
IP="${IP:-N/A}"
TOOLTIP="$IFACE  |   $UP   $DOWN  |  IP: $IP"

# Check if WiFi
IFACE_TYPE=$(nmcli -t -f DEVICE,TYPE device status 2>/dev/null | grep "^${IFACE}:" | cut -d: -f2)

if [[ "$IFACE_TYPE" == "wifi" ]]; then
    SSID=$(nmcli -t connection show --active 2>/dev/null | awk -F: "/:${IFACE}$/ {print \$1}")
    if [[ -n "$SSID" ]]; then
        SIGNAL=$(nmcli -t -f SSID,SIGNAL device wifi list 2>/dev/null | grep "^${SSID}:" | cut -d: -f2)
        TEXT=""
        TOOLTIP="SSID: $SSID  |  Signal: ${SIGNAL:-?}%  |  $TOOLTIP"
    else
        TEXT=" ?"
    fi
else
    TEXT="󰀂"
fi

jq -cn --arg t "$TEXT" --arg tt "$TOOLTIP" '{"text":$t,"tooltip":$tt}'
