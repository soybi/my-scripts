#!/usr/bin/env bash
set -euo pipefail

# Ensure script is not run directly as root so $HOME resolves to your user account
if [[ "$EUID" -eq 0 ]]; then
    echo "Please run this script as your regular user (without sudo). It will prompt for sudo when needed."
    exit 1
fi

echo "==> 1. Installing CachyOS LTS kernel, NVIDIA 390xx drivers, Bumblebee, VirtualGL, and dependencies..."
sudo pacman -Syu --needed \
    linux-cachyos-lts \
    linux-cachyos-lts-headers \
    nvidia-390xx-dkms \
    nvidia-390xx-utils \
    lib32-nvidia-390xx-utils \
    nvidia-390xx-settings \
    bumblebee \
    primus \
    lib32-primus \
    virtualgl \
    lib32-virtualgl \
    mesa-utils \
    lib32-mesa-utils \
    libcurl-gnutls

echo "==> 2. Blacklisting nouveau and rebuilding initramfs..."
echo "blacklist nouveau" | sudo tee /etc/modprobe.d/blacklist-nouveau.conf > /dev/null
sudo mkinitcpio -P

echo "==> 3. Configuring Bumblebee (PMMethod=none & PCI:01:00:0 to prevent freezes)..."
sudo tee /etc/bumblebee/bumblebee.conf > /dev/null << 'EOF'
[bumblebeed]
VirtualDisplay=:8
KeepUnusedXServer=false
ServerGroup=bumblebee
TurnCardOffAtExit=false
NoEcoModeOverride=false
Driver=nvidia

[optirun]
Bridge=auto
VGLTransport=proxy
PrimusLibraryPath=/usr/lib/primus:/usr/lib32/primus
AllowFallbackToIGC=false

[driver-nvidia]
KernelDriver=nvidia
PMMethod=none
LibraryPath=/usr/lib/nvidia:/usr/lib32/nvidia:/usr/lib:/usr/lib32
XorgModulePath=/usr/lib/nvidia/xorg,/usr/lib/xorg/modules
XorgConfFile=/etc/bumblebee/xorg.conf.nvidia
EOF

sudo tee /etc/bumblebee/xorg.conf.nvidia > /dev/null << 'EOF'
Section "ServerLayout"
    Identifier  "Layout0"
    Option      "AutoAddDevices" "false"
    Option      "AutoAddGPU" "false"
EndSection

Section "Device"
    Identifier  "DiscreteNvidia"
    Driver      "nvidia"
    VendorName  "NVIDIA Corporation"
    BusID       "PCI:01:00:0"
    Option      "ProbeAllGpus" "false"
    Option      "NoLogo" "true"
    Option      "UseEDID" "false"
    Option      "UseDisplayDevice" "none"
EndSection
EOF

sudo gpasswd -a "$USER" bumblebee
sudo systemctl enable bumblebeed.service

echo "==> 4. Creating general-purpose /usr/local/bin/nvrun wrapper..."
sudo tee /usr/local/bin/nvrun > /dev/null << 'EOF'
#!/bin/bash
export PRIMUS_LOAD_GLOBAL="libGL.so.1"
export PRIMUS_libGLd="/usr/lib/libGLX_nvidia.so.0:/usr/lib32/libGLX_nvidia.so.0"
exec primusrun "$@"
EOF
sudo chmod +x /usr/local/bin/nvrun

echo "==> 5. Setting GRUB to remember your last selected kernel (safe on ext4)..."
sudo sed -i 's/^#*GRUB_DEFAULT=.*/GRUB_DEFAULT=saved/' /etc/default/grub
if grep -q '^#*GRUB_SAVEDEFAULT=' /etc/default/grub; then
    sudo sed -i 's/^#*GRUB_SAVEDEFAULT=.*/GRUB_SAVEDEFAULT=true/' /etc/default/grub
else
    echo 'GRUB_SAVEDEFAULT=true' | sudo tee -a /etc/default/grub > /dev/null
fi
sudo grub-mkconfig -o /boot/grub/grub.cfg

echo "==> 6. Setting up Team Fortress 2 VirtualGL launcher & Xfce menu shortcut..."
mkdir -p "$HOME/.local/bin" "$HOME/.local/share/applications"

cat > "$HOME/.local/bin/tf2-nvidia.sh" << 'EOF'
#!/bin/bash
cd "$HOME/.local/share/Steam/steamapps/common/Team Fortress 2/" || exit 1
export SteamAppId=440
export SteamGameId=440
export LD_LIBRARY_PATH="$PWD/bin/linux64:$HOME/.local/share/Steam/linux64:$LD_LIBRARY_PATH"
export VGL_READBACK=pbo
exec optirun -b virtualgl -c proxy ./tf_linux64 -steam -gl -novid -nojoy -nosteamcontroller -nohltv -particles 1 -precachefontchars "$@"
EOF
chmod +x "$HOME/.local/bin/tf2-nvidia.sh"

cat > "$HOME/.local/share/applications/tf2-nvidia.desktop" << EOF
[Desktop Entry]
Name=Team Fortress 2 (GT 630M)
Comment=Play Team Fortress 2 on NVIDIA GeForce GT 630M
Exec=$HOME/.local/bin/tf2-nvidia.sh
Icon=steam_icon_440
Terminal=false
Type=Application
Categories=Game;ActionGame;
EOF
update-desktop-database "$HOME/.local/share/applications/"

echo "==> 7. Applying mastercomfig overrides & CPU optimizations for TF2..."
TF2_OVERRIDES="$HOME/.local/share/Steam/steamapps/common/Team Fortress 2/tf/cfg/overrides"
if [[ -d "$HOME/.local/share/Steam/steamapps/common/Team Fortress 2/tf" ]]; then
    mkdir -p "$TF2_OVERRIDES"

    cat > "$TF2_OVERRIDES/modules.cfg" << 'EOF'
shadows=off
ragdolls=off
gibs=off
props=low
sprays=off
muzzleflash=off
dynamic_background=off
packet_rate=congestion
characters=low
eyes=off
lighting=low
water=low
EOF

    cat > "$TF2_OVERRIDES/autoexec.cfg" << 'EOF'
cl_showfps 1
fov_desired 90
viewmodel_fov 70
tf_use_min_viewmodels 1
mat_queue_mode 2
r_drawtracers_firstperson 0
cl_jiggle_bone_framerate_cutoff 0
glow_outline_effect_enable 0
tf_enable_glows_after_respawn 0
cl_playerspraydisable 1
r_eyemove 0
r_flex 0
fps_max 60
EOF
else
    echo "    (TF2 folder not found yet; skipping cfg overrides.)"
fi

echo "==> Done! Reboot into 'linux-cachyos-lts' once so GRUB saves it as default."
