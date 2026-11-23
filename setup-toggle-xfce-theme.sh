#!/usr/bin/env bash
set -euo pipefail

BIN_DIR="$HOME/.local/bin"
SCRIPT_PATH="$BIN_DIR/toggle-xfce-theme.sh"

# 1. Create the toggle script
mkdir -p "$BIN_DIR"

cat << 'EOF' > "$SCRIPT_PATH"
#!/usr/bin/env bash

# --- LIGHT PRESET ---
LIGHT_GTK="Matcha-light-aliz"
LIGHT_WM="Matcha-light-aliz"
LIGHT_ICONS="Papirus-Light"
LIGHT_WALL="/usr/share/backgrounds/Asta.jpg"

# --- DARK PRESET ---
DARK_GTK="Matcha-dark-aliz"
DARK_WM="Matcha-dark-aliz"
DARK_ICONS="Papirus-Dark"
DARK_WALL="/usr/share/backgrounds/Asta.jpg"

# Check current GTK theme
CURRENT_GTK=$(xfconf-query -c xsettings -p /Net/ThemeName)

if [ "$CURRENT_GTK" = "$LIGHT_GTK" ]; then
    TARGET_GTK="$DARK_GTK"
    TARGET_WM="$DARK_WM"
    TARGET_ICONS="$DARK_ICONS"
    TARGET_WALL="$DARK_WALL"
else
    TARGET_GTK="$LIGHT_GTK"
    TARGET_WM="$LIGHT_WM"
    TARGET_ICONS="$LIGHT_ICONS"
    TARGET_WALL="$LIGHT_WALL"
fi

# Apply GTK, Icons, and Window Manager themes
xfconf-query -c xsettings -p /Net/ThemeName -s "$TARGET_GTK"
xfconf-query -c xsettings -p /Net/IconThemeName -s "$TARGET_ICONS"
xfconf-query -c xfwm4 -p /general/theme -s "$TARGET_WM"

# Apply wallpaper
xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitorLVDS-1/workspace0/last-image -s "$TARGET_WALL"
EOF

chmod +x "$SCRIPT_PATH"
echo "[1/2] Installed toggle script at $SCRIPT_PATH"

# 2. Create the Xfce Panel Launcher automatically
if command -v xfconf-query >/dev/null 2>&1 && command -v xfce4-panel >/dev/null 2>&1; then
    # Find the next available plugin ID in xfce4-panel
    MAX_ID=$(xfconf-query -c xfce4-panel -p /plugins -l 2>/dev/null | grep -oE 'plugin-[0-9]+' | cut -d'-' -f2 | sort -n | tail -n1)
    NEXT_ID=$(( ${MAX_ID:-0} + 1 ))

    LAUNCHER_DIR="$HOME/.config/xfce4/panel/launcher-$NEXT_ID"
    mkdir -p "$LAUNCHER_DIR"

    DESKTOP_FILE="$LAUNCHER_DIR/$(date +%s)1.desktop"
    cat << EOF > "$DESKTOP_FILE"
[Desktop Entry]
Version=1.0
Type=Application
Name=Toggle Theme
Comment=Switch between Light and Dark Xfce themes
Exec=$SCRIPT_PATH
Icon=weather-clear-night
Terminal=false
StartupNotify=false
EOF

    # Register the new launcher plugin in xfconf
    xfconf-query -c xfce4-panel -p "/plugins/plugin-$NEXT_ID" -n -t string -s "launcher"
    xfconf-query -c xfce4-panel -p "/plugins/plugin-$NEXT_ID/items" -n -a -t string -s "$(basename "$DESKTOP_FILE")"

    # Append the plugin ID to panel-1's plugin-ids array
    EXISTING_IDS=$(xfconf-query -c xfce4-panel -p /panels/panel-1/plugin-ids 2>/dev/null | tail -n +3)
    if [ -n "$EXISTING_IDS" ]; then
        ARGS=()
        while IFS= read -r id; do
            [ -n "$id" ] && ARGS+=(-t int -s "$id")
        done <<< "$EXISTING_IDS"
        ARGS+=(-t int -s "$NEXT_ID")
        xfconf-query -c xfce4-panel -p /panels/panel-1/plugin-ids "${ARGS[@]}"
    else
        xfconf-query -c xfce4-panel -p /panels/panel-1/plugin-ids -n -a -t int -s "$NEXT_ID"
    fi

    # Restart panel so the new launcher appears immediately
    xfce4-panel -r >/dev/null 2>&1 &
    echo "[2/2] Added 'Toggle Theme' launcher (plugin-$NEXT_ID) to panel-1."
else
    echo "[2/2] Skipped panel launcher (xfconf-query or xfce4-panel not found)."
fi

echo "Done! Your 1-click theme switcher is ready."
