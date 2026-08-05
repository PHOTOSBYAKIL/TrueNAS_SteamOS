#!/bin/bash
set -e

echo "=== [SteamOS Container] Checking for System Updates ==="
sudo pacman -Syu --noconfirm --needed
sudo pacman -Scc --noconfirm

echo "=== [SteamOS Container] Starting Virtual Display (Xvfb) ==="
# Create a 1080p 60Hz virtual monitor on display port :99
Xvfb :99 -screen 0 1920x1080x24 -nolisten tcp -dpi 96 +extension RANDR &
export DISPLAY=:99

echo "=== [SteamOS Container] Starting Sunshine ==="
# Launch Sunshine in the background to capture Display :99
sunshine &

echo "=== [SteamOS Container] Launching SteamOS Big Picture Mode ==="
# Launch Steam into the virtual display
exec steam -gamepadui -steamos -silent "$@"
