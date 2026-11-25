#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (e.g., sudo ./revert-scrolllock-led.sh)"
    exit 1
fi

echo "[1/4] Removing helper scripts..."
rm -f /usr/local/bin/toggle-scroll-led.sh
rm -f /usr/local/bin/lightdm-scroll-led.sh

echo "[2/4] Cleaning up state file and turning off LED..."
rm -f /tmp/scroll_led_state
if command -v xset >/dev/null 2>&1 && [ -n "$DISPLAY" ]; then
    xset -led named "Scroll Lock" 2>/dev/null || true
fi

echo "[3/4] Restoring /etc/lightdm/lightdm.conf..."
if [ -f /etc/lightdm/lightdm.conf ]; then
    cp /etc/lightdm/lightdm.conf "/etc/lightdm/lightdm.conf.bak.$(date +%Y%m%d%H%M%S)"
    sed -i 's|^greeter-setup-script=/usr/local/bin/lightdm-scroll-led.sh|#greeter-setup-script=|' /etc/lightdm/lightdm.conf
fi

echo "[4/4] Removing XFCE keyboard shortcut..."
TARGET_USER="${SUDO_USER:-$USER}"
if [ -n "$TARGET_USER" ] && [ "$TARGET_USER" != "root" ]; then
    USER_ID=$(id -u "$TARGET_USER")
    DBUS_ADDR="unix:path=/run/user/${USER_ID}/bus"
    if [ -S "/run/user/${USER_ID}/bus" ]; then
        sudo -u "$TARGET_USER" DBUS_SESSION_BUS_ADDRESS="$DBUS_ADDR" xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/Scroll_Lock" -r 2>/dev/null || true
        echo "XFCE shortcut removed for user $TARGET_USER."
    else
        echo "Note: Remove the Scroll_Lock shortcut manually in XFCE Settings -> Keyboard -> Application Shortcuts."
    fi
fi

echo "Revert complete!"
