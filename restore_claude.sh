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

# --update: skip any file that's newer locally than in the backup. Plain
# `cp -r` overwrites unconditionally regardless of which side is actually
# newer - confirmed causing real data loss (2026-09-12): a stale Dropbox
# backup (from before the SessionEnd hook's path broke, see the settings.json
# handling below) silently reverted several memory files that had been
# updated more recently than the last successful backup. rsync -au only
# pulls in what's actually missing or stale locally.
rsync -au "$BACKUP_DIR/projects/" ~/.claude/projects/

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

echo "Restored Claude history and settings from $BACKUP_DIR"
