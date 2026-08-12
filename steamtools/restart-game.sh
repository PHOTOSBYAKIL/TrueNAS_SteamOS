#!/bin/bash
# Emergency force-close of the running game — use when it is frozen or hung.
# Kills the whole Proton/game process tree (by AppId root) so Steam returns to
# the Gamepad UI. Same engine as close-game.sh, kept separate so Moonlight
# users get a clearly-labelled "force restart" action.
source "$(dirname "$0")/common.sh"
steam_env
LOG=/tmp/steamtools.log
get_game_pid
echo "$(date) restart-game: game_pid=$GAME_PID" >> "$LOG"

if [ -z "$GAME_PID" ]; then
  echo "$(date) restart-game: no game running (Steam or idle)" >> "$LOG"
  exit 0
fi

kill_tree "$GAME_PID"
echo "$(date) restart-game: force-closed game (pid $GAME_PID, back to Steam)" >> "$LOG"
exit 0
