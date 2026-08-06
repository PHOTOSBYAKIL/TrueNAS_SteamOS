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

# Window manager so Steam's Big Picture fills the screen (bare X has no WM).
openbox >/dev/null 2>&1 &

# Input hotplug helper. Sunshine 2026.x creates its virtual keyboard/mouse/gamepad
# on every client connect. The container's /dev is a private tmpfs, so those new
# devices have NO /dev/input/eventN node here and Xorg's libinput cannot open
# them. Watch for the devices (Wolf's technique): mknod the nodes, chmod them,
# and re-trigger udev so Xorg attaches them.
(
  while true; do
    sleep 2
    devs=$(awk -v RS='' '/passthrough|Sunshine/ { for(i=1;i<=NF;i++){ if($i ~ /^event[0-9]+$/ || $i ~ /^js[0-9]+$/) print $i } }' /proc/bus/input/devices 2>/dev/null | sort -u)
    [ -z "$devs" ] && continue
    created=0
    for dev in $devs; do
      case "$dev" in
        event*) minor=$((64 + ${dev#event})) ;;
        js*)    minor=$((128 + ${dev#js})) ;;
        *) continue ;;
      esac
      if [ ! -e "/dev/input/$dev" ]; then
        sudo mknod "/dev/input/$dev" c 13 "$minor" 2>/dev/null && created=1
      fi
      sudo chmod 666 "/dev/input/$dev" 2>/dev/null || true
    done
    if [ "$created" = "1" ]; then
      sudo udevadm trigger --subsystem-match=input 2>/dev/null || true
    fi
  done
) &

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

echo "=== [SteamOS Container] Starting VirtualHere USB client ==="
# Controllers plugged into the Moonlight client (Mac) become real USB devices
# here. Set VH_SERVER=<mac-ip> in the container env to enable it.
if [ -n "${VH_SERVER:-}" ]; then
  /usr/local/bin/vhclient -n -t "$VH_SERVER" >/dev/null 2>&1 &
  echo "VirtualHere client connecting to ${VH_SERVER}"
fi

echo "=== [SteamOS Container] Launching SteamOS Big Picture Mode ==="
# Steam supervisor: just keeps Steam running (no forced restarts — those blanked
# the screen on every client connect). Controllers are picked up by Steam Input
# via the mknod/udev helper above.
(
  while true; do
    if ! pgrep -x steam >/dev/null 2>&1; then
      echo "[SteamOS] Starting Steam..."
      dbus-run-session -- steam -gamepadui -steamos -silent >/dev/null 2>&1 &
      sleep 15
    fi
    sleep 5
  done
) &

# Launch Steam via the supervisor below (it owns Steam's lifecycle so it can
# restart Steam when a gamepad appears). Keep the container alive as PID1.
exec sleep infinity
