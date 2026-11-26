#!/usr/bin/env bash
# KDE Meta+D: same rofi app launcher as Hyprland's SUPER+D (JaKooLit config),
# minus the Hyprland-only wallpaper-link step. The "power" tab (log out, reboot,
# shut down via KDE's confirm screen) comes from rofi-power.sh.
pkill -x rofi || true
exec rofi -show drun -modi "drun,filebrowser,run,window,power:$HOME/.local/bin/rofi-power.sh" -config "$HOME/.config/rofi/config.rasi"
