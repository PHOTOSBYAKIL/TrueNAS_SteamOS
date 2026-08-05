#!/bin/bash
set -e

echo "=== [SteamOS Container] Checking for System & Steam Updates ==="

# Force refresh package database and upgrade all system packages + multilib libraries
sudo pacman -Syu --noconfirm --needed

# Clean package cache to keep container layer lightweight
sudo pacman -Scc --noconfirm

echo "=== [SteamOS Container] Starting X-Server / Display Environment ==="

# Ensure runtime socket directory exists with proper permissions
sudo mkdir -p /tmp/.X11-unix
sudo chmod 1777 /tmp/.X11-unix

# Launch Steam with Steam Deck/SteamOS UI flags:
# -gamepadui : Launches the modern SteamOS 3.0 Big Picture interface
# -steamos   : Enables SteamOS specific overlay hooks and power options
# -silent    : Prevents popup dialogs from delaying full screen boot
echo "=== [SteamOS Container] Launching SteamOS Big Picture Mode ==="
exec steam -gamepadui -steamos -silent "$@"
