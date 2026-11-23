#!/usr/bin/env bash
set -e

BIN_DIR="$HOME/.local/bin"
SCRIPT_PATH="$BIN_DIR/toggle-xfce-theme.sh"
PANEL_DIR="$HOME/.config/xfce4/panel"
FISH_FUNC="$HOME/.config/fish/functions/toggle-theme.fish"
PANEL_CHANGED=0

# 1. Remove the toggle script
if [ -f "$SCRIPT_PATH" ]; then
    rm -f "$SCRIPT_PATH"
    echo "Removed $SCRIPT_PATH"
fi

# 2. Remove optional fish function if present
if [ -f "$FISH_FUNC" ]; then
    rm -f "$FISH_FUNC"
    echo "Removed $FISH_FUNC"
fi

# 3. Find and remove any Xfce panel launcher referencing toggle-xfce-theme.sh
if [ -d "$PANEL_DIR" ]; then
    for dir in "$PANEL_DIR"/launcher-*; do
        [ -d "$dir" ] || continue
        if grep -rq "toggle-xfce-theme.sh" "$dir" 2>/dev/null; then
            PLUGIN_NAME=$(basename "$dir")
            PLUGIN_ID="${PLUGIN_NAME#launcher-}"

            # Remove plugin ID from all panel plugin-ids arrays
            for panel_prop in $(xfconf-query -c xfce4-panel -p /panels -l 2>/dev/null | grep "/plugin-ids$"); do
                CURRENT_IDS=$(xfconf-query -c xfce4-panel -p "$panel_prop" 2>/dev/null | grep -E '^[0-9]+$' || true)
                ARGS=()
                FOUND=0
                for id in $CURRENT_IDS; do
                    if [ "$id" = "$PLUGIN_ID" ]; then
                        FOUND=1
                    else
                        ARGS+=(-t int -s "$id")
                    fi
                done

                if [ "$FOUND" -eq 1 ]; then
                    if [ ${#ARGS[@]} -gt 0 ]; then
                        xfconf-query -c xfce4-panel -p "$panel_prop" -n -a "${ARGS[@]}"
                    else
                        xfconf-query -c xfce4-panel -p "$panel_prop" -r -R
                    fi
                    PANEL_CHANGED=1
                fi
            done

            # Reset xfconf plugin node and delete launcher directory
            xfconf-query -c xfce4-panel -p "/plugins/plugin-$PLUGIN_ID" -r -R 2>/dev/null || true
            rm -rf "$dir"
            echo "Removed panel launcher $PLUGIN_NAME"
        fi
    done
fi

# 4. Reload panel if modified
if [ "$PANEL_CHANGED" -eq 1 ] && command -v xfce4-panel >/dev/null 2>&1; then
    xfce4-panel -r
    echo "Reloaded xfce4-panel"
fi

# 5. Optional theme reset to default dark preset
if [ "${1:-}" = "--reset-theme" ]; then
    xfconf-query -c xsettings -p /Net/ThemeName -s "Adwaita-dark"
    xfconf-query -c xsettings -p /Net/IconThemeName -s "elementary"
    xfconf-query -c xfwm4 -p /general/theme -s "Adwaita-dark"
    if command -v gsettings >/dev/null 2>&1; then
        gsettings set org.gnome.desktop.interface color-scheme "prefer-dark" 2>/dev/null || true
        gsettings set org.gnome.desktop.interface gtk-theme "Adwaita-dark" 2>/dev/null || true
    elif command -v dconf >/dev/null 2>&1; then
        dconf write /org/gnome/desktop/interface/color-scheme "'prefer-dark'" 2>/dev/null || true
        dconf write /org/gnome/desktop/interface/gtk-theme "'Adwaita-dark'" 2>/dev/null || true
    fi
    echo "Reset theme to Adwaita-dark / elementary"
fi

echo "Reversal complete."
