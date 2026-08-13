#!/bin/bash
# Reveal the recovery toolbar over the fullscreen gamescope surface.
# gamescope nested is a single fullscreen surface under sway, so un-fullscreen
# it and the layer-top waybar becomes visible and clickable above it. Also
# un-hide the bar if it was minimized (SIGUSR1 toggles waybar visibility).
source "$(dirname "$0")/common.sh"
steam_env
LOG=/tmp/steamtools.log
echo "$(date) reveal-bar: un-fullscreening gamescope surface" >> "$LOG"
swaymsg fullscreen disable >/dev/null 2>&1
killall -SIGUSR1 waybar 2>/dev/null
exit 0
