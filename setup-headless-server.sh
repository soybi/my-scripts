#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# CONFIGURATION - Edit these values before running
# ==============================================================================
OPTICAL_DRIVE_UUID="YOUR_OPTICAL_DRIVE_UUID"   # From: lsblk -o NAME,SIZE,FSTYPE,UUID
OPTICAL_DRIVE_FSTYPE="ext4"                       # Usually ext4 (or ntfs/exfat)
MEDIA_BASE_DIR="/srv/media"                       # Optical bay drive mounts here
BACKUP_DEST_DIR="/mnt/backup"                     # Optional external USB backup path
SAMBA_USER="mediauser"
SAMBA_PASS="CHANGE_ME_STRONG_PASSWORD"
IMMICH_DB_PASS="CHANGE_ME_STRONG_PASSWORD"
TIMEZONE="Asia/Manila"
HDD_SPINDOWN_MINUTES=20                           # Spin down optical bay HDD after X mins idle
# ==============================================================================

if [[ $EUID -ne 0 ]]; then
   echo "Error: Please run this script as root (sudo bash $0)"
   exit 1
fi

if [[ "$OPTICAL_DRIVE_UUID" == "PASTE-YOUR-DRIVE-UUID-HERE" || -z "$OPTICAL_DRIVE_UUID" ]]; then
   echo "Error: Please set OPTICAL_DRIVE_UUID at the top of the script first."
   echo "Run 'lsblk -o NAME,SIZE,FSTYPE,UUID' to find your optical bay drive's UUID."
   exit 1
fi

echo ">>> 1. Updating Debian 13 and installing headless server packages..."
apt-get update && apt-get upgrade -y
apt-get install -y curl wget git ufw samba rsync ca-certificates gnupg zram-tools hdparm

echo ">>> 2. Configuring Headless Boot & Screen Power-Off..."
systemctl set-default multi-user.target

if ! grep -q "consoleblank=60" /etc/default/grub; then
    sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="consoleblank=60 /' /etc/default/grub
    update-grub
fi

sed -i 's/#HandleLidSwitch=suspend/HandleLidSwitch=ignore/' /etc/systemd/logind.conf
sed -i 's/#HandleLidSwitchExternalPower=suspend/HandleLidSwitchExternalPower=ignore/' /etc/systemd/logind.conf
systemctl restart systemd-logind

echo ">>> 3. Optimizing OS SSD Lifespan (Weekly TRIM + Root noatime)..."
systemctl enable --now fstrim.timer

cp /etc/fstab /etc/fstab.bak

# Add 'noatime' to root (/) mount options in /etc/fstab to minimize SSD metadata writes
awk '$2 == "/" && $4 !~ /noatime/ { $4 = $4 ",noatime" } { print }' /etc/fstab.bak > /etc/fstab

echo ">>> 4. Mounting Optical Bay Secondary Drive via UUID & Setting HDD Spin-Down..."
mkdir -p "$MEDIA_BASE_DIR"

if ! grep -q "$OPTICAL_DRIVE_UUID" /etc/fstab; then
    echo "UUID=$OPTICAL_DRIVE_UUID $MEDIA_BASE_DIR $OPTICAL_DRIVE_FSTYPE defaults,nofail,noatime 0 2" >> /etc/fstab
fi

systemctl daemon-reload
mount -a

if ! mountpoint -q "$MEDIA_BASE_DIR"; then
    echo "Error: Optical bay drive failed to mount at $MEDIA_BASE_DIR. Check UUID and filesystem type."
    exit 1
fi

# Configure automatic HDD spin-down on the optical bay drive to save power and reduce heat
OPTICAL_PART=$(blkid -U "$OPTICAL_DRIVE_UUID")
OPTICAL_DISK="/dev/$(lsblk -no pkname "$OPTICAL_PART" | head -n1)"

if [[ -b "$OPTICAL_DISK" ]]; then
    # hdparm -S uses units of 5 seconds for values 1-240 (20 mins = 1200s / 5 = 240)
    SPINDOWN_VAL=$(( (HDD_SPINDOWN_MINUTES * 60) / 5 ))
    if [[ $SPINDOWN_VAL -gt 240 ]]; then SPINDOWN_VAL=240; fi

    cat <<EOF > /etc/systemd/system/optical-hdd-spindown.service
[Unit]
Description=Set idle spin-down timeout for Optical Bay HDD ($OPTICAL_DISK)
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/sbin/hdparm -B 127 -S $SPINDOWN_VAL $OPTICAL_DISK
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now optical-hdd-spindown.service
fi

echo ">>> 5. Optimizing Memory (ZRAM + Smart Swapfile Check) for 4GB RAM Ceiling..."
cat <<EOF > /etc/default/zramswap
ALGO=zstd
PERCENT=50
PRIORITY=100
EOF
systemctl restart zramswap || true

