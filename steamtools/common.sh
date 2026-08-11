#!/bin/bash
# Shared helpers for the TrueNAS_SteamOS recovery toolbar.

steam_env() {
  export SWAYSOCK=${SWAYSOCK:-/run/user/1000/sway-ipc.sock}
  export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/1000}
  export PATH="$PATH:/usr/sbin:/usr/bin:/bin"
}

# Print PID=/CLASS=/NAME=/FULLSCREEN= of the currently focused sway view.
focused_info() {
  swaymsg -t get_tree --raw 2>/dev/null | python3 -c '
import json, sys
try:
    t = json.load(sys.stdin)
except Exception:
    sys.exit(1)
def walk(n):
    if n.get("focused"):
        print("PID=" + str(n.get("pid") or 0))
        wp = n.get("window_properties") or {}
        cls = n.get("class") or wp.get("class") or n.get("app_id") or ""
        print("CLASS=" + cls)
        print("NAME=" + (n.get("name") or ""))
        print("FULLSCREEN=" + str(n.get("fullscreen_mode") or 0))
        return True
    for c in n.get("nodes", []) + n.get("floating_nodes", []):
        if walk(c):
            return True
    return False
walk(t)
'
}

# Populate globals PID / CLASS / NAME / FULLSCREEN from the focused view.
get_focused() {
  PID=; CLASS=; NAME=; FULLSCREEN=0
  local info line
  info=$(focused_info) || return 1
  while IFS= read -r line; do
    case "$line" in
      PID=*) PID=${line#PID=} ;;
      CLASS=*) CLASS=${line#CLASS=} ;;
      NAME=*) NAME=${line#NAME=} ;;
      FULLSCREEN=*) FULLSCREEN=${line#FULLSCREEN=} ;;
    esac
  done <<< "$info"
}

# Recursively print all descendant pids of $1.
_descendants() {
  local c
  for c in $(pgrep -P "$1" 2>/dev/null); do
    echo "$c"
    _descendants "$c"
  done
}

# Force-kill $1 and its entire process tree. For Proton games this walks up
# /proc to the "SteamLaunch AppId=" root (reaper/supervisor) and takes the
# whole stack down with it, while leaving the Steam client itself running.
kill_tree() {
  local pid=$1 root=$pid cur=$pid ppid cmdline
  while [ "$cur" -gt 1 ]; do
    cmdline=$(tr '\0' ' ' < "/proc/$cur/cmdline" 2>/dev/null)
    if [[ "$cmdline" == *"SteamLaunch"* ]]; then
      root=$cur
    fi
    ppid=$(ps -o ppid= -p "$cur" 2>/dev/null | tr -d ' ')
    if [ -z "$ppid" ]; then
      break
    fi
    if [[ "$ppid" == *[!0-9]* ]] || [ "$ppid" -le 1 ]; then
      break
    fi
    cur=$ppid
  done
  kill -9 $(_descendants "$root") "$root" "$pid" 2>/dev/null
  pkill -9 -P "$pid" 2>/dev/null
}
