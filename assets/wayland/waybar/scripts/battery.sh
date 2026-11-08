#!/bin/sh
# Battery for the Android host, read from the Termux:API bridge in /tmp.
pct=100
state=unknown
if [ -r /tmp/lfa-android-battery.env ]; then
    # shellcheck disable=SC1090
    . /tmp/lfa-android-battery.env
    pct=${BATTERY_PERCENT:-100}
    state=${BATTERY_STATE:-unknown}
fi
case "$pct" in ''|*[!0-9]*) pct=100 ;; esac
if [ "$state" = "CHARGING" ] || [ "$state" = "FULL" ]; then
    icon="󰂄"
elif [ "$pct" -ge 90 ]; then icon="󰁹"
elif [ "$pct" -ge 70 ]; then icon="󰂁"
elif [ "$pct" -ge 50 ]; then icon="󰁿"
elif [ "$pct" -ge 30 ]; then icon="󰁽"
elif [ "$pct" -ge 10 ]; then icon="󰁻"
else icon="󰁺"
fi
printf '%s %s%%' "$icon" "$pct"
