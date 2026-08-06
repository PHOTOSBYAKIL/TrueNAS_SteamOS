#!/bin/bash
set -e

# TrueNAS_SteamOS — standalone container:
# Xvfb virtual display + Sunshine (Moonlight host) + Steam Big Picture.
# Arch ships the current Mesa (>= 25.2.1) so SteamVR's Steam Link driver works.

echo "=== [SteamOS Container] Preparing runtime environment ==="
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/tmp/runtime-steam}
sudo mkdir -p "$XDG_RUNTIME_DIR" 2>/dev/null || true
sudo chown -R "$(id -u):$(id -g)" "$XDG_RUNTIME_DIR" 2>/dev/null || true
sudo chmod 0700 "$XDG_RUNTIME_DIR" 2>/dev/null || true
# The mounted HOME may have been created as root — make it writable
sudo chown -R "$(id -u):$(id -g)" "$HOME" 2>/dev/null || true

echo "=== [SteamOS Container] Starting system services (D-Bus + NetworkManager) ==="
# Steam reports "waiting for network" if it cannot reach NetworkManager's D-Bus
# API. Start the system bus + NetworkManager (requires root; steam has NOPASSWD sudo).
sudo dbus-uuidgen --ensure 2>/dev/null || true
sudo mkdir -p /run/dbus
sudo dbus-daemon --system --fork
sudo NetworkManager

echo "=== [SteamOS Container] Granting device access ==="
# Sunshine 2026.x uses inputtino virtual devices (uinput) for ALL input —
# mouse, keyboard, touch, pen, gamepads. The device nodes arrive with host
# group IDs, so open them up for the steam user.
sudo chmod 666 /dev/uinput 2>/dev/null || true
sudo chmod 666 /dev/dri/* 2>/dev/null || true
sudo chmod 666 /dev/input/* 2>/dev/null || true

echo "=== [SteamOS Container] Starting PulseAudio ==="
export PULSE_SERVER=unix:/tmp/pulseaudio.socket
pulseaudio --daemonize=no --exit-idle-time=-1 \
  --load="module-native-protocol-unix socket=/tmp/pulseaudio.socket" >/dev/null 2>&1 &

echo "=== [SteamOS Container] Starting Virtual Display (Xorg dummy) ==="
# A real Xorg server with the dummy video driver. Sunshine 2026.x injects input
# through uinput/inputtino virtual devices; Xorg (with /run/udev mounted) picks
# those up and attaches them to the display. Xvfb cannot process evdev input.
sudo Xorg :99 -ac -nolisten tcp -noreset -config /etc/X11/xorg-headless.conf \
  >/dev/null 2>&1 &
export DISPLAY=:99

# Wait until the X server accepts connections before starting Sunshine
for i in $(seq 1 60); do
  [ -S /tmp/.X11-unix/X99 ] && break
  sleep 0.5
done

# The dummy driver falls back to 1024x768; set a sane default resolution.
# (xrandr can also switch this to match a Moonlight client later.)
xrandr --newmode 1920x1080_60.00 173.00 1920 2048 2248 2576 1080 1083 1088 1120 -hsync +vsync 2>/dev/null
xrandr --addmode DUMMY0 1920x1080_60.00 2>/dev/null
xrandr --output DUMMY0 --mode 1920x1080_60.00 2>/dev/null || true

echo "=== [SteamOS Container] Seeding Sunshine config ==="
# Prevent Sunshine's "CSRF Protection Error" on the welcome page: seed the
# config with this host's real origin. NOTE: csrf_allowed_origins is a
# comma-separated list WITHOUT brackets (e.g. "https://host:47990"), and
# origin_web_ui_allowed is a single value: pc / lan / wan.
SUNCONF="$HOME/.config/sunshine/sunshine.conf"
if [ ! -s "$SUNCONF" ]; then
  LAN_IP=$(ip route get 1.1.1.1 2>/dev/null | sed -n 's/.*src \([0-9.]*\).*/\1/p' | head -1)
  [ -z "$LAN_IP" ] && LAN_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
  mkdir -p "$(dirname "$SUNCONF")"
  cat > "$SUNCONF" <<EOF
origin_web_ui_allowed = lan
csrf_allowed_origins = https://${LAN_IP}:47990
EOF
  echo "Wrote Sunshine config for origin https://${LAN_IP}:47990"
fi

echo "=== [SteamOS Container] Starting Sunshine ==="
# Launch Sunshine in the background to capture Display :99
sunshine &

echo "=== [SteamOS Container] Launching SteamOS Big Picture Mode ==="
# Launch Steam into the virtual display
exec steam -gamepadui -steamos -silent "$@"
