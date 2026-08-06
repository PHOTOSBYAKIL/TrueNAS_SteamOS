# TrueNAS_SteamOS

An Arch Linux, SteamOS-style container for TrueNAS with current graphics drivers.

Ships a rolling Arch base, so the **Mesa** userspace driver is always the latest
release (≥ 25.2.1) — required by SteamVR's Steam Link headset driver for Quest VR.

The image is built automatically from this repo and published to
`ghcr.io/photosbyakil/truenas_steamos:main`.

## What it does

* Runs **Steam** (Big Picture / `-steamos`) inside an **Xvfb** virtual display.
* Runs **Sunshine**, so any Moonlight client can stream the display (games, desktop).
* Runs **PulseAudio**, so game audio works over the stream.
* Provides the GPU (AMD/Intel) + current Mesa to Steam, including 32-bit support.

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
* Steam runs Big Picture on the virtual display.
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

### Troubleshooting

* **Proton / Windows games crash at launch** — DXVK needs DRI3 (GPU
  presentation), which the default dummy X driver doesn't provide. Two fixes:
  1. **HDMI EDID emulator** (cheap "dummy plug") in the host's GPU port, then set
     `USE_AMDGPU=1` in the container env. The AMD GPU then drives a real
     connected display with DRI3, and games run while Sunshine still captures.
  2. **Kernel parameter** `amdgpu.virtual_display=1` on the TrueNAS host
     (System → Advanced → Kernel Parameters, then reboot) — same effect,
     no hardware.
  Without one of these, streaming + Steam work but DXVK games will crash.

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

* **No audio in streams** — confirm PulseAudio is running in the container
  (`pgrep pulseaudio` inside the app shell) and that the streamed app is not
  muting the monitor device.

* **Sunshine shows no apps / blank "Apps" page** — `apps.json` is generated on
  first run; if you replaced the volume, reseed it by restarting the app once,
  or run `sunshine --creds` / re-pair Moonlight.

## Building locally

```bash
docker build -t truenas-steamos:latest .
```

The GitHub Actions workflow (`/.github/workflows/docker-publish.yml`) builds and
publishes the image on every push to `main`.
