# Plan — Sparkle auto-update integration (PG-096)

- **ADR:** `docs/adr/0031-sparkle-auto-update-integration.md`
  (the architect wrote it to `docs/architecture/ADR-0031-sparkle-auto-update-integration.md`;
  the orchestrator relocates it, as it did for ADR-0030 on 2026-09-04, and removes the filing
  note at the top)
- **SPEC:** `SPEC.md` at the worktree root (R-01 … R-10)
- **BRAINSTORM / UX blueprint:** none exist for this chain, skipped at Gate 1b/1c. The SPEC
  states why: the design decisions were settled in the interview, and the only new UI surface is
  one menu item plus Sparkle's own native window, which is out of scope for this app's
  design-token surface.
- **Branch base:** `feat-add-sparkle` worktree, forked from `main`.
- **Style:** TDD. Red precondition first on every task, per this repo's last eight chains.
- **Roadmap:** PG-096 is **not** in the `TODO.md` backlog roadmap. It is an independent chain.
  Nothing in Phases 1–9 of that roadmap is a dependency, a blocker or related in any way; do not
  touch any of it.

---

## Before anything: what the SPEC says that the world does not

Every row was **checked live on 2026-09-04**, not recalled. Do not design or code against the
left column.

| # | SPEC says | Reality says | Where |
|---|---|---|---|
| C1 | §Scope / R-07: publish the Release **and** the appcast on `istefox/Pergamenum` | **Neither works on that repo.** `gh repo view` → `{"isPrivate":true,"visibility":"PRIVATE"}`; `gh api repos/istefox/Pergamenum/pages` → `404`; `releases` → `0`. **A release asset on a private repo requires authentication and Sparkle's downloader sends none** — the `<enclosure>` URL would 404 for every user. Pages on a private repo is either access-controlled (Sparkle cannot read it) or public (and then `docs/` — thirty ADRs and the full SPEC — is world-readable). Host is a **new public repo, `istefox/pergamenum-updates`** | ADR §D9; ADR §Context |
| C2 | §Edge cases: *"confirmed: GitHub Pro/Team plan on this account"* | **Not confirmable from here.** `gh api user --jq '.plan.name'` → `null`. Moot under C1: Pages on a *public* repo needs no plan | ADR §Context |
| C3 | §Scope step 4: appcast *"via Sparkle's `generate_appcast` tool or an equivalent hand-built step"* | **`generate_appcast` cannot do this job.** One `--download-url-prefix` for all items (each GitHub release has its own tag), a local archive folder standing in as the feed's history, and delta generation which is an explicit non-goal. Take the hand-built branch the SPEC already permits: `scripts/appcast.py` | ADR §D10 |
| C4 | §Stack: Sparkle *"added via SPM in `Tuist/Package.swift`, then `tuist install`"* | Correct, **and it is a `.binaryTarget`**, not a source target. `PackageSettings(productTypes:)` at `Tuist/Package.swift:10-17` has no effect on one and must **not** gain a `"Sparkle"` entry. Tuist's handling of remote SPM binary targets has known embed failures (tuist#3269/#3346/#5761/#6665) — the embed is **verified on the built bundle**, never assumed | ADR §D1; Sparkle `Package.swift` (fetched) |
| C5 | §Architecture: controller created *"at app launch, `startingUpdater: true`"* | **`startingUpdater: false`, started from the window's `.task`.** `SPUUpdater.startUpdater` can present a modal alert; `PergamenumApp.swift:121-130` and `:59-62` record in their own words why nothing NSApp-adjacent happens in `init`. Sparkle documents the split as supported | ADR §D3 |
| C6 | §UI flows: one menu item, Sparkle's stock UI | Correct, **and the UI suite is the hazard nobody named.** Eighteen files under `UITests/` call `launch()`. An updater that starts on every launch, before any appcast exists, puts an alert on screen — the same shape as the incident that produced 18 failures all at exactly 60.2 s. Needs `-disableUpdater YES` on every UI-test file | ADR §D4; CLAUDE.md §Working agreements |
| C7 | §Architecture: the SwiftUI wiring (implicitly Sparkle's documented sample) | Sparkle's sample is `ObservableObject` + `updater.publisher(for:)`. **`grep -rln "import Combine" Sources/ Tests/` returns nothing** and `~/.claude/rules/swift.md` forbids `ObservableObject` in new code. Use `@Observable` + one `NSKeyValueObservation` | ADR §D5 |
| C8 | §Edge cases: the stapled-vs-notarized zip gap | **Confirmed, at the byte.** `release.sh:118` cuts `$OUTPUT/$BUILD.zip` from `$BUNDLE`; `:127` staples `$BUNDLE` afterwards. Read off the installed copy: `/Applications/Pergamenum.app/Contents/CodeResources` (1674 bytes, `15:17`) is the ticket, written a minute after `Info.plist` (`15:16`) — i.e. after the zip existed. A **new** `$DIST` variable, cut after the Gatekeeper verdict | ADR §D8 |
| — | §Scope: the tools (`generate_keys`, `sign_update`) | **They are inside the SPM zip.** `unzip -l Sparkle-for-Swift-Package-Manager.zip` shows `bin/generate_keys`, `bin/sign_update`, `bin/generate_appcast`, `bin/BinaryDelta`. Its SHA-256 is `8d5fb41d…` — the exact checksum Sparkle's `Package.swift` pins, so tools and framework are provably the same build | ADR §D11 |
| — | §Scope: *"never into `Sources/Core`, `perg`, or `pergamenum-mcp`"* | Confirmed safe: `Project.swift:72-107` lists `Sources/Core/**`, `Sources/Connector/**` and 30 named files. **`Sources/App/**` is not among them.** Nothing enforces that but a manifest line, so this chain adds a test | ADR §D2 |

**Three constraints the SPEC could not know:**

1. **`Sparkle.framework` carries five signed executables** (`Sparkle`, `Autoupdate`,
   `Updater.app/Contents/MacOS/Updater`, `Downloader.xpc`, `Installer.xpc`). `codesign --verify
   --deep --strict` at `release.sh:113` will walk every one. `/Applications/Pergamenum.app/Contents/`
   has **no `Frameworks/` directory today**.
2. **`.claude/test-cmd` is `-only-testing:PergamenumTests`** and runs at the end of every turn
   through the `Stop` hook. It does **not** build `perg` or `pergamenum-mcp`, so R-01's real
   enforcement has to be a unit test, not a build that somebody might run.
3. **`build/` is already gitignored** (`.gitignore:66`), so `build/tools/` and
   `build/release/*.zip` need no gitignore edit.

---

## Contract changes and their already-grepped call sites

Every row was grepped **before** this plan was written. The coder does not go looking for these;
they are listed and updated in the same task that changes the contract. **Run the full unit
suite after each task, not just the touched file's tests.**

| Contract | Change | Call sites that break or go stale |
|---|---|---|
| `Tuist/Package.swift` `package.dependencies` | `+ .package(url: ".../Sparkle", from: "2.9.6")` | Regenerates `Tuist/Package.resolved` (tracked in git — commit the change). `PackageSettings.productTypes` **is not touched** (C4). No existing dependency moves. |
| `Project.swift` app target `dependencies:` | `[]` → `[.external(name: "Sparkle")]` | **App target only.** `perg` (`:219`) keeps `[]`; `pergamenum-mcp` (`:236`) keeps `[.external(name: "MCP")]`. Both must still build — verified explicitly in Task 2, since `.claude/test-cmd` does not build them. |
| `Project.swift` `infoPlist` | `+ SUFeedURL`, `+ SUPublicEDKey`, `+ SUEnableAutomaticChecks`, `+ SUSendsSystemProfile` | No compile error anywhere. **New test goes red until present:** `Tests/UpdaterConfigurationTests.swift` (Task 1). Requires `tuist generate` before the assertion can pass. |
| `PergamenumApp` | `+ @State private var updater = SparkleUpdateController()`; `armCapture()` gains `updater.start()`; `.commands` gains `UpdateCommands(updater: updater)` | `init()` (`:71-119`) — the new `@State` needs the same `_updater = State(initialValue:)` treatment as the others **only if** `commandActions` needs it; it does not, so a plain inline default is enough. `armCapture()` (`:125-130`). `.commands` block (`:196-215`). No other file constructs `PergamenumApp`. |
| `UITests/**` (18 files) | every `XCUIApplication()` gains `-disableUpdater YES` beside the existing `-disableCalendar YES` | Grepped: `-disableCalendar` appears in all 18 files. Same edit, same place, in one task. **Do not add a 19th file in this chain without it.** |
| `scripts/release.sh` | `+` preflight after `:46`; `+` `$DIST` stage after `:135`; `+` sign/publish/appcast stage; summary heredoc updated | `$zip` (`:118`), `$log` (`:123`), `$archive` (`:59`), the `[ -e "$archive" ]` guard (`:62`) — **all untouched.** `version` (`:137`) moves **up**, above the new `$DIST` stage, because `$DIST`'s filename uses it. That is the only existing line that moves. |
| `.claude/protected-interfaces` | **nothing added, nothing touched** | Checked one by one: `IndexCache.schemaVersion` (no index change), `VaultAPI.LintFinding` (SPEC §API: no `VaultAPI` capability, no CLI flag, no MCP tool), `CompletingTextView+Pasteboard.swift` (no editor file edited). `interface-check.sh` must stay silent for the whole chain. **If a task looks like it needs to edit an editor or connector file, stop and report.** |

---

## Conventions binding on every task

- **The tester owns the interface, the coder owns the body** (ADR-0155). Swift is compiled: a
  batch that leaves the target unable to build produces no red tests at all, only a build error.
  Every new type's *declaration* — stored properties, function signatures returning a stub — is
  written in the **tester's** task together with the tests that call it. The coder fills bodies.
- **`tuist generate --no-open` after every task that adds a file under `Sources/` or edits
  `Project.swift`.** After Task 2, `tuist install` first.
- **Swift Testing (`@Test`/`#expect`) for all new tests.** Never XCTest, except inside `UITests/`,
  which is an XCTest bundle and stays one.
- **Every new source, test and script file's header cites both `ADR-0031` and this plan's
  basename** (`2026-09-04-sparkle-auto-update-integration`). That includes
  `scripts/appcast.py` and `scripts/fetch-sparkle-tools.sh` (ADR-0154: a harness that names
  neither is descoped).
- **One principal type per file** (`~/.claude/rules/swift.md`).
- **`import Sparkle` appears in exactly one file**, `Sources/App/SparkleUpdateController.swift`.
  Task 2's test enforces it. If a task looks like it needs a second, **stop and report**.
- **Nothing goes under `Sources/Core`, `Sources/Connector`, `Sources/Index`, `Sources/Calendar`
  or `Sources/Vault`** — those are `sharedSources` globs or named files, and an AppKit/Sparkle
  import there breaks both connector builds (ADR-0001 §D1).
- **The unit test command is `.claude/test-cmd` exactly as it stands** —
  `-only-testing:PergamenumTests`. Do not widen it: the UI tests in there terminate the app the
  person at the keyboard is using, and it runs at the end of every turn through the `Stop` hook.
- **`scripts/uitests.sh` runs once, in Task 10, before merge** — never per task, and with **no
  argument** (an argument *replaces* the selection rather than adding to it).
- **Every shell script is Bash 3.2-clean.** macOS ships bash 3.2: no `mapfile`, no associative
  arrays, no `${x^^}`/`${x,,}`. Header `#!/usr/bin/env bash` + `set -euo pipefail`, every variable
  quoted (`~/.claude/rules/shell.md`).
- **`python3`, never `python`** (global CLAUDE.md).
- **No release is cut and nothing is pushed to GitHub by any task in this plan.** Running
  `scripts/release.sh` is Stefano's own deliberate act and is the HITL gate (SPEC §Scope step 6).
  Tasks verify script *stages* in isolation with fixtures; the end-to-end run is Task 10 and is
  his.
- **`weakening-scan.sh` reports every Swift Testing test as `zero-assertion-test`** because it
  treats `#expect` as a comment. Expected, systematically wrong for this stack, advisory.
- **The secret scanner will fire on this chain more than most** — `SUPublicEDKey`, `sign_update`,
  `edSignature`, `keychain`. Read every hit. **The public key is public and belongs in
  `Project.swift`; the private key must never appear in any file, ever** (R-05).

---

## Phase 1 — the app side (no script is touched yet)

### Task 1 — the four `SU*` keys are a value type, asserted against the shipped `Info.plist` (R-03, R-04, R-08)

- Budget: `Sources/App/UpdaterConfiguration.swift` (new), `Project.swift`,
  `Tests/UpdaterConfigurationTests.swift` (new) (~220 lines)
- **Tester first.** Write `Tests/UpdaterConfigurationTests.swift` and, in the same task, the
  *declaration* of `UpdaterConfiguration` (properties + `init?(infoDictionary:)` returning `nil`
  + `problems` returning `[]`). The suite must **build** and go **red**.
- The type takes a `[String: Any]`, not a `Bundle` — a dictionary can be faked in a test and a
  bundle cannot, so the same code is exercised against literal fixtures *and* the real plist
  (ADR §D6). **No `import Sparkle`** here: the keys are strings.
- Fixture tests: all four keys present and valid → non-nil, `problems` empty. `SUFeedURL` absent
  → `nil`. `SUFeedURL` on `http://` → one problem naming it. `SUPublicEDKey` empty → one problem.
  `SUEnableAutomaticChecks: true` → one problem (this is R-03's assertion). `SUSendsSystemProfile:
  true` → one problem (R-04's).
- **The real-plist test** resolves the host app bundle defensively, because it is not certain
  which bundle `Bundle.main` is under a Tuist-hosted unit test: use `Bundle.main` when its
  `bundleURL.pathExtension == "app"`, else walk three levels up from
  `Bundle(for: <a local final class>.self).bundleURL` (the test bundle sits at
  `Pergamenum.app/Contents/PlugIns/PergamenumTests.xctest`). If neither resolves to a `.app`,
  the test **fails with a message naming both paths** — never skips silently.
  `ThemeEngine.swift:303` is the repo's precedent for a two-candidate bundle probe.
- **Coder** fills the bodies and adds the four keys to `Project.swift`'s existing
  `.extendingDefault(with:)` block, beside `CFBundleVersion` (`:119-163`). `SUPublicEDKey` is a
  **placeholder string** at this task — the real key comes from Task 9's `generate_keys` run.
  Leave a comment saying so; a placeholder that survives to Task 10 is caught by R-08's hand check.
- `SUFeedURL` = `https://istefox.github.io/pergamenum-updates/appcast.xml` (ADR §D9).
- Run `tuist generate --no-open` before expecting the real-plist assertion to pass.
- Green: `.claude/test-cmd`.

### Task 2 — Sparkle is linked into the app and into nothing else, and the embed is verified (R-01)

- Budget: `Tuist/Package.swift`, `Tuist/Package.resolved`, `Project.swift`,
  `Tests/SharedSourcesPurityTests.swift` (new) (~120 lines)
- **Tester first.** `Tests/SharedSourcesPurityTests.swift` walks the repo from `#filePath`
  (one `deletingLastPathComponent()` off `Tests/` gives the root) and asserts that **no** `.swift`
  file under `Sources/Core`, `Sources/Connector`, `Sources/Index`, `Sources/Calendar`,
  `Sources/Vault`, `Sources/CLI` or `Sources/MCPServer` contains `import Sparkle`. If the root
  does not resolve, **fail naming the path** — never skip. Green from the first run (nothing
  imports it yet); it is the guard, not the red.
- **Coder:** add `.package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.6")` to
  `Tuist/Package.swift`'s `dependencies`. **Do not touch `PackageSettings.productTypes`** — it has
  no effect on a `.binaryTarget` and an entry there is misleading (ADR §D1). Set the app target's
  `dependencies:` to `[.external(name: "Sparkle")]` (`Project.swift:171`). Leave `perg`'s `[]` and
  `pergamenum-mcp`'s `[.external(name: "MCP")]` alone.
- `tuist install && tuist generate --no-open`. Commit the regenerated `Tuist/Package.resolved`.
- **The embed check is the acceptance, and it is mechanical.** Build the app scheme, then confirm
  on the product:
  - `Pergamenum.app/Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle` exists;
  - `Versions/B/Autoupdate` and `Versions/B/Updater.app` exist;
  - `codesign --verify --deep --strict <app>` exits 0.
- **Then build both tool schemes explicitly** — `.claude/test-cmd` does not:
  `xcodebuild -workspace Pergamenum.xcworkspace -scheme perg -destination 'platform=macOS' build`
  and the same for `pergamenum-mcp`. Both must succeed.
- **If the framework is linked but not embedded, STOP AND REPORT.** Do not improvise a copy
  phase. The named fallback is ADR §A2 (a vendored `.xcframework` declared in `Project.swift`,
  fetched by Task 6's script) and it changes the shape of this task; it is a decision for the
  orchestrator, not a patch.
- Green: `.claude/test-cmd` plus the four checks above.

### Task 3 — the updater controller: allocated in `init`, started from the window, absent under `-disableUpdater` (R-02, R-03)

- Budget: `Sources/App/SparkleUpdateController.swift` (new),
  `Sources/App/PergamenumApp.swift`, `Tests/SparkleUpdateControllerTests.swift` (new)
  (~200 lines)
- **Tester first.** Declaration + tests. The class:
  `@MainActor @Observable final class SparkleUpdateController` holding an
  `SPUStandardUpdaterController` built with `startingUpdater: false, updaterDelegate: nil,
  userDriverDelegate: nil`, plus `private(set) var canCheckForUpdates = false`,
  `private let isIsolated = UserDefaults.standard.bool(forKey: "disableUpdater")`,
  `func start()`, `func checkForUpdates()`, and a stored `NSKeyValueObservation?`.
- **Do not instantiate `SPUStandardUpdaterController` in a unit test.** `startUpdater` can put a
  modal alert on screen; a modal alert in the unit suite is a hang, and the suite runs at the end
  of every turn. The tests assert only what can be asserted without it: that `isIsolated` reads
  the `disableUpdater` default (set it in a `UserDefaults` suite in the test and read it back
  through the same key), and that `start()` is a no-op when isolated. If a test cannot be written
  without constructing the Sparkle object, **do not write it** — R-02 and R-08's real coverage is
  Task 4's UI test and Task 10's hand check. Say so in the test file's header comment rather than
  leaving a gap nobody can see.
- **Coder** fills the bodies:
  - `start()` returns immediately when `isIsolated`; otherwise `controller.startUpdater()` and
    installs the KVO observation:
    `controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] u, _ in MainActor.assumeIsolated { self?.canCheckForUpdates = u.canCheckForUpdates } }`.
    **Store the returned token** — KVO stops the instant it is discarded, silently.
    `MainActor.assumeIsolated` and not a `Task { @MainActor in … }`: Sparkle posts this on the
    main thread and a hop would make the menu item lag its own state (ADR §D5).
  - `checkForUpdates()` → `controller.updater.checkForUpdates()`.
  - `PergamenumApp`: `@State private var updater = SparkleUpdateController()` (a plain inline
    default — nothing in `init` needs it, unlike `navigation`/`history`), and `updater.start()`
    added to `armCapture()` (`:125-130`), which is where the hot key is registered and where the
    file's own comment says NSApp-adjacent work belongs. **Not in `init()`** (ADR §D3).
- Green: `.claude/test-cmd`. Then launch a Debug build by hand once
  (`APP=$(ls -dt ~/Library/Developer/Xcode/DerivedData/Pergamenum-*/Build/Products/Debug/Pergamenum.app | head -1); open -n "$APP" --args -recentVaults '("/tmp/throwaway")'`)
  and confirm no alert appears at launch. Use `-t` on the `ls`, or you get a stale build.

### Task 4 — «Cerca Aggiornamenti…» in the Pergamenum menu, beside «Informazioni su Pergamenum» (R-02)

- Budget: `Sources/App/MenuCommands.swift`, `Sources/App/PergamenumApp.swift`,
  `UITests/UpdateMenuUITests.swift` (new) (~120 lines)
- **Tester first.** `UITests/UpdateMenuUITests.swift`, XCTest (the UI bundle stays XCTest), which
  launches with **both** `-disableCalendar YES` **and** `-disableUpdater YES`, opens the
  `Pergamenum` app menu and asserts a menu item titled «Cerca Aggiornamenti…» exists.
  **It never clicks it** — a click is a real network fetch and, under `-disableUpdater`, a
  no-op that proves nothing. R-02's "triggers Sparkle's standard update-check UI" half is
  verified by hand in Task 10; say so in the test's header.
- This is the one place in the repo where finding a control by its title is correct rather than
  forbidden: CLAUDE.md's rule is about *app-authored* controls, and a `CommandGroup` button has no
  `accessibilityIdentifier` surface. The title is the contract here.
- **Coder:** a new `struct UpdateCommands: Commands` in `Sources/App/MenuCommands.swift`
  (the file that already holds `ViewCommands`, `EditCommands`, `HelpCommands`):

  ```
  CommandGroup(after: .appInfo) {
      Button("Cerca Aggiornamenti…") { updater.checkForUpdates() }
          .disabled(!updater.canCheckForUpdates)
  }
  ```

  `after: .appInfo` is Sparkle's own documented placement and is the standard macOS location.
  **No `import Sparkle` in this file** — it speaks to `SparkleUpdateController` only (ADR §D2).
  **No `ShortcutCommand` case and no key binding**: ADR-0023 §D5's precedent — the catalogue is
  the set of rebindable shortcuts, not all commands, and this one never had a key.
- Register it in `PergamenumApp`'s `.commands` block (`:196-215`), after `HelpCommands`.
- Green: `.claude/test-cmd` (unaffected) plus this one UI test run in isolation:
  `scripts/uitests.sh PergamenumUITests/UpdateMenuUITests` — remember an argument **replaces**
  the selection.

### Task 5 — every UI-test file keeps the updater out of its launch (R-02, R-03)

- Budget: all 18 files under `UITests/` (~40 lines)
- Add `-disableUpdater YES` to every `XCUIApplication().launchArguments`, beside the
  `-disableCalendar YES` that is already in all eighteen. **All of them, not only the ones that
  would notice** — the same rule CLAUDE.md states for the calendar flag, bought the hard way.
- No new test. This is the prophylactic against the failure mode ADR §D4 describes: an updater
  that starts on every launch, before any appcast exists, putting an alert on screen and turning
  a whole run into 60.2 s launch timeouts that look like defects and are not.
- Green: `scripts/uitests.sh` with **no argument**, the full bundle, once. Read the per-test
  seconds it prints beside any failure before believing it, and kill stale instances first
  (`ps -Ao pid,command | grep Pergamenum.app/Contents/MacOS`) — the script does this itself, but
  a red run with stale instances alive is not evidence.

---

## Phase 2 — the release path (no app file is touched again)

### Task 6 — the Sparkle tools arrive pinned and checksum-verified (R-05, R-06)

- Budget: `scripts/fetch-sparkle-tools.sh` (new) (~90 lines)
- Bash 3.2, `#!/usr/bin/env bash`, `set -euo pipefail`, every variable quoted. Header comment
  cites `ADR-0031` and `2026-09-04-sparkle-auto-update-integration`.
- Downloads `https://github.com/sparkle-project/Sparkle/releases/download/2.9.6/Sparkle-for-Swift-Package-Manager.zip`,
  verifies its SHA-256 against the pinned constant
  `8d5fb41d960b43f4a68aa14126bf62b098544ec8d191cdcc73eb14e63a8e7606` **before unpacking anything**,
  and extracts `bin/` into `build/tools/sparkle/bin/`. That checksum is the value in Sparkle's own
  `Package.swift`, so the tools and the framework Task 2 links are provably the same build
  (ADR §D11). `build/` is already gitignored (`.gitignore:66`) — no gitignore edit.
- **Idempotent:** an existing unpack whose `bin/sign_update` is present and whose recorded
  checksum matches is left alone and reported, not re-downloaded.
- **Fails loud on a checksum mismatch and deletes nothing** — it reports both hashes and exits
  non-zero. Never `rm -rf` anything (a chained `rm -rf` gets the whole Bash call denied on this
  machine, and this script must stay runnable).
- Verification for this task: run it twice. First run downloads and unpacks; second run reports
  "already present" and exits 0 in under a second.
  `build/tools/sparkle/bin/sign_update --help` runs.
  Then flip one character of the pinned checksum in a scratch copy and confirm it refuses.
- No unit test: this repo has no shell test harness and inventing one for a 90-line fetcher is
  the wrong trade. The verification above is the coverage, and it is written into the task.

### Task 7 — the release preflight, and the distributable cut from the stapled bundle (R-06)

- Budget: `scripts/release.sh` (~90 lines)
- Textual guard, written by the tester before the coder (Step 5 record): `Tests/ReleasePipelineTests.swift`
  asserts the `$DIST`/staple ordering, `sparkle_tool()`, the pinned checksum of Task 6 and the
  self-test of Task 8 (R-06, R-07).
- **Two insertions, both in one task because the first exists to protect the second.**
- **Preflight**, immediately after the branch/clean-tree guards at `:44-46`, before the
  ten-minute archive:
  - resolve `sign_update` via `$SPARKLE_BIN` → `build/tools/sparkle/bin` → `PATH`, in that order,
    in a `sparkle_tool()` function; `fail` naming `scripts/fetch-sparkle-tools.sh` if absent;
  - `gh auth status` exits 0;
  - the EdDSA private key is in the login Keychain — **verify the exact service/account
    `generate_keys` writes before hardcoding them** (`security find-generic-password -s <service>
    -a <account>` with output suppressed; never print the key). If Task 9 has not run yet, this
    check is written but the script is not run end to end, which is fine.
  - `command -v python3`.
  This is the script's own philosophy applied one step earlier — `:92-97` reads *"Check what came
  out, before asking Apple to bless it… Each of these has been wrong at least once."*
- **The distributable**, after the `spctl` verdict at `:133-135`. Move the existing
  `version=` line (`:137`) **up**, above the new stage, since the filename uses it — that is the
  only existing line this task moves. Then:

  ```
  step "Impacchetto la build firmata e ticketata"
  readonly DIST="$OUTPUT/Pergamenum-$version-$BUILD.zip"
  ditto -c -k --sequesterRsrc --keepParent "$BUNDLE" "$DIST"
  ```

  **`$zip` (`:118`) is not reused, not renamed, not overwritten**, and `$log` (`:123`) is left
  pointing at it: `$zip` is the record of what notarytool was handed, and the two files have
  opposite ticket status (ADR §D8). `--sequesterRsrc` is added because Sparkle's publishing
  documentation asks for it.
- Verification without cutting a release: `bash -n scripts/release.sh` passes; then run the
  preflight block alone in a scratch shell with the same resolution order and confirm it passes
  with the tools present and fails with `SPARKLE_BIN=/nonexistent`. Confirm the `$DIST` `ditto`
  line against the **already-installed** `/Applications/Pergamenum.app` in a temp directory, and
  check the ticket survives the round trip:
  `ditto -c -k --sequesterRsrc --keepParent /Applications/Pergamenum.app /tmp/t.zip && ditto -x -k /tmp/t.zip /tmp/x && xcrun stapler validate /tmp/x/Pergamenum.app`.
  That last command passing **is** R-06's proof, and it is the one thing today's `$BUILD.zip`
  would fail.

### Task 8 — `scripts/appcast.py`, with its own self-test (R-07)

- Budget: `scripts/appcast.py` (new) (~230 lines)
- `python3`, stdlib only (`xml.etree.ElementTree`, `urllib.request`, `argparse`, `email.utils`).
  Header cites `ADR-0031` and this plan's basename.
- **Why not `generate_appcast`:** one `--download-url-prefix` for all items where each release has
  its own tag, a local archive folder standing in as the feed's history, and delta generation
  which is a non-goal (ADR §D10). The SPEC permits the hand-built branch explicitly.
- Interface: `appcast.py --feed-url <url> --version <build> --short-version <v>
  --min-system <x.y> --download-url <url> --signature <sparkle:edSignature value>
  --length <bytes> --notes-link <url> --output <path>`.
- Behaviour: fetch the currently published feed from `--feed-url`; **a 404 yields a fresh
  skeleton, not an error** (that is the state before the first release, and it must be the happy
  path once). Register the `sparkle` namespace
  (`http://www.andymatuschak.org/xml-namespaces/sparkle`) so the output uses the `sparkle:` prefix
  rather than `ns0:`. Insert the `<item>` at the top of `<channel>`; if an item with the same
  `sparkle:version` exists, **replace it in place** rather than duplicating. Write to `--output`.
  A feed that exists but does not parse is a **loud failure**, never a silent skeleton.
- **On parsing XML fetched over the network:** stay on stdlib `xml.etree.ElementTree`. Do **not**
  add `defusedxml` — it is a third-party package and this repo has no Python dependency file to
  put it in. `ElementTree` on Python 3 does not resolve external entities and refuses undefined
  ones outright, so neither XXE nor billion-laughs applies; the input is additionally a document
  fetched over HTTPS from a repository this account owns. Reject any feed carrying a `<!DOCTYPE`
  before parsing it — one `if b"<!DOCTYPE" in raw: fail(...)` line, so the reasoning is enforced
  rather than remembered.
- The item carries exactly: `<title>`, `<pubDate>` (RFC 2822 via `email.utils.formatdate`),
  `<sparkle:version>`, `<sparkle:shortVersionString>`, `<sparkle:minimumSystemVersion>`,
  `<sparkle:releaseNotesLink>`, and one `<enclosure url= sparkle:edSignature= length=
  type="application/octet-stream"/>`.
- **`--self-test`** mode with in-process assertions — no new test framework, no second runner,
  `scripts/mcp-smoke.py` is the precedent. Cases: (1) empty/absent feed → one item, well-formed,
  `sparkle:` prefix present; (2) existing feed with one item → two items, the old one intact and
  the new one first; (3) same `sparkle:version` twice → still one item, updated; (4) malformed
  existing feed → non-zero exit and a message naming the parse error.
- Verification for this task: `python3 scripts/appcast.py --self-test` exits 0 and prints what it
  checked. Then feed the output through `python3 -c "import xml.dom.minidom,sys; xml.dom.minidom.parse(sys.argv[1])"`.
- **Nothing is published by this task.** It writes a local file.

### Task 9 — the keypair, and the publish stage wired into `release.sh` (R-05, R-07)

- Budget: `scripts/release.sh`, `Project.swift` (~110 lines)
- **The keypair first, and by hand.** Run `build/tools/sparkle/bin/generate_keys` once. It writes
  the private key to the login Keychain and prints the public key. Put the **public** key into
  `Project.swift`'s `SUPublicEDKey`, replacing Task 1's placeholder, and `tuist generate`.
  Task 1's real-plist test must still pass.
- **R-05's verification is a repo-wide search, run and its output recorded before the commit:**
  `git grep -n -i -E "BEGIN (OPENSSH|PRIVATE)|ed25519.*private|SUPrivateEDKey"` returns nothing,
  and `security find-generic-password -s <service> -a <account>` finds the item (**without
  `-w`** — never print the key). The private key never appears in `scripts/release.sh`, in
  `Project.swift`, or in any tracked file: `sign_update` reads it from the Keychain itself.
- **The publish stage**, appended after Task 7's `$DIST` stage:
  1. `sig_line="$("$(sparkle_tool sign_update)" "$DIST")"` — parse `sparkle:edSignature="…"` and
     `length="…"` out of it. **Verify the tool's actual output format against the real binary
     before writing the parser**; do not assume it from documentation.
  2. `gh release create "v$version-$BUILD" --repo istefox/pergamenum-updates --title "Pergamenum $version ($BUILD)" --notes-file "$notes" "$DIST"`.
     `$notes` is a file the script requires to exist (`$OUTPUT/$BUILD-notes.md`) and `fail`s
     without — release notes are written by a person, and a release with an empty body is a
     release nobody can read. SPEC non-goals forbid a `CHANGELOG.md`; this is per-release prose,
     not a maintained file.
  3. `python3 scripts/appcast.py` with the values from steps 1–2, plus
     `--min-system "$(PlistBuddy -c 'Print :LSMinimumSystemVersion' "$BUNDLE/Contents/Info.plist")"`
     — read from the built plist, never a second literal in the script.
  4. Publish `appcast.xml` to `istefox/pergamenum-updates` via
     `gh api -X PUT repos/istefox/pergamenum-updates/contents/appcast.xml` with the base64 body and
     the current `sha` (fetched first; absent on the very first publish). **No second git worktree
     and no branch checkout** — `release.sh` refuses a dirty tree at `:46` and must not be the
     thing that creates one.
  5. Update the closing summary heredoc (`:138-146`) to name `$DIST`, the release URL and the
     appcast URL alongside the existing install instructions.
- **Nothing in this task runs `release.sh` end to end.** `bash -n` passes; each new command is
  rehearsed in isolation against a scratch tag/file that is then removed by hand.
- Green: `.claude/test-cmd` (unaffected by a script change, but it runs anyway).

---

## Phase 3 — the record and the one thing only Stefano can do

### Task 10 — the documentation, the HITL gates, and the end-to-end proof (R-05, R-08, R-09, R-10)

- Budget: `CLAUDE.md`, `docs/20260811_Pergamenum_SpecApp.md`, `PROJECT_BRIEF.md` (~120 lines)
- **Documentation, written by the coder:**
  - `CLAUDE.md` §Binding architectural principles, principle 2: append the named exception —
    *fully offline except one user-initiated update check, which carries version identifiers and
    nothing else; `SUSendsSystemProfile` stays off; no other feature gains network access.* Point
    at ADR-0031 §D13. **Do not delete or weaken principle 2's sentence** — qualify it.
  - `CLAUDE.md` §Chain decision index: one `ADR-0031` row, matching the ten already there.
  - `CLAUDE.md` §Commands: `scripts/fetch-sparkle-tools.sh` and `scripts/appcast.py --self-test`.
  - `docs/20260811_Pergamenum_SpecApp.md`: a §14 row recording the manual-only choice and its
    reason, so it is not reopened from memory.
  - `PROJECT_BRIEF.md` §Status.
  - **R-10 is satisfied by ADR-0031 §D13 itself**, which is already written; this task confirms
    it survived the relocation to `docs/adr/` intact and that CLAUDE.md points at it.
- **HITL gates — none of these is the coder's to take:**
  1. **Create `istefox/pergamenum-updates` as a public repository** and enable Pages on it.
     This is a visibility decision under a personal account and it cannot be undone quietly
     (ADR §D9). If it is refused, the fallback is ADR §A7 (a `gh-pages` orphan branch on
     `istefox/Pergamenum`) and `SUFeedURL` changes — **that is a new task, not a patch**.
  2. **Run `scripts/release.sh`.** Stefano runs it himself; that invocation *is* the gate
     (SPEC §Scope step 6). Nothing in this plan runs it.
  3. Commit, push, PR, merge — as always.
- **R-08's proof, by hand, after the first release exists:** install the released build over
  `/Applications` (moving the previous copy aside, never deleting it — CLAUDE.md), cut a second
  release, then in the older running copy choose «Cerca Aggiornamenti…» and confirm the update is
  offered, downloaded, signature-verified and installed with a relaunch. Also confirm the
  no-update path ("You're up to date!") and the offline path (Wi-Fi off → Sparkle's own error
  alert, no crash).
- **R-09's proof:** `git diff main...HEAD --stat` and read it. The changeset must touch only
  `Sources/App/{SparkleUpdateController,UpdaterConfiguration,MenuCommands,PergamenumApp}.swift`,
  `Project.swift`, `Tuist/Package.{swift,resolved}`, `Tests/`, `UITests/`, `scripts/`, and docs.
  **Any file under `Sources/Core`, `Sources/Connector`, `Sources/Vault`, `Sources/Index`,
  `Sources/Calendar` or `Sources/Features` in that diff is a defect** — stop and report.
- **Before merge:** `scripts/uitests.sh` with no argument (the full bundle), plus explicit builds
  of the `perg` and `pergamenum-mcp` schemes, plus `scripts/mcp-smoke.py` if any connector file
  was touched (it must not have been). `interface-check.sh` must be silent.

**Deviation, recorded at Gate 5.06 (specialized review), applied post-snapshot per ADR-0158:**
- `SparkleUpdateController.controller` was `internal` in the Task 3 implementation, defeating
  ADR-0031 §D2's single-entry-point promise (any file in the module could reach `SPUUpdater`
  without `import Sparkle`, bypassing `isIsolated`). Made `private`; no call site existed outside
  the file. `checkForUpdates()` was also missing the `isIsolated` guard `start()` already has —
  inherited verbatim from the ADR §D3 code sample, not a Task 3 deviation, but fixed alongside
  since it is the same file and the same invariant.
- `scripts/release.sh`'s publish stage (Task 10) committed the appcast via the GitHub Contents API
  and declared success without ever confirming `SUFeedURL` (GitHub Pages) actually serves the
  published bytes — Pages rebuilds asynchronously and can be unconfigured, stale, or failed
  silently. Added a bounded poll (`curl` the live feed for the just-signed EdDSA signature, 6
  tries × 10s) after the `gh api PUT`; `fail`s naming the URL if the feed never reflects the
  release within 60s. Not yet exercised end-to-end — `scripts/release.sh` still has not been run
  (Gate 2 of this task remains Stefano's alone).

---

## Requirement coverage

| ID | Tasks |
|---|---|
| R-01 | 2 |
| R-02 | 3, 4, 5 |
| R-03 | 1, 3, 5 |
| R-04 | 1 |
| R-05 | 6, 9, 10 |
| R-06 | 6, 7 |
| R-07 | 8, 9 |
| R-08 | 1, 10 |
| R-09 | 10 |
| R-10 | 10 |

R-05, R-08, R-09 and R-10 carry `(no-test: …)` in the SPEC. Each still has a citing task: the
marker exempts the *test* axis, never the *plan* axis (ADR-0138).

---

TEST-CMD CANDIDATE: xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -derivedDataPath "/Users/stefer/Developer/Pergamenum/.build/DerivedData" -only-testing:PergamenumTests test
TEST-CMD MODE: brownfield

EXTERNAL DEPENDENCY: istefox/pergamenum-updates | vendor-account | provisioned: false
EXTERNAL DEPENDENCY: build/tools/sparkle/bin/sign_update | file | provisioned: false
EXTERNAL DEPENDENCY: gh | binary | provisioned: true
EXTERNAL DEPENDENCY: python3 | binary | provisioned: true
EXTERNAL DEPENDENCY: Sparkle EdDSA private key (login Keychain) | vendor-account | provisioned: false

CODER-MODEL CANDIDATE: opus
