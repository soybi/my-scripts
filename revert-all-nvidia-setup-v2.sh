#!/usr/bin/env bash
set -euo pipefail

if [[ "$EUID" -eq 0 ]]; then
    echo "Please run this script as your regular user (without sudo). It will prompt for sudo when needed."
    exit 1
fi

echo "==> 1. Stopping and disabling Bumblebee service..."
sudo systemctl disable --now bumblebeed.service 2>/dev/null || true

echo "==> 2. Removing custom scripts, desktop entries, and temporary folders..."
rm -rf \
    "$HOME/.local/share/primus-fix" \
    "$HOME/.local/share/sober-vgl" \
    "$HOME/.local/bin/tf2-nvidia.sh" \
    "$HOME/.local/bin/sober-nvidia.sh" \
    "$HOME/.local/share/applications/tf2-nvidia.desktop" \
    "$HOME/.local/share/applications/sober-nvidia.desktop" \
    "$HOME/.local/share/applications/firefox.desktop" \
    "$HOME/.local/share/applications/brave-browser.desktop" \
    "$HOME/setup-gt630m-tf2.sh"

sudo rm -f /usr/local/bin/nvrun /etc/modprobe.d/blacklist-nouveau.conf
update-desktop-database "$HOME/.local/share/applications/" 2>/dev/null || true

echo "==> 3. Reverting Team Fortress 2 overrides and restoring tf.sh..."
TF2_DIR="$HOME/.local/share/Steam/steamapps/common/Team Fortress 2"
if [[ -f "$TF2_DIR/tf.sh.bak" ]]; then
    mv -f "$TF2_DIR/tf.sh.bak" "$TF2_DIR/tf.sh"
fi
rm -f \
    "$TF2_DIR/tf/cfg/overrides/modules.cfg" \
    "$TF2_DIR/tf/cfg/overrides/autoexec.cfg"
rmdir --ignore-fail-on-non-empty "$TF2_DIR/tf/cfg/overrides" 2>/dev/null || true

echo "==> 4. Reverting Sober (Roblox) Flatpak overrides and config..."
if command -v flatpak >/dev/null 2>&1; then
    flatpak override --user --reset org.vinegarhq.Sober 2>/dev/null || true
fi
rm -f "$HOME/.var/app/org.vinegarhq.Sober/config/sober/config.json"

echo "==> 5. Removing user from bumblebee group..."
sudo gpasswd -d "$USER" bumblebee 2>/dev/null || true

echo "==> 6. Uninstalling NVIDIA 390xx, Bumblebee, Primus, VirtualGL, and extra packages..."
PKGS_TO_REMOVE=(
    nvidia-390xx-dkms
    nvidia-390xx-utils
    lib32-nvidia-390xx-utils
    nvidia-390xx-settings
    libxnvctrl-390xx
    bumblebee
    primus
    lib32-primus
    virtualgl
    lib32-virtualgl
    lib32-mesa-utils
    libcurl-gnutls
)

INSTALLED_PKGS=()
for pkg in "${PKGS_TO_REMOVE[@]}"; do
    if pacman -Qi "$pkg" >/dev/null 2>&1; then
        INSTALLED_PKGS+=("$pkg")
    fi
done

if [[ ${#INSTALLED_PKGS[@]} -gt 0 ]]; then
    sudo pacman -Rns --noconfirm "${INSTALLED_PKGS[@]}"
fi

echo "==> 7. Rebuilding initramfs..."
sudo mkinitcpio -P

echo "==> Done! All changes have been reverted while keeping your GRUB settings intact. Reboot your system when ready."
