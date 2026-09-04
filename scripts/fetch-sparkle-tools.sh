#!/usr/bin/env bash
#
# Fetches Sparkle's command-line tools (sign_update, generate_keys, ...) into a
# gitignored build/tools/sparkle/bin, from the same artifact the app links.
#
# ADR-0031 §D11, plan docs/superpowers/plans/2026-09-04-sparkle-auto-update-integration.md.
#
# The zip below is the one Sparkle's own Package.swift declares as its `.binaryTarget`,
# and the checksum is the value written in that manifest. Verifying against it is what
# makes the tools and the framework Xcode links provably the same build: a signature
# produced by a sign_update from somewhere else would still verify, but nothing would
# say which Sparkle it came from.
#
# Usage:  scripts/fetch-sparkle-tools.sh
#
# Idempotent: an unpack already recorded under the pinned checksum is reported and left
# alone. Nothing is ever deleted - on a checksum mismatch the download is kept, its path
# printed, and the script exits non-zero.

set -euo pipefail

readonly REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly SPARKLE_TAG="2.9.6"
readonly SPARKLE_SHA256="8d5fb41d960b43f4a68aa14126bf62b098544ec8d191cdcc73eb14e63a8e7606"
readonly SPARKLE_URL="https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_TAG/Sparkle-for-Swift-Package-Manager.zip"
readonly TOOLS="$REPO/build/tools/sparkle"
readonly BIN="$TOOLS/bin"
# What is recorded here is the checksum of the artifact the current bin/ came out of,
# so a change to the pinned tag re-fetches instead of trusting a stale unpack.
readonly STAMP="$TOOLS/.fetched-sha256"

fail() {
    echo "fetch-sparkle-tools: $*" >&2
    exit 1
}

step() {
    echo
    echo "==> $*"
}

# --- Already here? ----------------------------------------------------------------

if [ -x "$BIN/sign_update" ] && [ -f "$STAMP" ] && [ "$(cat "$STAMP")" = "$SPARKLE_SHA256" ]; then
    echo "Sparkle $SPARKLE_TAG già presente: $BIN"
    exit 0
fi

# --- Download, then verify, then unpack -------------------------------------------
#
# In that order, and the order is the point: the checksum decides whether the archive
# is ever opened, so a tampered or truncated download never reaches unzip.

staging="$(mktemp -d "${TMPDIR:-/tmp}/sparkle-tools.XXXXXX")"
archive="$staging/Sparkle-for-Swift-Package-Manager.zip"

step "Scarico Sparkle $SPARKLE_TAG"
curl --fail --location --silent --show-error --retry 2 \
    --output "$archive" "$SPARKLE_URL" \
    || fail "download fallito da $SPARKLE_URL"

step "Verifico lo SHA-256"
actual="$(shasum -a 256 "$archive" | awk '{ print $1 }')"
if [ "$actual" != "$SPARKLE_SHA256" ]; then
    echo "fetch-sparkle-tools: checksum non corrispondente, non apro l'archivio" >&2
    echo "  atteso:  $SPARKLE_SHA256" >&2
    echo "  ottenuto: $actual" >&2
    echo "  archivio conservato: $archive" >&2
    exit 1
fi
echo "$actual"

step "Estraggo bin/ in $BIN"
unzip -q "$archive" -d "$staging/unpacked" || fail "unzip fallito su $archive"
source_bin="$(find "$staging/unpacked" -maxdepth 3 -type d -name bin | head -1)"
[ -n "$source_bin" ] || fail "nessuna directory bin/ dentro l'archivio, struttura inattesa"
[ -f "$source_bin/sign_update" ] || fail "sign_update assente da $source_bin, struttura inattesa"

mkdir -p "$BIN"
# -R because bin/ is not flat: Sparkle ships an old_dsa_scripts/ directory beside the
# tools, and a plain cp refuses it and takes the whole fetch down with it.
cp -pR "$source_bin"/* "$BIN/"
find "$BIN" -maxdepth 1 -type f -exec chmod +x {} +
echo "$SPARKLE_SHA256" >"$STAMP"

ls "$BIN"

cat <<SUMMARY

==> Sparkle $SPARKLE_TAG pronto: $BIN
    Staging temporaneo lasciato in $staging (niente viene cancellato qui).
SUMMARY
