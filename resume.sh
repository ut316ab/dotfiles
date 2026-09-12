#!/bin/bash
# Restore this machine's setup on a fresh Omarchy, vanilla Arch, or CachyOS
# install. Not for EndeavourOS/Garuda.
#
# Usage: git clone https://github.com/ut316ab/dotfiles ~/dotfiles
#        cd ~/dotfiles && bash resume.sh

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() { printf '\033[1;33m==>\033[0m %s\n' "$1"; }

detect_os() {
  . /etc/os-release
  OS_ID=$ID
  log "Detected OS: $OS_ID"
}

# CachyOS has no official Omarchy support. omarchy-settings ships a
# mkinitcpio HOOKS drop-in that overwrites CachyOS's systemd-based hooks with
# legacy ones - dangerous on LUKS installs, but verified safe to boot on a
# no-LUKS BTRFS/Limine/Snapper CachyOS VM (see project_resume_sh.md memory
# for the full test). This box doesn't use LUKS on CachyOS, so installing
# the real omarchy + omarchy-settings packages directly is the right call
# instead of relying on unofficial, currently-broken community forks.
bootstrap_cachyos_omarchy_repo() {
  if ! grep -q '^\[omarchy\]' /etc/pacman.conf; then
    log "Adding Omarchy's pacman repo (trust-all until the keyring is installed)"
    sudo tee -a /etc/pacman.conf >/dev/null <<'EOF'

[omarchy]
SigLevel = Never
Server = https://pkgs.omarchy.org/stable/$arch
EOF
  fi

  # Checked separately from the block above (not just "does [omarchy] exist")
  # so a resume.sh run interrupted between adding the repo and dropping the
  # trust-all override - power loss, ctrl-C, a forced reboot mid-install -
  # finishes the trust dance on re-run instead of leaving the repo
  # permanently unverified.
  if grep -A1 '^\[omarchy\]$' /etc/pacman.conf | grep -q '^SigLevel = Never$'; then
    log "Finishing Omarchy repo trust bootstrap (keyring not yet installed)"
    sudo pacman -Sy
    sudo pacman -S --needed --noconfirm omarchy-keyring
    sudo pacman-key --populate omarchy
    # Drop the temporary trust-all override now that the keyring is trusted -
    # falls back to pacman.conf's global SigLevel like every other repo.
    sudo sed -i '/^\[omarchy\]$/{n;/^SigLevel = Never$/d}' /etc/pacman.conf
    sudo pacman -Sy
  fi
}

# omarchy-settings ships /etc/mkinitcpio.conf.d/omarchy_hooks.conf, which
# unconditionally overwrites CachyOS's native systemd-based HOOKS with a
# legacy set that includes `encrypt` - regardless of whether the system
# actually has LUKS anywhere. Confirmed on a real CachyOS VM with zero LUKS
# on disk (blkid/lsblk/fstab all plain vfat+btrfs): the cachyos/cachyos-lts
# kernels then failed to boot ("failed to open encryption mapping...not a
# LUKS volume"), while the plain linux kernel (built in the same mkinitcpio
# batch, identical cmdline) booted fine - encrypt has no business being
# forced on here. Strips just that one hook, keeps everything else
# omarchy_hooks.conf sets (Plymouth splash theming, keymap, etc.), then
# rebuilds every installed kernel's initramfs/UKI so the fix actually takes
# effect immediately rather than waiting for the next kernel update.
fix_cachyos_encrypt_hook() {
  log "Removing the encrypt hook from omarchy_hooks.conf (no LUKS on this system) and rebuilding initramfs"
  sudo sed -i -E '/^HOOKS=/ { s/\bencrypt\b//; s/  +/ /g }' /etc/mkinitcpio.conf.d/omarchy_hooks.conf
  sudo mkinitcpio -P
}

