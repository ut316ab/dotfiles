# dotfiles

My CachyOS + KDE Plasma setup, and the way back to it: if I reinstall Linux
(for example after trying FreeBSD on this machine), `resume.sh` puts my
programs and settings back on a fresh CachyOS (or Arch) install with KDE.

This repo is public only so a fresh install can fetch it with nothing but
`git`, with no GitHub login needed. It's for my own use.

## Restoring

```bash
sudo pacman -S --needed git
git clone https://github.com/ut316ab/dotfiles ~/dotfiles
cd ~/dotfiles && bash resume.sh
```

Run it as your normal user, from a terminal inside the KDE session. It asks
for the sudo password once, and asks a few questions along the way: whether to
keep an existing git identity (or enter `user.name` / `user.email`), and
whether to set up the Claude backup hook. Running it again is safe. Config
files it would overwrite are kept with a `.before-resume-<date>` suffix.

When it finishes, it lists what's left to do by hand:

1. Sign in to Dropbox in the browser and let it sync.
2. Run `bash restore_claude.sh` (see below).
3. Reboot.

## What resume.sh does

- **Packages:** `packages/pacman.txt` (repo) and `packages/aur.txt` (AUR,
  through paru). A reviewed list of what I actually use; the base system and
  KDE come with the CachyOS installer and aren't listed.
- **System:** SSH server, libvirt/QEMU (VMs run as my user), a unit that
  backs up VM definitions to `/mnt/storage` whenever they change, an
  ananicy-cpp override so VMs run at normal priority, the firewall (only KDE
  Connect and SSH allowed in), Flathub, the SDDM login screen.
- **My configs:** everything under `config/home/` is copied into `~`: KDE
  Plasma settings (look, window rules, shortcuts, panel, monitor), kitty,
  zsh, rofi (Meta+D launcher), fastfetch, btop, micro, MangoHud, my scripts
  in `~/.local/bin` and their launchers, and the hyprfollow KWin script.
  System files are in `config/etc/`.
- **zsh:** Oh My Zsh with zsh-autosuggestions and zsh-syntax-highlighting,
  the agnosterzak theme, and zsh as the login shell (CachyOS defaults to fish).
- **Rust:** rustup with the stable toolchain and rust-analyzer.
- **LazyVim:** the official starter, with language support for Python, C/C++,
  Go, Rust, Lua, Bash, JSON, YAML, TOML and Markdown; plugins and language
  servers are installed during the run.
- **Dropbox:** autostart, and it opens the sign-in if run inside KDE.

## Things fetched from their authors, not stored here

Oh My Zsh and its plugins, the
[agnosterzak](https://github.com/zakaziko99/agnosterzak-ohmyzsh-theme) theme,
the [Catppuccin](https://github.com/catppuccin) themes for btop and micro,
LazyVim, and Krohnkite (from the AUR) are all downloaded from their own
sources during the restore. They belong to their authors, so they aren't
copied into this repo.

## Claude Code history

Not restored by `resume.sh`, and not stored in this repo: conversation
history and memory don't belong in a public repo. They're backed up to
Dropbox (`~/Dropbox/claudebackup`) instead.

- `backup_claude.sh` runs automatically at the end of every Claude Code
  session (a `SessionEnd` hook, which `resume.sh` offers to set up). It copies
  `~/.claude/projects`, `settings.json`, the project folders listed in
  `WORK_PROJECTS` in `claude_backup_lib.sh`, and a few other pieces to
  Dropbox. On FreeBSD, where there's no Dropbox app, it uploads the backup
  with rclone instead.
- `restore_claude.sh` is run by hand once Dropbox has finished syncing on a
  new machine. It never overwrites a memory file that changed on both sides;
  it saves the other version next to it for merging by hand.

## Credits and license

The rofi theme (`config/home/.config/rofi`), the fastfetch configs and the
kitty settings come from
[LinuxBeginnings/Hyprland-Dots](https://github.com/LinuxBeginnings/Hyprland-Dots)
by JaKooLit and contributors, licensed under GPL-3.0; their credit headers are
kept in those files.

This repo is licensed under the GNU General Public License v3.0; see
[LICENSE](LICENSE).
