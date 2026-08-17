# ============================================================================
# TrueNAS_SteamOS
#
# Headless Arch Linux streaming container with minimal sway compositor.
# Steam Big Picture runs inside sway. Sunshine captures via wlr-screencopy.
#
# Image: ghcr.io/photosbyakil/truenas_steamos:main
# ============================================================================
FROM archlinux:latest

RUN echo -e "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist" >> /etc/pacman.conf && \
    echo -e "\n[lizardbyte]\nSigLevel = Optional\nServer = https://github.com/LizardByte/pacman-repo/releases/latest/download" >> /etc/pacman.conf

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
    sway \
    xorg-xwayland \
    seatd \
    pipewire \
    pipewire-pulse \
    wireplumber \
    pipewire-audio \
    lib32-pipewire \
    lib32-libpulse \
    libva \
    libva-utils \
    vulkan-tools \
    mesa-utils \
    && pacman -Scc --noconfirm

ENV USER=steam
ENV HOME=/home/${USER}

RUN useradd -m -s /bin/bash ${USER} && \
    echo "${USER} ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers.d/${USER} && \
    chmod 0440 /etc/sudoers.d/${USER}

RUN usermod -aG video,audio,input ${USER}

COPY --chown=steam:steam entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

COPY sway.config /etc/sway/config

COPY --chown=steam:steam steamtools/kill-steam.sh /usr/local/bin/kill-steam.sh

RUN wget -q -O /usr/local/bin/vhclient https://www.virtualhere.com/sites/default/files/usbclient/vhclientx86_64 && \
    chmod +x /usr/local/bin/vhclient

USER ${USER}
WORKDIR ${HOME}

ENV XDG_RUNTIME_DIR=/tmp/runtime-steam
ENV STEAM_FRAME_RATE_LIMIT=0

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
