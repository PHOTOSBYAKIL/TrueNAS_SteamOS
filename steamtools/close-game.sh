#!/bin/bash
# Graceful close of the focused game: ask the window to close, wait up to
# 10s, then force-kill the process tree if it hangs. Steam is left running.
source "$(dirname "$0")/common.sh"
steam_env
LOG=/tmp/steamtools.log
get_focused
echo "$(date) close-game: pid=$PID class=$CLASS name=$NAME" >> "$LOG"

if [ -z "$PID" ] || [ "$PID" -le 1 ] || [[ "$CLASS" == steam ]]; then
  echo "$(date) close-game: nothing to close (Steam or empty window focused)" >> "$LOG"
  exit 0
fi

# Ask the compositor to close the window gracefully (WM_DELETE / Wayland close).
swaymsg kill >/dev/null 2>&1

for _ in $(seq 1 10); do
  if ! kill -0 "$PID" 2>/dev/null; then
    echo "$(date) close-game: closed gracefully (pid $PID)" >> "$LOG"
    exit 0
  fi
  sleep 1
done

echo "$(date) close-game: window closed but pid $PID still alive — force-killing tree" >> "$LOG"
kill_tree "$PID"
exit 0
