# TrueNAS_SteamOS

A headless SteamOS-style streaming container for TrueNAS. Uses **gamescope** as the session compositor (same as the Steam Deck) with **Sunshine** for Moonlight streaming.

## Architecture

```
gamescope (session compositor, DRM/KMS) → Steam Big Picture → Sunshine (wlr-screencopy)
```

* **gamescope** IS the compositor — manages the entire game lifecycle (launch, focus, close)
* **Steam Big Picture** (`-tenfoot`) runs inside gamescope as a child process
* **Sunshine** captures gamescope's output via wlr-screencopy and encodes with VA-API
* **PipeWire** provides audio (null sink for Sunshine capture)

Games open and close seamlessly — no workspace tricks, no focus hacks, no recovery toolbar.

## Install on TrueNAS

The container is a **Custom App** (docker-compose based).

1. **Apps → Discover Apps → Custom App**
2. Give it a name (e.g. `steamos`)
3. Paste the compose YAML from the **`Container Installation YAML`** file
4. Adjust the volume path to a pool that exists on your TrueNAS
5. Leave `privileged` and devices as-is
6. **Install**

First start takes a couple of minutes (Steam downloads/updates itself).

### Requirements

* Host kernel parameter: `amdgpu.virtual_display=desc:1920x1080` (System → Advanced → Kernel Parameters)
* GPU passthrough: `/dev/dri` device must be available
* AMD, Intel, or NVIDIA GPU (VA-API hardware encoding)

## Using it

* Pair **Moonlight** with this box like any Sunshine host
  (open `http://<nas-ip>:47990`, get the pairing PIN)
* Steam runs Big Picture in gamescope
* Games launch and close seamlessly

### Controller pass-through (VirtualHere)

Controllers plugged into the Moonlight client (e.g. your Mac) can appear as real
USB devices inside this container.

1. On the **Mac**: download and run **VirtualHere** from https://www.virtualhere.com/usb_client_software
2. In the container, VirtualHere runs automatically if `VH_SERVER` is set
3. Steam Input picks the controllers up

## Environment variables

| Var | Default | Purpose |
|---|---|---|
| `PUID` | `1000` | User ID |
| `PGID` | `1000` | Group ID |
| `VH_SERVER` | *(unset)* | VirtualHere server IP (Mac) |
| `TZ` | `America/New_York` | Timezone |

## Troubleshooting

* **Gamescope fails to start** — verify `amdgpu.virtual_display=desc:1920x1080` is in `/proc/cmdline`
* **No stream / "Unable to find display"** — Sunshine supervisor auto-restarts with backoff. If stuck, restart the app.
* **CSRF error on Sunshine web UI** — edit `<volume>/home/.config/sunshine/sunshine.conf` and set `csrf_allowed_origins = https://<nas-ip>:47990`
* **No audio** — confirm PipeWire is running (`pgrep pipewire` in container) and app audio isn't muted
* **Kill Steam** — from TrueNAS shell: `docker exec truenas-steamos kill-steam.sh`

## Building locally

```bash
docker build -t truenas-steamos:latest .
```

GitHub Actions builds and publishes on every push to `main`.
