#!/bin/bash
# Restore this machine's setup on a fresh CachyOS (or Arch) + KDE Plasma install.
# This is the way back to Linux: run it after reinstalling, then follow the
# manual steps it prints at the end.
#
# Usage: git clone https://github.com/ut316ab/dotfiles ~/dotfiles
#        cd ~/dotfiles && bash resume.sh
#
# Run it as your normal user from a terminal inside the KDE session (it uses
# sudo where needed). It's safe to run again: every step checks first, and any
# config file it would overwrite is kept with a ".before-resume-<date>" suffix.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"

log() { printf '\033[1;33m==>\033[0m %s\n' "$1"; }
warn() { printf '\033[1;31m!!\033[0m %s\n' "$1" >&2; }

# --- 1. checks ----------------------------------------------------------------

check_system() {
  if [[ $EUID -eq 0 ]]; then
    warn "Run this as your normal user, not root (it calls sudo itself)."
    exit 1
  fi
  . /etc/os-release
  case "$ID" in
    cachyos | arch) log "Detected $NAME" ;;
    *)
      warn "This script is for CachyOS or Arch, not '$ID'."
      exit 1
      ;;
  esac
}

# Ask for the sudo password once, then keep sudo's timestamp fresh in the
# background so a long package install doesn't stop halfway for a password.
start_sudo() {
  sudo -v
  while kill -0 $$ 2>/dev/null; do
    sudo -n true
    sleep 50
  done 2>/dev/null &
}

# --- 2-4. packages ------------------------------------------------------------

# paru comes from CachyOS's own repo; on plain Arch it's built from the AUR.
install_paru() {
  if command -v paru >/dev/null; then
    return
  fi
  if pacman -Si paru &>/dev/null; then
    log "Installing paru"
    sudo pacman -S --needed --noconfirm paru
  else
    log "Building paru-bin from the AUR (paru isn't in this system's repos)"
    sudo pacman -S --needed --noconfirm base-devel git
    local tmp
    tmp="$(mktemp -d)"
    git clone --depth 1 https://aur.archlinux.org/paru-bin.git "$tmp/paru-bin"
    (cd "$tmp/paru-bin" && makepkg -si --noconfirm)
    rm -rf "$tmp"
  fi
}

# A package on the list that conflicts with something already installed makes
# pacman ask "Remove X?", and --noconfirm answers no, aborting the whole
# install. For the two known cases, remove the old one first with -Rdd (skip
# the dependency check): the replacement provides the same things, so whatever
# depended on the old one is satisfied again by the install that follows.
#   jack2 -> pipewire-jack (both provide "jack"; CachyOS ships jack2)
#   rust  -> rustup        (rustup provides "rust" and "cargo")
replace_conflicting() {
  local old="$1" new="$2"
  if pacman -Q "$old" &>/dev/null && ! pacman -Q "$new" &>/dev/null; then
    log "Replacing $old with $new"
    sudo pacman -Rdd --noconfirm "$old"
    sudo pacman -S --needed --noconfirm "$new"
  fi
}

