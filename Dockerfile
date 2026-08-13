# ============================================================================
# TrueNAS_SteamOS
#
# A universal, headless SteamOS-style gaming container built on CachyOS
# (x86-64-v3 / AVX2) for TrueNAS SCALE, Unraid or Proxmox. Works on AMD,
# Intel and NVIDIA hosts; the entrypoint auto-detects the GPU and picks the
# right drivers, Vulkan device and Sunshine encoder.
#
#   - Base:  cachyos/cachyos-v3  (x86-64-v3 userspace — last 10 years of CPUs)
#   - UI:    sway (headless virtual output) + nested gamescope (Steam `-gamepadui`)
#   - GPU:   auto-detected: AMD/Intel -> RADV/ANV + VA-API; NVIDIA -> NVENC
#   - Capture: Sunshine wlr-screencopy from the sway virtual output (no kernel
#            params, works on every host)
#   - Audio: PipeWire null sink + optional client-mic tunnel + rnnoise
#   - Recovery: waybar toolbar + sway hotkeys + Sunshine "apps"
#               (Close Game / Restart Steam / Kill Steam) — see steamtools/
#
# The image is built automatically from this repo and published to:
#   ghcr.io/photosbyakil/truenas_steamos:main
#
# IMPORTANT — DO NOT run this container alongside any OTHER Sunshine host
# (including Wolf / Games on Whales, or a second SteamOS instance) on the same
# machine. Sunshine and Wolf are both Moonlight streaming servers and claim the
# same ports (47984/47989 TCP and 47999/48010/48100/48200 UDP), so one of them
# will fail to start ("Address already in use").
#   - Run this box INSTEAD of Wolf, or
#   - Run it on a separate machine/NAS, or
#   - If you really must run both, stop Wolf (or change Sunshine's ports) first.
#
# See README.md and "Container Installation YAML" for TrueNAS setup.
# ============================================================================
FROM cachyos/cachyos-v3:latest

# CachyOS's v3 image ships pacman.conf with [cachyos-v3], [cachyos], [core],
# [extra] and [multilib] already enabled — no pacman.conf surgery needed.
# `sunshine` and `gamescope` (plus the cachyos-gaming stack) come from the
# CachyOS repos, so the external LizardByte repo is not required.
#
# pacman 7.x sandboxes its post-transaction hooks (systemd-hook etc.) in a
# network namespace. That fails inside Docker/buildx (no CAP_SYS_ADMIN /
# user namespace) with "could not isolate the network (Operation not
# permitted)" -> every hook errors and pacman exits 1. The CachyOS pacman
# fork reads the option as a bare flag inside the FIRST [options] section.
RUN sed -i '0,/^\[options\]/s//[options]\nDisableSandbox/' /etc/pacman.conf
#
# 1. Full system + universal runtime. Drivers for ALL vendors are installed so
#    the same image runs on AMD, Intel and NVIDIA boxes; the entrypoint picks
#    the active one at boot.
#
#    NOTE: mesa-git/lib32-mesa-git (CachyOS patched Mesa) are used instead of
#    stock mesa because cachyos-gaming-meta -> wine-cachyos-opt depends on
#    mesa-git. mesa-git BUNDLES the RADV + ANV drivers, so the split
#    vulkan-radeon / vulkan-intel / vulkan-mesa-implicit-layers packages are
#    intentionally NOT installed (they conflict with mesa-git).
RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm --needed \
    base-devel \
    sudo \
    wget \
    usbutils \
    pciutils \
    python \
    ttf-liberation \
    ttf-dejavu \
    dbus \
    networkmanager \
    seatd \
    xorg-xwayland \
    pipewire \
    pipewire-pulse \
    wireplumber \
    pipewire-audio \
    lib32-pipewire \
    lib32-libpulse \
    libinput \
    wayland-utils \
    sway \
    swaybg \
    swayidle \
    waybar \
    mesa-git \
    lib32-mesa-git \
    vulkan-icd-loader \
    lib32-vulkan-icd-loader \
    vulkan-validation-layers \
    gamemode \
    lib32-gamemode \
    intel-media-driver \
    nvidia-utils \
    lib32-nvidia-utils \
    libva \
    libva-utils \
    vulkan-tools \
    mesa-utils \
    cachyos-gaming-meta \
    steam \
    gamescope \
    mangohud \
    lib32-mangohud \
    sunshine \
    noise-suppression-for-voice \
    ladspa \
    swh-plugins \
    && pacman -Scc --noconfirm

# Sunshine's wlr-screencopy capture does not need CAP_SYS_ADMIN (the old KMS
# path did). The setcap is harmless in a privileged container and enables the
# KMS path if someone opts in, so it stays for compatibility.
RUN setcap cap_sys_admin+eip "$(command -v sunshine)" 2>/dev/null || true

# 2. Create non-root user 'steam'
ENV USER=steam
ENV HOME=/home/${USER}

RUN useradd -m -s /bin/bash ${USER} && \
    echo "${USER} ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers.d/${USER} && \
    chmod 0440 /etc/sudoers.d/${USER}

# Sunshine + gamescope need the video group for DRM/Vulkan; input for uinput.
RUN usermod -aG video,audio,input ${USER}

# 3. Copy Startup Script & Set Permissions
COPY --chown=steam:steam entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Headless sway config (WLR_BACKENDS=headless,libinput). sway drives the
# virtual output; gamescope runs NESTED on top of it for games.
COPY sway.config /etc/sway/config

# Recovery scripts. Installed under /usr/local/lib (NOT $HOME) so the
# /home/steam bind mount cannot shadow them; the entrypoint copies them into
# $HOME/steamtools on boot. See steamtools/README for usage.
COPY --chown=steam:steam steamtools/ /usr/local/lib/steamtools/

# Waybar config + CSS for the recovery toolbar (seeded into $HOME/.config/waybar
# on boot by the entrypoint; same "copy only if missing" rule as steamtools).
COPY --chown=steam:steam waybar/ /usr/local/lib/steamos-waybar/

# VirtualHere USB client — lets controllers plugged into the Moonlight client
# (e.g. a Mac) appear as real USB devices in this container (needs the vhci_hcd
# kernel module on the host). Connect it by setting VH_SERVER=<ip> in the env.
RUN wget -q -O /usr/local/bin/vhclient https://www.virtualhere.com/sites/default/files/usbclient/vhclientx86_64 && \
    chmod +x /usr/local/bin/vhclient

USER ${USER}
WORKDIR ${HOME}

# 4. SteamOS Environment Variables
ENV XDG_RUNTIME_DIR=/tmp/runtime-steam
ENV STEAM_FRAME_RATE_LIMIT=0

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
