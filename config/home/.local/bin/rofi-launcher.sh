#!/usr/bin/env bash
# KDE Meta+D: same rofi app launcher as Hyprland's SUPER+D (JaKooLit config),
# minus the Hyprland-only wallpaper-link step.
pkill -x rofi || true
exec rofi -show drun -modi drun,filebrowser,run,window -config "$HOME/.config/rofi/config.rasi"
