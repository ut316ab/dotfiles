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

Run this at the local console, not over SSH. `resume.sh` is interactive by
design (it asks about git identity and the Claude backup hook so you can
choose what gets resumed), and `ufw enable` separately prompts for
confirmation whenever it detects it's running under SSH — a prompt this
script doesn't suppress, so over SSH it can sit waiting for a keypress you
weren't expecting.

## What resume.sh does

- Detects the OS and bootstraps Omarchy (official installer on vanilla Arch;
  a direct repo+keyring bootstrap on CachyOS, since there's no official
  Omarchy support there — see the `bootstrap_cachyos_omarchy_repo` comment
  in the script for why that's safe on this machine specifically)
- Installs `packages/pacman.txt` and `packages/aur.txt` (curated, not raw
  `pacman -Qqe` output — gaming, VirtualBox, and one-off session installs
  were deliberately excluded)
- Restores `plugins.txt` (Omarchy third-party plugins, including the
  `dorneles.omapod` APOD bar widget — its 1-click wallpaper action is the
  wallpaper source, so no wallpaper file is stored in this repo)
- Restores Hyprland configs (`config/hypr/*.lua`) and the Quickshell
  (omarchy-shell) bar config (`config/omarchy/shell.json`)
- Installs and configures Dropbox via Omarchy's own
  `omarchy-install-service-dropbox` (not tracked in `packages/pacman.txt` —
  that script owns `dropbox`, `dropbox-cli`, `nautilus-dropbox`,
  `libappindicator`, and `python-gpgme` itself), plus `dropbox-cli
  autostart y` since Omarchy's script doesn't set that up either
- Replicates libvirt/UFW/Flathub config that installing packages alone
  doesn't set up

## What it doesn't do yet

Git identity is queried at runtime instead (see `setup_git_identity`). Other
dotfiles (`btop`, `fcitx5`, Dropbox autostart, etc.) aren't captured yet —
out of scope for now, restricted to Hyprland + the bar config.

## Claude Code history

Not restored by `resume.sh` at all — this repo is public, and Claude
conversation history/memory isn't something that belongs in public git
history. It's backed up to Dropbox instead (`~/Dropbox/claudebackup`).

Once Dropbox is signed in and has finished syncing on the new machine, run:

```bash
bash restore_claude.sh
```

separately. It's not wired into the main `resume.sh` run because Dropbox's
own sign-in/sync isn't something the rest of the script can wait on.

The Dropbox side (keeping the backup itself current) is automated:
`backup_claude.sh` rsyncs `~/.claude/projects` and `settings.json` to
`~/Dropbox/claudebackup`, run automatically by a `SessionEnd` hook. No
cron/systemd timer needed: rsync only copies what changed, so it's cheap to
run at the end of every session. If Dropbox isn't set up on a machine, the
script just exits quietly instead of failing.

That hook is installed by `resume.sh` itself (`setup_claude_backup_hook`),
not restored via Dropbox — it merges a `SessionEnd` entry into
`~/.claude/settings.json` pointed at *this machine's* actual `$REPO_DIR`.
Deliberately not just synced as part of `settings.json` from
`~/Dropbox/claudebackup`: that path is frozen at backup time, and would be
wrong on a fresh machine whose clone doesn't happen to live at the exact
same path as wherever it was last backed up from.
