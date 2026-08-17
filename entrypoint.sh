#!/bin/bash
set -o pipefail

# TrueNAS_SteamOS — headless gamescope streaming container.
# Runs: D-Bus -> NetworkManager -> PipeWire -> seatd -> gamescope (-e, DRM)
#       -> Steam Big Picture -> Sunshine (wlr-screencopy, VA-API encode).
#
# Gamescope IS the session compositor (same as Steam Deck). It manages the
# game lifecycle — launch, focus, close, overlay. No workspace tricks or
# focus hacks needed.
#
# Requires host kernel param: amdgpu.virtual_display=desc:1920x1080

PUID=${PUID:-1000}
PGID=${PGID:-1000}
USER_NAME=${UNAME:-steam}
export HOME=${HOME:-/home/steam}
export XDG_RUNTIME_DIR=/run/user/${PUID}

echo "=== [SteamOS] Preparing runtime ==="
sudo mkdir -p "$XDG_RUNTIME_DIR" "$XDG_RUNTIME_DIR/pipewire" "$XDG_RUNTIME_DIR/pulse" "$XDG_RUNTIME_DIR/dbus-1"
sudo chown -R "${PUID}:${PGID}" "$XDG_RUNTIME_DIR" 2>/dev/null || true
sudo chmod 0700 "$XDG_RUNTIME_DIR" 2>/dev/null || true
chown -R "${PUID}:${PGID}" "$HOME" 2>/dev/null || true

echo "=== [SteamOS] Starting system services (D-Bus + NetworkManager) ==="
sudo dbus-uuidgen --ensure 2>/dev/null || true
sudo mkdir -p /run/dbus
sudo dbus-daemon --system --fork
sudo NetworkManager

DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"
export DBUS_SESSION_BUS_ADDRESS
sudo -u "$USER_NAME" env DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \
  XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" HOME="$HOME" \
  dbus-daemon --session --address="$DBUS_SESSION_BUS_ADDRESS" --nofork >/tmp/dbus-session.log 2>&1 &

