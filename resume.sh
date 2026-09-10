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
  if grep -q '^\[omarchy\]' /etc/pacman.conf; then
    return
  fi
  log "Adding Omarchy's pacman repo (trust-all until the keyring is installed)"
  sudo tee -a /etc/pacman.conf >/dev/null <<'EOF'

[omarchy]
SigLevel = Never
Server = https://pkgs.omarchy.org/stable/$arch
EOF
  sudo pacman -Sy
  sudo pacman -S --needed --noconfirm omarchy-keyring
  sudo pacman-key --populate omarchy
  # Drop the temporary trust-all override now that the keyring is trusted -
  # falls back to pacman.conf's global SigLevel like every other repo.
  sudo sed -i '/^\[omarchy\]$/{n;/^SigLevel = Never$/d}' /etc/pacman.conf
  sudo pacman -Sy
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
    ;;
  *)
    echo "Unsupported OS for this script: $OS_ID (only omarchy, arch, cachyos)" >&2
    exit 1
    ;;
  esac
}

install_paru() {
  if command -v paru >/dev/null; then
    return
  fi
  log "Installing paru"
  sudo pacman -S --needed --noconfirm paru
}

install_packages() {
  log "Installing official-repo packages"
  # shellcheck disable=SC2046
  sudo pacman -S --needed --noconfirm $(grep -vE '^\s*(#|$)' "$REPO_DIR/packages/pacman.txt")

  log "Installing AUR packages via paru"
  # shellcheck disable=SC2046
  paru -S --needed --noconfirm $(grep -vE '^\s*(#|$)' "$REPO_DIR/packages/aur.txt")
}

install_plugins() {
  log "Restoring Omarchy plugins"
  while read -r id url; do
    [[ -z $id || $id == \#* ]] && continue
    omarchy plugin add "$url" --enable --yes
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
  sudo ufw enable
}

# Installing the flatpak package does NOT add Flathub - it has to be
# registered as a remote separately.
setup_flatpak() {
  log "Adding Flathub remote"
  flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
}

restore_dotfiles() {
  log "TODO: dotfiles restore not implemented yet (deliberately done last)"
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
  install_plugins
  setup_libvirt
  setup_ufw
  setup_flatpak
  setup_git_identity
  restore_dotfiles

  log "Done. Remaining manual steps:"
  echo "  - Review makepkg.conf's BUILDENV to confirm ccache is actually enabled"
  echo "  - Log out/in (or reboot) for the kvm/libvirt group membership to take effect"
}

main "$@"
