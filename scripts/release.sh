#!/usr/bin/env bash
#
# Builds, signs and notarizes a release, stamped with a build number nobody has to
# remember: the number of commits behind HEAD.
#
# Every notarized build before this script went out as 1.0 (1), so two copies of the
# app were indistinguishable from the outside. Now Informazioni reads a number that
# changes with every release, and `git rev-list --count HEAD` on any commit says which
# release that commit would have produced.
#
# Usage:  scripts/release.sh
#
# Leaves the finished app in build/release/ and does not install it: putting it in
# /Applications replaces what is already running there, and that stays a decision.

set -euo pipefail

readonly REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly OUTPUT="$REPO/build/release"
readonly SCHEME="Pergamenum"
readonly APP="Pergamenum.app"
# Overridable: the credentials live in a keychain profile created once with
# `xcrun notarytool store-credentials`.
NOTARY_PROFILE="${NOTARY_PROFILE:-pergamenum}"

cd "$REPO"

fail() {
    echo "release: $*" >&2
    exit 1
}

step() {
    echo
    echo "==> $*"
}

# --- What is being released ------------------------------------------------------
#
# A release has to be something you can come back to. Neither guard is bureaucracy:
# a build made from uncommitted work cannot be reproduced, and one made off main is
# numbered from a history that main does not have.

branch="$(git rev-parse --abbrev-ref HEAD)"
[ "$branch" = "main" ] || fail "sei su $branch: una release si taglia da main"
[ -z "$(git status --porcelain)" ] || fail "l'albero di lavoro non è pulito: committa o metti da parte prima"

# --- Preflight -------------------------------------------------------------------
#
# ADR-0031 §D12. The same philosophy the script already states at «Check what came out,
# before asking Apple to bless it», applied one step earlier. All four checks are
# instantaneous, and all four would otherwise surface after roughly ten minutes of
# archiving and notarizing - the moment a release is least recoverable.

# Resolution order for a Sparkle command-line tool: $SPARKLE_BIN, then the pinned unpack
# scripts/fetch-sparkle-tools.sh writes, then PATH (ADR-0031 §D11). Prints the path it
# found, returns non-zero when there is none.
sparkle_tool() {
    local name="$1"
    if [ -n "${SPARKLE_BIN:-}" ] && [ -x "$SPARKLE_BIN/$name" ]; then
        echo "$SPARKLE_BIN/$name"
        return 0
    fi
    if [ -x "$REPO/build/tools/sparkle/bin/$name" ]; then
        echo "$REPO/build/tools/sparkle/bin/$name"
        return 0
    fi
    command -v "$name" 2>/dev/null || return 1
}

step "Preflight"

SIGN_UPDATE="$(sparkle_tool sign_update)" \
    || fail "sign_update non trovato: esegui scripts/fetch-sparkle-tools.sh (oppure indica \$SPARKLE_BIN)"
readonly SIGN_UPDATE
echo "sign_update: $SIGN_UPDATE"

gh auth status >/dev/null 2>&1 \
    || fail "gh non autenticato: esegui gh auth login (serve a pubblicare la release)"

# Sparkle's generate_keys stores the private key as a generic password under the service
# "https://sparkle-project.org" and the account "ed25519": Sparkle 2.9.6,
# generate_keys/main.swift:15-29 (commonKeychainItemAttributes - kSecAttrService at :22,
# kSecAttrAccount at :25) and :160-161 (the --account option defaults to "ed25519");
# sign_update/main.swift:13-18 reads the same pair back. `-w` is never passed here: the
# presence of the item is the check, its contents are never printed.
security find-generic-password -s "https://sparkle-project.org" -a "ed25519" >/dev/null 2>&1 \
    || fail "chiave privata EdDSA assente dal portachiavi: esegui \"\$(sparkle_tool generate_keys)\" una volta"

command -v python3 >/dev/null 2>&1 || fail "python3 non trovato: serve a scripts/appcast.py"

readonly BUILD="$(git rev-list --count HEAD)"
[ -n "$BUILD" ] && [ "$BUILD" -gt 0 ] || fail "numero di build non calcolabile da git"
readonly SHA="$(git rev-parse --short HEAD)"

step "Pergamenum build $BUILD, da $SHA"

# --- Generate, archive, export ---------------------------------------------------

step "Genero il progetto con TUIST_BUILD_NUMBER=$BUILD"
TUIST_BUILD_NUMBER="$BUILD" tuist generate --no-open >/dev/null

