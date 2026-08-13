#!/bin/bash
set -o pipefail

# TrueNAS_SteamOS — universal headless CachyOS sway + gamescope streaming box.
#
# Boot order:
#   D-Bus -> NetworkManager -> PipeWire (+ null sink / mic tunnel / rnnoise)
#        -> seatd -> sway (headless + libinput, virtual output) -> nested
#           gamescope -> Steam (Gamepad UI) -> Sunshine (wlr-screencopy capture;
#           VA-API on AMD/Intel, NVENC on NVIDIA).
#
# Capture is ALWAYS wlr-screencopy from the sway virtual output — works on any
# host, no kernel params required. (On AMD hosts the optional
# amdgpu.virtual_display=<PCI>,<count> kernel param keeps the GPU rendering +
# DMA-BUFs working, but sway's headless output does not depend on it.)
#
# GPU drivers (Vulkan/VA-API) are auto-detected from lspci — no vendor env
# needed.
#
# Host requirements (documented in README):
#   - /dev/dri, /dev/input, /dev/uinput passed in. Nothing else.
#   - NVIDIA: nvidia-drm.modeset=1 + nvidia-container-toolkit runtime

PUID=${PUID:-1000}
PGID=${PGID:-1000}
USER_NAME=${UNAME:-steam}
export HOME=${HOME:-/home/steam}
export XDG_RUNTIME_DIR=/run/user/${PUID}

# Audio configuration (all configurable via env; defaults work out of the box)
export MIC_SERVER=${MIC_SERVER:-192.168.86.42}          # Moonlight client running PulseAudio
export AUDIO_MIC_ENABLED=${AUDIO_MIC_ENABLED:-true}      # tunnel the client's mic in
export AUDIO_NOISE_SUPPRESSION=${AUDIO_NOISE_SUPPRESSION:-true}  # rnnoise
export AUDIO_ECHO_CANCEL=${AUDIO_ECHO_CANCEL:-false}     # WebRTC AEC
export AUDIO_TUNNEL_LATENCY_MS=${AUDIO_TUNNEL_LATENCY_MS:-200}
export MIC_SOURCE=${MIC_SOURCE:-}                        # empty = follow the Mac's default mic

# Display (gamescope) settings
export GAMESCOPE_RES=${GAMESCOPE_RES:-1920x1080}
export GAMESCOPE_REFRESH=${GAMESCOPE_REFRESH:-60}
GS_W=${GAMESCOPE_RES%x*}
GS_H=${GAMESCOPE_RES#*x}

# ============================================================================
echo "=== [SteamOS Container] Scanning hardware ==="
# ============================================================================
PCI_GPU=$(lspci -nn 2>/dev/null | grep -iE 'vga|3d|display' | head -1)
GPU_VENDOR=unknown
if echo "$PCI_GPU" | grep -qi nvidia; then
  GPU_VENDOR=nvidia
elif echo "$PCI_GPU" | grep -qi 'amd\|ati'; then
  GPU_VENDOR=amd
elif echo "$PCI_GPU" | grep -qi intel; then
  GPU_VENDOR=intel
fi
VK_DEVICE=$(echo "$PCI_GPU" | sed -n 's/.*\[\([0-9A-Fa-f]\{4\}:[0-9A-Fa-f]\{4\}\)\].*/\1/p' | tr 'a-f' 'A-F')
echo "GPU: $GPU_VENDOR ($VK_DEVICE) — $PCI_GPU"

# Per-vendor env + encoder selection. The compositor stack is the same for
# every GPU: sway (headless + libinput) drives the virtual output and gamescope
# runs NESTED on top of it; Sunshine uses wlr-screencopy capture. Only the
# encoder differs (VA-API on AMD/Intel, NVENC on NVIDIA).
ENCODER=vaapi
ADAPTER=/dev/dri/renderD128

case "$GPU_VENDOR" in
  nvidia)
    echo "NVIDIA detected — NVENC encoder"
    export __NV_PRIME_RENDER_OFFLOAD=1
    export __GLX_VENDOR_LIBRARY_NAME=nvidia
    export VK_DRIVER_FILES=/usr/share/vulkan/icd.d/nvidia_icd.json
    ENCODER=nvenc
    ADAPTER=nvidia
    ;;
  intel)
    echo "Intel detected — VA-API (iHD) encoder"
    export LIBVA_DRIVER_NAME=iHD
    ;;
  amd|*)
    echo "AMD/other detected — VA-API (radeonsi) encoder"
    export RADV_PERFTEST=gpl
    export AMD_VULKAN_ICD=RADV
    export LIBVA_DRIVER_NAME=radeonsi
    ;;
