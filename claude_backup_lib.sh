# Shared helpers for backup_claude.sh / restore_claude.sh.
#
# Two problems these solve, both specific to sharing one Dropbox backup
# across multiple machines (currently: whitehole, a WSL/Arch instance, and
# the freebsd16-current VM, which reaches Dropbox through rclone instead of
# the Dropbox client; see the FreeBSD upload in backup_claude.sh):
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

# rclone remote for Dropbox on machines without the Dropbox client (FreeBSD).
RCLONE_DROPBOX_REMOTE="Dropbox:"

# Project folders under ~/Work that live only on this disk (no git remote,
# or holding files that can't go on GitHub, like game data and ROMs).
# backup_claude.sh copies each into $BACKUP_DIR/work/<name>, and
# restore_claude.sh copies them back. Skipped on a machine that doesn't
# have the folder.
WORK_PROJECTS=(wizardry7-amiga rssreader)

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
  # Portable form: no GNU find -printf (FreeBSD's find rejects "%P" and the
  # 2>/dev/null used to hide that, returning an empty list).
  (cd "$base" 2>/dev/null && find projects -path '*/memory/*.md' 2>/dev/null) | sort
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

# Claude Code files memory under ~/.claude/projects/<encoded path>/memory,
# where the encoded path is the working folder with every non-alphanumeric
# character turned into "-" (/home/darryl/Work -> -home-darryl-Work). A
# restore onto an account with a different username (found 2026-11-04:
# backup from "darryl", restored as "lizzie") leaves all memory under the old
# user's folders, where Claude never looks. For each old-user folder with
# real memory (another user under the same parent folder as $HOME), link
# the matching folder for this $HOME to it, so both share one set of files.
# Never touches a folder that already has memory of its own.
# backup_claude.sh skips links (--no-links), so these never reach Dropbox;
# each restore makes them again. Assumes the old username has no "-" in it.
link_foreign_memory() {
  local projects="$HOME/.claude/projects" me parent src name old_prefix suffix dest
  me="$(printf '%s' "$HOME" | sed 's/[^A-Za-z0-9]/-/g')"
  parent="$(dirname "$HOME" | sed 's/[^A-Za-z0-9]/-/g')"
  for src in "$projects"/*/memory; do
    [[ -d "$src" && ! -L "$src" ]] || continue
    [[ -n "$(ls -A "$src")" ]] || continue
    name="$(basename "$(dirname "$src")")"
    [[ "$name" == "$me" || "$name" == "$me"-* ]] && continue
    [[ "$name" =~ ^("$parent"-[A-Za-z0-9_]+)(-.*)?$ ]] || continue
    old_prefix="${BASH_REMATCH[1]}"
    suffix="${BASH_REMATCH[2]:-}"
    dest="$projects/$me$suffix/memory"
    if [[ -L "$dest" ]]; then
      [[ "$(readlink "$dest")" == "../$name/memory" ]] ||
        echo "Not linking $name memory: $dest already links to $(readlink "$dest")" >&2
      continue
    fi
    if [[ -d "$dest" ]]; then
      if [[ -n "$(ls -A "$dest")" ]]; then
        echo "Not linking $name memory: $dest already has its own files" >&2
        continue
      fi
      rmdir -- "$dest"
    fi
    mkdir -p -- "$(dirname "$dest")"
    ln -s -- "../$name/memory" "$dest"
    echo "Linked memory from ${old_prefix#"$parent"-}'s $name to this account"
  done
  return 0
}