archive="$OUTPUT/$BUILD.xcarchive"
export_dir="$OUTPUT/$BUILD"
mkdir -p "$OUTPUT"
[ -e "$archive" ] && fail "$archive esiste già: la build $BUILD è già stata fatta (sposta build/release/$BUILD* per rifarla)"

step "Archivio"
xcodebuild -workspace "$SCHEME.xcworkspace" -scheme "$SCHEME" \
    -destination 'platform=macOS' -configuration Release \
    -archivePath "$archive" archive >/dev/null

step "Esporto con Developer ID"
options="$OUTPUT/ExportOptions.plist"
cat >"$options" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>developer-id</string>
	<key>teamID</key>
	<string>T7H24G7BFW</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>destination</key>
	<string>export</string>
</dict>
</plist>
PLIST
xcodebuild -exportArchive -archivePath "$archive" \
    -exportOptionsPlist "$options" -exportPath "$export_dir" >/dev/null

readonly BUNDLE="$export_dir/$APP"

# --- Check what came out, before asking Apple to bless it ------------------------
#
# Each of these has been wrong at least once. The build number silently stayed at 1
# for every release until now, and two builds were notarized only because the missing
# hardened runtime was noticed by hand and re-signed - an unrecorded step that would
# have gone on being needed forever.

step "Verifico il bundle"
stamped="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$BUNDLE/Contents/Info.plist")"
[ "$stamped" = "$BUILD" ] || fail "il bundle dice build $stamped, doveva dire $BUILD"

# Read once into a variable, and matched with a here-string rather than through a
# pipe. `codesign … | grep -q` looks right and fails on a correct bundle: grep exits at
# the first match, codesign dies of SIGPIPE, and pipefail reports that 141 as the
# pipeline's status. The first run of this script refused to ship a bundle that had the
# hardened runtime all along.
signature="$(codesign -dv --verbose=4 "$BUNDLE" 2>&1)"
grep -q 'flags=.*runtime' <<<"$signature" \
    || fail "hardened runtime assente: la notarizzazione la rifiuterebbe"
grep -q 'Authority=Developer ID Application' <<<"$signature" \
    || fail "non è firmata con Developer ID"
codesign --verify --deep --strict "$BUNDLE" || fail "la firma non verifica"

# --- Notarize --------------------------------------------------------------------

step "Notarizzo (qualche minuto)"
zip="$OUTPUT/$BUILD.zip"
ditto -c -k --keepParent "$BUNDLE" "$zip"

# The exit code alone is not enough: notarytool exits 0 on a submission that came back
# Invalid, so the status line is what decides.
log="$OUTPUT/$BUILD-notarization.txt"
xcrun notarytool submit "$zip" --keychain-profile "$NOTARY_PROFILE" --wait | tee "$log"
grep -q 'status: Accepted' "$log" || fail "notarizzazione non accettata, vedi $log"

step "Applico il ticket"
xcrun stapler staple "$BUNDLE" >/dev/null
xcrun stapler validate "$BUNDLE" >/dev/null || fail "il ticket non è allegato"

# The last check is the one the user's Mac will do: everything above can pass on a
# bundle Gatekeeper still refuses.
verdict="$(spctl -a -t exec -vvv "$BUNDLE" 2>&1)"
grep -q 'source=Notarized Developer ID' <<<"$verdict" \
    || fail "Gatekeeper non la riconosce come notarizzata"

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$BUNDLE/Contents/Info.plist")"

# --- The distributable -----------------------------------------------------------
#
# ADR-0031 §D8. Cut here and nowhere earlier: $zip above is what notarytool was handed
# and has no ticket by construction, and $BUILD-notarization.txt is the log describing
# it. This archive is the one a user's copy of the app downloads, so it must come from
# the bundle after `stapler staple` - and it gets its own name, because that name
# becomes a public URL. --sequesterRsrc is what Sparkle's publishing documentation asks
# for; it is a no-op on a bundle with no resource forks, and costs nothing to be right
# about.

step "Impacchetto la build firmata e ticketata"
readonly DIST="$OUTPUT/Pergamenum-$version-$BUILD.zip"
ditto -c -k --sequesterRsrc --keepParent "$BUNDLE" "$DIST"

cat <<SUMMARY

==> Pronta: Pergamenum $version ($BUILD), da $SHA
    $BUNDLE

    Per installarla:
      osascript -e 'tell application "Pergamenum" to quit'
      ditto "$BUNDLE" /Applications/$APP
SUMMARY
