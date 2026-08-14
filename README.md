# TrueNAS_SteamOS

An Arch Linux, SteamOS-style container for TrueNAS with current graphics drivers.

Ships a rolling Arch base, so the **Mesa** userspace driver is always the latest
release (≥ 25.2.1) — required by SteamVR's Steam Link headset driver for Quest VR.

The image is built automatically from this repo and published to
`ghcr.io/photosbyakil/truenas_steamos:main`.

## What it does

* Runs **Steam** (Big Picture, `-tenfoot`) inside a headless **sway (Wayland)** session.
* Runs **Sunshine**, so any Moonlight client can stream the display (games, desktop).
* Runs **PipeWire** audio, so game audio works over the stream.
* Provides the GPU (AMD/Intel) + current Mesa to Steam, including 32-bit support.
* Every window is forced **fullscreen** in sway, so games open on top of Steam.

## Install on TrueNAS (manual — appears in your Apps list)

The container is a **Custom App** (docker-compose based), so it shows up and is
managed from the TrueNAS Apps UI like any other app.

1. **Apps → Discover Apps → Custom App**
2. Give it a name (e.g. `steamos`).
3. Paste the compose YAML from the **`Container Installation YAML`** file.
4. Adjust the volume path to a pool that exists on your TrueNAS, e.g.
   `/mnt/GAMING_1TB_SSD/apps/steamos/home` (a fast SSD pool is recommended).
5. Leave `privileged` and the devices as-is (GPU, input, uinput).
6. **Install**.

First start takes a couple of minutes (Steam downloads/updates itself).

### Using it

* Pair **Moonlight** with this box like any Sunshine host
  (open `http://<nas-ip>:47990`, get the pairing PIN).
* Steam runs Big Picture on the headless sway session.
* For Quest VR via Steam Link: with the box on your LAN, open the **Steam Link**
  app on the Quest and connect to the Steam client here — the current Mesa
  passes SteamVR's driver check.

### Controller pass-through (VirtualHere)

Controllers plugged into the Moonlight client (e.g. your Mac) can appear as real
USB devices inside this container — Steam and Linux then recognize the actual
controller model.

1. On the **Mac** (the Moonlight client): download and run **VirtualHere**
   from https://www.virtualhere.com/usb_client_software (macOS build). Share the
   Mac's USB devices (the app exposes a "share" option).
