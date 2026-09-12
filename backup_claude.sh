#!/bin/bash
# Backs up Claude Code history/memory to Dropbox so restore_claude.sh always
# has something current to restore from. Companion to restore_claude.sh -
# see that script for why this lives in Dropbox instead of the public
# dotfiles repo. Run automatically by a SessionEnd hook (~/.claude/settings.json);
# safe to also run by hand any time. rsync only copies what changed, so this
# is a cheap no-op when nothing's new.

set -euo pipefail

BACKUP_DIR="$HOME/Dropbox/claudebackup"

if [[ ! -d "$HOME/Dropbox" ]]; then
  exit 0
fi

mkdir -p "$BACKUP_DIR/projects"
rsync -a "$HOME/.claude/projects/" "$BACKUP_DIR/projects/"
cp "$HOME/.claude/settings.json" "$BACKUP_DIR/settings.json"
