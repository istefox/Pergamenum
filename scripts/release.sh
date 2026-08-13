#!/usr/bin/env bash
#
# Builds, signs and notarizes a release, stamped with a build number nobody has to
# remember: the number of commits behind HEAD.
#
# Every notarized build before this script went out as 1.0 (1), so two copies of the
# app were indistinguishable from the outside. Now Informazioni reads 1.0 (55), and
# `git rev-list --count HEAD` on any commit says which one that was.
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
[ -e "$archive" ] && fail "$archive esiste già: la build $BUILD è già stata fatta"

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

codesign -dv --verbose=4 "$BUNDLE" 2>&1 | grep -q 'flags=.*runtime' \
    || fail "hardened runtime assente: la notarizzazione la rifiuterebbe"
codesign -dv --verbose=4 "$BUNDLE" 2>&1 | grep -q 'Authority=Developer ID Application' \
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
spctl -a -t exec -vvv "$BUNDLE" 2>&1 | grep -q 'source=Notarized Developer ID' \
    || fail "Gatekeeper non la riconosce come notarizzata"

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$BUNDLE/Contents/Info.plist")"
cat <<SUMMARY

==> Pronta: Pergamenum $version ($BUILD), da $SHA
    $BUNDLE

    Per installarla:
      osascript -e 'tell application "Pergamenum" to quit'
      ditto "$BUNDLE" /Applications/$APP
SUMMARY
