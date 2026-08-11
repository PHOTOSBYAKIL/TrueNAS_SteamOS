#!/bin/bash
# Reveal the recovery toolbar over a frozen fullscreen game.
# Waybar sits on layer "top", which sway hides behind fullscreen windows — so
# drop the focused game out of fullscreen and the bar becomes visible and
# clickable above it. Also un-hide the bar if it was minimized (SIGUSR1
# toggles waybar visibility, see waybar(5) SIGNALS).
source "$(dirname "$0")/common.sh"
steam_env
LOG=/tmp/steamtools.log
get_focused
echo "$(date) reveal-bar: class=$CLASS fullscreen=$FULLSCREEN" >> "$LOG"

# Only un-fullscreen actual games (steam_app_*), never Steam itself.
if [[ "$CLASS" == steam_app_* ]]; then
  swaymsg fullscreen disable >/dev/null 2>&1
fi
killall -SIGUSR1 waybar 2>/dev/null
exit 0
