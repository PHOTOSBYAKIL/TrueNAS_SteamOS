# ============================================================================
# TrueNAS_SteamOS
#
# A universal, headless SteamOS-style gaming container built on CachyOS
# (x86-64-v3 / AVX2) for TrueNAS SCALE, Unraid or Proxmox. Works on AMD,
# Intel and NVIDIA hosts; the entrypoint auto-detects the GPU and picks the
# right drivers, Vulkan device, gamescope backend and Sunshine capture/encoder.
#
#   - Base:  cachyos/cachyos-v3  (x86-64-v3 userspace — last 10 years of CPUs)
#   - UI:    gamescope (micro-compositor, Steam `-gamepadui`)
#   - GPU:   auto-detected: AMD/Intel -> RADV/ANV + KMS capture + VA-API;
#            NVIDIA            -> NVENC + X11 capture (gamescope embedded in Xvfb)
#   - Audio: PipeWire null sink + optional client-mic tunnel + rnnoise
#   - Recovery: Sunshine "apps" (Close Game / Restart Steam / Kill Steam)
#               launchable from Moonlight — no waybar needed under gamescope.
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
# permitted)" -> every hook errors and pacman exits 1. Disable the sandbox.
RUN printf '\n[options]\nDisableSandbox = yes\nDisableSandboxNetwork = yes\n' >> /etc/pacman.conf
#
# 1. Full system + universal runtime. Drivers for ALL vendors are installed so
#    the same image runs on AMD, Intel and NVIDIA boxes; the entrypoint picks
#    the active one at boot.
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
    xorg-server-xvfb \
    pipewire \
    pipewire-pulse \
    wireplumber \
    pipewire-audio \
    lib32-pipewire \
    lib32-libpulse \
    libinput \
    wayland-utils \
    mesa \
    lib32-mesa \
    vulkan-icd-loader \
    lib32-vulkan-icd-loader \
    vulkan-radeon \
    lib32-vulkan-radeon \
    libva-mesa-driver \
    vulkan-intel \
    lib32-vulkan-intel \
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

# Sunshine's KMS (kmsgrab) capture needs CAP_SYS_ADMIN. Harmless in a
# privileged container, but lets the KMS path work in non-privileged deploys
# too. (Not used by the X11/NVIDIA path, so the XDG-portal conflict is moot.)
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

# Recovery scripts. Installed under /usr/local/lib (NOT $HOME) so the
# /home/steam bind mount cannot shadow them; the entrypoint copies them into
# $HOME/steamtools on boot. See steamtools/README for usage.
COPY --chown=steam:steam steamtools/ /usr/local/lib/steamtools/

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
