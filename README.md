# dotfiles

Restores this Omarchy/Arch/CachyOS setup on a fresh install. Supports Omarchy,
vanilla Arch, and CachyOS — not EndeavourOS or Garuda.

## Bootstrap on a genuinely fresh machine

This repo is **public**, specifically so a fresh install needs zero GitHub
auth to get it — no token, no browser, no second device. Just:

```bash
sudo pacman -S --needed git
git clone https://github.com/ut316ab/dotfiles ~/dotfiles
cd ~/dotfiles && bash resume.sh
```

## What resume.sh does

- Detects the OS and bootstraps Omarchy (official installer on vanilla Arch;
  a direct repo+keyring bootstrap on CachyOS, since there's no official
  Omarchy support there — see the `bootstrap_cachyos_omarchy_repo` comment
  in the script for why that's safe on this machine specifically)
- Installs `packages/pacman.txt` and `packages/aur.txt` (curated, not raw
  `pacman -Qqe` output — gaming, VirtualBox, and one-off session installs
  were deliberately excluded)
- Restores `plugins.txt` (Omarchy third-party plugins)
- Replicates libvirt/UFW/Flathub config that installing packages alone
  doesn't set up

## What it doesn't do yet

Dotfiles restore (`~/.config/hypr`, `git`, `btop`, `fcitx5`, etc.) isn't wired
up yet — `restore_dotfiles()` in `resume.sh` is a placeholder.
