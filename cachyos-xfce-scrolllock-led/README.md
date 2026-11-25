CachyOS (XFCE + LightDM + fish) - External Keyboard Scroll Lock LED Guide

OVERVIEW
--------
This guide configures an external keyboard's backlight/LED (controlled via Scroll
Lock) to turn ON automatically at the LightDM login screen and toggle ON/OFF
reliably inside XFCE—without mapping Scroll_Lock to Mod3 (which breaks volume
and media shortcuts).

--------------------------------------------------------------------------------
STEP 1: Ensure xorg-xset is Installed
--------------------------------------------------------------------------------
Install `xset` via pacman:
  sudo pacman -S --needed xorg-xset

--------------------------------------------------------------------------------
STEP 2: Keep XKB Mod3 Clean (Prevent Volume Key Conflicts)
--------------------------------------------------------------------------------
Verify that `/usr/share/X11/xkb/symbols/pc` does NOT map `Scroll_Lock` to `Mod3`.
Line 41 should remain:
  modifier_map Mod3  { <LVL5> };

If `Scroll_Lock` was previously added, revert it with:
  sudo sed -i 's/modifier_map Mod3  { <LVL5>, Scroll_Lock };/modifier_map Mod3  { <LVL5> };/' /usr/share/X11/xkb/symbols/pc

--------------------------------------------------------------------------------
STEP 3: Create the XFCE Toggle Script (/usr/local/bin/toggle-scroll-led.sh)
--------------------------------------------------------------------------------
Because `Scroll_Lock` is not bound to an X11 modifier, `xset q` always reports
Scroll Lock as "off". Using a state file (`/tmp/scroll_led_state`) allows
reliable toggling.

Run in `fish` shell:
  printf '#!/bin/bash\nSTATE_FILE="/tmp/scroll_led_state"\nif [ -f "$STATE_FILE" ] && [ "$(cat "$STATE_FILE")" = "on" ]; then\n    xset -led named "Scroll Lock"\n    echo "off" > "$STATE_FILE"\nelse\n    xset led named "Scroll Lock"\n    echo "on" > "$STATE_FILE"\nfi\n' | sudo tee /usr/local/bin/toggle-scroll-led.sh > /dev/null
  sudo chmod +x /usr/local/bin/toggle-scroll-led.sh

--------------------------------------------------------------------------------
STEP 4: Configure LightDM Login Screen (/usr/local/bin/lightdm-scroll-led.sh)
--------------------------------------------------------------------------------
LightDM requires `greeter-setup-script` to exit with status `0`, otherwise the
greeter will fail to start.

1. Create the safe wrapper script:
  printf '#!/bin/sh\n/usr/bin/xset led named "Scroll Lock" || true\necho "on" > /tmp/scroll_led_state\nchmod 666 /tmp/scroll_led_state 2>/dev/null || true\nexit 0\n' | sudo tee /usr/local/bin/lightdm-scroll-led.sh > /dev/null
  sudo chmod +x /usr/local/bin/lightdm-scroll-led.sh

2. Point LightDM to the script in `/etc/lightdm/lightdm.conf` under `[Seat:*]`:
  sudo sed -i 's|^#greeter-setup-script=.*|greeter-setup-script=/usr/local/bin/lightdm-scroll-led.sh|' /etc/lightdm/lightdm.conf

--------------------------------------------------------------------------------
STEP 5: Bind the Shortcut in XFCE
--------------------------------------------------------------------------------
1. Open Settings -> Keyboard -> Application Shortcuts.
2. Click "+ Add".
3. Enter Command: /usr/local/bin/toggle-scroll-led.sh
4. Press the Scroll Lock key when prompted.

--------------------------------------------------------------------------------
VERIFICATION
--------------------------------------------------------------------------------
- Reboot your machine.
- At the LightDM login screen, the external keyboard LED turns ON automatically.
- After logging into XFCE, pressing Scroll Lock toggles the LED OFF and ON
  repeatedly while volume and media keys continue working normally.
================================================================================