# Check existing disk swap before creating an extra /swapfile
EXISTING_SWAP_MB=$(free -m | awk '/^Swap:/ {print $2}')
if [ ! -f /swapfile ] && [ "$EXISTING_SWAP_MB" -lt 2048 ]; then
    fallocate -l 4G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw,pri=10 0 0' >> /etc/fstab
    echo "Created 4GB /swapfile (existing swap was under 2GB)."
else
    echo "Skipping extra /swapfile creation (existing swap is ${EXISTING_SWAP_MB}MB + ZRAM active)."
fi

sysctl -w vm.swappiness=15
echo 'vm.swappiness=15' > /etc/sysctl.d/99-server-memory.conf

echo ">>> 6. Creating dedicated media user and folders on Optical Bay Drive..."
if ! id -u "$SAMBA_USER" >/dev/null 2>&1; then
    groupadd -g 3000 "$SAMBA_USER"
    useradd -m -u 3000 -g 3000 -s /usr/sbin/nologin "$SAMBA_USER"
fi

mkdir -p "$MEDIA_BASE_DIR/immich"
mkdir -p "$MEDIA_BASE_DIR/shared"
mkdir -p "$BACKUP_DEST_DIR"
mkdir -p /opt/immich

chown -R "$SAMBA_USER":"$SAMBA_USER" "$MEDIA_BASE_DIR"
chmod -R 775 "$MEDIA_BASE_DIR"

echo ">>> 7. Configuring Samba network file share..."
(echo "$SAMBA_PASS"; echo "$SAMBA_PASS") | smbpasswd -s -a "$SAMBA_USER"

cp /etc/samba/smb.conf /etc/samba/smb.conf.bak
cat <<EOF >> /etc/samba/smb.conf

[HomeMedia]
   comment = Home Photo and Video Share
   path = $MEDIA_BASE_DIR/shared
   browseable = yes
   read only = no
   guest ok = no
   valid users = $SAMBA_USER
   create mask = 0664
   directory mask = 0775
EOF

systemctl restart smbd
systemctl enable smbd

echo ">>> 8. Installing Docker Engine & Configuring SSD-Friendly Log Limits..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Cap Docker container logs at 10MB (max 3 files) to prevent endless SSD log writes
mkdir -p /etc/docker
cat <<EOF > /etc/docker/daemon.json
{
  "log-driver": "local",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
systemctl restart docker

echo ">>> 9. Deploying Lightweight Immich (Storing Media on Optical Bay Drive)..."
cd /opt/immich
wget -q -O docker-compose.yml https://github.com/immich-app/immich/releases/latest/download/docker-compose.yml

cat <<EOF > .env
UPLOAD_LOCATION=$MEDIA_BASE_DIR/immich
DB_DATA_LOCATION=/opt/immich/postgres
TZ=$TIMEZONE
IMMICH_VERSION=release
DB_PASSWORD=$IMMICH_DB_PASS
DB_USERNAME=postgres
DB_DATABASE_NAME=immich
EOF

cat <<EOF > docker-compose.override.yml
services:
  immich-machine-learning:
    deploy:
      replicas: 0
  database:
    deploy:
      resources:
        limits:
          memory: 512M
  redis:
    deploy:
      resources:
        limits:
          memory: 128M
EOF

docker compose up -d

echo ">>> 10. Setting up Low-Impact Daily Backup (Optical Bay -> Backup Drive)..."
cat <<EOF > /usr/local/bin/backup-media.sh
#!/usr/bin/env bash
if mountpoint -q "$BACKUP_DEST_DIR"; then
    ionice -c 3 nice -n 19 rsync -avh --delete "$MEDIA_BASE_DIR/" "$BACKUP_DEST_DIR/media_backup/" >> /var/log/media-backup.log 2>&1
    echo "\$(date): Backup completed successfully." >> /var/log/media-backup.log
else
    echo "\$(date): Skipping backup - no external drive mounted at $BACKUP_DEST_DIR." >> /var/log/media-backup.log
fi
EOF

chmod +x /usr/local/bin/backup-media.sh
(crontab -l 2>/dev/null | grep -v "backup-media.sh"; echo "0 3 * * * /usr/local/bin/backup-media.sh") | crontab -

echo ">>> 11. Configuring UFW Firewall..."
ufw allow OpenSSH
ufw allow Samba
ufw allow 2283/tcp comment 'Immich Web UI'
ufw --force enable

SERVER_IP=$(hostname -I | awk '{print $1}')
echo "======================================================================"
echo " Headless Asus K40IJ Media Server Setup Complete!"
echo " - Optical Bay Drive: Mounted at $MEDIA_BASE_DIR (Spindown: ${HDD_SPINDOWN_MINUTES}m)"
echo " - SSD Protection:    Weekly TRIM + root noatime + Docker log caps"
echo " - Immich Web UI:     http://$SERVER_IP:2283"
echo " - Samba Share:       \\\\$SERVER_IP\\HomeMedia (User: $SAMBA_USER)"
echo "======================================================================"