esac

echo "=== [SteamOS Container] Preparing runtime ==="
sudo mkdir -p "$XDG_RUNTIME_DIR" "$XDG_RUNTIME_DIR/pipewire" "$XDG_RUNTIME_DIR/pulse" "$XDG_RUNTIME_DIR/dbus-1"
sudo chown -R "${PUID}:${PGID}" "$XDG_RUNTIME_DIR" 2>/dev/null || true
sudo chmod 0700 "$XDG_RUNTIME_DIR" 2>/dev/null || true
chown -R "${PUID}:${PGID}" "$HOME" 2>/dev/null || true

echo "=== [SteamOS Container] Seeding recovery tools ==="
# The recovery scripts live in the bind-mounted home dir so they can be
# hot-patched without a rebuild. cp -n never overwrites user edits.
mkdir -p "$HOME/steamtools"
cp -n /usr/local/lib/steamtools/* "$HOME/steamtools/" 2>/dev/null || true
chown -R "${PUID}:${PGID}" "$HOME/steamtools" 2>/dev/null || true

# Waybar toolbar (Close/Restart/Kill Steam buttons) — sway.config exec's waybar,
# which reads ~/.config/waybar/. Seed it the same way (cp -n, never overwrite).
mkdir -p "$HOME/.config/waybar"
cp -n /usr/local/lib/steamos-waybar/* "$HOME/.config/waybar/" 2>/dev/null || true
chown -R "${PUID}:${PGID}" "$HOME/.config/waybar" 2>/dev/null || true

echo "=== [SteamOS Container] Starting system services (D-Bus + NetworkManager) ==="
sudo dbus-uuidgen --ensure 2>/dev/null || true
sudo mkdir -p /run/dbus
sudo rm -f /run/dbus/pid   # stale pid from a previous container run blocks dbus
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

echo "=== [SteamOS Container] Configuring PipeWire null sink ==="
# Deterministic audio: a null sink that Steam/games output to and Sunshine
# captures the monitor of. Created at PipeWire startup via a config drop-in.
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

echo "=== [SteamOS Container] Configuring microphone (tunnel + processing) ==="
# Mic input comes from the Moonlight client's PulseAudio over the network.
# Optional rnnoise noise suppression + WebRTC echo cancellation clean it up.
# All modules use nofail so PipeWire never crashes if a piece is unavailable.
mkdir -p "$HOME/.config/pipewire/pipewire.conf.d"

if [ "$AUDIO_MIC_ENABLED" = "true" ]; then
  cat > "$HOME/.config/pipewire/pipewire.conf.d/11-mic-tunnel.conf" <<PWTUNNEL
context.modules = [
    {
        name = libpipewire-module-pulse-tunnel
        flags = [ nofail ]
        args = {
            tunnel.mode = source
            pulse.server.address = "tcp:${MIC_SERVER}"
            pulse.latency = ${AUDIO_TUNNEL_LATENCY_MS}
            reconnect.interval.ms = 5000
            ${MIC_SOURCE:+"target.object = \"${MIC_SOURCE}\""}
            stream.props = {
                node.name = "mac-mic"
                node.description = "Mac Microphone"
                media.class = Audio/Source
            }
        }
    }
]
PWTUNNEL
fi

if [ "$AUDIO_NOISE_SUPPRESSION" = "true" ]; then
  cat > "$HOME/.config/pipewire/pipewire.conf.d/12-noise-suppression.conf" <<'PWFILTER'
context.modules = [
    {
        name = libpipewire-module-filter-chain
        flags = [ nofail ]
        args = {
            node.description = "Noise Canceling source"
            media.name = "Noise Canceling source"
            filter.graph = {
                nodes = [
                    {
                        type = ladspa
                        name = rnnoise
                        plugin = /usr/lib/ladspa/librnnoise_ladspa.so
                        label = noise_suppressor_mono
                        control = {
                            "VAD Threshold (%)" 50.0
                        }
                    }
                ]
            }
            capture.props = {
                node.name = "capture.rnnoise_source"
                node.passive = true
                audio.rate = 48000
            }
            playback.props = {
                node.name = "Noise Canceling source"
                media.class = Audio/Source
                audio.rate = 48000
            }
        }
    }
]
PWFILTER
fi

if [ "$AUDIO_ECHO_CANCEL" = "true" ]; then
  cat > "$HOME/.config/pipewire/pipewire.conf.d/13-echo-cancel.conf" <<'PWEC'
context.modules = [
    {
        name = libpipewire-module-echo-cancel
        flags = [ nofail ]
        args = {
            capture.props = { node.name = "Echo Cancel Capture" }
            source.props = { node.name = "Echo Cancellation Source" }
            sink.props = { node.name = "Echo Cancellation Sink" }
            playback.props = { node.name = "Echo Cancellation Playback" }
        }
    }
]
PWEC
fi

chown -R "${PUID}:${PGID}" "$HOME/.config/pipewire" 2>/dev/null || true

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
sudo -u "$USER_NAME" env XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" HOME="$HOME" \
  DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \
  PIPEWIRE_RUNTIME_DIR="$XDG_RUNTIME_DIR/pipewire" \
  wireplumber >/tmp/wireplumber.log 2>&1 &
sleep 2

# Steam/games output to the null sink; Sunshine captures its monitor.
sudo -u "$USER_NAME" env XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" HOME="$HOME" \
  PULSE_SERVER=unix:"$XDG_RUNTIME_DIR"/pulse/native \
  pactl set-default-sink sunshine-null 2>/dev/null || true

echo "=== [SteamOS Container] Starting seatd ==="
sudo seatd -g video >/tmp/seatd.log 2>&1 &
sleep 1

echo "=== [SteamOS Container] Starting sway (headless + libinput) ==="
# headless = virtual compositor output; libinput = Sunshine's uinput devices.
# WLR_LIBINPUT_NO_DEVICES=1 lets libinput start empty and pick up devices via
# udev when a Moonlight client connects.
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

sudo -u "$USER_NAME" env $SWAY_ENV sway -c /etc/sway/config >/tmp/sway.log 2>&1 &
SWAY_PID=$!
export WAYLAND_DISPLAY=wayland-1

# Wait for sway to be ready
for i in $(seq 1 20); do
  [ -S "$XDG_RUNTIME_DIR/sway-ipc.sock" ] && break
  sleep 1
done

echo "=== [SteamOS Container] Seeding Sunshine config ==="
SUNCONF="$HOME/.config/sunshine/sunshine.conf"
if [ ! -s "$SUNCONF" ] || ! grep -q "capture = " "$SUNCONF"; then
  LAN_IP=$(ip route get 1.1.1.1 2>/dev/null | sed -n 's/.*src \([0-9.]*\).*/\1/p' | head -1)
  [ -z "$LAN_IP" ] && LAN_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
  mkdir -p "$(dirname "$SUNCONF")"
  cat > "$SUNCONF" <<EOF
