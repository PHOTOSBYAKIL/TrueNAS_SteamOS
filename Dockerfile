# ============================================================================
# TrueNAS_SteamOS
#
# Headless Arch Linux streaming container using gamescope as the session
# compositor (same as Steam Deck). Games open/close seamlessly — no workspace
# tricks, no focus management hacks. Sunshine captures via wlr-screencopy.
#
# Image: ghcr.io/photosbyakil/truenas_steamos:main
# ============================================================================
FROM archlinux:latest

# Enable 32-bit Multilib + LizardByte repos
RUN echo -e "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist" >> /etc/pacman.conf && \
    echo -e "\n[lizardbyte]\nSigLevel = Optional\nServer = https://github.com/LizardByte/pacman-repo/releases/latest/download" >> /etc/pacman.conf

# Install packages
RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm \
    base-devel \
    sudo \
    wget \
    ttf-liberation \
    ttf-dejavu \
    xterm \
    sunshine \
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
    xorg-xwayland \
    seatd \
    pipewire \
    pipewire-pulse \
    wireplumber \
    pipewire-audio \
    lib32-pipewire \
    lib32-libpulse \
    gamescope \
    mangohud \
    libva \
    libva-utils \
    vulkan-tools \
    mesa-utils \
    && pacman -Scc --noconfirm

# Create steam user
ENV USER=steam
ENV HOME=/home/${USER}

RUN useradd -m -s /bin/bash ${USER} && \
    echo "${USER} ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers.d/${USER} && \
    chmod 0440 /etc/sudoers.d/${USER}

RUN usermod -aG video,audio,input ${USER}

# Copy entrypoint
COPY --chown=steam:steam entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Emergency kill script (only one we keep)
COPY --chown=steam:steam steamtools/kill-steam.sh /usr/local/bin/kill-steam.sh

# VirtualHere USB client
RUN wget -q -O /usr/local/bin/vhclient https://www.virtualhere.com/sites/default/files/usbclient/vhclientx86_64 && \
    chmod +x /usr/local/bin/vhclient

USER ${USER}
WORKDIR ${HOME}

ENV XDG_RUNTIME_DIR=/tmp/runtime-steam
ENV STEAM_FRAME_RATE_LIMIT=0

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
