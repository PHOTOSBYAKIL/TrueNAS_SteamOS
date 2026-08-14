#!/bin/bash
# Restore the most recently minimized window — pairs with the title bar's
# minimize button, which moves the focused app to the sway scratchpad.
source "$(dirname "$0")/common.sh"
steam_env
LOG=/tmp/steamtools.log
echo "$(date) minimize-restore: showing scratchpad" >> "$LOG"
swaymsg scratchpad show >/dev/null 2>&1
exit 0
