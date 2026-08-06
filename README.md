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
   `/mnt/HDD_1TB/apps/steamos/home` (or use **Add** to mount a dataset).
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

### Important

* **Do not run this alongside Wolf (Games on Whales) on the same host.**
  Both are Moonlight streaming servers and claim the same ports
  (47984/47989/48010 + the 47xxx UDP ports). Run this box *instead of* Wolf,
  or on a separate machine.
* **Storage:** the mounted `/home/steam` volume holds the Steam client, config
  and library. Give it a pool with enough space for your games.

## Building locally

```bash
docker build -t truenas-steamos:latest .
```

The GitHub Actions workflow (`/.github/workflows/docker-publish.yml`) builds and
publishes the image on every push to `main`.