# omarchy-defaults.conf sets TARGET_OS_NAME="Omarchy" for limine-entry-tool,
# so installing omarchy creates a SEPARATE "/+Omarchy" Limine menu heading
# rather than updating CachyOS's own existing "/+CachyOS" one - and its
# ENABLE_UKI=yes setting deletes the old separate initramfs/vmlinuz files
# once UKIs are built for the same kernels (limine-entry-tool.conf: "Duplicate
# initramfs and vmlinuz files are automatically removed after generating
# UKIs"). The old CachyOS entries are then left pointing at files that no
# longer exist - confirmed on a real VM: they stopped booting once the
# Omarchy UKIs were built (the very mkinitcpio -P run just above). Only
# strips the top-level "/+CachyOS" section (and its own nested Snapshots
# history); everything from "/+Omarchy" onward is untouched.
remove_stale_cachyos_limine_entries() {
  log "Removing the now-broken /+CachyOS Limine entries (superseded by /+Omarchy)"
  sudo cp /boot/limine.conf /boot/limine.conf.pre-cachyos-cleanup.bak
  sudo awk '
    /^\/\+CachyOS$/ { skip=1; next }
    /^\/\+/ && skip { skip=0 }
    !skip
  ' /boot/limine.conf | sudo tee /boot/limine.conf.tmp >/dev/null
  sudo mv /boot/limine.conf.tmp /boot/limine.conf
}

install_omarchy() {
  case "$OS_ID" in
  omarchy)
    log "Already Omarchy, nothing to bootstrap"
    ;;
  arch)
    log "Running Omarchy's official installer (supported on a clean Arch base)"
    wget -qO- https://omarchy.org/install | bash
    ;;
  cachyos)
    bootstrap_cachyos_omarchy_repo
    log "Installing omarchy + omarchy-settings directly (no ISO installer on CachyOS)"
    sudo pacman -S --needed --noconfirm omarchy omarchy-settings
    fix_cachyos_encrypt_hook
    remove_stale_cachyos_limine_entries
    ;;
  *)
    echo "Unsupported OS for this script: $OS_ID (only omarchy, arch, cachyos)" >&2
    exit 1
    ;;
  esac
}

# The official installer runs this itself to bring a fresh account up to the
# current expected state (104 timestamped migration scripts as of writing,
# tracked via marker files in ~/.local/state/omarchy/migrations). Installing
# omarchy/omarchy-settings directly on CachyOS bypasses that entirely -
# found testing a real CachyOS VM reboot: the bar showed "104 pending
# migrations" and Hyprland failed to start. Idempotent (marker-based), so
# safe to run unconditionally regardless of which install_omarchy branch ran.
#
# Deliberately NOT run right after install_omarchy. Migrations assume the
# fully-provisioned system the official installer would normally hand off to
# them (all packages installed, services enabled, skel config seeded) -
# confirmed on real hardware: run that early, one migration looked for a
# sleep service that doesn't exist until later steps set it up, and another
# installed quickshell-git from AUR because it couldn't see that quickshell
# (pacman.txt) was already slated for install_packages. That AUR quickshell-git
# then conflicted with the real quickshell install and had to be removed by
# hand (pacman -Rdd quickshell-git) to recover. Runs last instead, after
# restore_dotfiles, so migrations see the same state the official installer
# would.
run_omarchy_migrations() {
  log "Running Omarchy migrations"
  omarchy-migrate
}

install_paru() {
  if command -v paru >/dev/null; then
    return
  fi
  log "Installing paru"
  sudo pacman -S --needed --noconfirm paru
}

