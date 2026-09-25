#!/usr/bin/env bash
#
# Installs scripts/git-hooks/pre-push into this repository's shared hooks
# directory, so a merge that silently overrides a parent's content (PG-240,
# ADR-0061) and a landing that puts a path back to a version main already
# moved past, squashed or rebased included (PG-242, ADR-0062), are refused
# before they leave the machine, not just reported after the fact by the
# advisory merge-integrity.yml workflow.
#
# The hook is copied, not linked: a machine that installed the ADR-0061 hook
# keeps running that copy, without the landing check, until this is rerun with
# --force (the installer cannot tell its own older copy from a foreign hook, so
# it refuses a differing one without it). check-merge-integrity.py warns on
# every run while the installed copy differs from scripts/git-hooks/pre-push.
#
# git worktrees share one hooks directory (the common dir), so running this
# once from any worktree covers all of them.
#
# Usage:  scripts/install-git-hooks.sh [--force]

set -euo pipefail

readonly REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly SRC="$REPO/scripts/git-hooks/pre-push"
readonly COMMON_DIR="$(cd "$(git -C "$REPO" rev-parse --git-common-dir)" && pwd)"
readonly HOOKS_DIR="$COMMON_DIR/hooks"
readonly DEST="$HOOKS_DIR/pre-push"

force=0
if [ "${1:-}" = "--force" ]; then
    force=1
fi

fail() {
    echo "install-git-hooks: $*" >&2
    exit 1
}

[ -f "$SRC" ] || fail "manca $SRC"

if [ -e "$DEST" ] && [ "$force" -ne 1 ] && ! cmp -s "$SRC" "$DEST"; then
    fail "$DEST esiste già e differisce da $SRC — rilancia con --force per sovrascriverlo"
fi

mkdir -p "$HOOKS_DIR"
cp "$SRC" "$DEST"
chmod +x "$DEST"

[ -x "$DEST" ] || fail "$DEST copiato ma non risulta eseguibile"

echo "pre-push installato in $DEST"

hooks_path_local="$(git -C "$REPO" config --local --get core.hooksPath 2>/dev/null || true)"
if [ -n "$hooks_path_local" ] && [ "$hooks_path_local" != "$HOOKS_DIR" ]; then
    echo "ATTENZIONE: core.hooksPath è impostato localmente a \"$hooks_path_local\","
    echo "diverso da $HOOKS_DIR: questo hook non verrà eseguito finché non viene corretto."
fi
