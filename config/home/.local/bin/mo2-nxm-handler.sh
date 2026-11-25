#!/bin/bash
# Pass Nexus "Download with manager" (nxm://) links to Cosmoem's Mod Organizer 2 (ModOrganizer.exe forwards them to the open instance;
# nxmhandler.exe silently did nothing here). MO2 runs under Proton (Steam shortcut 3506399820) and should already be open.
# Remove: delete this file and ~/.local/share/applications/mo2-nxm-handler.desktop
WINEBIN="$HOME/.local/share/Steam/compatibilitytools.d/Proton-CachyOS Latest/files/bin/wine"
export WINEPREFIX="$HOME/.local/share/Steam/steamapps/compatdata/3506399820/pfx"
export WINEDEBUG=-all
LOG="$HOME/.cache/mo2-nxm-handler.log"
echo "$(date '+%F %T') $1" >> "$LOG"
exec "$WINEBIN" 'Z:\home\darryl\Games\Cosmoem\ModOrganizer.exe' "$1" >> "$LOG" 2>&1
