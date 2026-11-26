#!/bin/bash
# Restores Claude Code history/memory from Dropbox onto this machine.
#
# Deliberately separate from resume.sh: Claude conversation history and
# memory can contain things that don't belong in a public git repo, so it
# lives in Dropbox instead. It also depends on Dropbox having finished its
# own sign-in + sync first, which isn't something resume.sh can wait on as
# part of an otherwise fully-automated, non-interactive run - run this
# script by hand once Dropbox has caught up.
#
# Usage: bash restore_claude.sh

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$REPO_DIR/claude_backup_lib.sh"

BACKUP_DIR="$HOME/Dropbox/claudebackup"

if [[ ! -d "$BACKUP_DIR" ]]; then
  echo "No Dropbox backup found at $BACKUP_DIR yet." >&2
  echo "Make sure Dropbox is signed in and has finished syncing, then re-run this script." >&2
  exit 1
fi

mkdir -p ~/.claude

# --update: skip any file that's newer locally than in the backup. Plain
# `cp -r` overwrites unconditionally regardless of which side is actually
# newer - confirmed causing real data loss (2026-09-12): a stale Dropbox
# backup (from before the SessionEnd hook's path broke, see the settings.json
# handling below) silently reverted several memory files that had been
# updated more recently than the last successful backup. rsync -au only
# pulls in what's actually missing or stale locally.
#
# memory/*.md is excluded here and handled below with a content-hash check
# instead of mtime - now that more than one machine shares this Dropbox
# backup, mtimes aren't reliable (cross-machine clock skew, Dropbox
# rewriting them on sync) and rsync -au can't tell "remote moved since I
# last synced" apart from "only I changed this locally" the way a
# last-known-synced hash can. Session transcripts/tool-results/subagent logs
# stay on plain rsync -au - they get a fresh UUID per session so they never
# collide, no hash bookkeeping needed.
if ! rsync_retry -au --exclude '*/memory/*.md' "$BACKUP_DIR/projects/" ~/.claude/projects/; then
  echo "restore_claude.sh: rsync failed after retries" >&2
  cleanup_rsync_temp_files ~/.claude/projects
  exit 1
fi
cleanup_rsync_temp_files ~/.claude/projects

# 3-way check per memory file: local hash, remote hash, and the hash each
# side last agreed on (see claude_backup_lib.sh). Only pulls when the
# remote clearly moved and local didn't; never silently picks a side when
# both changed since the last sync.
conflicts=()
while IFS= read -r relpath; do
  remote="$BACKUP_DIR/$relpath"
  local="$HOME/.claude/$relpath"
  remote_hash="$(file_hash "$remote")"
  local_hash="$(file_hash "$local")"
  last_hash="$(manifest_get "$relpath")"

  if [[ "$remote_hash" == "$local_hash" ]]; then
    : # already in sync
  elif [[ -z "$local_hash" || "$local_hash" == "$last_hash" ]]; then
    mkdir -p "$(dirname "$local")"
    cp "$remote" "$local"
    echo "Pulled newer $relpath from Dropbox"
  elif [[ "$remote_hash" == "$last_hash" ]]; then
    : # only changed locally - next backup push will cover it
    continue
  else
    echo "CONFLICT: $relpath changed on both sides since last sync - not overwriting" >&2
    cp "$remote" "$local.remote-conflict"
    echo "  remote version saved as $relpath.remote-conflict - merge by hand" >&2
    conflicts+=("$relpath")
    continue
  fi
  manifest_set "$relpath" "$remote_hash"
done < <(tracked_files "$BACKUP_DIR")

# Backup made under a different username: point this account at its memory.
link_foreign_memory

# The backed-up settings.json can carry a hooks.SessionEnd path baked in from
# whatever machine/checkout last ran backup_claude.sh - restoring it verbatim
# can clobber a correct, freshly-computed path that resume.sh's
# setup_claude_backup_hook already wrote for THIS machine, regardless of
# which script happened to run first (found in practice: the backup carried
# a stale ~/Work/dotfiles-resume path, overwriting the correct ~/dotfiles
# one resume.sh had just set). Deep-merge onto whatever's already at
# ~/.claude/settings.json instead of overwriting outright, so an existing
# hooks.SessionEnd always wins over the backup's.
[[ -f ~/.claude/settings.json ]] || echo '{}' >~/.claude/settings.json
tmp="$(mktemp)"
jq -s '.[1] * .[0]' ~/.claude/settings.json "$BACKUP_DIR/settings.json" >"$tmp"
mv "$tmp" ~/.claude/settings.json

