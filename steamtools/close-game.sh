#!/bin/bash
# Emergency close of the running game under gamescope: force-kill the whole
# Proton/game process tree (by SteamLaunch AppId root) so Steam returns to the
# Gamepad UI. Steam itself is left running. (There is no compositor close
# under gamescope, so this is a force-kill by design.)
source "$(dirname "$0")/common.sh"
steam_env
LOG=/tmp/steamtools.log
get_game_pid
echo "$(date) close-game: game_pid=$GAME_PID" >> "$LOG"

if [ -z "$GAME_PID" ]; then
  echo "$(date) close-game: no game running (Steam or idle)" >> "$LOG"
  exit 0
fi

kill_tree "$GAME_PID"
echo "$(date) close-game: force-closed game (pid $GAME_PID)" >> "$LOG"
exit 0
