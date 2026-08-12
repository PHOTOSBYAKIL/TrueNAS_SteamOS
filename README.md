# TrueNAS_SteamOS

A universal, headless SteamOS-style gaming container built on **CachyOS**
(x86-64-v3 / AVX2) for TrueNAS SCALE, Unraid or Proxmox. Runs **Steam Gamepad
UI** inside a **gamescope** micro-compositor and streams it to any **Moonlight**
client via **Sunshine**. GPU is **auto-detected** at boot — the same image runs
on AMD, Intel and NVIDIA hosts.

- **Base:** `cachyos/cachyos-v3` — CachyOS userspace compiled for x86-64-v3
  (AVX2; every AMD/Intel CPU from ~2013/Zen 1 onward), with CachyOS's patched
  Mesa, `gamescope` and `sunshine` builds plus the `cachyos-gaming-meta` stack
  (Proton-CachyOS, umu-launcher, protontricks).
- **UI:** gamescope → Steam `-gamepadui` (Steam Deck-style, isolated frame
  pacing, optional FSR upscaling).
- **Streaming:** Sunshine — **X11 capture** by default (gamescope embedded in a
  headless Xvfb; works on ANY host, no kernel params). AMD/Intel hosts with a
  virtual display can opt into zero-copy **KMS capture** with `CAPTURE=kms`.
  Encode is VA-API (AMD/Intel) or NVENC (NVIDIA). Audio via a PipeWire null sink.
- **Mic:** optional tunnel from the Moonlight client's PulseAudio (e.g. a Mac)
  with rnnoise noise suppression.
- **Recovery:** a frozen game is killed from Moonlight (host app list →
  `Close Game` / `Restart Steam` / `Kill Steam`).

The image is built automatically from this repo and published to
`ghcr.io/photosbyakil/truenas_steamos:main`.

## What it does

* Runs **Steam** (Gamepad UI) inside a headless **gamescope** session.
* Runs **Sunshine**, so any **Moonlight** client can stream the display.
* Runs **PipeWire** audio (null sink → stream), plus optional client-mic tunnel.
* Auto-detects the GPU and loads the right drivers — AMD (RADV), Intel (ANV),
  or NVIDIA (proprietary + NVENC).
* `cachyos-gaming-meta` provides the full gaming userspace (Proton-CachyOS,
  Wine, umu, protontricks) preinstalled.

## How the display works

By default the container runs **gamescope embedded in a headless Xvfb** and
Sunshine captures the X framebuffer (X11 capture) — this needs **no kernel
parameters and works on any hardware**. For lower-latency zero-copy streaming
on AMD/Intel, set `CAPTURE=kms` in the compose environment; that requires a
virtual display on the host (see below).

## Install on TrueNAS (manual — appears in your Apps list)

The container is a **Custom App** (docker-compose based), so it shows up and is
managed from the TrueNAS Apps UI like any other app.

1. **Apps → Discover Apps → Custom App**
2. Give it a name (e.g. `steamos`).
3. Paste the compose YAML for **your hardware** from the **`Container
   Installation YAML`** file (Template A = AMD/Intel, Template B = NVIDIA).
4. Adjust the volume path to a pool that exists on your TrueNAS, e.g.
   `/mnt/GAMING_1TB_SSD/apps/steamos/home` (a fast SSD pool is recommended).
5. Leave `privileged`, `ipc: host`, `shm_size` and the devices as-is.
6. **Install.**

First start takes a few minutes (Steam downloads/updates itself).

### Host requirements

The default **X11** capture mode needs nothing beyond the devices already in
the compose file. **KMS** capture (`CAPTURE=kms`) is optional and needs a
virtual output on the host:

| GPU | What to set (only for `CAPTURE=kms`) |
|---|---|
| **AMD** | TrueNAS → System → Advanced → Kernel Parameters: `amdgpu.virtual_display=0000:c5:00.0,1` (use your GPU's PCI ID from `lspci`, or `all,1`), then reboot. (Verify: `cat /proc/cmdline \| grep virtual`.) |
| **Intel** | i915 EDID firmware (`video=DP-1:e drm_kms_helper.edid_firmware=edid/1920x1080.bin`) or the `vkms` module to create a virtual output. |
| **NVIDIA** | KMS capture is not supported (NVIDIA always uses the X11 path). |

Without a virtual output, `CAPTURE=kms` will not be able to present frames;
the entrypoint logs a clear warning.

### Using it

* Pair **Moonlight** with this box like any Sunshine host
  (open `http://<nas-ip>:47990`, get the pairing PIN).
* Steam runs the Gamepad UI on the headless gamescope session. Press
  `Super+F` inside gamescope to toggle FSR upscaling.
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
| `GAMESCOPE_RES` | `1920x1080` | Gamescope output resolution |
| `GAMESCOPE_REFRESH` | `60` | Gamescope refresh rate |
| `CAPTURE` | `x11` | `x11` = works anywhere; `kms` = zero-copy (AMD/Intel, needs virtual display) |

An **audio supervisor** keeps the stack healthy: if the mic drops/reconnects,
a Bluetooth device switches, or the Mac's PulseAudio restarts, routing
recovers automatically in a few seconds. It never touches video/input routing.

### Recovery (close frozen games)

When a game freezes/crashes during a stream there is no taskbar to reach, so
the recovery actions are exposed as **Sunshine apps** and launched straight
from the Moonlight client's app list:

| App (Moonlight) | Action |
|---|---|
| `Close Game` | Force-kill the running game's Proton process tree → back to Steam |
| `Restart Steam` | Same engine, for hard-hung games |
| `Kill Steam` | Quit Steam → container stops (start again from TrueNAS Apps UI) |

See `steamtools/README.md` for how the process-tree kill works under gamescope.

### Troubleshooting

* **Mouse / keyboard / controller not working** — the entrypoint auto-creates
  Sunshine's virtual input device nodes in the container (Wolf's mknod
  technique) and re-triggers udev with `--action=add` so gamescope's libinput
  attaches them. If input stops, reconnect Moonlight (a fresh session recreates
  the devices); the trigger only fires when a new device appears.

* **Stream is black / gamescope fails to present** — the default X11 capture
  path needs nothing special. If you set `CAPTURE=kms`, gamescope must be able
  to present to a GPU output: verify the host virtual display is active
  (`cat /proc/cmdline | grep virtual` on AMD; EDID/vkms on Intel) and that
  `/dev/dri/renderD128` exists inside the container (`ls /dev/dri` in the app
  shell). NOTE: the virtual-display parameter is
  `amdgpu.virtual_display=<PCI>,<count>` — the `desc:1920x1080` form creates
  ZERO crtcs and never worked.

* **Sunshine chooses the wrong capture** — the entrypoint seeds
  `capture = kms` (AMD/Intel) or `capture = x11` + `encoder = nvenc`
  (NVIDIA) on first boot. You can override in
  `<volume>/home/.config/sunshine/sunshine.conf` via the web UI.

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

## Building locally

```bash
docker build -t truenas-steamos:latest .
```

The GitHub Actions workflow (`/.github/workflows/docker-publish.yml`) builds and
publishes the image on every push to `main`.