echo "=== [SteamOS] Granting device access ==="
sudo chmod 666 /dev/uinput 2>/dev/null || true
sudo chmod 666 /dev/dri/* 2>/dev/null || true
sudo chmod 666 /dev/input/* 2>/dev/null || true

echo "=== [SteamOS] Configuring PipeWire ==="
mkdir -p "$HOME/.config/pipewire/pipewire.conf.d"
cat > "$HOME/.config/pipewire/pipewire.conf.d/10-sunshine-null.conf" <<'PWEOF'
context.modules = [
    {
        name = libpipewire-module-loopback
        args = {
            "capture.props" = {
                "node.name" = "sunshine-null"
                "media.class" = "Audio/Sink"
                "audio.position" = [ "FL" "FR" ]
                "node.description" = "Sunshine Null Sink"
                "monitor.channel-volumes" = true
            }
            "playback.props" = {
                "node.name" = "sunshine-null-monitor"
                "media.class" = "Audio/Source"
                "audio.position" = [ "FL" "FR" ]
                "node.description" = "Sunshine Monitor"
                "monitor.channel-volumes" = true
            }
        }
    }
]
PWEOF
chown -R "${PUID}:${PGID}" "$HOME/.config/pipewire" 2>/dev/null || true

echo "=== [SteamOS] Starting PipeWire ==="
sudo -u "$USER_NAME" env XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" HOME="$HOME" \
  DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \
  PIPEWIRE_RUNTIME_DIR="$XDG_RUNTIME_DIR/pipewire" \
  pipewire >/tmp/pipewire.log 2>&1 &
sleep 1
sudo -u "$USER_NAME" env XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" HOME="$HOME" \
  DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \
  PIPEWIRE_RUNTIME_DIR="$XDG_RUNTIME_DIR/pipewire" \
  pipewire-pulse >/tmp/pipewire-pulse.log 2>&1 &
sleep 1
sudo -u "$USER_NAME" env XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" HOME="$HOME" \
  DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \
  PIPEWIRE_RUNTIME_DIR="$XDG_RUNTIME_DIR/pipewire" \
  wireplumber >/tmp/wireplumber.log 2>&1 &
sleep 2

sudo -u "$USER_NAME" env XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" HOME="$HOME" \
  PULSE_SERVER=unix:"$XDG_RUNTIME_DIR"/pulse/native \
  pactl set-default-sink sunshine-null 2>/dev/null || true

echo "=== [SteamOS] Starting seatd ==="
sudo seatd -g video >/tmp/seatd.log 2>&1 &
sleep 1

echo "=== [SteamOS] Starting gamescope ==="
# Gamescope is the session compositor (same as Steam Deck).
# -e = embedded mode, takes over display via DRM/KMS
# --force-grab-cursor = games that need cursor capture work correctly
# Steam is a child process of gamescope — it manages the lifecycle.
sudo rm -f "$XDG_RUNTIME_DIR"/wayland-* "$XDG_RUNTIME_DIR"/sway-ipc* 2>/dev/null || true
sudo rm -f /tmp/.X11-unix/X* /tmp/.X*-lock 2>/dev/null || true

GAMESCOPE_ENV="XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR
XDG_SESSION_TYPE=wayland
XDG_CURRENT_DESKTOP=gamescope
XDG_SESSION_DESKTOP=gamescope
HOME=$HOME
DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS
PIPEWIRE_RUNTIME_DIR=$XDG_RUNTIME_DIR/pipewire
DISPLAY=:0"

# Gamescope -e: embedded mode (DRM/KMS, takes over the virtual display).
# Gamescope creates its own Wayland display + Xwayland for Steam.
# Steam is launched as the child process after '--'.
sudo -u "$USER_NAME" env $GAMESCOPE_ENV \
  gamescope -e -W 1920 -H 1080 -r 60 --force-grab-cursor -- steam -tenfoot -silent \
  >/tmp/gamescope.log 2>&1 &
GAMESCOPE_PID=$!

# Wait for gamescope to expose its Wayland display
WAYLAND_DISPLAY=""
for i in $(seq 1 30); do
  WAYLAND_DISPLAY=$(basename "$(ls "$XDG_RUNTIME_DIR"/wayland-* 2>/dev/null | grep -v '\.lock$' | head -1)" 2>/dev/null)
  [ -n "$WAYLAND_DISPLAY" ] && break
  sleep 1
done
export WAYLAND_DISPLAY
if [ -z "$WAYLAND_DISPLAY" ]; then
  echo "WARNING: gamescope did not expose a Wayland display after 30s" >&2
  tail -20 /tmp/gamescope.log >&2 || true
else
  echo "gamescope ready on WAYLAND_DISPLAY=${WAYLAND_DISPLAY}"
fi

export DISPLAY=":0"
echo "DISPLAY=${DISPLAY} (gamescope manages Xwayland internally)"

echo "=== [SteamOS] Gamescope supervisor ==="
# If gamescope dies, kill the entrypoint to trigger container restart.
# Only kill processes named exactly 'steam' (not gamescope which contains
# 'steam' in its argument string from the 'gamescope -- steam' command).
(
  while true; do
    sleep 10
    if ! pgrep -x gamescope >/dev/null 2>&1; then
      echo "[$(date +%H:%M:%S)] gamescope died — restarting container"
      pkill -TERM -x steam 2>/dev/null
      sleep 5
      pkill -KILL -x steam 2>/dev/null
      exit 0
    fi
  done
) &

echo "=== [SteamOS] Seeding Sunshine config ==="
SUNCONF="$HOME/.config/sunshine/sunshine.conf"
if [ ! -s "$SUNCONF" ] || ! grep -q "capture = wlr" "$SUNCONF"; then
  LAN_IP=$(ip route get 1.1.1.1 2>/dev/null | sed -n 's/.*src \([0-9.]*\).*/\1/p' | head -1)
  [ -z "$LAN_IP" ] && LAN_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
  mkdir -p "$(dirname "$SUNCONF")"
  cat > "$SUNCONF" <<EOF
