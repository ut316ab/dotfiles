#!/bin/bash
# GUI sudo password prompt (SUDO_ASKPASS target). Lets `sudo -A` work from
# contexts with no terminal for an interactive password prompt - e.g. an
# agent's non-interactive shell.
zenity --password --title="sudo"
