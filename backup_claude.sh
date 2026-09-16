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

if ! rsync_retry -a "$HOME/.claude/projects/" "$BACKUP_DIR/projects/"; then
  echo "backup_claude.sh: rsync failed after retries, leaving Dropbox backup as-is" >&2
  cleanup_rsync_temp_files "$BACKUP_DIR/projects"
  exit 1
fi
cleanup_rsync_temp_files "$BACKUP_DIR/projects"

cp "$HOME/.claude/settings.json" "$BACKUP_DIR/settings.json"

# We just pushed these files to Dropbox, so they're now the "last known
# synced" state - record it for restore_claude.sh's 3-way conflict check
# (see claude_backup_lib.sh) on this or any other machine sharing this backup.
while IFS= read -r relpath; do
  manifest_set "$relpath" "$(file_hash "$HOME/.claude/$relpath")"
done < <(tracked_files "$HOME/.claude")
