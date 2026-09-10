# dotfiles

Restores this Omarchy/Arch/CachyOS setup on a fresh install. Supports Omarchy,
vanilla Arch, and CachyOS — not EndeavourOS or Garuda.

## Bootstrap on a genuinely fresh machine

This is a **private** repo, so it can't just be `git clone`d on a machine with
no GitHub auth yet. `resume.sh` can't do this part for you either — it lives
inside the repo you haven't cloned yet. A fresh Arch/CachyOS/Omarchy install
has no browser, so plan for that ahead of time — don't wait until you're
mid-reinstall to figure out auth.

### Preferred: pre-generate a token (no browser/phone needed at restore time)

Before wiping the old machine, from any browser:
1. https://github.com/settings/tokens → generate a classic PAT with `repo`,
   `read:org`, `gist` scopes
2. Save it in a password manager

Then on the fresh machine:
```bash
sudo pacman -S --needed git github-cli
echo "$GITHUB_TOKEN" | gh auth login --with-token
gh auth setup-git   # wires git's credential helper to gh's stored token
gh repo clone ut316ab/dotfiles ~/dotfiles
cd ~/dotfiles && bash resume.sh
```

### Fallback: device-code flow (needs a second device with a browser)

If there's no pre-generated token, `gh auth login` (no `--web` flag) prints a
short one-time code and a URL — open that URL from a phone or any other
device, enter the code, and it authenticates. No browser needed on the
machine being restored, but you do need *some* other device handy.

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