install_packages() {
  replace_conflicting jack2 pipewire-jack
  replace_conflicting rust rustup

  log "Installing packages from packages/pacman.txt"
  # shellcheck disable=SC2046
  sudo pacman -S --needed --noconfirm $(grep -vE '^\s*(#|$)' "$REPO_DIR/packages/pacman.txt")

  log "Installing AUR packages from packages/aur.txt"
  local pkgs=() p
  while read -r p; do
    [[ -z $p || $p == \#* ]] && continue
    # yay may already be there as CachyOS's repo package, which conflicts with yay-bin
    [[ $p == yay-bin ]] && command -v yay >/dev/null && continue
    pkgs+=("$p")
  done <"$REPO_DIR/packages/aur.txt"
  if ((${#pkgs[@]})); then
    paru -S --needed --noconfirm "${pkgs[@]}"
  fi
}

# Krohnkite (KWin tiling) is installed from its release .kwinscript, not the
# AUR package: the AUR PKGBUILD also checksums Codeberg's auto-generated source
# tarball, which Codeberg regenerates, so the build fails with "0.9.9.2.tar.gz
# ... FAILED" (seen 2026-11-03 and 2026-11-26) although the .kwinscript itself
# is unchanged. The sha256 below is the AUR's own for that .kwinscript.
# Per-user install, not tracked by pacman: to update, bump both values.
KROHNKITE_VERSION=0.9.9.2
KROHNKITE_SHA256=42f7f66531d366c74b5fc860381da3517ccb4cdccd1f80c122fcab6e9a8fcf7e

install_krohnkite() {
  local dir="$HOME/.local/share/kwin/scripts/krohnkite"
  if grep -qs "\"Version\": *\"$KROHNKITE_VERSION\"" "$dir/metadata.json"; then
    log "Krohnkite $KROHNKITE_VERSION already installed"
    return
  fi
  log "Installing Krohnkite $KROHNKITE_VERSION"
  local tmp
  tmp="$(mktemp -d)"
  curl -fsSL -o "$tmp/krohnkite.kwinscript" \
    "https://codeberg.org/anametologin/Krohnkite/releases/download/$KROHNKITE_VERSION/krohnkite.kwinscript"
  if ! echo "$KROHNKITE_SHA256  $tmp/krohnkite.kwinscript" | sha256sum -c --quiet -; then
    warn "Krohnkite download doesn't match the expected checksum; not installing it."
    rm -rf "$tmp"
    return 1
  fi
  if [[ -d $dir ]]; then
    kpackagetool6 --type KWin/Script --upgrade "$tmp/krohnkite.kwinscript"
  else
    kpackagetool6 --type KWin/Script --install "$tmp/krohnkite.kwinscript"
  fi
  rm -rf "$tmp"
}

# --- 5-10. system setup (sudo) --------------------------------------------------

setup_sshd() {
  log "Enabling the SSH server"
  sudo systemctl enable --now sshd
}

setup_libvirt() {
  log "Configuring libvirt"
  sudo sed -i 's/^#\?firewall_backend\s*=\s*".*"/firewall_backend = "iptables"/' /etc/libvirt/network.conf
  sudo sed -i 's/^#\?auth_unix_ro\s*=\s*".*"/auth_unix_ro = "polkit"/' /etc/libvirt/libvirtd.conf
  sudo sed -i 's/^#\?auth_unix_rw\s*=\s*".*"/auth_unix_rw = "polkit"/' /etc/libvirt/libvirtd.conf
  # VMs run as this user, so disk images in this user's folders work
  sudo sed -i "s/^#\?user\s*=\s*\".*\"/user = \"$USER\"/" /etc/libvirt/qemu.conf
  sudo usermod -aG kvm,libvirt "$USER"
  sudo systemctl enable --now libvirtd.service
  sudo virsh net-autostart default
  sudo virsh net-start default 2>/dev/null || true
}

# Copies VM definitions and their UEFI variables to /mnt/storage whenever they
# change (a .path unit watches the folders). Does nothing harmful if
# /mnt/storage isn't mounted; it just fails until it is.
setup_libvirt_config_backup() {
  log "Installing the libvirt config backup units"
  sudo install -m 644 "$REPO_DIR/config/etc/systemd/system/libvirt-config-backup.path" \
    "$REPO_DIR/config/etc/systemd/system/libvirt-config-backup.service" /etc/systemd/system/
  sudo systemctl daemon-reload
  sudo systemctl enable --now libvirt-config-backup.path
}

# CachyOS's ananicy rules run QEMU at low priority, which makes desktop VMs
# stutter; this override gives it normal priority.
setup_ananicy() {
  log "Installing the ananicy-cpp override for QEMU"
  sudo install -D -m 644 "$REPO_DIR/config/etc/ananicy.d/99-local/qemu.rules" /etc/ananicy.d/99-local/qemu.rules
  sudo systemctl enable ananicy-cpp
  sudo systemctl restart ananicy-cpp
}

setup_ufw() {
  log "Configuring the firewall: KDE Connect and SSH in, everything out"
  sudo ufw default deny incoming
  sudo ufw default allow outgoing
  sudo ufw allow 1714:1764/tcp comment 'KDE Connect'
  sudo ufw allow 1714:1764/udp comment 'KDE Connect'
  sudo ufw allow 22/tcp comment 'SSH'
  # --force skips ufw's own prompt, which only appears when run over SSH
  sudo ufw --force enable
  sudo systemctl enable ufw
}

# Installing flatpak doesn't add Flathub. System-wide, so via sudo: otherwise
# flatpak asks PolicyKit itself and can hang waiting for a password prompt.
setup_flatpak() {
  log "Adding the Flathub remote"
  sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
}

# Not called for now (2026-11-26): CachyOS KDE already enables Plasma Login
# Manager as display-manager.service, so `systemctl enable sddm` fails and
# set -e stops the whole restore. SDDM was only chosen for JaKooLit's Hyprland
# wallpaper sync, which is gone. To revisit: Plasma Login Manager's own
# wallpaper setting (System Settings > Login Screen), or switch to SDDM by
# disabling plasmalogin first.
setup_sddm() {
  log "Enabling the SDDM login screen"
  sudo systemctl enable sddm
}

# --- 11-14. your files ----------------------------------------------------------

# Oh My Zsh and its plugins come from their own repositories. Cloned before the
# configs are restored, because git won't clone into a folder that already exists.
setup_oh_my_zsh() {
  if [[ ! -d ~/.oh-my-zsh ]]; then
    log "Installing Oh My Zsh"
    git clone --depth 1 https://github.com/ohmyzsh/ohmyzsh.git ~/.oh-my-zsh
  fi
  local plugins=~/.oh-my-zsh/custom/plugins
  [[ -d $plugins/zsh-autosuggestions ]] ||
    git clone --depth 1 https://github.com/zsh-users/zsh-autosuggestions "$plugins/zsh-autosuggestions"
  [[ -d $plugins/zsh-syntax-highlighting ]] ||
    git clone --depth 1 https://github.com/zsh-users/zsh-syntax-highlighting.git "$plugins/zsh-syntax-highlighting"
}

# Themes by other authors are downloaded from them rather than kept in this
# repo: agnosterzak has no license (so it can't be redistributed), and the
# Catppuccin themes are fetched in their current official form.
fetch_themes() {
  log "Downloading the agnosterzak zsh theme from its author"
  local theme=~/.oh-my-zsh/themes/agnosterzak.zsh-theme
  curl -fsSL -o "$theme" \
    https://raw.githubusercontent.com/zakaziko99/agnosterzak-ohmyzsh-theme/master/agnosterzak.zsh-theme
  # No battery segment: this is a desktop (the same change JaKooLit's copy had)
  sed -i 's/^\(\s*\)prompt_battery$/\1#prompt_battery/' "$theme"

  log "Downloading Catppuccin Macchiato for btop and micro"
  mkdir -p ~/.config/btop/themes ~/.config/micro/colorschemes
  curl -fsSL -o ~/.config/btop/themes/catppuccin_macchiato.theme \
    https://raw.githubusercontent.com/catppuccin/btop/main/themes/catppuccin_macchiato.theme
  curl -fsSL -o ~/.config/micro/colorschemes/catppuccin-macchiato.micro \
    https://raw.githubusercontent.com/catppuccin/micro/main/themes/catppuccin-macchiato.micro
}

# Copies config/home into ~. A file that already exists and differs is kept as
# <name>.before-resume-<date> first. Plasma rewrites its panel and desktop file
# when it quits, so plasmashell is stopped while the files are copied and
# started again afterwards; otherwise it could overwrite the restored layout.
restore_configs() {
  log "Restoring configs into your home folder"
  local plasma_was_running=0
  if pgrep -x plasmashell >/dev/null; then
    plasma_was_running=1
    kquitapp6 plasmashell 2>/dev/null || pkill -x plasmashell || true
    sleep 2
  fi

  rsync -a --backup --suffix=".before-resume-$STAMP" "$REPO_DIR/config/home/" ~/
  chmod +x ~/.local/bin/*.sh ~/.local/bin/*.py 2>/dev/null || true
  update-desktop-database ~/.local/share/applications 2>/dev/null || true

  if ((plasma_was_running)); then
    (setsid kstart plasmashell >/dev/null 2>&1 &) || true
    # KWin reads its settings again (window rules, enabled scripts)
    qdbus6 org.kde.KWin /KWin reconfigure 2>/dev/null || true
  fi
}

set_login_shell() {
  local zsh_path current
  zsh_path="$(command -v zsh)"
  current="$(getent passwd "$USER" | cut -d: -f7)"
  if [[ $current != "$zsh_path" ]]; then
    log "Switching your login shell from $current to $zsh_path"
    sudo chsh -s "$zsh_path" "$USER"
  fi
}

# --- 15-16. developer tools ----------------------------------------------------

setup_rust() {
  log "Setting up Rust (stable toolchain + rust-analyzer)"
  rustup default stable
  rustup component add rust-analyzer
}

# Fresh LazyVim from its official starter. An existing Neovim setup is moved
# aside (config, data, state and cache, as LazyVim's own instructions say).
# The language extras are enabled in lazyvim.json, and the language tools are
# installed during a headless first start, so nvim is ready on first open.
LAZYVIM_EXTRAS=(
  lang.python lang.clangd lang.go lang.rust
  lang.json lang.yaml lang.toml lang.markdown
)
MASON_TOOLS=(
  basedpyright ruff
  clangd
  gopls
  lua-language-server stylua
  bash-language-server shellcheck shfmt
  json-lsp yaml-language-server taplo
  marksman markdownlint-cli2
)

setup_lazyvim() {
  if [[ -f ~/.config/nvim/lazyvim.json ]]; then
    log "LazyVim is already set up"
  else
    local d
    for d in ~/.config/nvim ~/.local/share/nvim ~/.local/state/nvim ~/.cache/nvim; do
      if [[ -e $d ]]; then
        log "Moving the existing $d to $d.before-resume-$STAMP"
        mv "$d" "$d.before-resume-$STAMP"
      fi
    done
    log "Installing the LazyVim starter"
    git clone --depth 1 https://github.com/LazyVim/starter ~/.config/nvim
    rm -rf ~/.config/nvim/.git

    local extras=() e
    for e in "${LAZYVIM_EXTRAS[@]}"; do extras+=("\"lazyvim.plugins.extras.$e\""); done
    printf '{\n  "extras": [%s],\n  "news": {},\n  "version": 8\n}\n' "$(IFS=,; echo "${extras[*]}")" \
      >~/.config/nvim/lazyvim.json

    # Bash language server: LazyVim has no bash extra, so turn it on directly
    mkdir -p ~/.config/nvim/lua/plugins
    cat >~/.config/nvim/lua/plugins/bash.lua <<'EOF'
-- Bash language server for shell scripts (added by resume.sh)
return {
  { "neovim/nvim-lspconfig", opts = { servers = { bashls = {} } } },
}
EOF
  fi

  # Not fatal: a download that fails here (network hiccup) shouldn't stop the
  # rest of the restore. LazyVim installs anything missing next time nvim opens.
  log "Installing LazyVim's plugins (headless, may take a few minutes)"
  nvim --headless "+Lazy! sync" +qa ||
    warn "Some LazyVim plugins didn't install; they'll be retried when you open nvim"
  log "Installing language servers and tools through Mason"
  nvim --headless "+Lazy! load mason.nvim" "+MasonInstall ${MASON_TOOLS[*]}" +qa ||
    warn "Some Mason tools didn't install; run :Mason in nvim to see which"
}

# --- 17-19. personal pieces (asked during the run) ----------------------------

# Never stored in this public repo: asked each time. If git already has an
# identity, it's shown, and Enter keeps it.
setup_git_identity() {
  local name email ans
  name="$(git config --global user.name || true)"
  email="$(git config --global user.email || true)"
  if [[ -n $name && -n $email ]]; then
    read -rp "Git identity is already set: $name <$email>. Skip and keep it? [Y/n] " ans || ans=y
    [[ ! $ans =~ ^[Nn]$ ]] && return
  fi
  read -rp "Git user.name: " name
  read -rp "Git user.email: " email
  git config --global user.name "$name"
  git config --global user.email "$email"
}

# Points the SessionEnd hook at THIS checkout's backup_claude.sh. Only merges
# that one key into ~/.claude/settings.json.
setup_claude_backup_hook() {
  log "Wiring up the Claude history backup hook (SessionEnd -> backup_claude.sh)"
  mkdir -p ~/.claude
  local settings=~/.claude/settings.json tmp
  [[ -f "$settings" ]] || echo '{}' >"$settings"
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

# Personal to this repo's owner, so ask (default no) rather than rewrite
# anyone's settings.json silently.
maybe_setup_claude_backup_hook() {
  local ans
  read -rp "Set up the Claude Code history backup to Dropbox (SessionEnd hook)? [y/N] " ans || ans=n
  if [[ $ans =~ ^[Yy]$ ]]; then
    setup_claude_backup_hook
  else
    log "Skipping the Claude backup hook"
  fi
}

# Autostart comes back with the restored configs (~/.config/autostart). The
# sign-in happens in a browser and can't be scripted, so if this is running
# inside the desktop session, start Dropbox now to open that sign-in.
setup_dropbox() {
  if [[ -n ${WAYLAND_DISPLAY:-}${DISPLAY:-} ]] && ! pgrep -x dropbox >/dev/null; then
    log "Starting Dropbox: sign in in the browser window it opens"
    (setsid dropbox >/dev/null 2>&1 &) || true
  fi
}

# --- 20. finish ----------------------------------------------------------------

finish() {
  log "Done. Manual steps left:"
  echo "  1. Sign in to Dropbox in the browser (if it didn't open: run 'dropbox')"
  echo "     and let it finish syncing."
  echo "  2. Restore Claude's history and memory: bash $REPO_DIR/restore_claude.sh"
  echo "  3. Reboot: needed for the kvm/libvirt groups, zsh as your login shell,"
  echo "     and the sudo askpass helper."
  echo
  echo "  Replaced config files were kept with a .before-resume-$STAMP suffix."
}

main() {
  check_system
  start_sudo

  install_paru
  install_packages
  install_krohnkite

  setup_sshd
  setup_libvirt
  setup_libvirt_config_backup
  setup_ananicy
  setup_ufw
  setup_flatpak
  # setup_sddm  # skipped for now, see the comment above setup_sddm

  setup_oh_my_zsh
  restore_configs
  fetch_themes
  set_login_shell

  setup_rust
  setup_lazyvim

  setup_git_identity
  maybe_setup_claude_backup_hook
  setup_dropbox

  finish
}

main "$@"
