#!/bin/bash
# swaybar status_command: renders the recovery toolbar and dispatches clicks.
# Blocks: [X] Close, [R] Restart, [S] Kill Steam, [B] Hide Bar.
LOG=/tmp/steamtools.log
TOOLS=/home/steam/steamtools

emit() {
  printf '{"version":1,"click_events":true}\n'
  printf '[{"name":"close","full_text":"  [X] Close  ","color":"#ff6b6b"},{"name":"restart","full_text":"  [R] Restart  ","color":"#ffd166"},{"name":"killsteam","full_text":"  [S] Kill Steam  ","color":"#ff4444"},{"name":"hidebar","full_text":"  [B] Hide Bar  ","color":"#9fb3c8"}]\n'
}

emit
while IFS= read -r line; do
  echo "$(date) toolbar click: $line" >> "$LOG"
  case "$line" in
    *'"name":"close"'*)     "$TOOLS/close-game.sh"   >/dev/null 2>&1 & ;;
    *'"name":"restart"'*)   "$TOOLS/restart-game.sh" >/dev/null 2>&1 & ;;
    *'"name":"killsteam"'*) "$TOOLS/kill-steam.sh"   >/dev/null 2>&1 & ;;
    *'"name":"hidebar"'*)   swaymsg bar mode toggle  >/dev/null 2>&1 & ;;
  esac
  emit
done
