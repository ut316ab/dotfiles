# dotfiles

Restores this Omarchy/Arch/CachyOS setup on a fresh install. Supports Omarchy,
vanilla Arch, and CachyOS — not EndeavourOS or Garuda.

## Bootstrap on a genuinely fresh machine

This is a **private** repo, so it can't just be `git clone`d on a machine with
no GitHub auth yet. `resume.sh` can't do this part for you either — it lives
inside the repo you haven't cloned yet. A fresh Arch/CachyOS/Omarchy install
has no browser, so plan for that ahead of time — don't wait until you're
mid-reinstall to figure out auth.

Neither path below needs a browser *on the fresh machine* — but the token
still has to get typed in somehow, so here's the actual mechanics, not just
"echo $TOKEN as if it appears from nowhere":

### Preferred: pre-generate a token, paste it in over SSH from another device

Before wiping the old machine, from any browser:
1. https://github.com/settings/tokens → generate a classic PAT with `repo`,
   `read:org`, `gist` scopes
2. Save it in a password manager (a phone app, not a browser, works fine)

On the fresh machine (keyboard + monitor, nothing else installed yet), just
enough to get remote access:
```bash
sudo pacman -S --needed openssh git github-cli
sudo systemctl enable --now sshd
ip a   # note the IP
```

From your phone (Termux/Blink/Termius) or any other device — open the
password manager app to view the token, then SSH into the fresh machine and
paste it there. The paste happens client-side in that SSH session, so it
doesn't matter that the fresh machine itself has no browser:
```bash
echo "<paste the token here>" | gh auth login --with-token
gh auth setup-git
gh repo clone ut316ab/dotfiles ~/dotfiles
cd ~/dotfiles && bash resume.sh
```

The real requirement isn't "a browser on the fresh machine" — it's one other
device, anywhere, that can view the token and open an SSH connection.

### Fallback: device-code flow (no pre-generated token needed)

If there's no token saved ahead of time, plain `gh auth login` (no `--web`
flag) prints a short one-time code and a URL — open that URL from a phone or
any other device's browser, enter the code, done.

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
