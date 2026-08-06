# ============================================================================
# TrueNAS_SteamOS
#
# An Arch Linux, SteamOS-style container for TrueNAS with current graphics
# drivers. Arch ships the latest Mesa (>= 25.2.1) which SteamVR's Steam Link
# headset driver requires for Quest VR.
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
FROM archlinux:latest

# 1. Enable 32-bit Multilib Repositories & LizardByte Custom Repository
RUN echo -e "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist" >> /etc/pacman.conf && \
    echo -e "\n[lizardbyte]\nSigLevel = Optional\nServer = https://github.com/LizardByte/pacman-repo/releases/latest/download" >> /etc/pacman.conf

# 2. Base Bootstrap (Pacman can now find sunshine!)
RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm \
    base-devel \
    sudo \
    wget \
    ttf-liberation \
    ttf-dejavu \
    xterm \
    xorg-server \
    xorg-server-xvfb \
    xorg-xinit \
    xorg-xrandr \
    wmctrl \
    sunshine \
    pulseaudio \
    lib32-pulseaudio \
    alsa-plugins \
    lib32-alsa-plugins \
    vulkan-icd-loader \
    lib32-vulkan-icd-loader \
    mesa \
    lib32-mesa \
    vulkan-radeon \
    lib32-vulkan-radeon \
    vulkan-intel \
    lib32-vulkan-intel \
    lib32-systemd \
    usbutils \
    steam \
    dbus \
    networkmanager \
    xf86-video-dummy \
    xf86-input-libinput \
    openbox \
    && pacman -Scc --noconfirm

# 3. Create non-root user 'steam'
ENV USER=steam
ENV HOME=/home/${USER}

RUN useradd -m -s /bin/bash ${USER} && \
    echo "${USER} ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers.d/${USER} && \
    chmod 0440 /etc/sudoers.d/${USER}

# Sunshine requires the user to be in the input group for controller emulation
RUN usermod -aG video,audio,input ${USER}

# 4. Copy Startup Script & Set Permissions
COPY --chown=steam:steam entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Headless X server config (xf86-video-dummy) — Sunshine 2026.x injects input
# via uinput/inputtino devices, which a real Xorg server (via udev) attaches to
# the display. Xvfb does NOT process evdev input, so input would not work.
COPY xorg-headless.conf /etc/X11/xorg-headless.conf

# VirtualHere USB client — lets controllers plugged into the Moonlight client
# (Mac) appear as real USB devices in this container (needs the vhci_hcd kernel
# module on the host). Connect it by setting VH_SERVER=<ip> in the container env.
RUN wget -q -O /usr/local/bin/vhclient https://www.virtualhere.com/sites/default/files/usbclient/vhclientx86_64 && \
    chmod +x /usr/local/bin/vhclient

USER ${USER}
WORKDIR ${HOME}

# 5. SteamOS Environment Variables
ENV XDG_RUNTIME_DIR=/tmp/runtime-steam
ENV STEAM_FRAME_RATE_LIMIT=0

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
