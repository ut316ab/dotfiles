#!/usr/bin/env bash
# Rebuild the KDE Rounded Corners effect (v0.11.0) against the installed KWin.
# Needed after every KDE/KWin update: KWin refuses effects built for another
# version, and the corners silently disappear until this is run.
# Check: journalctl --user -b | grep -i "built for a different version of KWin"
set -euo pipefail
cd "$HOME/.local/src/kwin-effect-rounded-corners-git"
makepkg -f --noconfirm --cleanbuild
pkg="$(ls -t kwin-effect-rounded-corners-git-*.pkg.tar.zst | head -1)"
sudo -A pacman -U --noconfirm "$pkg"
gdbus call --session -d org.kde.KWin -o /Effects -m org.kde.kwin.Effects.unloadEffect kwin4_effect_shapecorners >/dev/null || true
gdbus call --session -d org.kde.KWin -o /Effects -m org.kde.kwin.Effects.loadEffect kwin4_effect_shapecorners
echo "Built against: $(pacman -Q kwin)"
