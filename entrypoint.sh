#!/bin/bash
set -o pipefail

# TrueNAS_SteamOS — headless Wayland (sway) streaming container.
# Runs: D-Bus -> NetworkManager -> PipeWire -> seatd -> sway (headless+libinput)
#      -> Steam -> Sunshine (wlr-screencopy capture, VA-API encode).
#
# Requires host kernel parameter: amdgpu.virtual_display=desc:1920x1080
# (System -> Advanced -> Kernel Parameters, then reboot). Without it wlroots
# falls back to software rendering and games/streaming break.

PUID=${PUID:-1000}
PGID=${PGID:-1000}
USER_NAME=${UNAME:-steam}
export HOME=${HOME:-/home/steam}
export XDG_RUNTIME_DIR=/run/user/${PUID}

echo "=== [SteamOS Container] Preparing runtime ==="
mkdir -p "$XDG_RUNTIME_DIR" "$XDG_RUNTIME_DIR/pipewire" "$XDG_RUNTIME_DIR/pulse" "$XDG_RUNTIME_DIR/dbus-1"
chown -R "${PUID}:${PGID}" "$XDG_RUNTIME_DIR" 2>/dev/null || true
chmod 0700 "$XDG_RUNTIME_DIR" 2>/dev/null || true
chown -R "${PUID}:${PGID}" "$HOME" 2>/dev/null || true

echo "=== [SteamOS Container] Starting system services (D-Bus + NetworkManager) ==="
# Steam needs NetworkManager's D-Bus API for network state; sway needs D-Bus too.
sudo dbus-uuidgen --ensure 2>/dev/null || true
sudo mkdir -p /run/dbus
sudo dbus-daemon --system --fork
sudo NetworkManager

# Session bus
DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"
export DBUS_SESSION_BUS_ADDRESS
sudo -u "$USER_NAME" env DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \
  XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" HOME="$HOME" \
  dbus-daemon --session --address="$DBUS_SESSION_BUS_ADDRESS" --nofork >/tmp/dbus-session.log 2>&1 &

echo "=== [SteamOS Container] Granting device access ==="
sudo chmod 666 /dev/uinput 2>/dev/null || true
sudo chmod 666 /dev/dri/* 2>/dev/null || true
sudo chmod 666 /dev/input/* 2>/dev/null || true

echo "=== [SteamOS Container] Starting PipeWire ==="
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

echo "=== [SteamOS Container] Starting seatd ==="
seatd -g video >/tmp/seatd.log 2>&1 &
sleep 1

echo "=== [SteamOS Container] Starting sway (headless + libinput) ==="
# headless = virtual output; libinput = Sunshine's uinput input devices.
# WLR_LIBINPUT_NO_DEVICES=1 lets libinput start empty and pick up devices
# via udev when a Moonlight client connects.
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
export WAYLAND_DISPLAY=wayland-1

# Wait for sway to be ready
for i in $(seq 1 20); do
  [ -S "$XDG_RUNTIME_DIR/sway-ipc.sock" ] && break
  sleep 1
done

echo "=== [SteamOS Container] Seeding Sunshine config ==="
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

echo "=== [SteamOS Container] Starting Sunshine (wlr capture) ==="
sudo -u "$USER_NAME" env XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" HOME="$HOME" \
  WAYLAND_DISPLAY="$WAYLAND_DISPLAY" DISPLAY=:0 \
  DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \
  sunshine >/tmp/sunshine.log 2>&1 &

echo "=== [SteamOS Container] Starting VirtualHere USB client ==="
if [ -n "${VH_SERVER:-}" ]; then
  /usr/local/bin/vhclient -n -t "$VH_SERVER" >/dev/null 2>&1 &
  echo "VirtualHere client connecting to ${VH_SERVER}"
fi

echo "=== [SteamOS Container] Input hotplug helper ==="
# Sunshine creates its virtual input devices (uinput) per client connect. The
# container's /dev is private, so mknod the nodes + trigger udev so sway's
# libinput backend attaches them (Wolf's fake-udev technique).
(
  while true; do
    sleep 2
    devs=$(awk -v RS='' '/passthrough|Sunshine/ { for(i=1;i<=NF;i++){ if($i ~ /event[0-9]+/){ sub(/.*event/,"event",$i); if($i ~ /^event[0-9]+$/) print $i } if($i ~ /js[0-9]+/){ sub(/.*js/,"js",$i); if($i ~ /^js[0-9]+$/) print $i } } }' /proc/bus/input/devices 2>/dev/null | sort -u)
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

echo "=== [SteamOS Container] Launching Steam Big Picture ==="
sudo -u "$USER_NAME" env XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" HOME="$HOME" \
  WAYLAND_DISPLAY="$WAYLAND_DISPLAY" DISPLAY=:0 \
  DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \
  PIPEWIRE_RUNTIME_DIR="$XDG_RUNTIME_DIR/pipewire" \
  STEAM_USE_DYNAMIC_VK=1 \
  dbus-run-session -- steam -gamepadui -steamos -silent "$@" >/tmp/steam.log 2>&1

echo "=== [SteamOS Container] Steam exited — stopping container ==="
exit 0