origin_web_ui_allowed = lan
csrf_allowed_origins = https://${LAN_IP}:47990
capture = wlr
encoder = ${ENCODER}
adapter_name = ${ADAPTER}
audio_sink = sunshine-null
EOF
  echo "Wrote Sunshine config (wlr/$ENCODER, CSRF https://${LAN_IP}:47990)"
fi

# Recovery apps (Close Game / Restart Steam / Kill Steam) — launchable from
# Moonlight, in addition to the sway hotkeys/waybar toolbar. Merged into the
# Sunshine apps.json without clobbering user-added apps.
echo "=== [SteamOS Container] Seeding Sunshine recovery apps ==="
sudo -u "$USER_NAME" env HOME="$HOME" python3 - <<'PYEOF'
import json, os
p = os.path.join(os.environ["HOME"], ".config/sunshine/apps.json")
apps = []
if os.path.exists(p):
    try:
        data = json.load(open(p))
        apps = data.get("apps", []) if isinstance(data, dict) else []
    except Exception:
        apps = []
def add(name, cmd):
    if not any(a.get("name") == name for a in apps):
        apps.append({
            "name": name, "cmd": cmd, "detached": True, "output": "",
            "image-path": "", "working-dir": "", "prep-cmd": [],
            "exclude-global-prep-cmd": False, "auto-detach": True,
            "order": len(apps),
        })
