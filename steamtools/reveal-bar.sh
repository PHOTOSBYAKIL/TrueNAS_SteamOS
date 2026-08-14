#!/bin/bash
# Maximize recovery: drop the focused window out of fullscreen and make sure
# the title bar is visible again. Fullscreen only happens via the title bar's
# maximize button (sway hides the bar behind fullscreen windows), so this
# returns you to the tiled view with the title bar back on top.
source "$(dirname "$0")/common.sh"
steam_env
LOG=/tmp/steamtools.log
get_focused
echo "$(date) reveal-bar: class=$CLASS fullscreen=$FULLSCREEN" >> "$LOG"

swaymsg fullscreen disable >/dev/null 2>&1
killall -SIGUSR1 waybar 2>/dev/null
exit 0
