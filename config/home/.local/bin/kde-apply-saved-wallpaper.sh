#!/bin/bash
# Applies the desktop wallpaper saved in the dotfiles to the live Plasma desktops.
#
# Why: the saved plasma-org.kde.plasma.desktop-appletsrc ties the desktop to the
# old install's activity ID. A new install gets a new activity ID, so Plasma
# ignores the saved desktop and falls back to a plain image wallpaper. This
# reads the saved desktop's wallpaper plugin and its [General] settings and
# sets them on today's desktops through plasmashell's scripting interface.
#
# Usage: kde-apply-saved-wallpaper.sh [path/to/appletsrc]   (plasmashell must be running)
set -euo pipefail

src="${1:-$HOME/dotfiles/config/home/.config/plasma-org.kde.plasma.desktop-appletsrc}"
[[ -r $src ]] || { echo "No saved appletsrc at $src" >&2; exit 1; }

# The desktop containment is the [Containments][N] section with both an
# activityId and a wallpaperplugin (panels have an empty activityId).
read -r id plugin < <(awk -F= '
  /^\[Containments\]\[[0-9]+\]$/ { cur = $0; gsub(/[^0-9]/, "", cur); next }
  /^\[/ { cur = ""; next }
  cur != "" && $1 == "activityId" { act[cur] = $2 }
  cur != "" && $1 == "wallpaperplugin" { wp[cur] = $2 }
  END { for (c in wp) if (act[c] != "" && wp[c] != "") { print c, wp[c]; exit } }
' "$src") || true
[[ -n ${plugin:-} ]] || { echo "No desktop wallpaper found in $src" >&2; exit 1; }

# That plugin's [General] keys, as writeConfig() calls (values JS-escaped).
keys="$(awk -v sec="[Containments][$id][Wallpaper][$plugin][General]" '
  $0 == sec { on = 1; next }
  /^\[/ { on = 0 }
  on && index($0, "=") > 1 {
    k = substr($0, 1, index($0, "=") - 1); v = substr($0, index($0, "=") + 1)
    gsub(/\\/, "\\\\", v); gsub(/"/, "\\\"", v)
    printf "d.writeConfig(\"%s\", \"%s\"); ", k, v
  }
' "$src")"

# plasmashell may have just been restarted: wait up to 30 s for it.
for _ in $(seq 30); do
  qdbus6 org.kde.plasmashell /PlasmaShell >/dev/null 2>&1 && break
  sleep 1
done

qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "
for (const d of desktops()) {
  d.wallpaperPlugin = \"$plugin\";
  d.currentConfigGroup = [\"Wallpaper\", \"$plugin\", \"General\"];
  $keys
}"
echo "Desktop wallpaper set to $plugin"
