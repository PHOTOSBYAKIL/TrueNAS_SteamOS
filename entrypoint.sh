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

# Audio configuration (all configurable via env; defaults work out of the box)
export MIC_SERVER=${MIC_SERVER:-192.168.86.42}          # Moonlight client running PulseAudio
export AUDIO_MIC_ENABLED=${AUDIO_MIC_ENABLED:-true}      # tunnel the Mac's mic in
export AUDIO_NOISE_SUPPRESSION=${AUDIO_NOISE_SUPPRESSION:-true}  # rnnoise
export AUDIO_ECHO_CANCEL=${AUDIO_ECHO_CANCEL:-false}     # WebRTC AEC
export AUDIO_TUNNEL_LATENCY_MS=${AUDIO_TUNNEL_LATENCY_MS:-200}
export MIC_SOURCE=${MIC_SOURCE:-}                        # empty = follow the Mac's default mic

echo "=== [SteamOS Container] Preparing runtime ==="
sudo mkdir -p "$XDG_RUNTIME_DIR" "$XDG_RUNTIME_DIR/pipewire" "$XDG_RUNTIME_DIR/pulse" "$XDG_RUNTIME_DIR/dbus-1"
sudo chown -R "${PUID}:${PGID}" "$XDG_RUNTIME_DIR" 2>/dev/null || true
sudo chmod 0700 "$XDG_RUNTIME_DIR" 2>/dev/null || true
chown -R "${PUID}:${PGID}" "$HOME" 2>/dev/null || true