# Project folders (see WORK_PROJECTS in claude_backup_lib.sh). -u, so a
# file that's newer locally is never overwritten.
for name in "${WORK_PROJECTS[@]}"; do
  src="$BACKUP_DIR/work/$name"
  [[ -d "$src" ]] || continue
  mkdir -p "$HOME/Work/$name"
  if rsync_retry -au "$src/" "$HOME/Work/$name/"; then
    echo "Restored ~/Work/$name from Dropbox"
  else
    echo "restore_claude.sh: rsync of ~/Work/$name failed after retries" >&2
  fi
  cleanup_rsync_temp_files "$HOME/Work/$name"
done

# Folders directly under ~ (see HOME_FOLDERS in claude_backup_lib.sh). -u, so
# a file that's newer locally is never overwritten.
for name in "${HOME_FOLDERS[@]}"; do
  src="$BACKUP_DIR/home/$name"
  [[ -d "$src" ]] || continue
  mkdir -p "$HOME/$name"
  if rsync_retry -au "$src/" "$HOME/$name/"; then
    # Dropbox doesn't keep Unix permissions, and ssh refuses a private key
    # others can read (vms holds VM SSH keys), so make it owner-only again.
    chmod -R go-rwx "$HOME/$name"
    echo "Restored ~/$name from Dropbox"
  else
    echo "restore_claude.sh: rsync of ~/$name failed after retries" >&2
  fi
  cleanup_rsync_temp_files "$HOME/$name"
done

# Skills (see CLAUDE_SKILLS in claude_backup_lib.sh). A skill that already
# works here is left alone - it may be a symlink into a package, and copying
# through it would write into a root-owned folder. A broken link (the package
# was removed) is replaced with the backed-up copy.
for name in "${CLAUDE_SKILLS[@]}"; do
  src="$BACKUP_DIR/skills/$name"
  dest="$HOME/.claude/skills/$name"
  [[ -d "$src" ]] || continue
  [[ -d "$dest" ]] && continue
  [[ -L "$dest" ]] && rm -f -- "$dest"
  mkdir -p "$dest"
  if rsync_retry -a "$src/" "$dest/"; then
    echo "Restored Claude skill $name from Dropbox"
  else
    echo "restore_claude.sh: rsync of skill $name failed after retries" >&2
  fi
  cleanup_rsync_temp_files "$dest"
done

# Wizardry 8 save editor scripts and launchers go back into the game folder,
# only if the game is installed (the launchers point into it). -u, as above.
# The source patch isn't applied here: it needs a fresh clone and a rebuild.
w8_backup="$BACKUP_DIR/wizardry8-editor"
if [[ -d "$w8_backup/tools" && -d "$W8_GAME_DIR" ]]; then
  mkdir -p "$W8_GAME_DIR/tools"
  if rsync_retry -au "$w8_backup/tools/" "$W8_GAME_DIR/tools/"; then
    for f in "${W8_LAUNCHERS[@]}"; do
      if [[ -f "$w8_backup/$f" ]]; then
        rsync -au "$w8_backup/$f" "$W8_GAME_DIR/$f"
      fi
    done
    echo "Restored Wizardry 8 editor tools to $W8_GAME_DIR (source fixes: $w8_backup/local-fixes.patch)"
  else
    echo "restore_claude.sh: rsync of Wizardry 8 editor tools failed after retries" >&2
  fi
  cleanup_rsync_temp_files "$W8_GAME_DIR/tools"
fi

if ((${#conflicts[@]})); then
  echo "Restored Claude history and settings from $BACKUP_DIR, but ${#conflicts[@]} memory file(s) need manual merge: ${conflicts[*]}" >&2
  exit 2
fi

echo "Restored Claude history and settings from $BACKUP_DIR"
