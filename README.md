# My Linux Utility & Setup Scripts

A personal collection of Bash utilities, hardware workarounds, and automated system setup scripts for **CachyOS (Arch Linux)** and **Debian** homelab environments.

---

## Included Scripts

### 1. `health` — CachyOS System Health Reporter
A lightweight, dependency-minimal terminal diagnostic tool tailored for CachyOS/Arch systems.

**Features:**
- **System & Kernel:** Displays OS release, active kernel version, and uptime.
- **CPU, Load & Temperatures:** Shows CPU model, live utilization percentage, load averages, and hardware sensor temperatures (`lm_sensors` / thermal zones).
- **GPU Detection:** Lists single or dual-GPU configurations (Intel iGPU + NVIDIA dGPU) and live NVIDIA metrics when available.
- **Memory & ZRAM:** Summarizes RAM/Swap usage and CachyOS `zstd` ZRAM compression stats.
- **Storage & S.M.A.R.T.:** Reports physical partition usage (filtering out virtual/overlay filesystems), masks SMB network share IPs by default, and queries drive S.M.A.R.T. health, temperatures, and power-on hours.
- **Network & Internet:** Checks active interface, ICMP latency, and DNS resolution while keeping local and public IP addresses hidden by default.
- **Systemd & Package Health:** Flags failed systemd units, orphan packages, and `pacman` cache disk usage.

**Usage:**
```bash
health                  # Run full health check (IPs hidden for screenshot privacy)
health --ip             # Reveal local LAN IP, public WAN IP, and SMB share IPs
health --export         # Save a clean plain-text report (health-report-YYYYMMDD-HHMMSS.txt)
health -e ~/report.txt  # Export report to a custom file path
```

---

### 2. `scrolllock.sh` (and `cachyos-xfce-scrolllock-led-bundle.zip`)
Configures keyboard Scroll Lock LED toggling on X11/XFCE desktop environments (commonly required for backlit budget/gaming keyboards on Linux).

**Usage:**
```bash
chmod +x scrolllock.sh
./scrolllock.sh
```

---

### 3. `setup-gt630m-tf2.sh`
Configures legacy NVIDIA GeForce GT 630M drivers and Optimus/hybrid graphics offloading specifically tuned for running *Team Fortress 2* on Linux.

---

### 4. `revert-all-nvidia-setup.sh` & `revert-all-nvidia-setup-v2.sh`
Cleanup and rollback scripts to safely purge legacy proprietary NVIDIA drivers, Bumblebee/Optimus configurations, and custom X11/modprobe rules, restoring default open-source graphics drivers (`Mesa` / `nouveau`).
- **Note:** Use `revert-all-nvidia-setup-v2.sh` for the latest power-management and boot-freeze fixes.

---

### 5. `setup-headless-server.sh`
Automated provisioning script for setting up a lightweight, headless **Debian** home server (optimized for older laptops repurposed as low-power NAS/photo backup servers), including storage tuning (`noatime`, `hdparm` spin-down), swap configuration, and Docker log limits.

---

### 6. `setup-toggle-xfce-theme.sh`

Automated setup script that installs a 1-click Light/Dark theme switcher (`~/.local/bin/toggle-xfce-theme.sh`) and adds a corresponding toggle button directly to the **XFCE Panel**.

**Features:**
- **Full Desktop Toggle:** Switches GTK style (`Matcha-light-aliz` / `Matcha-dark-aliz`), window manager borders, icon themes (`Papirus-Light` / `Papirus-Dark`), and desktop wallpaper simultaneously via `xfconf-query`.
- **1-Click Panel Integration:** Automatically creates the `.desktop` launcher entry and registers it on `panel-1` so you can flip themes from the panel with zero background RAM usage.

**Usage:**
```bash
./setup-toggle-xfce-theme.sh
```

## Quick Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com ~/my-scripts
   cd ~/my-scripts
   ```

2. **Make scripts executable and symlink `health` to your local binary path:**
   ```bash
   chmod +x ~/my-scripts/*
   mkdir -p ~/.local/bin
   ln -sf ~/my-scripts/health ~/.local/bin/health
   ```

3. **Optional dependencies for `health`:**
   ```bash
   sudo pacman -S lm_sensors smartmontools
   sudo sensors-detect --auto
   ```
   *(Optional)* Allow passwordless S.M.A.R.T. checks without running `sudo health`:
   ```bash
   echo "\$USER ALL=(ALL) NOPASSWD: /usr/bin/smartctl" | sudo tee /etc/sudoers.d/smartctl > /dev/null
   ```
