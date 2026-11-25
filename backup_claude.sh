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

# FreeBSD: the rclone upload further down can take a while, and Claude Code
# cancels a SessionEnd hook that runs too long (seen 2026-11-25: "Hook
# cancelled" mid-upload). So hand the whole run to daemon(8) and return at
# once. lockf(1) makes overlapping runs (sessions closed in quick
# succession) wait their turn instead of running side by side. daemon
# changes to /, hence the absolute path to this script.
log="$HOME/.cache/claude_backup.log"
if [[ "$(uname -s)" == "FreeBSD" && -z "${CLAUDE_BACKUP_DETACHED:-}" ]]; then
  mkdir -p "$(dirname "$log")"
  CLAUDE_BACKUP_DETACHED=1 daemon -f \
    lockf -k "$HOME/.cache/claude_backup.lock" \
    bash "$REPO_DIR/$(basename "${BASH_SOURCE[0]}")"
  exit 0
fi
# The detached run has no terminal: send its errors to the log.
if [[ -n "${CLAUDE_BACKUP_DETACHED:-}" ]]; then
  exec 2>>"$log"
  echo "$(date '+%F %T') backup started" >>"$log"
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
  excludes=()
  for ex in ${WORK_EXCLUDES[$name]:-}; do
    excludes+=("--exclude=/$ex/")
  done
  if ! rsync_retry -a "${excludes[@]}" "$src/" "$BACKUP_DIR/work/$name/"; then
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
#   --checksum: compare by content, not timestamp. Dropbox can't change a
#     file's timestamp alone, so files that only got a new one (restore
#     copies memory with plain cp) would otherwise all be uploaded again,
#     which got rate-limited by Dropbox on 2026-11-25.
# The SessionEnd hook hides this script's output, so results go to a log.
# If the upload fails the manifest is left untouched, so it never records a
# state Dropbox doesn't actually have.
if [[ "$(uname -s)" == "FreeBSD" ]]; then
  mkdir -p "$(dirname "$log")"
  if rclone copy --update --checksum "$BACKUP_DIR" "${RCLONE_DROPBOX_REMOTE}claudebackup" >>"$log" 2>&1; then
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
