#!/usr/bin/env bash
# Rofi script mode for the "power" tab of the Meta+D launcher (rofi-launcher.sh).
# With no argument rofi wants the entries; with one it's the entry picked.
# Uses KDE's LogoutPrompt, so KDE's own confirm/countdown screen appears and a
# mis-click can be cancelled there.
case "${1:-}" in
  "")
    printf 'Log out\0icon\x1fsystem-log-out\n'
    printf 'Reboot\0icon\x1fsystem-reboot\n'
    printf 'Shut down\0icon\x1fsystem-shutdown\n'
    ;;
  "Log out") method=promptLogout ;;
  "Reboot") method=promptReboot ;;
  "Shut down") method=promptShutDown ;;
esac
if [[ -n ${method:-} ]]; then
  # Detached, so rofi can close before KDE's prompt opens.
  setsid -f qdbus6 org.kde.LogoutPrompt /LogoutPrompt "org.kde.LogoutPrompt.$method" >/dev/null 2>&1
fi
