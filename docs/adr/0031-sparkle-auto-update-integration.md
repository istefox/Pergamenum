# ADR-0031: The app can fetch its own next build, and nothing else on it goes near a network

- Status: proposed
- Date: 2026-09-04. Every external fact below was **checked live on this machine on this date**,
  not recalled: Sparkle's latest release and its `Package.swift` (GitHub API), the contents of
  `Sparkle-for-Swift-Package-Manager.zip` (downloaded, unzipped, checksummed), the visibility and
  Pages/Releases state of `istefox/Pergamenum` (`gh api`), and the location of a stapled
  notarization ticket (read off `/Applications/Pergamenum.app`). Where a check contradicts the
  SPEC, the check wins and the contradiction is named.
- **Supersedes nothing.** No mechanism of ADR-0018, ADR-0028, ADR-0029 or ADR-0030 is reopened;
  this ADR touches no view, no text container, no delegate and no token.
- **Narrowly and formally excepts CLAUDE.md principle 2 ("Fully offline. No network call in any
  feature.")** — D13, which is R-10's whole content. The exception is the updater and nothing
  else.
- **Does not reopen ADR-0007 §D3/§D4.** The vault still never opens a socket, `perg` and
  `pergamenum-mcp` gain nothing, and the reason Sparkle is absent from both connectors is the
  reason EventKit is (§D4): an interactive-app capability does not belong in a headless tool
  somebody else launched.
- **Amends SPEC §Scope R-07's host** — the appcast and the update archive are published from a
  dedicated **public** repository, not from `istefox/Pergamenum`. The SPEC's premise that a
  private repo can serve either is false, measured (D9). This is the one place this ADR
  contradicts the SPEC, and it is a correctness fix, not a preference.
- Depends on: **ADR-0001 §D1** (no AppKit/SwiftUI in `sharedSources`), **ADR-0007 §D2/§D4**
  (the connectors compile the same files and deliberately lack interactive-app capabilities),
  `scripts/release.sh` as it stands at `main`, and `Project.swift`'s `sharedSources` list
  (`:72-107`).

## Context

**There is no way to learn that a new build exists.** `scripts/release.sh` produces a signed,
notarized, stapled bundle in `build/release/<n>/Pergamenum.app` and prints two lines telling the
person to `ditto` it into `/Applications` by hand. Nothing on the running app knows a newer one
was cut. `CFBundleVersion` is already the number of commits behind `HEAD`
(`Project.swift:46-54`), so the app already carries a strictly monotonic build number — the one
thing an updater needs — and does nothing with it.

**What was measured, on 2026-09-04, rather than assumed.**

```
$ gh api repos/sparkle-project/Sparkle/releases --jq '.[0:3]|.[]|"\(.tag_name) \(.published_at)"'
2.9.6 2026-08-17T01:40:46Z
2.9.5 2026-08-02T14:07:07Z
2.9.4 2026-07-03T03:42:15Z

$ gh api repos/sparkle-project/Sparkle/contents/Package.swift | base64 -d
// swift-tools-version:5.5
let tag = "2.9.6"
let checksum = "8d5fb41d960b43f4a68aa14126bf62b098544ec8d191cdcc73eb14e63a8e7606"
let url = ".../releases/download/\(tag)/Sparkle-for-Swift-Package-Manager.zip"
    targets: [ .binaryTarget(name: "Sparkle", url: url, checksum: checksum) ]
```

Four things follow from that manifest, and three of them change the design:

1. **Sparkle's SPM package is a `.binaryTarget`, not a source target.** The
   `PackageSettings(productTypes:)` block in `Tuist/Package.swift:10-17` — which exists so
   `MCP`/`Logging`/`SystemPackage`/`EventSource` build as static frameworks a bare executable can
   link — has **no effect on a binary target** and must not gain a `"Sparkle"` entry. A binary
   target arrives as a precompiled `.xcframework` and is *embedded*, not built.
2. **The framework carries nested executables.** Downloaded and listed:
   ```
   Sparkle.framework/Versions/B/Sparkle                       977616
   Sparkle.framework/Versions/B/Autoupdate                     726224
   Sparkle.framework/Versions/B/Updater.app/Contents/MacOS/Updater      290560
   Sparkle.framework/Versions/B/XPCServices/Downloader.xpc/…/Downloader 188672
   Sparkle.framework/Versions/B/XPCServices/Installer.xpc/…/Installer   223456
   ```
   `/Applications/Pergamenum.app/Contents/` has **no `Frameworks/` directory today**. After this
   change it must have one, and `codesign --verify --deep --strict` (`release.sh:113`) will walk
   into every one of those five binaries. Notarization requires each to carry a Developer ID
   signature and the hardened runtime.
3. **The same zip ships the command-line tools.** `bin/generate_keys`, `bin/sign_update`,
   `bin/generate_appcast`, `bin/BinaryDelta` are inside
   `Sparkle-for-Swift-Package-Manager.zip`, whose SHA-256 is the checksum the package manifest
   pins. So the release script's tools and the app's framework can come from one pinned,
   checksum-verified artifact rather than from two unrelated downloads (D11).
4. Sparkle's own `INSTALL` file says XPC services matter only *"for integrating XPC Services in a
   Sandboxed Application"*. Pergamenum is not sandboxed in v1 (CLAUDE.md §Stack), so
   `SUEnableInstallerLauncherService` and the sandbox entitlements are absent by design (D12).

**Where the SPEC's hosting plan does not work, measured.**

```
$ gh repo view istefox/Pergamenum --json visibility,isPrivate
{"isPrivate":true,"visibility":"PRIVATE"}
$ gh api repos/istefox/Pergamenum/pages
{"message":"Not Found","status":"404"}
$ gh api repos/istefox/Pergamenum/releases --jq 'length'
0
$ gh api user --jq '.plan.name'
null
```

Nothing is provisioned: no Pages site, no releases, and the account plan is not even readable
with the token in use — so the SPEC's *"confirmed: GitHub Pro/Team plan on this account"* is an
interview claim this ADR could not verify. That matters less than what *is* verified:
**release assets on a private repository require authentication.** Sparkle's downloader sends
none; an `<enclosure url="https://github.com/istefox/Pergamenum/releases/download/…">` would
return 404 to every user of the feature, including the only user. The SPEC's step 3 and step 5
therefore cannot both be satisfied on a private `istefox/Pergamenum`, and D9 resolves it.

**Where the release script's zip is wrong today, and why the SPEC is right about it.**
`release.sh:118-119` builds `$OUTPUT/$BUILD.zip` from `$BUNDLE`; `:124` submits it to notarytool;
`:127-129` staples **`$BUNDLE`**, not the zip. Read off the installed copy, the ticket is a file
inside the bundle:

```
$ ls -la /Applications/Pergamenum.app/Contents/
-rw-r--r--  1674  Aug 29 15:17  CodeResources     ← the stapled ticket
-rw-r--r--  2424  Aug 29 15:16  Info.plist
drwxr-xr-x   224  Aug 29 15:16  Resources
drwxr-xr-x    96  Aug 29 15:17  _CodeSignature
```

`CodeResources` is a minute newer than `Info.plist`, timestamped with `_CodeSignature`: it was
written by `stapler`, after the zip at `:119` had already been cut. So the zip on disk contains a
bundle with **no ticket**, and a Mac that is offline the first time it opens the unpacked app has
nothing local to check against. That zip is fine as a notarization *submission* — the ticket does
not exist yet when you submit — and unusable as a *distributable*. Today it is never distributed,
so the gap has never bitten; the moment Sparkle publishes something, it would.

**Sparkle's own SwiftUI recipe does not fit this codebase.** The documented setup
(`sparkle-project.org/documentation/programmatic-setup`) is an `ObservableObject` with
`updater.publisher(for: \.canCheckForUpdates).assign(to:)`, and it constructs the controller with
`startingUpdater: true` inside `App.init()`. Both halves collide with this repo:

- `grep -rln "import Combine" Sources/ Tests/` returns **nothing**. `~/.claude/rules/swift.md`
  requires `@Observable` and forbids `ObservableObject` for new code. D5 replaces the publisher
  with one `NSKeyValueObservation`.
- `PergamenumApp.swift:121-130` records, in its own words, why nothing NSApp-adjacent happens in
  `init`: *"registering a hot key is `NSApp`-adjacent work and does not belong in a scene's
  constructor"*, and `:59-62` says the `CapturePanel`'s `NSPanel` is made on first show for the
  same reason. `SPUUpdater.startUpdater` can present a modal alert when it fails — during scene
  construction that is not recoverable. D3 starts it from the window's `.task`, beside
  `armCapture()`.

**The UI suite is the sharpest hazard in this whole feature.** Eighteen files under `UITests/`
each call `XCUIApplication().launch()`, many of them repeatedly. If the app starts the updater on
every launch, then before the first appcast is ever published every one of those launches fetches
a URL that 404s and lets Sparkle put an alert on screen — the same shape as the incident CLAUDE.md
records, where a launch that could not complete produced 18 failures all timing out at exactly
60.2 s and none of them a real defect. The repo already has the answer: `-disableCalendar YES` and
`EventKitStore.isIsolated` (`CalendarService.swift:137-151`), a launch argument rather than a
compile-time flag *"because the app the UI suite drives has to be the app that ships"*. D4 copies
it verbatim.

**Nothing here may enter `sharedSources`.** `Project.swift:72-107` lists `Sources/Core/**`,
`Sources/Connector/**` and 30 named files under `Index`/`Calendar`/`Vault`. `Sources/App/**` is
not among them — confirmed by reading the list — so a file there may `import Sparkle` without
breaking `perg` or `pergamenum-mcp`. That is a property of one manifest line and nothing enforces
it, which is why D2 makes it a test instead of a memory.

## Decision

**D1. Sparkle 2.9.6 enters through `Tuist/Package.swift` as an ordinary SPM dependency and is
attached to the `Pergamenum` app target alone. `PackageSettings.productTypes` is not touched.**

```
.package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.6"),
```

and, on the app target only, `dependencies: [.external(name: "Sparkle")]`. The `perg` and
`pergamenum-mcp` targets keep `dependencies: []` and `[.external(name: "MCP")]` unchanged; a
dependency in Tuist is per target, so resolving Sparkle in the package manifest does not link it
into anything that does not ask for it.

`productTypes` gains **no** `"Sparkle"` entry. Its four existing entries exist because a
command-line tool has no bundle to embed a dynamic framework into (the comment at
`Tuist/Package.swift:7-9`); Sparkle is a `.binaryTarget` whose product type is fixed by the
`.xcframework` it ships, the consumer is an `.app` that *does* have a `Contents/Frameworks`, and
the setting would be both ineffective and misleading.

**The embed is verified, not assumed.** Tuist's handling of remote SPM binary targets has a
documented history of linking an xcframework without embedding it (tuist#3269, tuist#3346,
tuist#5761, tuist#6665), and an unembedded Sparkle is a dyld failure at launch, not a warning.
The acceptance for R-01 is therefore a check on the built product —
`Pergamenum.app/Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle` exists, and
`codesign --verify --deep --strict` passes over it — plus a clean `xcodebuild` of both tool
schemes. If Tuist 4.206.0 links without embedding, the fallback is A2 below (a vendored
`.xcframework` declared in `Project.swift`, fetched by the same script that fetches the tools),
and the plan's Task 2 stops and reports rather than improvising.

Rejected: **adding the package through Xcode's UI.** CLAUDE.md forbids it in two places — the
`.xcworkspace` is generated, and *"new dependencies go through `Tuist/Package.swift` followed by
`tuist install`"*.

**D2. Exactly one file in the repository says `import Sparkle`, it lives in `Sources/App/`, and a
unit test enforces that.**

`Sources/App/SparkleUpdateController.swift` is the only file that names the framework. The menu
entry, the configuration reader and the app scene all speak to *it*, never to `SPUUpdater`, so the
blast radius of the dependency is one file and its own test.

`Tests/SharedSourcesPurityTests.swift` walks the repository from `#filePath` and asserts that no
file under `Sources/Core`, `Sources/Connector`, `Sources/Index`, `Sources/Calendar`,
`Sources/Vault`, `Sources/CLI` or `Sources/MCPServer` contains `import Sparkle`. That is R-01
turned from *"the tool build will break loudly"* into *"a named test goes red in the same turn"* —
the difference matters because the tool builds are not in `.claude/test-cmd`
(`-only-testing:PergamenumTests`) and are therefore only run deliberately.

Rejected: **relying on the tool builds alone.** They do enforce it (CLAUDE.md: *"a new file under
`Sources/Core` that imports SwiftUI breaks both tool builds, which is ADR-0001 §D1 enforcing
itself"*) — but only when somebody runs them. A red unit test at the end of the turn is the
enforcement that actually fires.

Rejected: **putting the controller in `Sources/Features/`.** It is app-lifetime infrastructure
with no view of its own, which is what `Sources/App/` already holds (`GlobalHotkey`,
`MenuBarItem`, `ShortcutStore`).

**D3. The controller is built with `startingUpdater: false` and started from the window's
`.task`, never from `PergamenumApp.init()`.**

```
// Sources/App/SparkleUpdateController.swift
@MainActor @Observable
final class SparkleUpdateController {
    private let controller: SPUStandardUpdaterController
    private var observation: NSKeyValueObservation?
    private(set) var canCheckForUpdates = false

    init() {                       // no work beyond allocation
        controller = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
    }
    func start() { … }             // called once, from armCapture()
    func checkForUpdates() { controller.updater.checkForUpdates() }
}
```

Sparkle documents the split explicitly (*"If you want to start the updater manually, pass false to
`startingUpdater` and call `.startUpdater()` later"*), so this is the supported path and not a
workaround. The reason to take it is this repo's own: `PergamenumApp.init()` builds `CapturePanel`
with a comment promising *"Nothing in the constructor touches AppKit"*, and `armCapture()` exists
because *"window work and `NSApp` must not happen while the app is still coming up"*. `startUpdater`
can put a modal alert on screen. It goes where the hot key goes.

`updaterDelegate` and `userDriverDelegate` stay `nil`. Everything this feature needs — manual-only
checking, no profiling, the feed, the key — is declared in `Info.plist`; a delegate would be a
second place for the same facts to be stated and to disagree.

Rejected: **`startingUpdater: true` in `init`**, Sparkle's own sample. It is correct for an app
whose `init` does nothing else; it is not correct for this one, and the incident that taught this
codebase otherwise is written into the file it would go in.

**D4. `-disableUpdater YES` keeps Sparkle out of a launch entirely, and every file under
`UITests/` passes it — not only the ones that would otherwise notice.**

```
private let isIsolated = UserDefaults.standard.bool(forKey: "disableUpdater")
```

the exact shape of `EventKitStore.isIsolated` (`CalendarService.swift:151`). When set,
`SparkleUpdateController.start()` returns without starting anything, `canCheckForUpdates` stays
`false`, and the menu item renders disabled. The app under test is still the app that ships — the
framework is linked, the plist keys are there, the menu is there — which is the whole reason the
calendar flag is a launch argument and not a `#if`.

All eighteen UI-test files get the flag, for the reason CLAUDE.md gives about the calendar one:
*"Every one of the thirteen files passes it, not only the one that needed it"*. A file that omits
it is a file that will one day fail on a network hiccup and cost an afternoon.

Rejected: **letting the updater run in UI tests and pointing it at a local file URL.** A second
feed, a second failure mode, and a fixture that has to be kept in step with the real appcast's
schema, to test a framework this project does not own.

**D5. `canCheckForUpdates` reaches SwiftUI through `@Observable` plus one
`NSKeyValueObservation`, never through Combine.**

```
observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) {
    [weak self] updater, _ in
    MainActor.assumeIsolated { self?.canCheckForUpdates = updater.canCheckForUpdates }
}
```

`MainActor.assumeIsolated` and not a `Task { @MainActor in … }`: Sparkle posts this KVO change on
the main thread, and a hop would make the menu item's enabled state lag a frame behind the state
it describes. The observation is stored and released with the controller; without holding it, KVO
stops the moment the returned token is discarded, which is the one way this can silently do
nothing.

Rejected: **Sparkle's documented `ObservableObject` + `publisher(for:)`.** It would be the first
`import Combine` in the repository (grepped: zero today) and the first `ObservableObject` in new
code, which `~/.claude/rules/swift.md` forbids, in exchange for three saved lines.

Rejected: **no observation at all, with the menu item always enabled.** Two clicks during a check
in flight is a small ugliness, but the real cost is that "the updater failed to start" would then
be invisible: a disabled item is the only signal this design has, and D4 leans on it.

**D6. The four `SU*` keys are declared in `Project.swift`'s `infoPlist` and read back by a pure
value type, so R-03, R-04 and R-08 are unit tests rather than promises.**

Added to the existing `.extendingDefault(with:)` block beside `CFBundleVersion`:

```
"SUFeedURL": .string("https://istefox.github.io/pergamenum-updates/appcast.xml"),
"SUPublicEDKey": .string("<generate_keys output>"),
"SUEnableAutomaticChecks": .boolean(false),
"SUSendsSystemProfile": .boolean(false),
```

and a Foundation-only `Sources/App/UpdaterConfiguration.swift`:

```
struct UpdaterConfiguration: Equatable, Sendable {
    let feedURL: URL
    let publicEDKey: String
    let checksAutomatically: Bool
    let sendsSystemProfile: Bool
    init?(infoDictionary: [String: Any])
    var problems: [String] { … }   // https-only feed, non-empty key, both flags false
}
```

It takes a **dictionary**, not a `Bundle`, for one reason: a `Bundle` cannot be faked in a test
and a dictionary can, so the same type is exercised against literal fixtures *and* against the
real `Info.plist` of the built app. No `import Sparkle` here — the keys are strings, and reading
them must not drag a framework into a test that has no business linking one.

Rejected: **trusting the manifest.** `Project.swift` is the source of truth but it is not what
ships; a key can be present in the manifest and absent from the product for reasons ranging from
a stale `tuist generate` to a typo in a build setting. The assertion is on the built plist.

**D7. `SUEnableAutomaticChecks: false` is the whole of R-03. No timer, no
`automaticallyChecksForUpdates` assignment, no scheduler.**

Sparkle's docs are explicit that `automaticallyChecksForUpdates` should be set *only* when the
user changes it in a settings UI, and this feature has no settings UI (SPEC non-goals). The
`Info.plist` key is the declaration; writing the property from code as well would create a second
source of the same fact, backed by `UserDefaults`, that could outlive a change to the plist. R-03
is verified by the key's value plus a grep returning nothing for
`automaticallyChecksForUpdates` / `Timer` / `checkForUpdatesInBackground` in the changeset.

**D8. The distributable is a new variable cut from the stapled bundle after the Gatekeeper
verdict. `$zip` is not reused, not renamed, not overwritten.**

Inserted in `scripts/release.sh` after the `spctl` check (`:133-135`) and after `version=`
(`:137`), before the closing summary:

```
step "Impacchetto la build firmata e ticketata"
readonly DIST="$OUTPUT/Pergamenum-$version-$BUILD.zip"
ditto -c -k --sequesterRsrc --keepParent "$BUNDLE" "$DIST"
```

Four reasons it is `$DIST` and not `$zip`:

1. **`$zip` is evidence.** It is what `notarytool` was handed, and `$OUTPUT/$BUILD-notarization.txt`
   is the log of that submission. Overwriting it in place would leave a log describing a file that
   no longer exists in the form it described.
2. **The two files are not the same artifact.** One has no ticket by construction; the other must
   have one or the feature is broken on the machine it matters on. Giving them one name invites
   exactly the confusion this ADR exists to close.
3. **The name is a public URL.** `$DIST` becomes the `<enclosure url>` a user's app downloads.
   `Pergamenum-1.1-56.zip` says what it is; `56.zip` does not.
4. `--sequesterRsrc` is added because Sparkle's publishing documentation asks for it. It is a
   no-op for a bundle with no resource forks, which this one is, and costs nothing to be right
   about.

`$zip` and its log stay exactly where they are. The `[ -e "$archive" ]` idempotency guard at
`:62` is untouched and still refuses a second run of the same build number, so `$DIST` cannot be
silently regenerated from a different bundle.

**D9. The appcast and the update archive are published from a dedicated public repository,
`istefox/pergamenum-updates`. This amends R-07, and it is the one place this ADR contradicts the
SPEC.**

The SPEC asks for both on `istefox/Pergamenum`. Measured above, that repository is private, has no
Pages site and no releases. Two independent things break:

- **A release asset on a private repo requires authentication.** Sparkle's downloader sends none.
  The `<enclosure>` URL would 404 for everybody, and Sparkle would report a failed download rather
  than a wrong version — a fail-closed, but a permanent one.
- **Pages on a private repo is a plan-gated feature with two bad settings.** Access-controlled
  Pages is unreachable to an unauthenticated fetch, so Sparkle cannot read the feed. Public Pages
  is readable, but then whatever is in the published tree is world-readable, and this repository's
  `docs/` holds thirty ADRs and a full product specification. The account's plan could not even be
  confirmed from here (`gh api user --jq '.plan.name'` → `null`).

A separate public repository holding **only** the appcast and the release binaries fixes both and
removes the SPEC's own edge case (*"if that plan ever lapses, Pages serving stops silently"*):
Pages on a public repository needs no plan at all. Nothing about the source, the specification or
the ADRs becomes public. The release-notes body written per release is user-facing prose by
definition and belongs in a public place.

Concretely: `SUFeedURL` = `https://istefox.github.io/pergamenum-updates/appcast.xml`, served from
that repo's Pages; `gh release create --repo istefox/pergamenum-updates` attaches `$DIST`; the
`<enclosure>` points at
`https://github.com/istefox/pergamenum-updates/releases/download/<tag>/Pergamenum-<v>-<b>.zip`;
`sparkle:releaseNotesLink` points at that release's page.

**This is a Gate-2 decision for the human, not for the coder.** Creating a public repository under
a personal account is a deliberate act with a visibility consequence, and it is the one step of
this chain that cannot be undone quietly. The plan's Task 10 carries it as an explicit HITL
checkpoint, and `EXTERNAL DEPENDENCY: istefox/pergamenum-updates | vendor-account |
provisioned: false` records that nothing exists yet.

Rejected: **a `gh-pages` orphan branch on `istefox/Pergamenum` carrying the appcast and the
zips.** It keeps R-07 literally true and it does contain the exposure (Pages serves only the
published branch, so no ADR leaks). But it puts a ~20 MB binary into git history on every release,
forever, in a repository whose whole point is source; it keeps the Pro-plan dependency the SPEC
already flagged as a silent-404 risk; and it runs into Pages' 1 GB site limit on a horizon of
about fifty releases. It is the fallback if the separate repository is refused, and it is recorded
here so the choice is not re-litigated from memory.

Rejected: **making `istefox/Pergamenum` public.** Not this ADR's decision to take, and far larger
than the problem.

Rejected: **any third-party host (S3, Cloudflare R2, a VPS).** A second account, a second
credential in the release path, and a monthly bill, for a file that GitHub serves for free.

**D10. The appcast item is hand-built by `scripts/appcast.py`. `sign_update` is used;
`generate_appcast` is not.**

`sign_update` is the only way to produce the EdDSA signature and is used exactly as documented.
`generate_appcast` is rejected on three counts, each fatal on its own:

1. **It derives every download URL from one `--download-url-prefix`.** Each GitHub release lives
   under its own tag, so every item needs a different prefix. There is no per-archive form of the
   flag.
2. **It treats a local folder of archives as the feed's history.** The published appcast would
   silently truncate to whatever `build/` happens to contain — a gitignored directory on one Mac.
   A feed that forgets its own past when a disk is wiped is worse than no feed.
3. **It generates binary delta updates** from the archives it finds, which is an explicit SPEC
   non-goal, and `BinaryDelta` artifacts would then need retaining and publishing too.

`scripts/appcast.py` is `python3`, not bash, and that is deliberate: assembling XML with `sed`
is how feeds break, and `scripts/mcp-smoke.py` is this repo's existing precedent for a `python3`
helper under `scripts/`. It reads the currently published `appcast.xml` (fetched over HTTPS,
falling back to a fresh skeleton on a 404 — which is exactly the state before the first release),
inserts or replaces the `<item>` for this build using `xml.etree.ElementTree` with the
`sparkle:` namespace registered, and writes the result. It carries a `--self-test` mode with
in-process assertions — no new test framework, no second runner — covering: a first item into an
empty feed, a second item preserving the first, a re-run of the same build replacing rather than
duplicating, and a malformed existing feed refusing loudly.

The item's fields come from values the script already holds, never from a second literal:
`sparkle:version` = `$BUILD`, `sparkle:shortVersionString` = `$version` (both read back out of the
built `Info.plist` with `PlistBuddy`, as `release.sh:100` and `:137` already do),
`sparkle:minimumSystemVersion` from `LSMinimumSystemVersion` in the same plist,
`sparkle:edSignature` and `length` from `sign_update`'s output, and `pubDate` from `date -R`.

**D11. The Sparkle command-line tools come from the same pinned, checksum-verified artifact the
framework does, fetched once into a gitignored `build/tools/`.**

`scripts/fetch-sparkle-tools.sh` downloads
`Sparkle-for-Swift-Package-Manager.zip` at the pinned tag, verifies its SHA-256 against
`8d5fb41d960b43f4a68aa14126bf62b098544ec8d191cdcc73eb14e63a8e7606` — the value in Sparkle's own
`Package.swift`, so the tools and the linked framework are provably the same build — and unpacks
`bin/` into `build/tools/sparkle/bin/`. `build/` is already gitignored (`.gitignore:66`). It is
idempotent: an existing, checksum-matching unpack is left alone.

Resolution order at release time, honoured by a `sparkle_tool` shell function:
`$SPARKLE_BIN` → `build/tools/sparkle/bin` → `PATH`. Not found is a `fail` with the exact command
to fix it. Bash 3.2 throughout: no `mapfile`, no associative arrays, no `${x^^}` (macOS ships bash
3.2, and this script runs on this machine only).

Rejected: **globbing the tools out of Tuist's SPM artifact cache.** The path carries a version and
a hash and is Tuist's private business; it would break on a Tuist upgrade with an error naming a
directory nobody wrote.

Rejected: **Homebrew.** There is no formula for Sparkle's tools, and the cask installs the wrong
thing.

**D12. A preflight runs at the top of `release.sh`, before the archive.**

Placed immediately after the existing branch/clean-tree guards (`:44-46`), the preflight resolves
`sign_update`, checks `gh auth status`, checks the EdDSA private key is present in the login
Keychain, and checks `python3` exists. All four are cheap; all four are things that today would
surface only after roughly ten minutes of archiving and notarizing, at the exact moment a release
is least recoverable.

This is not a new philosophy imported into the script — it is the one the script already states.
Its own comment at `:92-97` reads *"Check what came out, before asking Apple to bless it… Each of
these has been wrong at least once."* The preflight is that sentence applied one step earlier.

**D13. The exception to CLAUDE.md principle 2, recorded formally. This section is R-10.**

Principle 2 says: *"Fully offline. No network call in any feature. No server, no account, no
telemetry."* An update check is a network call, so the principle has to either forbid this feature
or admit a named exception. It admits one, on these terms:

- **What crosses the wire.** Two `GET` requests, both initiated by the user choosing «Cerca
  Aggiornamenti…» and never otherwise: one for `appcast.xml`, and one for the release archive if
  and only if the user then chooses to install. The request carries the app's own version
  identifiers (`CFBundleVersion`, `CFBundleShortVersionString`) in Sparkle's user-agent, and the
  requester's IP address as an unavoidable artifact of any HTTP request. **No vault content, no
  note text, no path, no file name, no tag, no task, no calendar data, of any kind, ever.**
- **`SUSendsSystemProfile` is `false` and stays false.** Sparkle's optional anonymous
  hardware/OS profile is telemetry proper. Principle 2 forbids telemetry outright and this
  exception does not reach it. R-04 is that key, asserted by a test (D6).
- **The exception is scoped to the updater and does not travel.** No feature of the vault,
  Workspace, tasks, calendar, editor or index gains network access because of this chain, and the
  changeset is small enough to confirm that by reading it: one new controller, one new value type,
  one menu group, four `Info.plist` keys, and three files under `scripts/`. That is R-09.
- **ADR-0007's boundary is untouched.** The vault still never opens a socket, and neither
  connector learns anything. `perg` and `pergamenum-mcp` are updated the way they always were, by
  `scripts/install-cli.sh`.
- **The check is manual.** An app that phones home on a schedule is a different thing from an app
  that answers a question when asked. R-03 is what keeps this exception narrow in *time* as well
  as in *content*: with no automatic check, an offline Pergamenum makes zero network requests for
  its entire life, which is the promise principle 2 was actually making.

**D14. Nothing is persisted, no schema moves, no protected interface is touched.**

`IndexCache.schemaVersion` stays 3. No frontmatter key, no `.canvas` property, no index field, no
`VaultSettings` field, no migration. Sparkle keeps its own `UserDefaults` keys (last-check date,
skipped version) in the app's domain — that is Sparkle's storage, not the vault's, and CLAUDE.md
principle 3's "rebuildable index" is about derived vault state, which this is not.

Checked one by one against `.claude/protected-interfaces`: `IndexCache.schemaVersion` (no index
change of any kind), `VaultAPI.LintFinding` (no connector change — SPEC §API is explicit that this
feature exposes no `VaultAPI` capability, no CLI flag, no MCP tool),
`CompletingTextView+Pasteboard.swift` (no editor file is touched). `interface-check.sh` must stay
silent for the whole chain.

**D15. No entitlements change, no sandbox keys, no `SUEnableInstallerLauncherService`.**

Pergamenum is not sandboxed in v1 (CLAUDE.md §Stack). Sparkle's `Downloader.xpc` and
`Installer.xpc` ship inside the framework and go unused; they must still be signed as embedded
content, which the app's own signing pass handles. The hardened runtime already applies to Release
only, on the app target only (`Project.swift:37-40`), and Sparkle needs no additional entitlement
for a non-sandboxed Developer ID app. Recorded so nobody adds the sandbox keys from Sparkle's
documentation by pattern-matching.

## Alternatives considered

**A1. Do nothing — keep the manual `ditto` into `/Applications`.** Zero code, zero network, zero
exception to principle 2. Rejected because the cost is not the copy, it is knowing a new build
exists at all: nothing on the running app can tell, so the only signal is remembering to look,
and the build number that would make the comparison trivial has been sitting in the plist unused
since `scripts/release.sh` was written.

**A2. Vendor `Sparkle.xcframework` and declare it in `Project.swift` as a `.xcframework(path:)`
dependency.** This gives Tuist an explicit, unambiguous embed instruction and sidesteps every open
question about how Tuist handles a remote SPM binary target. Rejected as the primary path because
it means either a ~40 MB binary committed to a source repository, or a fetch step that has to run
before `tuist generate` — which makes `tuist generate` conditionally broken on a fresh clone, a
worse failure than the one it avoids. **Retained as the named fallback** if D1's embed check fails
in the plan's Task 2: the fetch script of D11 already exists by then and would need one more
target directory.

**A3. Write a bespoke updater — a `GET` on a JSON manifest, compare `CFBundleVersion`, open the
release page in a browser.** Perhaps eighty lines, no dependency, no framework to embed, no
signing complication, and it would satisfy "tell me a new build exists" completely. Rejected on
the half it cannot do: replacing a running application on disk is the part that is genuinely hard
— quitting, unpacking, validating the signature and notarization ticket, swapping the bundle,
relaunching, and recovering when any of that fails midway. Sparkle is the framework the entire
Developer-ID Mac ecosystem uses for exactly that, its EdDSA verification is the thing that makes
an update over HTTP safe at all, and a hand-rolled substitute would be this project's most
security-sensitive code with the least review.

**A4. Sparkle with automatic background checks, as ~every Sparkle app ships.** Rejected by the
SPEC, and correctly: an app that reaches the network on a timer cannot honestly describe itself as
offline, and D13's exception would then be a rewriting of principle 2 rather than a hole punched
in it. The version of this feature that survives is the one where an offline Pergamenum makes zero
requests unless asked.

**A5. Sparkle's documented `ObservableObject` + Combine view model.** Rejected under D5: it would
introduce Combine to a codebase with none and `ObservableObject` to new code that forbids it, to
save three lines over one `NSKeyValueObservation`.

**A6. `generate_appcast` for the feed.** Rejected under D10 on three counts — one URL prefix for
all items, a local archive folder standing in for the feed's history, and delta generation that is
a non-goal.

**A7. A `gh-pages` orphan branch on `istefox/Pergamenum`.** Rejected under D9 — binaries in git
history forever, the Pro-plan dependency retained, and Pages' 1 GB site limit reached in the
low tens of releases. Retained as the fallback if a second repository is refused at Gate 2.

**A8. Keep the updater out of the UI-test build with `#if DEBUG` or a compile-time flag.**
Rejected under D4 for the reason `CalendarService.swift:148-150` already gives about
`-disableCalendar`: *"the app the UI suite drives has to be the app that ships; a build with the
calendar compiled out would not be the thing under test."*

**A9. Reuse `$OUTPUT/$BUILD.zip` for distribution, re-cutting it after the staple.** The
smallest possible diff to `release.sh`. Rejected under D8: it destroys the record of what was
submitted to Apple, leaves `$BUILD-notarization.txt` describing a file that has since changed, and
gives two artifacts with opposite ticket status one name — which is precisely the confusion that
produced the pre-existing gap this ADR is closing.

## Consequences

**Positive.**

- The app can tell its user a new build exists and install it, verified end to end by an EdDSA
  signature and a Gatekeeper check, without anyone remembering to look at GitHub.
- **A real, pre-existing correctness gap closes.** Every zip this project has ever produced
  contained an unstapled bundle. Nothing was distributed from one, so nothing broke, but the first
  time one had been handed to another machine it would have failed Gatekeeper offline. D8 makes
  the distributable the stapled one by construction.
- The release script fails at second five instead of minute ten when a tool, a credential or a key
  is missing (D11, D12).
- Principle 2 comes out of this stronger rather than weaker: it now has one written, bounded,
  argued exception with a test behind each of its two hard limits (`SUEnableAutomaticChecks` and
  `SUSendsSystemProfile`, both asserted by D6), instead of an unwritten assumption nobody had had
  to defend.
- The account's GitHub plan stops being load-bearing for updates (D9).
- `perg` and `pergamenum-mcp` gain a test that says they are clean, not just a build that would
  have broken (D2).

**Negative.**

- **The app is no longer offline in the absolute sense**, and the sentence in CLAUDE.md that says
  so needs the qualifier this ADR writes. That is a genuine loss of a very clean property, traded
  for a capability, and D13 is the record of the trade rather than a denial of it.
- **A new public repository has to exist**, under a personal account, holding release binaries.
  It is a small, permanent surface that did not exist before, and it cannot be created quietly.
- **A ~12 MB framework with five nested signed executables enters the app bundle**, and the
  release path's `codesign --verify --deep --strict` now has to walk all of them. A signing
  problem in Sparkle's nested `Updater.app` would block a release, and the error would name a
  path inside a framework nobody in this project wrote.
- **The release script roughly doubles in length** and gains three external tool dependencies
  (`sign_update`, `gh`, `python3`) on top of the four it already has. Every one is a new way for a
  release to stop, and `gh` in particular now needs write scope on a second repository.
- **Tuist's handling of remote SPM binary targets is the least-proven part of this design.** The
  fallback is named (A2) and the check is mechanical, but it is the one task in the plan that
  could turn into a different task.
- The eighteen UI-test files each grow a launch argument, and a nineteenth added later will need
  it too — the same standing tax `-disableCalendar YES` already levies.

**Neutral.**

- Sparkle's update window is a system framework surface, not a SwiftUI view this project authors,
  so the design-token rule (*"a view that uses a colour or a font without going through a token
  does not pass review"*) does not reach it. It will not look like the rest of the app and that is
  correct; a custom `SPUUserDriver` to make it match would be a large amount of security-adjacent
  code for a window seen twice a year.
- Sparkle's UI is English. The rest of the app is Italian. Sparkle ships localisations including
  Italian, so the window follows the system language rather than the app's, which is the normal
  behaviour for a framework surface.
- The first Sparkle-enabled build still has to be installed by hand: no build shipped before it
  carries a `SUFeedURL`, and nothing can retroactively teach an installed copy to check.
- Sparkle persists a skipped version and a last-check date in the app's `UserDefaults` domain.
  With checks manual-only, neither ever suppresses anything the user asked for.
- The feature adds no test to the UI suite's runtime beyond one menu-existence assertion, and
  nothing at all to `.claude/test-cmd`'s.

## Non-goals

Restated from the SPEC so the boundary is in one place: no automatic or scheduled checks; no
binary delta updates; no `CHANGELOG.md` or changelog habit; no Impostazioni surface for updates;
no rollback, phased rollout or update channels; no change to `perg` or `pergamenum-mcp`; no change
to ADR-0007's network boundary; no custom `SPUUserDriver`; no sandbox entitlements; no persisted
state in the vault or the index.

## References

- SPEC: `SPEC.md` (this chain, R-01 … R-10) — R-07's host is amended by D9.
- Plan: `docs/superpowers/plans/2026-09-04-sparkle-auto-update-integration.md`.
- `CLAUDE.md` — principle 2 (excepted by D13), principle 3 (untouched, D14), §Stack (not
  sandboxed, D15), §AI connector (`sharedSources`, D1/D2), §Working agreements (the UI-suite
  incidents behind D4, the `tuist generate` rule behind D1).
- ADR-0001 §D1 — no AppKit/SwiftUI in the shared globs.
- ADR-0007 §D2/§D4 — the connectors compile the same files; EventKit is deliberately absent from
  them, and Sparkle is absent for the same reason.
- `scripts/release.sh` at `main` — `:44-46` (guards, preflight anchor), `:92-97` (the philosophy
  D12 extends), `:118-125` (the notarization zip), `:127-135` (staple and Gatekeeper, D8's
  insertion anchor), `:137` (`version`).
- `Project.swift` — `:37-40` (hardened runtime, Release/app only), `:46-54` (`buildNumber`),
  `:72-107` (`sharedSources`), `:119-163` (`infoPlist`, D6's anchor), `:171` (app `dependencies`).
- `Sources/App/PergamenumApp.swift` — `:59-62`, `:71-119` (`init`), `:121-130` (`armCapture`,
  D3's anchor), `:196-215` (`.commands`, D6/menu anchor).
- `Sources/Calendar/CalendarService.swift:137-151` — `-disableCalendar YES`, the precedent D4
  copies.
- Sparkle documentation: `sparkle-project.org/documentation` (basic setup, `SUPublicEDKey`),
  `/programmatic-setup` (`SPUStandardUpdaterController`, `CommandGroup(after: .appInfo)`,
  `startingUpdater:`), `/publishing` (`sign_update`, `generate_appcast`, appcast item shape,
  `sparkle:minimumSystemVersion`), `/sandboxing` (not applicable, D15).
- Sparkle 2.9.6 — `github.com/sparkle-project/Sparkle`, released 2026-08-17; SPM artifact
  SHA-256 `8d5fb41d960b43f4a68aa14126bf62b098544ec8d191cdcc73eb14e63a8e7606` (verified by
  download on 2026-09-04).
- Tuist SPM binary-target friction: tuist#3269, tuist#3346, tuist#5761, tuist#6665; Sparkle's own
  SPM support PR sparkle-project/Sparkle#1634.
