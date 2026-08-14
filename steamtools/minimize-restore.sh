#!/bin/bash
# Restore the most recently minimized window — pairs with the title bar's
# minimize button, which moves the focused app to the sway scratchpad.
# The scratchpad round-trip leaves the window floating:user_on at a small size,
# so re-tile Steam so it fills the output under the title bar again.
source "$(dirname "$0")/common.sh"
steam_env
LOG=/tmp/steamtools.log
echo "$(date) minimize-restore: showing scratchpad" >> "$LOG"
swaymsg scratchpad show >/dev/null 2>&1
swaymsg '[class="steam"] floating disable' >/dev/null 2>&1
exit 0
