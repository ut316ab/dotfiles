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

BACKUP_DIR="$HOME/Dropbox/claudebackup"

if [[ ! -d "$BACKUP_DIR" ]]; then
  echo "No Dropbox backup found at $BACKUP_DIR yet." >&2
  echo "Make sure Dropbox is signed in and has finished syncing, then re-run this script." >&2
  exit 1
fi

mkdir -p ~/.claude
cp -r "$BACKUP_DIR/projects" ~/.claude/
cp "$BACKUP_DIR/settings.json" ~/.claude/settings.json

echo "Restored Claude history and settings from $BACKUP_DIR"