# pipewire-jack and jack2 both provide the virtual "jack" package and
# explicitly conflict with each other. ffmpeg (pulled in transitively by
# ffmpegthumbnailer, an Omarchy base package) needs "jack", and when the
# whole package list is resolved as one giant transaction, pacman can pick
# literal jack2 to satisfy that before crediting the also-requested
# pipewire-jack - discovered this exact failure testing on a real CachyOS VM.
# Installing pipewire-jack on its own first "locks in" the right provider
# before anything else's dependency resolution gets a chance to pick jack2.
#
# CachyOS's own base image already has jack2 installed (discovered testing on
# a real fresh CachyOS VM with no desktop environment) - installing
# pipewire-jack standalone then hits the same conflict from the other
# direction, and --noconfirm answers pacman's "Remove jack2?" prompt with its
# default of N, aborting the whole transaction. A plain `pacman -R jack2` then
# fails too: ffmpeg, fluidsynth, portaudio, and vlc-plugin-jack all depend on
# it, and pacman only checks currently-installed packages during a standalone
# removal, so it can't see that the very next command reinstalls an
# ABI-compatible provider. Confirmed pipewire-jack provides the exact same
# virtual packages/sonames jack2 does (jack, libjack.so=0-64,
# libjacknet.so=0-64, libjackserver.so=0-64), so skipping the dependency check
# on removal (-Rdd) is safe here - those dependents are satisfied again the
# moment the install below completes.
install_packages() {
  if pacman -Qi jack2 &>/dev/null; then
    log "Removing jack2 (conflicts with pipewire-jack, which this setup uses instead)"
    sudo pacman -Rdd --noconfirm jack2
  fi

  log "Installing pipewire-jack first (avoids a jack2 conflict - see comment above)"
  sudo pacman -S --needed --noconfirm pipewire pipewire-alsa pipewire-jack pipewire-pulse

  log "Installing official-repo packages"
  # shellcheck disable=SC2046
  sudo pacman -S --needed --noconfirm $(grep -vE '^\s*(#|$)' "$REPO_DIR/packages/pacman.txt")

  log "Installing AUR packages via paru"
  # shellcheck disable=SC2046
  paru -S --needed --noconfirm $(grep -vE '^\s*(#|$)' "$REPO_DIR/packages/aur.txt")
}

# networkmanager is only a package in pacman.txt - nothing else in this
# script ever enables the service. The install media/live environment
# already has working network on its own, so this went unnoticed until a
# real reboot left the installed system with no network at all (found
# testing a real CachyOS VM reboot).
enable_networkmanager() {
  log "Enabling NetworkManager"
  sudo systemctl enable --now NetworkManager
}

# Same category of bug as enable_networkmanager - sddm is a package in
# pacman.txt but nothing ever enables it, so a fresh install boots to a
# plain TTY with no graphical login at all (found testing a real CachyOS
# VM reboot). Enabled only, not started now (--now would try to take over
# the display mid-script, disrupting whatever session is actually running
# resume.sh) - takes effect on the next boot.
enable_sddm() {
  log "Enabling SDDM (takes effect next boot)"
  sudo systemctl enable sddm
}

# Omarchy's SDDM greeter theme (Main.qml) reads userModel.lastUser and shows
# only a password field for that user - no username entry at all. lastUser
# is populated by SDDM itself after a first successful login, but on a
# genuinely fresh install nothing has ever logged in via SDDM, so it's
# empty and the greeter submits a blank username - a real deadlock: can't
# log in without a last-user, can't set one without logging in first
# (confirmed via journalctl -u sddm: "Authentication for user  ""  failed",
# "user unknown"). Pre-seeding SDDM's own state file with the real user
# breaks the deadlock exactly like a first successful login would have.
seed_sddm_last_user() {
  log "Seeding SDDM's last-user state (works around its empty-username deadlock on first boot)"
  sudo mkdir -p /var/lib/sddm
  printf '[Last]\nSession=omarchy.desktop\nUser=%s\n' "$USER" | sudo tee /var/lib/sddm/state.conf >/dev/null
}

# Delegates to Omarchy's own installer instead of us tracking dropbox,
# dropbox-cli, nautilus-dropbox, libappindicator and python-gpgme ourselves -
# omarchy-install-service-dropbox installs all of that, enables the
# omarchy.dropbox bar widget (redundant with restore_dotfiles's shell.json
# copy, but harmless), and starts the daemon. It does NOT set up autostart
# though, so that one line stays ours - confirmed dropbox-cli's own
# "autostart" subcommand just copies the package-shipped
# /usr/share/applications/dropbox.desktop to ~/.config/autostart/dropbox.desktop.
setup_dropbox() {
  log "Installing and configuring Dropbox via Omarchy's own installer"
  omarchy-install-service-dropbox
  log "Enabling Dropbox autostart"
  dropbox-cli autostart y
}

