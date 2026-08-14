#!/bin/bash
# Title-bar minimize/restore toggle — pairs with the waybar [–] button.
#   - A window is focused        → hide it (move to the sway scratchpad).
#   - Nothing is focused          → the app is minimized: restore it and re-tile
#                                  Steam so it fills the output under the bar.
source "$(dirname "$0")/common.sh"
steam_env
LOG=/tmp/steamtools.log
get_focused

if [ -z "$PID" ] || [ "$PID" -le 1 ]; then
  echo "$(date) minimize-toggle: nothing focused — restoring from scratchpad" >> "$LOG"
  swaymsg scratchpad show >/dev/null 2>&1
  swaymsg '[class="steam"] floating disable' >/dev/null 2>&1
else
  echo "$(date) minimize-toggle: hiding focused pid=$PID class=$CLASS" >> "$LOG"
  swaymsg move scratchpad >/dev/null 2>&1
fi
exit 0
