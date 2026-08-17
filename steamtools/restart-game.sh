#!/bin/bash
# Emergency force-close of the focused game — use when it is frozen or hung
# and ignores the graceful close. Kills the whole Proton/game process tree
# (by AppId root) so Steam returns to Big Picture.
source "$(dirname "$0")/common.sh"
steam_env
LOG=/tmp/steamtools.log
get_focused
echo "$(date) restart-game: pid=$PID class=$CLASS name=$NAME" >> "$LOG"

if [ -z "$PID" ] || [ "$PID" -le 1 ] || [[ "$CLASS" == steam ]]; then
  echo "$(date) restart-game: nothing to close (Steam or empty window focused)" >> "$LOG"
  exit 0
fi

kill_tree "$PID"
echo "$(date) restart-game: force-closed pid $PID (back to Steam)" >> "$LOG"
sleep 0.3
swaymsg workspace 1
exit 0
