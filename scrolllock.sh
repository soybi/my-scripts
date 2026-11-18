#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (e.g., sudo ./setup-debian-headless-scrolllock.sh)"
  exit 1
fi

echo "[1/5] Installing brightnessctl and triggerhappy..."
apt-get update -qq
apt-get install -y -qq brightnessctl triggerhappy

echo "[2/5] Creating Scroll Lock LED toggle script at /usr/local/bin/toggle-scroll-led.sh..."
cat << 'EOF' > /usr/local/bin/toggle-scroll-led.sh
#!/bin/bash
# Automatically detect all scrolllock LEDs under /sys/class/leds/
LEDS=$(ls -d /sys/class/leds/*scrolllock 2>/dev/null || true)

if [ -z "$LEDS" ]; then
    exit 0
fi

for LED_PATH in $LEDS; do
    DEV_NAME=$(basename "$LED_PATH")
    CURRENT=$(brightnessctl -d "$DEV_NAME" get 2>/dev/null || echo 0)
    if [ "$CURRENT" -eq 0 ]; then
        brightnessctl -d "$DEV_NAME" set 1 >/dev/null 2>&1 || true
    else
        brightnessctl -d "$DEV_NAME" set 0 >/dev/null 2>&1 || true
    fi
done
EOF
chmod +x /usr/local/bin/toggle-scroll-led.sh

echo "[3/5] Creating boot-time script to turn LED ON at /usr/local/bin/boot-scroll-led.sh..."
cat << 'EOF' > /usr/local/bin/boot-scroll-led.sh
#!/bin/bash
LEDS=$(ls -d /sys/class/leds/*scrolllock 2>/dev/null || true)
for LED_PATH in $LEDS; do
    DEV_NAME=$(basename "$LED_PATH")
    brightnessctl -d "$DEV_NAME" set 1 >/dev/null 2>&1 || true
done
EOF
chmod +x /usr/local/bin/boot-scroll-led.sh

echo "[4/5] Configuring triggerhappy daemon to listen for KEY_SCROLLLOCK..."
mkdir -p /etc/triggerhappy/triggers.d
cat << 'EOF' > /etc/triggerhappy/triggers.d/scrolllock.conf
KEY_SCROLLLOCK 1 /usr/local/bin/toggle-scroll-led.sh
EOF

# Ensure triggerhappy runs as root so it can write to /sys/class/leds/ without udev permission errors
mkdir -p /etc/systemd/system/triggerhappy.service.d
cat << 'EOF' > /etc/systemd/system/triggerhappy.service.d/override.conf
[Service]
ExecStart=
ExecStart=/usr/sbin/thd --triggers /etc/triggerhappy/triggers.d/ --socket /run/thd.socket --user root --deviceglob /dev/input/event*
EOF

echo "[5/5] Creating systemd boot service and udev rule for hotplugging..."
cat << 'EOF' > /etc/systemd/system/scrolllock-led-boot.service
[Unit]
Description=Turn on Scroll Lock LED at boot on headless Debian
After=systemd-udev-settle.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/boot-scroll-led.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# Udev rule so plugging in an external USB keyboard after boot also turns its LED on
cat << 'EOF' > /etc/udev/rules.d/99-scrolllock-led.rules
ACTION=="add", SUBSYSTEM=="leds", KERNEL=="*scrolllock", RUN+="/bin/sh -c 'echo 1 > /sys$devpath/brightness'"
EOF

udevadm control --reload-rules
systemctl daemon-reload
systemctl enable --now scrolllock-led-boot.service
systemctl restart triggerhappy.service
systemctl enable triggerhappy.service

echo ""
echo "Setup complete for headless Debian!"
echo "- The Scroll Lock LED will turn ON automatically at boot and when plugged in."
echo "- Pressing the Scroll Lock key will toggle the LED ON/OFF anywhere (even before TTY login)."
