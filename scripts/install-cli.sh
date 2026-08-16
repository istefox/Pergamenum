#!/usr/bin/env bash
#
# Builds the two connectors of ADR-0007 and puts them somewhere on the PATH.
#
# Release rather than Debug, and copied rather than symlinked into DerivedData: a
# symlink into a build directory is a tool that stops working the day Xcode cleans, and
# does so with an error that says nothing about why.
#
# Not signed and not notarized. Gatekeeper quarantines what is downloaded, not what is
# built here, so a locally built tool runs as it is. The day these are handed to another
# machine they need `scripts/release.sh`'s treatment; until then, signing them would be
# ceremony (ADR-0007).
#
# Usage:  scripts/install-cli.sh [destinazione]
#         default /usr/local/bin, which needs sudo on a stock macOS

set -euo pipefail

readonly REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly DESTINATION="${1:-/usr/local/bin}"
readonly TOOLS=(perg pergamenum-mcp)

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

# Not created here on purpose - a script that makes directories on the way to somewhere
# else is a script that puts binaries where nobody meant them to go. It says how instead.
# Braces around the second one: the guillemet that follows would otherwise be read as
# part of the variable's name, and the script dies on «unbound variable» while trying to
# explain something else.
[ -d "$DESTINATION" ] || fail "$DESTINATION non esiste: creala con «mkdir -p ${DESTINATION}»,
   e controlla che sia nel PATH, altrimenti installarci dentro non serve a niente"
if [ ! -w "$DESTINATION" ]; then
    fail "$DESTINATION non è scrivibile: rilancia con sudo, oppure passa una cartella tua (~/bin)"
fi

# Said before the build rather than after: ten minutes of compilation followed by "and now
# it is not reachable" is worse than the same sentence up front.
case ":$PATH:" in
    *":$DESTINATION:"*) ;;
    *) echo "install-cli: attenzione, $DESTINATION non è nel PATH; aggiungi" >&2
       echo "   export PATH=\"$DESTINATION:\$PATH\"   allo ~/.zshrc" >&2 ;;
esac

for tool in "${TOOLS[@]}"; do
    step "Compilo $tool in Release"
    xcodebuild -workspace Pergamenum.xcworkspace -scheme "$tool" \
        -destination 'platform=macOS' -configuration Release build >/dev/null

    built="$(find ~/Library/Developer/Xcode/DerivedData/Pergamenum-*/Build/Products/Release \
        -maxdepth 1 -name "$tool" -type f 2>/dev/null | head -1)"
    [ -n "$built" ] || fail "non trovo il binario di $tool: la build è andata a buon fine?"

    # Moved aside rather than overwritten, like the app bundle: a tool you can go back to
    # is worth the one file it costs.
    if [ -e "$DESTINATION/$tool" ]; then
        mv "$DESTINATION/$tool" "$DESTINATION/$tool.previous"
        echo "la copia precedente è ora $DESTINATION/$tool.previous"
    fi
    cp "$built" "$DESTINATION/$tool"
    echo "installato $DESTINATION/$tool"
done

step "Fatto"
"$DESTINATION/perg" --help | head -3
echo
echo "il vault si sceglie con --vault, con \$PERGAMENUM_VAULT, o si eredita da quello"
echo "che Pergamenum ha aperto per ultimo"
echo
echo "per registrare il server MCP in Claude Code, in sola lettura:"
echo "  claude mcp add pergamenum -- $DESTINATION/pergamenum-mcp"
echo "e con la scrittura, quando ti fidi, aggiungendo --allow-write in fondo"
