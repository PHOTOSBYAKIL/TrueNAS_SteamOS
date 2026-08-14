#!/bin/bash
# Title bar hint shown when the focused app is minimized (hidden in the sway
# scratchpad) and no window is focused — a visible way to restore it. Prints
# nothing otherwise so waybar leaves no empty block.
source "$(dirname "$0")/common.sh"
steam_env

get_focused
if [ -n "$PID" ] && [ "$PID" -gt 1 ]; then
  exit 0
fi

if swaymsg -t get_tree --raw 2>/dev/null | python3 -c '
import json, sys
try:
    t = json.load(sys.stdin)
except Exception:
    sys.exit(0)
def has_scratch(n):
    if n.get("type") == "workspace" and n.get("name") == "__i3_scratch":
        return bool(n.get("nodes") or n.get("floating_nodes"))
    for c in n.get("nodes", []):
        if has_scratch(c):
            return True
    return False
sys.exit(0 if has_scratch(t) else 1)
'; then
  printf '\u2304 minimized \u2014 click \u2013 to restore'
fi
exit 0
