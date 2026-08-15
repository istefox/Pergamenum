#!/usr/bin/env bash
#
# Builds `perg` and puts it somewhere on the PATH.
#
# Release rather than Debug, and copied rather than symlinked into DerivedData: a
# symlink into a build directory is a tool that stops working the day Xcode cleans, and
# does so with an error that says nothing about why.
#
# Not signed and not notarized. Gatekeeper quarantines what is downloaded, not what is
# built here, so a locally built tool runs as it is. The day this is handed to another
# machine it needs `scripts/release.sh`'s treatment; until then, signing it would be
# ceremony (ADR-0007).
#
# Usage:  scripts/install-cli.sh [destinazione]
#         default /usr/local/bin, which needs sudo on a stock macOS

set -euo pipefail

readonly REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly DESTINATION="${1:-/usr/local/bin}"
readonly TOOL="perg"

cd "$REPO"

fail() {
    echo "install-cli: $*" >&2
    exit 1
}

step() {
    echo
    echo "==> $*"
}

step "Genero il progetto"
tuist generate --no-open >/dev/null

step "Compilo $TOOL in Release"
xcodebuild -workspace Pergamenum.xcworkspace -scheme "$TOOL" \
    -destination 'platform=macOS' -configuration Release build >/dev/null

built="$(find ~/Library/Developer/Xcode/DerivedData/Pergamenum-*/Build/Products/Release \
    -maxdepth 1 -name "$TOOL" -type f 2>/dev/null | head -1)"
[ -n "$built" ] || fail "non trovo il binario compilato: la build è andata a buon fine?"

step "Installo in $DESTINATION"
[ -d "$DESTINATION" ] || fail "$DESTINATION non esiste"
if [ ! -w "$DESTINATION" ]; then
    fail "$DESTINATION non è scrivibile: rilancia con sudo, oppure passa una cartella tua (~/bin)"
fi

# Moved aside rather than overwritten, like the app bundle: a tool you can go back to
# is worth the one file it costs.
if [ -e "$DESTINATION/$TOOL" ]; then
    mv "$DESTINATION/$TOOL" "$DESTINATION/$TOOL.previous"
    echo "la copia precedente è ora $DESTINATION/$TOOL.previous"
fi
cp "$built" "$DESTINATION/$TOOL"

step "Fatto"
"$DESTINATION/$TOOL" --help | head -3
echo
echo "il vault si sceglie con --vault, con \$PERGAMENUM_VAULT, o si eredita da quello"
echo "che Pergamenum ha aperto per ultimo"
