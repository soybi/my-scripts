#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (e.g., sudo ./setup-scrolllock-led.sh)"
    exit 1
fi

echo "[1/5] Installing xorg-xset..."
pacman -Sy --needed --noconfirm xorg-xset

echo "[2/5] Ensuring XKB Mod3 does not include Scroll_Lock..."
if [ -f /usr/share/X11/xkb/symbols/pc ]; then
    sed -i 's/modifier_map Mod3  { <LVL5>, Scroll_Lock };/modifier_map Mod3  { <LVL5> };/' /usr/share/X11/xkb/symbols/pc
fi

echo "[3/5] Creating /usr/local/bin/toggle-scroll-led.sh..."
cat << 'EOF' > /usr/local/bin/toggle-scroll-led.sh
#!/bin/bash
STATE_FILE="/tmp/scroll_led_state"
if [ -f "$STATE_FILE" ] && [ "$(cat "$STATE_FILE")" = "on" ]; then
    xset -led named "Scroll Lock"
    echo "off" > "$STATE_FILE"
else
    xset led named "Scroll Lock"
    echo "on" > "$STATE_FILE"
fi
EOF
chmod +x /usr/local/bin/toggle-scroll-led.sh

echo "[4/5] Creating LightDM wrapper script and updating /etc/lightdm/lightdm.conf..."
cat << 'EOF' > /usr/local/bin/lightdm-scroll-led.sh
#!/bin/sh
/usr/bin/xset led named "Scroll Lock" || true
echo "on" > /tmp/scroll_led_state
chmod 666 /tmp/scroll_led_state 2>/dev/null || true
exit 0
EOF
chmod +x /usr/local/bin/lightdm-scroll-led.sh

if [ -f /etc/lightdm/lightdm.conf ]; then
    cp /etc/lightdm/lightdm.conf "/etc/lightdm/lightdm.conf.bak.$(date +%Y%m%d%H%M%S)"
    if grep -q "^#greeter-setup-script=" /etc/lightdm/lightdm.conf; then
        sed -i 's|^#greeter-setup-script=.*|greeter-setup-script=/usr/local/bin/lightdm-scroll-led.sh|' /etc/lightdm/lightdm.conf
    elif grep -q "^greeter-setup-script=" /etc/lightdm/lightdm.conf; then
        sed -i 's|^greeter-setup-script=.*|greeter-setup-script=/usr/local/bin/lightdm-scroll-led.sh|' /etc/lightdm/lightdm.conf
    else
        sed -i '/^\[Seat:\*\]/a greeter-setup-script=/usr/local/bin/lightdm-scroll-led.sh' /etc/lightdm/lightdm.conf
    fi
fi

echo "[5/5] Binding Scroll_Lock shortcut in XFCE (if active session is detected)..."
TARGET_USER="${SUDO_USER:-$USER}"
if [ -n "$TARGET_USER" ] && [ "$TARGET_USER" != "root" ]; then
    USER_ID=$(id -u "$TARGET_USER")
    DBUS_ADDR="unix:path=/run/user/${USER_ID}/bus"
    if [ -S "/run/user/${USER_ID}/bus" ]; then
        sudo -u "$TARGET_USER" DBUS_SESSION_BUS_ADDRESS="$DBUS_ADDR" xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/Scroll_Lock" -n -t string -s "/usr/local/bin/toggle-scroll-led.sh" 2>/dev/null || true
        echo "XFCE shortcut bound for user $TARGET_USER."
    else
        echo "Note: No active DBus session found. Bind /usr/local/bin/toggle-scroll-led.sh to Scroll_Lock manually in XFCE Settings -> Keyboard -> Application Shortcuts."
    fi
fi

echo "Setup complete! Reboot your system to apply LightDM changes."
