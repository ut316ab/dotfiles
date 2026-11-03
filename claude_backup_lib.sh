# Shared helpers for backup_claude.sh / restore_claude.sh.
#
# Two problems these solve, both specific to sharing one Dropbox backup
# across multiple machines (currently: whitehole and a WSL/Arch instance):
#
# 1. backup_claude.sh's push is a plain rsync -a: whichever machine runs it
#    last wins, with no way to tell "remote moved since I last synced" apart
#    from "only I changed this locally" - the same failure class that
#    already caused real data loss on 2026-09-12 (see restore_claude.sh).
#    tracked_files/file_hash/manifest_get/manifest_set give restore_claude.sh
#    a 3-way comparison (local, remote, last-known-synced) so it can pull
#    safely, leave local-only changes alone, and flag genuine conflicts
#    instead of guessing. Scoped to settings.json + memory/*.md only -
#    session transcripts get a fresh UUID per session and never collide.
#
# 2. Dropbox's Windows client can hold a destination file locked mid-sync,
#    which fails rsync's temp-file rename with EACCES (confirmed 2026-09-16,
#    WSL pushing into /mnt/c/Dropbox) and can leave a stray
#    ".name.RANDOM" temp file behind. rsync_retry/cleanup_rsync_temp_files
#    retry past the transient lock and sweep up any leftovers automatically.
#
# Source this file; it defines functions/vars only, no side effects.

MANIFEST="$HOME/.claude/.backup_sync_manifest"

# Project folders under ~/Work that live only on this disk (no git remote,
# or holding files that can't go on GitHub, like game data and ROMs).
# backup_claude.sh copies each into $BACKUP_DIR/work/<name>, and
# restore_claude.sh copies them back. Skipped on a machine that doesn't
# have the folder.
WORK_PROJECTS=(wizardry7-amiga)

# Wizardry 8 save editor: ~/Work/Wizardry8Editor is a clone of a public repo
# (anonidiot/Wizardry8Editor) with two uncommitted local fixes, and the
# helper scripts/launchers live in the game folder. The clone itself (675 MB,
# mostly build output) isn't worth copying - only the fixes as a patch, plus
# the scripts and launchers, go to $BACKUP_DIR/wizardry8-editor.
W8_EDITOR_SRC="$HOME/Work/Wizardry8Editor"
W8_GAME_DIR="$HOME/Games/wizardry-8"
W8_LAUNCHERS=(editor.sh editor-wine.sh)

# Claude Code skills in ~/.claude/skills worth keeping across reinstalls.
# Some are only symlinks into a package (diagnose-crash points into
# /usr/share/omarchy), so backup_claude.sh copies the real files (rsync -L)
# to $BACKUP_DIR/skills/<name>, and restore_claude.sh puts them back on a
# machine where the skill is missing or its link is broken.
CLAUDE_SKILLS=(diagnose-crash)

# Relpaths (under either $BACKUP_DIR or ~/.claude) of files that can
# actually collide between machines. $1 = tree root (BACKUP_DIR or ~/.claude).
tracked_files() {
  local base="$1"
  find "$base/projects" -path '*/memory/*.md' -printf 'projects/%P\n' 2>/dev/null | sort
}

file_hash() {
  # Missing file = empty hash, not a failure: callers run under set -e and
  # a non-zero return here aborts them on the first not-yet-restored file.
  [[ -f "$1" ]] || return 0
  sha256sum "$1" 2>/dev/null | cut -d' ' -f1
}

manifest_get() {
  local relpath="$1"
  [[ -f "$MANIFEST" ]] || return 0
  awk -F'\t' -v f="$relpath" '$2==f{print $1; exit}' "$MANIFEST"
}

manifest_set() {
  local relpath="$1" hash="$2" tmp
  mkdir -p "$(dirname "$MANIFEST")"
  tmp="$(mktemp)"
  [[ -f "$MANIFEST" ]] && awk -F'\t' -v f="$relpath" '$2!=f' "$MANIFEST" >"$tmp"
  printf '%s\t%s\n' "$hash" "$relpath" >>"$tmp"
  mv "$tmp" "$MANIFEST"
}

# Retries a plain rsync a few times with a short backoff before giving up -
# rides out a transient Dropbox-client file lock instead of failing outright.
rsync_retry() {
  local attempt
  for attempt in 1 2 3; do
    if rsync "$@"; then
      return 0
    fi
    echo "rsync attempt $attempt/3 failed, retrying..." >&2
    sleep 2
  done
  return 1
}

# Sweeps up rsync's abandoned "*.RANDOM6CHARS" temp files - left behind when
# a transfer errors out mid-rename and not always cleaned up by rsync itself.
cleanup_rsync_temp_files() {
  local dir="$1" f base
  [[ -d "$dir" ]] || return 0
  while IFS= read -r -d '' f; do
    base="$(basename "$f")"
    [[ "$base" =~ ^\..+\.[A-Za-z0-9]{6}$ ]] && rm -f -- "$f"
  done < <(find "$dir" -type f -name '.*' -print0 2>/dev/null)
  # The loop's status is its last [[ ]] test, which is false for any dotfile
  # that isn't an rsync temp file - callers run under set -e.
  return 0
}