# omarchy plugin add tries to hot-register the plugin with a running
# omarchy-shell (Quickshell) process, and returns exit 1 if none is running -
# which is exactly the case on a fresh install, before Hyprland/omarchy-shell
# has ever been started. The plugin's files still get installed correctly
# either way (the shell picks it up on its next start/rescan), so this
# failure isn't fatal - don't let `set -e` kill the rest of the script over it.
install_plugins() {
  log "Restoring Omarchy plugins"
  while read -r id url; do
    [[ -z $id || $id == \#* ]] && continue
    if ! omarchy plugin add "$url" --enable --yes; then
      log "Plugin $id: files installed, but couldn't hot-register (omarchy-shell not running yet - fine on a fresh install)"
    fi
  done <"$REPO_DIR/plugins.txt"
}

# Chris Titus Tech's linutil (arch/virtualization.sh) is what actually set
# this up originally - confirmed by the exact non-default firewall_backend
# and polkit auth lines already present in /etc/libvirt/*.conf, which a bare
# `pacman -S libvirt virt-manager` would never produce on its own.
setup_libvirt() {
  log "Configuring libvirt (replicating linutil's virtualization.sh edits)"
  sudo sed -i 's/^#\?firewall_backend\s*=\s*".*"/firewall_backend = "iptables"/' /etc/libvirt/network.conf
  sudo sed -i 's/^#\?auth_unix_ro\s*=\s*".*"/auth_unix_ro = "polkit"/' /etc/libvirt/libvirtd.conf
  sudo sed -i 's/^#\?auth_unix_rw\s*=\s*".*"/auth_unix_rw = "polkit"/' /etc/libvirt/libvirtd.conf
  sudo usermod -aG kvm,libvirt "$USER"
  sudo systemctl enable --now libvirtd.service
  sudo virsh net-autostart default
}

# Exact current rules, captured live rather than replaying linutil's generic
# UFW baseline (which allows 22/80/443 - none of which are actually open here).
setup_ufw() {
  log "Configuring UFW with the actual rules this machine uses"
  sudo ufw allow 53317/udp
  sudo ufw allow 53317/tcp
  sudo ufw allow from 172.16.0.0/12 to 172.17.0.1 port 53 proto udp comment 'allow-docker-dns'
  sudo ufw allow from 192.168.0.0/16 to 172.17.0.1 port 53 proto udp comment 'allow-docker-dns'
  sudo ufw default deny incoming
  sudo ufw default allow outgoing
  # --force skips ufw's own "may disrupt existing ssh connections" prompt -
  # it only appears when ufw detects it's running under SSH, so it's silent
  # at a local console anyway. Matches --noconfirm everywhere else in this
  # script rather than being the one interactive exception.
  sudo ufw --force enable
}

# Installing the flatpak package does NOT add Flathub - it has to be
# registered as a remote separately. This is a system-wide (not --user)
# remote, so run as root via sudo - without it, flatpak escalates through
# PolicyKit instead, which prompts for a password on its own text-mode
# agent and hangs the script waiting for it (found testing over SSH, where
# no graphical polkit agent is running to handle it silently either).
setup_flatpak() {
  log "Adding Flathub remote"
  sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
}

# Points the hook at THIS machine's actual $REPO_DIR rather than trusting a
# path baked into a settings.json that may have been restored from a
# different machine's Dropbox backup (e.g. a dev checkout elsewhere, vs the
# README's documented ~/dotfiles clone target). Idempotent - merges just this
# one key, safe to run whether or not restore_claude.sh has already restored
# other settings.
setup_claude_backup_hook() {
  log "Wiring up the Claude history backup hook (SessionEnd -> backup_claude.sh)"
  mkdir -p ~/.claude
  local settings=~/.claude/settings.json
  [[ -f "$settings" ]] || echo '{}' >"$settings"
  local tmp
  tmp="$(mktemp)"
  jq --arg cmd "bash $REPO_DIR/backup_claude.sh 2>/dev/null || true" '
    .hooks.SessionEnd = [{
      "hooks": [{
        "type": "command",
        "command": $cmd,
        "statusMessage": "Backing up Claude history to Dropbox..."
      }]
    }]
  ' "$settings" >"$tmp" && mv "$tmp" "$settings"
}

# This whole Claude-backup arrangement (Dropbox path, hook, restore_claude.sh)
# is a personal setup specific to this repo's original owner - anyone else
# cloning this public repo shouldn't have their ~/.claude/settings.json
# silently rewritten. Ask, default to skip. `read` failing (piped/non-tty
# stdin) falls through to skip rather than aborting the whole script.
maybe_setup_claude_backup_hook() {
  local ans
  read -rp "Set up Claude Code history backup to Dropbox (SessionEnd hook, personal to this repo's owner)? [y/N] " ans || ans="n"
  if [[ "$ans" =~ ^[Yy]$ ]]; then
    setup_claude_backup_hook
  else
    log "Skipping Claude backup hook setup"
  fi
}

# Scoped to just Hyprland + the Quickshell (omarchy-shell) bar config for now.
# The apod plugin (installed above by install_plugins) supplies the wallpaper
# itself via its bar widget's 1-click "set wallpaper" action - no separate
# wallpaper file needs to live in this repo.
#
# The baseline (non-customized) files under ~/.config/hypr and ~/.config/omarchy
# normally get seeded from /etc/skel/.config at account-creation time - that
# never happens here, since omarchy/omarchy-settings are installed onto an
# already-existing user account rather than through the official installer,
# which handles this itself. Without it, hyprland.lua's require("hypr.autostart")
# fails outright since autostart.lua (and other skel baseline files) simply
# never existed (found testing a real CachyOS VM: "module 'hypr.autostart' not
# found", plus 27 more similar errors). -n (no-clobber) so this only fills in
# what's missing and never touches the customized files restored right after.
seed_config_from_skel() {
  log "Seeding baseline ~/.config/hypr and ~/.config/omarchy from /etc/skel (normally done at account creation, skipped here)"
  mkdir -p ~/.config/hypr ~/.config/omarchy
  cp -rn /etc/skel/.config/hypr/. ~/.config/hypr/
  cp -rn /etc/skel/.config/omarchy/. ~/.config/omarchy/
}

restore_dotfiles() {
  seed_config_from_skel

  log "Restoring Hyprland configs"
  cp -f "$REPO_DIR"/config/hypr/*.lua ~/.config/hypr/

  log "Restoring Quickshell (omarchy-shell) bar config"
  cp -f "$REPO_DIR/config/omarchy/shell.json" ~/.config/omarchy/shell.json
}

# SUDO_ASKPASS wired via ~/.config/environment.d/ rather than ~/.bashrc -
# this system launches Hyprland through uwsm (Universal Wayland Session
# Manager), which reads systemd's environment.d for the whole graphical
# session, so it's inherited by every terminal and process under it
# (including a non-interactive agent shell). ~/.bashrc explicitly returns
# early for non-interactive shells (`[[ $- != *i* ]] && return`), so it
# wouldn't reach those. Lets `sudo -A` pop a GUI password prompt from
# contexts with no terminal to prompt in.
setup_sudo_askpass() {
  log "Installing GUI sudo askpass helper"
  mkdir -p ~/.local/bin
  cp -f "$REPO_DIR/config/askpass.sh" ~/.local/bin/askpass.sh
  chmod +x ~/.local/bin/askpass.sh

  mkdir -p ~/.config/environment.d
  printf 'SUDO_ASKPASS=%s/.local/bin/askpass.sh\n' "$HOME" >~/.config/environment.d/askpass.conf
}

# Queried at runtime instead of committed to the repo - this repo is public,
# and there's no reason for a name/email to sit in public git history when
# two prompts do the job.
setup_git_identity() {
  if git config --global user.email >/dev/null 2>&1; then
    return
  fi
  log "Git identity (not stored in this repo - entered fresh each restore)"
  read -rp "Git user.name: " git_name
  read -rp "Git user.email: " git_email
  git config --global user.name "$git_name"
  git config --global user.email "$git_email"
}

main() {
  detect_os
  install_omarchy
  install_paru
  install_packages
  enable_networkmanager
  enable_sddm
  seed_sddm_last_user
  setup_dropbox
  install_plugins
  setup_libvirt
  setup_ufw
  setup_flatpak
  setup_sudo_askpass
  setup_git_identity
  maybe_setup_claude_backup_hook
  restore_dotfiles
  run_omarchy_migrations

  log "Done. Remaining manual steps:"
  echo "  - Review makepkg.conf's BUILDENV to confirm ccache is actually enabled"
  echo "  - Log out/in (or reboot) for the kvm/libvirt group membership to take effect"
  echo "  - Log out/in (or reboot) for SUDO_ASKPASS (environment.d) to take effect"
}

main "$@"
