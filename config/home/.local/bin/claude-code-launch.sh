#!/usr/bin/env bash
# Meta+Ctrl+Shift+A in KDE (via ~/.local/share/applications/claude-code-launch.desktop).
# Same as Hyprland's SUPER+CTRL+SHIFT+A. Edit here; no KDE reload needed.
exec kitty --directory "$HOME/Work" --title "Claude Code" claude --permission-mode auto