2. In the container, the VirtualHere client runs automatically if `VH_SERVER` is
   set (the YAML sets it to the Mac's IP). It connects to the Mac's VirtualHere
   on port 7575 and creates the virtual USB devices via the host's `vhci_hcd`
   kernel module (already present on TrueNAS).
3. Steam Input picks the controllers up; enable them under
   Settings → Controllers.

Note: the VirtualHere **server** needs a license to share more than one device
at a time (free = 1 device).

### Important

* **Do not run this alongside Wolf (Games on Whales) on the same host.**
  Both are Moonlight streaming servers and claim the same ports
  (47984/47989/48010 + the 47xxx UDP ports). Run this box *instead of* Wolf,
  or on a separate machine.
* **Storage:** the mounted `/home/steam` volume holds the Steam client, config
  and library. Give it a pool with enough space for your games.

### Microphone (from the Moonlight client)

Game audio output works automatically. For a **microphone**, the box tunnels
the Moonlight client's (Mac) PulseAudio default mic over the network and
optional **rnnoise noise suppression** cleans it up:

1. On the **Mac**: make sure PulseAudio is running and serving over the network:
   ```bash
   brew services start pulseaudio
   ```
   (config: `module-native-protocol-tcp auth-anonymous=1`, port 4713 — already
   set up if you previously used a PulseAudio mic tunnel). Grant PulseAudio
   Microphone permission in System Settings → Privacy & Security.
2. In the container set `MIC_SERVER` to the Mac's IP (the YAML defaults it).
3. The Mac's default mic appears in the box as a **"Noise Canceling source"**
   that games/Steam use. Switch mics (RØDE ↔ Bluetooth headset) by changing the
   Mac's default input — the box follows it automatically.

Environment variables:

| Var | Default | Purpose |
|---|---|---|
| `MIC_SERVER` | `192.168.86.42` | Mac's PulseAudio server |
| `AUDIO_MIC_ENABLED` | `true` | Load the mic tunnel |
| `AUDIO_NOISE_SUPPRESSION` | `true` | rnnoise noise-canceled source |
| `AUDIO_ECHO_CANCEL` | `false` | WebRTC echo cancellation |
| `AUDIO_TUNNEL_LATENCY_MS` | `200` | Tunnel latency |
| `MIC_SOURCE` | *(empty)* | Pin to a specific Mac mic name, or empty = follow Mac default |

An **audio supervisor** keeps the stack healthy: if the mic drops/reconnects,
a Bluetooth device switches, or the Mac's PulseAudio restarts, routing
recovers automatically in a few seconds. It never touches video/input routing.

### Recovery toolbar (close frozen games)

When a game freezes/crashes during a stream there is no taskbar to reach, so
the box ships a **recovery toolbar** — **Waybar** (`extra/waybar`, Wayland
gtk-layer-shell), a slim bar pinned to the bottom. It sits on layer `top`, so
it hides behind fullscreen games and never covers them — over Steam Big
Picture / the desktop it is visible with clickable buttons:

* **`[X] Close`** — close the focused game gracefully (`swaymsg kill`), then
  force-kill its process tree if it hangs.
* **`[R] Restart`** — emergency force-close of the focused game → back to
  Steam Big Picture.
* **`[S] Kill Steam`** — quit Steam and stop the box (start it again from the
  TrueNAS Apps UI).
* **`[M] Minimize`** — hide the bar.

The same actions are on hotkeys, which work even when a crashed game covers
the whole screen (Sunshine's input reaches sway via uinput/libinput):

| Combo | Action |
|---|---|
| `Mod4+Ctrl+Shift+Q` | Close focused game |
| `Mod4+Ctrl+Shift+R` | Force-restart focused game |
| `Mod4+Ctrl+Shift+X` | Kill Steam / stop the box |
| `Mod4+Ctrl+Shift+B` | Reveal the bar over the current game (un-fullscreens it) |

`Mod4` = the Super/Windows key. See `steamtools/README.md` for details.

### Troubleshooting

* **Mouse / keyboard / controller not working** — the entrypoint auto-creates
  Sunshine's virtual input device nodes in the container (Wolf's mknod
  technique) and re-triggers udev with `--action=add` so sway's libinput
  attaches them. If input stops, reconnect Moonlight (a fresh session recreates
  the devices); the trigger only fires when a new device appears.

* **Proton / Windows games crash at launch** — the box now uses a headless
  **sway (Wayland)** compositor, which lets games present directly to the GPU
  (no DRI3/X11 requirement). This requires the host kernel parameter
  `amdgpu.virtual_display=desc:1920x1080` (TrueNAS → System → Advanced →
  Kernel Parameters, then reboot) — without it wlroots falls back to software
  rendering and games/streaming break. Verify with `cat /proc/cmdline | grep virtual`.

* **"CSRF Protection Error" / "Internal Server Error" on the Sunshine welcome
  page** — the entrypoint auto-seeds `sunshine.conf` with your host's real
  origin, but if you changed your IP or edited the config, fix it manually:

  1. Edit `<your-volume>/home/.config/sunshine/sunshine.conf` and set:
     ```
  origin_web_ui_allowed = lan
  csrf_allowed_origins = https://<your-nas-ip>:47990
  ```
  2. Restart the app (Apps → steamos → Restart).

  Note: `csrf_allowed_origins` is a comma-separated list **without brackets**
  (e.g. `https://host:47990`) — bracket form like `["https://..."]` is parsed
  literally (with `[]`) and silently never matches. `origin_web_ui_allowed`
  takes a single value: `pc`, `lan`, or `wan`.

* **"Address already in use" when Sunshine starts** — another Sunshine host
  (Wolf, a second SteamOS instance) is running on the same machine. See the
  Wolf note above.

* **No audio in streams** — confirm PipeWire is running in the container
  (`pgrep pipewire` inside the app shell) and that the streamed app is not
  muting the monitor device.

* **Sunshine shows no apps / blank "Apps" page** — `apps.json` is generated on
  first run; if you replaced the volume, reseed it by restarting the app once,
  or run `sunshine --creds` / re-pair Moonlight.

* **Moonlight can't connect / streams fail right after a NAS or container
  restart** — the entrypoint used to hardcode `WAYLAND_DISPLAY=wayland-1` and
  start Sunshine the moment sway's **IPC** socket appeared. The Wayland display
  socket (the one Sunshine actually needs) appears later, and `/run/user/1000`
  is **not** wiped by `docker stop/start` — stale `sway-ipc*.sock` and
  `wayland-*.lock` files from the previous boot made the readiness wait succeed
  instantly and shifted the display number sway picked. Sunshine starts once,
  never retries, so a lost race left it "up" (web UI + ports listening) but with
  `Unable to find display or encoder` and no stream until the container was
  recreated.

  **Fixed in the image**: the entrypoint now (a) wipes stale sway/Wayland
  sockets before starting sway, (b) waits for the actual
  `wayland-*.sock` socket and derives `WAYLAND_DISPLAY` from it instead of
  hardcoding a number, and (c) runs a **Sunshine supervisor** that restarts it
  (with backoff) whenever it dies or boots without a working encoder. After
  updating the image and restarting the app, Sunshine self-heals on boot — no
  manual steps needed.

## Building locally

```bash
docker build -t truenas-steamos:latest .
```

The GitHub Actions workflow (`/.github/workflows/docker-publish.yml`) builds and
publishes the image on every push to `main`.
