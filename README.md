# dotfiles

Restores this Omarchy/Arch/CachyOS setup on a fresh install. Supports Omarchy,
vanilla Arch, and CachyOS — not EndeavourOS or Garuda.

## Bootstrap on a genuinely fresh machine

This is a **private** repo, so it can't just be `git clone`d on a machine with
no GitHub auth yet. `resume.sh` can't do this part for you either — it lives
inside the repo you haven't cloned yet. Run this first:

```bash
sudo pacman -S --needed git github-cli
gh auth login       # interactive: GitHub.com, HTTPS, browser-based login
gh auth setup-git   # wires git's credential helper to gh's stored token
gh repo clone ut316ab/dotfiles ~/dotfiles
cd ~/dotfiles && bash resume.sh
```

The `gh auth login` step is the one part that can't be scripted — it's an
interactive OAuth flow (open a URL, approve a one-time code in a browser on
any device). Everything after that is unattended.

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
