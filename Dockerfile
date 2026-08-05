FROM archlinux:latest

# 1. Enable 32-bit Multilib Repositories (Mandatory for Steam & Proton DirectX translation)
RUN echo -e "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist" >> /etc/pacman.conf

# 2. Base Bootstrap - Install system requirements, graphics drivers & Steam
RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm \
    base-devel \
    sudo \
    ttf-liberation \
    xorg-server \
    xorg-xinit \
    xorg-xrandr \
    wmctrl \
    # Audio stack (PulseAudio / PipeWire compat)
    pulseaudio \
    lib32-pulseaudio \
    alsa-plugins \
    lib32-alsa-plugins \
    # Graphics drivers & Vulkan loader (Intel/AMD Mesa default)
    vulkan-icd-loader \
    lib32-vulkan-icd-loader \
    mesa \
    lib32-mesa \
    vulkan-radeon \
    lib32-vulkan-radeon \
    vulkan-intel \
    lib32-vulkan-intel \
    # Game Controller / Input Dependencies
    lib32-systemd \
    usbutils \
    # Steam
    steam \
    && pacman -Scc --noconfirm

# 3. Create non-root user 'steam' (Steam prevents root execution)
ENV USER=steam
ENV HOME=/home/${USER}

RUN useradd -m -s /bin/bash ${USER} && \
    echo "${USER} ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers.d/${USER} && \
    chmod 0440 /etc/sudoers.d/${USER}

# Grant user permissions to GPU render loops, input controllers, and audio
RUN usermod -aG video,audio,input ${USER}

# 4. Copy Startup Script & Set Permissions
COPY --chown=steam:steam entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

USER ${USER}
WORKDIR ${HOME}

# 5. SteamOS Environment Variables
ENV DISPLAY=:0
ENV XDG_RUNTIME_DIR=/tmp/runtime-steam
ENV STEAM_FRAME_RATE_LIMIT=0

# Trigger the auto-update and Big Picture launch
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
