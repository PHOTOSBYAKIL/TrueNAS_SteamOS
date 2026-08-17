#!/bin/bash
# Close the focused app. For a game: ask the window to close, wait up to 10s,
# then force-kill the process tree if it hangs (Steam stays running, back to
# Big Picture). For Steam itself — or whenever no game window is focused
# (focus on the workspace, Steam minimized to scratchpad, etc.): quit Steam.
# The entrypoint exits when Steam exits, which stops the container, drops the
# stream, and returns the Moonlight client to its selection screen.
source "$(dirname "$0")/common.sh"
steam_env
LOG=/tmp/steamtools.log
get_focused
echo "$(date) close-game: pid=$PID class=$CLASS name=$NAME" >> "$LOG"

if [[ "$CLASS" == steam ]] || [ -z "$PID" ] || [ "$PID" -le 1 ]; then
  # Closing Steam (or closing with nothing but Steam around) = ending the
  # Moonlight session (see header comment).
  echo "$(date) close-game: no game focused — quitting Steam (back to Moonlight selection)" >> "$LOG"
  /home/steam/steamtools/kill-steam.sh
  exit 0
fi

# Ask the compositor to close the window gracefully (WM_DELETE / Wayland close).
swaymsg kill >/dev/null 2>&1

for _ in $(seq 1 10); do
  if ! kill -0 "$PID" 2>/dev/null; then
    echo "$(date) close-game: closed gracefully (pid $PID)" >> "$LOG"
    swaymsg workspace 1
    exit 0
  fi
  sleep 1
done

echo "$(date) close-game: window closed but pid $PID still alive — force-killing tree" >> "$LOG"
kill_tree "$PID"
swaymsg workspace 1
exit 0