echo "=== [SteamOS Container] Seeding recovery toolbar ==="
# Copy the toolbar scripts into the mounted home dir once (cp -n never
# overwrites user edits, so this is safe on every boot). The sway config
# references /home/steam/steamtools for these.
mkdir -p "$HOME/steamtools"
cp -n /usr/local/lib/steamtools/* "$HOME/steamtools/" 2>/dev/null || true
chown -R "${PUID}:${PGID}" "$HOME/steamtools" 2>/dev/null || true

# Waybar config + CSS for the toolbar (also copy-once).
mkdir -p "$HOME/.config/waybar"
cp -n /usr/local/lib/steamos-waybar/* "$HOME/.config/waybar/" 2>/dev/null || true
chown -R "${PUID}:${PGID}" "$HOME/.config/waybar" 2>/dev/null || true

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
# Mic input comes from the Moonlight client's (Mac) PulseAudio over the network.
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
# headless = virtual output; libinput = Sunshine's uinput input devices.
# WLR_LIBINPUT_NO_DEVICES=1 lets libinput start empty and pick up devices
# via udev when a Moonlight client connects.
#
# /run/user/1000 is NOT wiped on `docker stop/start` (only when the container
# is recreated), so stale sway-ipc*.sock / wayland-*.lock files from the
# previous boot survive. They would (a) shift the display number sway picks
# and (b) make the readiness wait below succeed instantly against a dead
# socket — both leaving Sunshine pointed at the wrong/absent display. Wipe
# them so sway deterministically binds wayland-0 on every boot.
sudo rm -f "$XDG_RUNTIME_DIR"/wayland-* "$XDG_RUNTIME_DIR"/sway-ipc* 2>/dev/null || true

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

# Wait for sway to be ready — the Wayland DISPLAY socket specifically, not the
# IPC socket: sway creates the IPC socket before the display socket is
# connectable, and Sunshine needs the display socket. Derive WAYLAND_DISPLAY
# from whatever sway actually bound instead of hardcoding a number.
# NOTE: the socket is named `wayland-N` with NO `.sock` suffix (wlroots),
# and sway leaves a parallel `wayland-N.lock` — exclude the lock file.
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

echo "=== [SteamOS Container] Sway supervisor ==="
# sway has no self-recovery: if it dies (xwayland crash, xcb error, etc.)
# nothing restarts it and the whole stream is dead until the container is
# recreated. A sway crash also invalidates every Wayland client connection,
# so the only clean recovery is a full restart — kill Steam (which ends the
# entrypoint) and let the `restart: unless-stopped` policy bring the box back
# up fresh.
(
  while true; do
    sleep 10
    if ! pgrep -x sway >/dev/null 2>&1; then
      echo "[$(date +%H:%M:%S)] sway died — restarting container (killing Steam)" >> /tmp/sway.log
      pkill -TERM -f 'steam -tenfoot' 2>/dev/null
      sleep 5
      pkill -KILL -f 'steam -tenfoot' 2>/dev/null
      exit 0
    fi
  done
) &

echo "=== [SteamOS Container] Seeding Sunshine config ==="
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

# Sunshine's process manager aborts the whole parse when apps.json lacks an
# "env" key ("No such node (env)") — the parser throws, Sunshine aborts at
# startup, and /applist goes empty. The volume may carry a stale apps.json
# from an older image (the CachyOS experiment wrote one without env), so
# always heal the file before launching. This is idempotent.
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

echo "=== [SteamOS Container] Starting Sunshine (wlr capture) ==="
# Sunshine never retries: if the Wayland display isn't connectable when it
# boots (a NAS/container restart races sway, or sway hiccups) it stays up but
# broken — web UI/ports listen, but "Unable to find display or encoder" and
# no stream is ever available until the container is recreated. (Re)launch it
# with a fresh wait for the display socket and keep it supervised below.
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
    WAYLAND_DISPLAY="$d" DISPLAY=:0 \
    DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \
    sunshine >/tmp/sunshine.log 2>&1 &
  # Wait for the process to actually appear so callers (the supervisor checks
  # right after this returns) never race the background fork and launch a
  # duplicate that dies with "Address already in use" on the RTSP port.
  for i in $(seq 1 10); do
    pgrep -x sunshine >/dev/null 2>&1 && break
    sleep 1
  done
}

start_sunshine

# Sunshine supervisor — restart it when it dies, and when it is alive but
# logged a fatal no-display/no-encoder boot (streams are broken even though
# the process lives). Backs off on failure so a genuinely absent display
# doesn't hot-restart-loop.
(
  BACKOFF=5
  while true; do
    # Sleep first so the very first check doesn't race the initial launch.
    sleep 10
    if ! pgrep -x sunshine >/dev/null 2>&1; then
      echo "[$(date +%H:%M:%S)] Sunshine not running — (re)starting"
      start_sunshine
      sleep "$BACKOFF"
      [ "$BACKOFF" -lt 60 ] && BACKOFF=$((BACKOFF + 5))
      continue
    fi
    # Healthy boot = the log shows a found encoder. Broken boot = the fatal
    # line is present and the log stopped being written >=15s ago.
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

echo "=== [SteamOS Container] Starting VirtualHere USB client ==="
if [ -n "${VH_SERVER:-}" ]; then
  # Start the daemon first, then tell it to connect to the server (the
  # combined -n -t form fails because the IPC daemon must be up).
  /usr/local/bin/vhclient -n >/dev/null 2>&1 &
  sleep 2
  /usr/local/bin/vhclient -t "$VH_SERVER" >/dev/null 2>&1 || true
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
      sudo udevadm trigger --action=add --subsystem-match=input 2>/dev/null || true
    fi
  done
) &

echo "=== [SteamOS Container] Audio supervisor ==="
# Self-heals the audio stack so mid-session device changes (mic unplug/replug,
# Bluetooth switch, Mac PA restart, app sink-switch) recover in a few seconds.
# Only touches audio routing — never sway/Steam/Sunshine video/input.
(
  export PULSE_SERVER=unix:"$XDG_RUNTIME_DIR"/pulse/native
  while true; do
    sleep 3
    # Keep the game/output sink pinned so Sunshine keeps capturing
    if [ "$(pactl get-default-sink 2>/dev/null)" != "sunshine-null" ]; then
      pactl set-default-sink sunshine-null 2>/dev/null || true
    fi
    if [ "$AUDIO_MIC_ENABLED" = "true" ]; then
      # Games should use the processed (noise-suppressed) mic
      if [ "$(pactl get-default-source 2>/dev/null)" != "Noise Canceling source" ]; then
        pactl set-default-source "Noise Canceling source" 2>/dev/null || true
      fi
      # Ensure the rnnoise filter captures from the mac-mic tunnel (re-links
      # after the tunnel drops/reconnects or the source name changes)
      out=$(pw-link -o 2>/dev/null | grep -m1 "^mac-mic:")
      in=$(pw-link -i 2>/dev/null | grep -m1 "capture.rnnoise_source")
      if [ -n "$out" ] && [ -n "$in" ]; then
        pw-link "$out" "$in" 2>/dev/null || true
      fi
    fi
  done
) &

echo "=== [SteamOS Container] Launching Steam Big Picture ==="
sudo -u "$USER_NAME" env XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" HOME="$HOME" \
  WAYLAND_DISPLAY="$WAYLAND_DISPLAY" DISPLAY=:0 \
  DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \
  PIPEWIRE_RUNTIME_DIR="$XDG_RUNTIME_DIR/pipewire" \
  STEAM_USE_DYNAMIC_VK=1 \
  dbus-run-session -- steam -tenfoot -silent "$@" >/tmp/steam.log 2>&1

echo "=== [SteamOS Container] Steam exited — stopping container ==="
exit 0
