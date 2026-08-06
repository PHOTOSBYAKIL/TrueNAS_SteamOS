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

echo "=== [SteamOS Container] Starting PulseAudio ==="
export PULSE_SERVER=unix:/tmp/pulseaudio.socket
pulseaudio --start --exit-idle-time=-1 \
  --load="module-native-protocol-unix socket=/tmp/pulseaudio.socket" 2>/dev/null || true

echo "=== [SteamOS Container] Starting Virtual Display (Xvfb) ==="
# Create a 1080p 60Hz virtual monitor on display port :99
Xvfb :99 -screen 0 1920x1080x24 -nolisten tcp -dpi 96 +extension RANDR &
export DISPLAY=:99

# Wait until the X server accepts connections before starting Sunshine
for i in $(seq 1 30); do
  [ -S /tmp/.X11-unix/X99 ] && break
  sleep 0.5
done

echo "=== [SteamOS Container] Starting Sunshine ==="
# Launch Sunshine in the background to capture Display :99
sunshine &

echo "=== [SteamOS Container] Launching SteamOS Big Picture Mode ==="
# Launch Steam into the virtual display
exec steam -gamepadui -steamos -silent "$@"