origin_web_ui_allowed = lan
csrf_allowed_origins = https://${LAN_IP}:47990
capture = wlr
encoder = vaapi
adapter_name = /dev/dri/renderD128
audio_sink = sunshine-null
EOF
  echo "Wrote Sunshine config (wlr capture, CSRF origin https://${LAN_IP}:47990)"
fi

APPS="$HOME/.config/sunshine/apps.json"
if [ -f "$APPS" ]; then
  python3 - "$APPS" <<'PYEOF'
import json, sys
p = sys.argv[1]
try:
    data = dict(json.load(open(p)))
except Exception:
    data = {}
data.setdefault("env", {})
if "apps" not in data:
    data["apps"] = []
json.dump(data, open(p, "w"), indent=4)
PYEOF
  echo "Healed Sunshine apps.json (ensured apps + env keys)"
fi

echo "=== [SteamOS] Starting Sunshine (wlr capture) ==="
start_sunshine() {
  local d="" i
  for i in $(seq 1 30); do
    d=$(basename "$(ls "$XDG_RUNTIME_DIR"/wayland-* 2>/dev/null | grep -v '\.lock$' | head -1)" 2>/dev/null)
    [ -n "$d" ] && break
    sleep 1
  done
  [ -z "$d" ] && d="$WAYLAND_DISPLAY"
  echo "[$(date +%H:%M:%S)] Launching Sunshine on WAYLAND_DISPLAY=${d:-<none>}"
  sudo -u "$USER_NAME" env XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" HOME="$HOME" \
    WAYLAND_DISPLAY="$d" DISPLAY="$DISPLAY" \
    DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \
    sunshine >/tmp/sunshine.log 2>&1 &
  for i in $(seq 1 10); do
    pgrep -x sunshine >/dev/null 2>&1 && break
    sleep 1
  done
}

start_sunshine

# Sunshine supervisor
(
  BACKOFF=5
  while true; do
    sleep 10
    if ! pgrep -x sunshine >/dev/null 2>&1; then
      echo "[$(date +%H:%M:%S)] Sunshine not running — (re)starting"
      start_sunshine
      sleep "$BACKOFF"
      [ "$BACKOFF" -lt 60 ] && BACKOFF=$((BACKOFF + 5))
      continue
    fi
    if grep -q "Unable to find display or encoder" /tmp/sunshine.log 2>/dev/null; then
      now=$(date +%s)
      mtime=$(stat -c %Y /tmp/sunshine.log 2>/dev/null || echo 0)
      if [ "$(( now - mtime ))" -ge 15 ]; then
        echo "[$(date +%H:%M:%S)] Sunshine booted without display/encoder — restarting"
        pkill -x sunshine
        sleep 2
        : > /tmp/sunshine.log
        start_sunshine
        sleep "$BACKOFF"
        [ "$BACKOFF" -lt 60 ] && BACKOFF=$((BACKOFF + 5))
        continue
      fi
    fi
    BACKOFF=5
    sleep 15
  done
) &

echo "=== [SteamOS] Starting VirtualHere USB client ==="
if [ -n "${VH_SERVER:-}" ]; then
  /usr/local/bin/vhclient -n >/dev/null 2>&1 &
  sleep 2
  /usr/local/bin/vhclient -t "$VH_SERVER" >/dev/null 2>&1 || true
  echo "VirtualHere client connecting to ${VH_SERVER}"
fi

echo "=== [SteamOS] Audio supervisor ==="
(
  export PULSE_SERVER=unix:"$XDG_RUNTIME_DIR"/pulse/native
  while true; do
    sleep 3
    if [ "$(pactl get-default-sink 2>/dev/null)" != "sunshine-null" ]; then
      pactl set-default-sink sunshine-null 2>/dev/null || true
    fi
  done
) &

echo "=== [SteamOS] Waiting for gamescope to exit ==="
wait $GAMESCOPE_PID 2>/dev/null

echo "=== [SteamOS] Gamescope exited — stopping container ==="
exit 0
