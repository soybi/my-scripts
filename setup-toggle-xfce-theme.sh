#!/usr/bin/env bash
set -e

BIN_DIR="$HOME/.local/bin"
SCRIPT_PATH="$BIN_DIR/toggle-xfce-theme.sh"

mkdir -p "$BIN_DIR"

cat << 'EOF' > "$SCRIPT_PATH"
#!/usr/bin/env bash

LIGHT_GTK="Matcha-light-aliz"
LIGHT_WM="Matcha-light-aliz"
LIGHT_ICONS="Papirus-Light"

DARK_GTK="Matcha-dark-aliz"
DARK_WM="Matcha-dark-aliz"
DARK_ICONS="Papirus-Dark"

CURRENT_GTK=$(xfconf-query -c xsettings -p /Net/ThemeName)

if [ "$CURRENT_GTK" = "$LIGHT_GTK" ]; then
    TARGET_GTK="$DARK_GTK"
    TARGET_WM="$DARK_WM"
    TARGET_ICONS="$DARK_ICONS"
    COLOR_SCHEME="prefer-dark"
else
    TARGET_GTK="$LIGHT_GTK"
    TARGET_WM="$LIGHT_WM"
    TARGET_ICONS="$LIGHT_ICONS"
    COLOR_SCHEME="prefer-light"
fi

xfconf-query -c xsettings -p /Net/ThemeName -s "$TARGET_GTK"
xfconf-query -c xsettings -p /Net/IconThemeName -s "$TARGET_ICONS"
xfconf-query -c xfwm4 -p /general/theme -s "$TARGET_WM"

if command -v gsettings >/dev/null 2>&1; then
    gsettings set org.gnome.desktop.interface color-scheme "$COLOR_SCHEME" 2>/dev/null
    gsettings set org.gnome.desktop.interface gtk-theme "$TARGET_GTK" 2>/dev/null
fi
EOF

chmod +x "$SCRIPT_PATH"

# Create Xfce Panel Launcher
PANEL_ID=1
NEXT_ID=$(xfconf-query -c xfce4-panel -p /plugins -l | grep -oE 'plugin-[0-9]+' | cut -d- -f2 | sort -n | tail -1)
NEXT_ID=$((NEXT_ID + 1))
LAUNCHER_DIR="$HOME/.config/xfce4/panel/launcher-$NEXT_ID"

mkdir -p "$LAUNCHER_DIR"
DESKTOP_FILE="$LAUNCHER_DIR/$(date +%s)1.desktop"

cat << EOF > "$DESKTOP_FILE"
[Desktop Entry]
Version=1.0
Type=Application
Name=Toggle Theme
Comment=Toggle Light and Dark Xfce Theme
Exec=$SCRIPT_PATH
Icon=weather-clear-night
Path=
Terminal=false
StartupNotify=false
EOF

xfconf-query -c xfce4-panel -p "/plugins/plugin-$NEXT_ID" -n -t string -s "launcher"
xfconf-query -c xfce4-panel -p "/plugins/plugin-$NEXT_ID/items" -n -a -t string -s "$(basename "$DESKTOP_FILE")"

# Append new plugin ID to panel-1 plugin-ids array
CURRENT_IDS=$(xfconf-query -c xfce4-panel -p "/panels/panel-$PANEL_ID/plugin-ids" | grep -E '^[0-9]+$')
ARGS=()
for id in $CURRENT_IDS; do
    ARGS+=(-t int -s "$id")
done
ARGS+=(-t int -s "$NEXT_ID")

xfconf-query -c xfce4-panel -p "/panels/panel-$PANEL_ID/plugin-ids" -n -a "${ARGS[@]}"
xfce4-panel -r

echo "Installed $SCRIPT_PATH and added Toggle Theme launcher to panel-$PANEL_ID."
