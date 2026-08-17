#!/bin/bash
set -o pipefail

# TrueNAS_SteamOS — minimal headless sway streaming container.
# Runs: D-Bus -> NetworkManager -> PipeWire -> seatd -> sway (headless)
#       -> Steam Big Picture -> Sunshine (wlr-screencopy, VA-API encode).
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

echo "=== [SteamOS] Starting D-Bus + NetworkManager ==="
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
sudo chmod 666 /dev/dri/* 2>/dev/null || true

# Official Sunshine udev rules (from LizardByte docs + Arch-specific fixes)
echo "=== [SteamOS] Writing udev rules ==="
sudo mkdir -p /etc/udev/rules.d

# Official Sunshine uinput rule (matches LizardByte documentation exactly)
sudo tee /etc/udev/rules.d/60-sunshine-uinput.rules >/dev/null <<'RULES'
KERNEL=="uinput", SUBSYSTEM=="misc", OPTIONS+="static_node=uinput", TAG+="uaccess", GROUP="input", MODE="0660"
KERNEL=="uhid", TAG+="uaccess", GROUP="input", MODE="0660"
RULES

# Sunshine/inputtino virtual device tagging for libinput recognition
sudo tee /etc/udev/rules.d/99-sunshine-input.rules >/dev/null <<'RULES'
# Sunshine/inputtino virtual devices (vendor 0x3434 = 13364 decimal)
ACTION=="add|change", SUBSYSTEM=="input", ATTRS{vendor}=="13364", ENV{ID_INPUT}="1", MODE="0666"

# Keyboard passthrough
ACTION=="add|change", SUBSYSTEM=="input", ATTRS{name}=="Keyboard passthrough", ENV{ID_INPUT}="1", ENV{ID_INPUT_KEYBOARD}="1", ENV{ID_INPUT_KEY}="1", MODE="0666"

# Mouse passthrough (relative)
ACTION=="add|change", SUBSYSTEM=="input", ATTRS{name}=="Mouse passthrough", ENV{ID_INPUT}="1", ENV{ID_INPUT_POINTER}="1", MODE="0666"

# Mouse passthrough (absolute)
ACTION=="add|change", SUBSYSTEM=="input", ATTRS{name}=="Mouse passthrough (absolute)", ENV{ID_INPUT}="1", ENV{ID_INPUT_POINTER}="1", MODE="0666"

# Touch passthrough
ACTION=="add|change", SUBSYSTEM=="input", ATTRS{name}=="Touch passthrough", ENV{ID_INPUT}="1", ENV{ID_INPUT_POINTER}="1", MODE="0666"

# Pen passthrough
ACTION=="add|change", SUBSYSTEM=="input", ATTRS{name}=="Pen passthrough", ENV{ID_INPUT}="1", ENV{ID_INPUT_POINTER}="1", MODE="0666"

# Xbox gamepad
ACTION=="add|change", SUBSYSTEM=="input", ATTRS{name}=="Sunshine X-Box One*", ENV{ID_INPUT}="1", ENV{ID_INPUT_JOYSTICK}="1", MODE="0666"

# All input event devices — world accessible
SUBSYSTEM=="input", KERNEL=="event[0-9]*", MODE="0666"
KERNEL=="js[0-9]*", MODE="0666"
RULES

echo "=== [SteamOS] Starting udevd ==="
sudo /usr/lib/systemd/systemd-udevd --daemon 2>/dev/null || true
sudo udevadm control --reload-rules 2>/dev/null || true
sudo udevadm trigger --subsystem-match=input 2>/dev/null || true
sudo udevadm settle --timeout=5 2>/dev/null || true
# Ensure /dev/uinput is accessible (Sunshine needs write access to create virtual devices)
# Use 0666 as safety net — in Docker containers, group resolution via sudo -u can be unreliable
sudo chmod 0666 /dev/uinput 2>/dev/null || true
sudo chmod 0666 /dev/uhid 2>/dev/null || true

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

echo "=== [SteamOS] Starting sway ==="
sudo rm -f "$XDG_RUNTIME_DIR"/wayland-* "$XDG_RUNTIME_DIR"/sway-ipc* 2>/dev/null || true
sudo rm -f /tmp/.X11-unix/X* /tmp/.X*-lock 2>/dev/null || true

SWAY_ENV="XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR
XDG_SESSION_TYPE=wayland
XDG_CURRENT_DESKTOP=sway
XDG_SESSION_DESKTOP=sway
HOME=$HOME
DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS
PIPEWIRE_RUNTIME_DIR=$XDG_RUNTIME_DIR/pipewire
WLR_BACKENDS=headless,libinput
WLR_LIBINPUT_NO_DEVICES=1
SWAYSOCK=$XDG_RUNTIME_DIR/sway-ipc.sock"

sudo -u "$USER_NAME" env $SWAY_ENV sway -c /etc/sway/config \
  >/tmp/sway.log 2>&1 &
SWAY_PID=$!

WAYLAND_DISPLAY=""
for i in $(seq 1 30); do
  WAYLAND_DISPLAY=$(basename "$(ls "$XDG_RUNTIME_DIR"/wayland-* 2>/dev/null | grep -v '\.lock$' | head -1)" 2>/dev/null)
  [ -n "$WAYLAND_DISPLAY" ] && break
  sleep 1
done
export WAYLAND_DISPLAY
if [ -z "$WAYLAND_DISPLAY" ]; then
  echo "WARNING: sway did not expose a Wayland display socket after 30s" >&2
  tail -20 /tmp/sway.log >&2 || true
else
  echo "sway ready on WAYLAND_DISPLAY=${WAYLAND_DISPLAY}"
fi

X_DISPLAY=""
for i in $(seq 1 10); do
  X_DISPLAY=$(ls /tmp/.X11-unix/ 2>/dev/null | grep -E '^X[0-9]+$' | sed 's/^X//' | sort -n | head -1)
  [ -n "$X_DISPLAY" ] && break
  sleep 1
done
export DISPLAY=":${X_DISPLAY:-0}"
echo "XWayland ready on DISPLAY=${DISPLAY}"

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
keyboard = enabled
mouse = enabled
gamepad = xone
EOF
  echo "Wrote Sunshine config (wlr capture, input enabled, CSRF origin https://${LAN_IP}:47990)"
fi
# Ensure input settings are always present (safe to add to existing config)
if [ -f "$SUNCONF" ]; then
  grep -q "^keyboard" "$SUNCONF" || echo "keyboard = enabled" >> "$SUNCONF"
  grep -q "^mouse" "$SUNCONF" || echo "mouse = enabled" >> "$SUNCONF"
  # Force gamepad to xone for stability (auto mode causes disconnects)
  sed -i 's/^gamepad = auto/gamepad = xone/' "$SUNCONF"
  grep -q "^gamepad" "$SUNCONF" || echo "gamepad = xone" >> "$SUNCONF"
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
  echo "Healed Sunshine apps.json"
fi

echo "=== [SteamOS] Starting input device watcher ==="
# The host's /dev/input is bind-mounted. The host's udevd creates nodes
# with its own GID (105 on this host) which doesn't match our container's
# input group (992). We must chmod ALL devices every cycle to ensure the
# steam user can always access them regardless of host GID mismatch.
(
  while true; do
    # Continuously chmod all input devices (host GID mismatch means
    # 0660 root:105 blocks our steam user even though it's in "input")
    chmod 666 /dev/input/event* /dev/input/js* /dev/input/mouse* 2>/dev/null || true
    # Trigger udev so libinput picks up devices with ID_INPUT_* tags
    udevadm trigger --subsystem-match=input 2>/dev/null || true
    sleep 2
  done
) &

echo "=== [SteamOS] Starting Sunshine ==="
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

# After Sunshine starts, trigger udev once for any devices it created
sleep 3
chmod 666 /dev/input/event* /dev/input/js* 2>/dev/null || true
udevadm trigger --subsystem-match=input 2>/dev/null || true

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

echo "=== [SteamOS] Launching Steam Big Picture ==="
for i in $(seq 1 30); do
  [ -S /tmp/.X11-unix/X"${DISPLAY#:}" ] && break
  sleep 1
done
[ -S /tmp/.X11-unix/X"${DISPLAY#:}" ] || echo "WARNING: X socket ${DISPLAY} not ready after 30s" >&2
sudo -u "$USER_NAME" env XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" HOME="$HOME" \
  WAYLAND_DISPLAY="$WAYLAND_DISPLAY" DISPLAY="$DISPLAY" \
  DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \
  PIPEWIRE_RUNTIME_DIR="$XDG_RUNTIME_DIR/pipewire" \
  STEAM_USE_DYNAMIC_VK=1 \
  dbus-run-session -- steam -tenfoot -silent "$@" >/tmp/steam.log 2>&1

echo "=== [SteamOS] Steam exited — stopping container ==="
exit 0