add("Close Game", "/home/steam/steamtools/close-game.sh")
add("Restart Steam", "/home/steam/steamtools/restart-game.sh")
add("Kill Steam", "/home/steam/steamtools/kill-steam.sh")
os.makedirs(os.path.dirname(p), exist_ok=True)
json.dump({"apps": apps}, open(p, "w"), indent=4)
PYEOF

echo "=== [SteamOS Container] Starting Sunshine (wlr capture) ==="
SUN_ENV="XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR
HOME=$HOME
DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS
XDG_SESSION_TYPE=wayland
WAYLAND_DISPLAY=$WAYLAND_DISPLAY"
sudo -u "$USER_NAME" env $SUN_ENV sunshine >/tmp/sunshine.log 2>&1 &

echo "=== [SteamOS Container] Starting VirtualHere USB client ==="
if [ -n "${VH_SERVER:-}" ]; then
  /usr/local/bin/vhclient -n >/dev/null 2>&1 &
  sleep 2
  /usr/local/bin/vhclient -t "$VH_SERVER" >/dev/null 2>&1 || true
  echo "VirtualHere client connecting to ${VH_SERVER}"
fi

echo "=== [SteamOS Container] Input hotplug helper ==="
# Sunshine creates its virtual input devices (uinput) per client connect. The
# container's /dev is private, so mknod the nodes + trigger udev so gamescope's
# libinput backend attaches them.
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
      sudo udevadm trigger --action=add --subsystem-match=input 2>/dev/null || true
    fi
  done
) &

echo "=== [SteamOS Container] Audio supervisor ==="
# Self-heals the audio stack so mid-session device changes (mic unplug/replug,
# client PA restart, app sink-switch) recover in a few seconds. Only touches
# audio routing — never gamescope/Steam/Sunshine video/input.
(
  export PULSE_SERVER=unix:"$XDG_RUNTIME_DIR"/pulse/native
  while true; do
    sleep 3
    if [ "$(pactl get-default-sink 2>/dev/null)" != "sunshine-null" ]; then
      pactl set-default-sink sunshine-null 2>/dev/null || true
    fi
    if [ "$AUDIO_MIC_ENABLED" = "true" ]; then
      if [ "$(pactl get-default-source 2>/dev/null)" != "Noise Canceling source" ]; then
        pactl set-default-source "Noise Canceling source" 2>/dev/null || true
      fi
      out=$(pw-link -o 2>/dev/null | grep -m1 "^mac-mic:")
      in=$(pw-link -i 2>/dev/null | grep -m1 "capture.rnnoise_source")
      if [ -n "$out" ] && [ -n "$in" ]; then
        pw-link "$out" "$in" 2>/dev/null || true
      fi
    fi
  done
) &

echo "=== [SteamOS Container] Launching gamescope (nested) + Steam ($GPU_VENDOR) ==="
# gamescope runs NESTED under sway: WAYLAND_DISPLAY is set, so gamescope
# auto-selects the Wayland backend and presents as a fullscreen surface on
# sway's output. Steam runs inside gamescope (FSR/frame-pacing), Sunshine
# captures sway via wlr-screencopy.
sudo -u "$USER_NAME" env XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" HOME="$HOME" \
  DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \
  PIPEWIRE_RUNTIME_DIR="$XDG_RUNTIME_DIR/pipewire" \
  WAYLAND_DISPLAY="$WAYLAND_DISPLAY" \
  XDG_SESSION_TYPE=wayland \
  dbus-run-session -- gamescope -e -o 1 -r "$GAMESCOPE_REFRESH" \
    -W "$GS_W" -H "$GS_H" -f \
    ${VK_DEVICE:+--prefer-vk-device "$VK_DEVICE"} \
    -- steam -gamepadui -silent "$@" >/tmp/gamescope.log 2>&1

echo "=== [SteamOS Container] Steam/gamescope exited — stopping container ==="
exit 0
