#!/bin/bash
# Backs up Claude Code history/memory to Dropbox so restore_claude.sh always
# has something current to restore from. Companion to restore_claude.sh -
# see that script for why this lives in Dropbox instead of the public
# dotfiles repo. Run automatically by a SessionEnd hook (~/.claude/settings.json);
# safe to also run by hand any time. rsync only copies what changed, so this
# is a cheap no-op when nothing's new.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$REPO_DIR/claude_backup_lib.sh"

BACKUP_DIR="$HOME/Dropbox/claudebackup"

if [[ ! -d "$HOME/Dropbox" ]]; then
  exit 0
fi

mkdir -p "$BACKUP_DIR/projects"

# --no-links: memory links made by restore_claude.sh (link_foreign_memory)
# stay on this machine; restore makes them again elsewhere.
if ! rsync_retry -a --no-links "$HOME/.claude/projects/" "$BACKUP_DIR/projects/"; then
  echo "backup_claude.sh: rsync failed after retries, leaving Dropbox backup as-is" >&2
  cleanup_rsync_temp_files "$BACKUP_DIR/projects"
  exit 1
fi
cleanup_rsync_temp_files "$BACKUP_DIR/projects"

cp "$HOME/.claude/settings.json" "$BACKUP_DIR/settings.json"

# Project folders (see WORK_PROJECTS in claude_backup_lib.sh). No --delete:
# an empty or half-restored folder on a fresh install must never wipe the
# backup copy. Files deleted locally just stay in the backup, which is
# harmless. A failure here is reported but doesn't stop the memory manifest
# update below.
for name in "${WORK_PROJECTS[@]}"; do
  src="$HOME/Work/$name"
  [[ -d "$src" ]] || continue
  mkdir -p "$BACKUP_DIR/work/$name"
  if ! rsync_retry -a "$src/" "$BACKUP_DIR/work/$name/"; then
    echo "backup_claude.sh: rsync of $src failed after retries" >&2
  fi
  cleanup_rsync_temp_files "$BACKUP_DIR/work/$name"
done

# Wizardry 8 save editor (see W8_EDITOR_SRC in claude_backup_lib.sh). The
# patch is only replaced when the clone still has local changes, so a fresh
# upstream checkout can't overwrite the saved fixes with an empty file.
w8_backup="$BACKUP_DIR/wizardry8-editor"
if [[ -d "$W8_EDITOR_SRC/.git" ]] && ! git -C "$W8_EDITOR_SRC" diff --quiet; then
  mkdir -p "$w8_backup"
  patch_tmp="$(mktemp)"
  {
    echo "Local fixes to anonidiot/Wizardry8Editor, made against commit $(git -C "$W8_EDITOR_SRC" rev-parse --short HEAD)."
    echo "Apply in a fresh clone with: git apply local-fixes.patch"
    echo
    git -C "$W8_EDITOR_SRC" diff
  } >"$patch_tmp"
  mv "$patch_tmp" "$w8_backup/local-fixes.patch"
fi
if [[ -d "$W8_GAME_DIR/tools" ]]; then
  mkdir -p "$w8_backup/tools"
  if ! rsync_retry -a --exclude=__pycache__ "$W8_GAME_DIR/tools/" "$w8_backup/tools/"; then
    echo "backup_claude.sh: rsync of $W8_GAME_DIR/tools failed after retries" >&2
  fi
  cleanup_rsync_temp_files "$w8_backup/tools"
  for f in "${W8_LAUNCHERS[@]}"; do
    if [[ -f "$W8_GAME_DIR/$f" ]]; then
      cp -p "$W8_GAME_DIR/$f" "$w8_backup/$f"
    fi
  done
fi

# Skills (see CLAUDE_SKILLS in claude_backup_lib.sh). -L copies the files a
# symlinked skill points at, so the backup still works once that package is
# gone. Skipped if the skill is missing or its link is broken here.
for name in "${CLAUDE_SKILLS[@]}"; do
  src="$HOME/.claude/skills/$name"
  [[ -d "$src" ]] || continue
  mkdir -p "$BACKUP_DIR/skills/$name"
  if ! rsync_retry -aL "$src/" "$BACKUP_DIR/skills/$name/"; then
    echo "backup_claude.sh: rsync of skill $name failed after retries" >&2
  fi
  cleanup_rsync_temp_files "$BACKUP_DIR/skills/$name"
done

# FreeBSD has no Dropbox client: ~/Dropbox there is a local copy kept with
# rclone, so nothing above has reached Dropbox yet. Upload the backup folder
# here, before the manifest below claims these files are synced.
#   copy, never sync: copy never deletes anything in Dropbox.
#   --update: a file another machine pushed more recently is left alone.
# The SessionEnd hook hides this script's output, so results go to a log.
# If the upload fails the manifest is left untouched, so it never records a
# state Dropbox doesn't actually have.
if [[ "$(uname -s)" == "FreeBSD" ]]; then
  log="$HOME/.cache/claude_backup.log"
  mkdir -p "$(dirname "$log")"
  if rclone copy --update "$BACKUP_DIR" "${RCLONE_DROPBOX_REMOTE}claudebackup" >>"$log" 2>&1; then
    echo "$(date '+%F %T') uploaded $BACKUP_DIR to ${RCLONE_DROPBOX_REMOTE}claudebackup" >>"$log"
  else
    echo "$(date '+%F %T') rclone upload FAILED - manifest not updated" >>"$log"
    echo "backup_claude.sh: rclone upload failed, see $log" >&2
    exit 1
  fi
fi

# We just pushed these files to Dropbox, so they're now the "last known
# synced" state - record it for restore_claude.sh's 3-way conflict check
# (see claude_backup_lib.sh) on this or any other machine sharing this backup.
while IFS= read -r relpath; do
  manifest_set "$relpath" "$(file_hash "$HOME/.claude/$relpath")"
done < <(tracked_files "$HOME/.claude")
