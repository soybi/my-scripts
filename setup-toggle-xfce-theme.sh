#!/usr/bin/env bash
set -e

BIN_DIR="$HOME/.local/bin"
SCRIPT_PATH="$BIN_DIR/toggle-xfce-theme.sh"

mkdir -p "$BIN_DIR"

cat << 'EOF' > "$SCRIPT_PATH"
#!/usr/bin/env bash

FALLBACK_LIGHT_GTK="Adwaita"
FALLBACK_DARK_GTK="Adwaita-dark"
FALLBACK_LIGHT_ICONS="elementary"
FALLBACK_DARK_ICONS="elementary"

theme_exists() {
    local name="$1"
    [ -d "$HOME/.themes/$name" ] || [ -d "$HOME/.local/share/themes/$name" ] || [ -d "/usr/share/themes/$name" ]
}

icon_exists() {
    local name="$1"
    [ -d "$HOME/.icons/$name" ] || [ -d "$HOME/.local/share/icons/$name" ] || [ -d "/usr/share/icons/$name" ]
}

CURRENT_GTK=$(xfconf-query -c xsettings -p /Net/ThemeName)
CURRENT_WM=$(xfconf-query -c xfwm4 -p /general/theme)
CURRENT_ICONS=$(xfconf-query -c xsettings -p /Net/IconThemeName)

if [[ "$CURRENT_GTK" =~ -[Dd]ark ]]; then
    COLOR_SCHEME="prefer-light"
    TARGET_GTK=$(echo "$CURRENT_GTK" | sed -E 's/-dark/-light/g; s/-Dark/-Light/g')
    if ! theme_exists "$TARGET_GTK"; then
        STRIPPED=$(echo "$CURRENT_GTK" | sed -E 's/-[Dd]ark//g')
        if theme_exists "$STRIPPED"; then
            TARGET_GTK="$STRIPPED"
        else
            TARGET_GTK="$FALLBACK_LIGHT_GTK"
        fi
    fi

    TARGET_WM=$(echo "$CURRENT_WM" | sed -E 's/-dark/-light/g; s/-Dark/-Light/g')
    if ! theme_exists "$TARGET_WM"; then
        STRIPPED_WM=$(echo "$CURRENT_WM" | sed -E 's/-[Dd]ark//g')
        theme_exists "$STRIPPED_WM" && TARGET_WM="$STRIPPED_WM" || TARGET_WM="$TARGET_GTK"
    fi

    TARGET_ICONS=$(echo "$CURRENT_ICONS" | sed -E 's/-dark/-light/g; s/-Dark/-Light/g')
    if ! icon_exists "$TARGET_ICONS"; then
        STRIPPED_ICONS=$(echo "$CURRENT_ICONS" | sed -E 's/-[Dd]ark//g')
        icon_exists "$STRIPPED_ICONS" && TARGET_ICONS="$STRIPPED_ICONS" || TARGET_ICONS="$FALLBACK_LIGHT_ICONS"
    fi
else
    COLOR_SCHEME="prefer-dark"
    if [[ "$CURRENT_GTK" =~ -[Ll]ight ]]; then
        TARGET_GTK=$(echo "$CURRENT_GTK" | sed -E 's/-light/-dark/g; s/-Light/-Dark/g')
    else
        theme_exists "${CURRENT_GTK}-dark" && TARGET_GTK="${CURRENT_GTK}-dark" || TARGET_GTK="${CURRENT_GTK}-Dark"
    fi
    theme_exists "$TARGET_GTK" || TARGET_GTK="$FALLBACK_DARK_GTK"

    if [[ "$CURRENT_WM" =~ -[Ll]ight ]]; then
        TARGET_WM=$(echo "$CURRENT_WM" | sed -E 's/-light/-dark/g; s/-Light/-Dark/g')
    else
        theme_exists "${CURRENT_WM}-dark" && TARGET_WM="${CURRENT_WM}-dark" || TARGET_WM="${CURRENT_WM}-Dark"
    fi
    theme_exists "$TARGET_WM" || TARGET_WM="$TARGET_GTK"

    if [[ "$CURRENT_ICONS" =~ -[Ll]ight ]]; then
        TARGET_ICONS=$(echo "$CURRENT_ICONS" | sed -E 's/-light/-dark/g; s/-Light/-Dark/g')
    else
        icon_exists "${CURRENT_ICONS}-dark" && TARGET_ICONS="${CURRENT_ICONS}-dark" || icon_exists "${CURRENT_ICONS}-Dark" && TARGET_ICONS="${CURRENT_ICONS}-Dark"
    fi
    icon_exists "$TARGET_ICONS" || TARGET_ICONS="$FALLBACK_DARK_ICONS"
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

# Create Xfce Panel Launcher only if one does not already exist
if ! grep -rl "toggle-xfce-theme.sh" "$HOME/.config/xfce4/panel/" >/dev/null 2>&1; then
    PANEL_ID=$(xfconf-query -c xfce4-panel -p /panels 2>/dev/null | grep -E '^[0-9]+$' | sort -n | head -n 1)
    PANEL_ID=${PANEL_ID:-1}
    LAST_ID=$(xfconf-query -c xfce4-panel -p /plugins -l 2>/dev/null | grep -oE 'plugin-[0-9]+' | cut -d- -f2 | sort -n | tail -1)
    NEXT_ID=$(( ${LAST_ID:-0} + 1 ))
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

    CURRENT_IDS=$(xfconf-query -c xfce4-panel -p "/panels/panel-$PANEL_ID/plugin-ids" | grep -E '^[0-9]+$')
    ARGS=()
    for id in $CURRENT_IDS; do
        ARGS+=(-t int -s "$id")
    done
    ARGS+=(-t int -s "$NEXT_ID")

    xfconf-query -c xfce4-panel -p "/panels/panel-$PANEL_ID/plugin-ids" -n -a "${ARGS[@]}"
    xfce4-panel -r
    echo "Installed $SCRIPT_PATH and added Toggle Theme launcher to panel-$PANEL_ID."
else
    echo "Updated $SCRIPT_PATH (existing panel launcher preserved)."
fi
