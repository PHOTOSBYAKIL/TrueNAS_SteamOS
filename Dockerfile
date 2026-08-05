FROM archlinux:latest

# 1. Enable 32-bit Multilib Repositories
RUN echo -e "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist" >> /etc/pacman.conf

# 2. Base Bootstrap (Includes xterm for Steam setup and sunshine for streaming)
RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm \
    base-devel \
    sudo \
    wget \
    ttf-liberation \
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

USER ${USER}
WORKDIR ${HOME}

# 5. SteamOS Environment Variables
ENV XDG_RUNTIME_DIR=/tmp/runtime-steam
ENV STEAM_FRAME_RATE_LIMIT=0

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
