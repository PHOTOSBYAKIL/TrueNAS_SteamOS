#!/bin/bash
# Shared helpers for the TrueNAS_SteamOS recovery tools (gamescope edition).
# No sway/waybar — recovery actions are launched as Sunshine apps from Moonlight.

steam_env() {
  export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/1000}
  export PATH="$PATH:/usr/sbin:/usr/bin:/bin"
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

# Populate GAME_PID with the most recently started game managed by Steam.
# Under gamescope there is no window list to query, so scan /proc for the
# "SteamLaunch AppId=" reaper root (Steam itself never has this in its
# cmdline, so it is never matched).
get_game_pid() {
  GAME_PID=""
  local pid
  for pid in $(pgrep -f 'SteamLaunch AppId=' 2>/dev/null | sort -n -r); do
    if [ -r "/proc/$pid/cmdline" ]; then
      GAME_PID=$pid
      break
    fi
  done
}
