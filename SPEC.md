# SPEC — Sparkle auto-update integration (PG-096)

**Topic slug:** sparkle-auto-update-integration

## Objectives

Pergamenum ships as a Developer ID, notarized, non-App-Store macOS app (`scripts/release.sh`).
Today there is no in-app way for Stefano to learn a new build exists or to install it — he has to
remember to check GitHub and manually `ditto` a new bundle into `/Applications`. This feature adds
Sparkle (the standard macOS Developer-ID update framework) so the app can check for, download and
install new signed/notarized builds, and extends `scripts/release.sh` to produce and publish
everything Sparkle needs (a signed update archive plus an appcast feed entry) as part of the
existing release flow.

## Explicit exception to CLAUDE.md Principle 2 ("Fully offline")

Principle 2 states: *"No network call in any feature. No server, no account, no telemetry."* An
update check is inherently a network call (`GET` on the appcast URL, then on the update archive
URL if the user chooses to install). This SPEC treats it as a **narrow, named exception**, not a
reopening of the principle:

- The exception covers **only** the update-check/download/install mechanism. It carries no vault
  content, no note text, no user data of any kind — only the app's own version identifiers
  (`CFBundleVersion`, `CFBundleShortVersionString`) and, implicitly, the requester's IP address as
  an artifact of any HTTP request (unavoidable, not additional telemetry).
- `SUSendsSystemProfile` (Sparkle's optional anonymous hardware/OS profiling) stays **off** — this
  would be telemetry proper and Principle 2 forbids it outright, exception or not.
- No feature of the app (vault, Workspace, tasks, calendar) gains network access as a result of
  this chain. The exception is scoped to the updater target/module only.
- The ADR produced from this SPEC records this exception formally, alongside the existing ADR-0007
  network-boundary reasoning for the AI connector (which stays a *"never opens a socket"* boundary
  for the vault itself — unaffected by this feature).

## Scope

In scope:
- Add Sparkle as an SPM dependency (`Tuist/Package.swift`), wired into the `Pergamenum` app target
  only — never into `Sources/Core`, `perg`, or `pergamenum-mcp` (mirrors the existing EventKit
  exclusion rationale: an update mechanism belongs to the interactive app, not to a headless CLI
  invoked by something else).
- A **manual-only** update check: no automatic/background/periodic checking.
  `SUEnableAutomaticChecks` / `automaticallyChecksForUpdates` is `false`, and Sparkle's own
  first-launch "may I check automatically?" consent dialog is suppressed as a result (there is
  nothing to consent to).
- One new UI entry point: **"Cerca Aggiornamenti…"** in the `Pergamenum` app menu, next to
  "Informazioni su Pergamenum" — the standard macOS location for this command. No Settings/
  Impostazioni surface.
- Sparkle's own stock update UI (`SPUStandardUserDriver`, the native "A new version is available"
  window, download progress, "Install and Relaunch") is used as-is. **This window is a system
  framework surface, not part of Pergamenum's SwiftUI view tree** — it is out of scope for the
  design-token binding rule ("no hardcoded colors in views") because it is not a view this app
  authors.
- EdDSA signing keypair generated once via Sparkle's own `generate_keys` tool, private key stored
  in this Mac's login Keychain, public key embedded in `Info.plist` as `SUPublicEDKey`. The private
  key is never written to disk in cleartext and never committed.
- `scripts/release.sh` extended, end-to-end, to (after the existing notarize+staple steps):
  1. Re-package the **stapled** bundle into a distributable zip (today's script staples the
     bundle but only ever notarizes/ships the pre-staple zip — see Edge cases).
  2. Sign that zip with Sparkle's `sign_update` tool (reads the private key from Keychain).
  3. Publish a GitHub Release (via `gh release create`) on `istefox/Pergamenum` with the zip
     attached and a written release-notes body.
  4. Regenerate `appcast.xml` (via Sparkle's `generate_appcast` tool or an equivalent hand-built
     step) with a new `<item>` entry: version, build number, download URL (the GitHub Release
     asset), EdDSA signature, length, minimum system version, and a `sparkle:releaseNotesLink`
     pointing at the GitHub Release page itself.
  5. Push the updated `appcast.xml` to GitHub Pages on `istefox/Pergamenum` (confirmed: GitHub
     Pro/Team plan on this account, so Pages works on a private repo).
  6. All of the above runs automatically when Stefano runs `scripts/release.sh` himself — that
     manual invocation **is** the HITL checkpoint (CLAUDE.md's "never push/deploy without asking"
     is satisfied by the fact that running the release script is itself the deliberate,
     ask-before action; nothing here fires unattended or from a Claude Code session on its own).
- `SUFeedURL` in `Info.plist`/`Project.swift` pointed at the GitHub Pages `appcast.xml` URL.
- Version comparison uses the existing `CFBundleVersion` scheme (commits behind `HEAD`, stamped by
  `scripts/release.sh` via `TUIST_BUILD_NUMBER`) — Sparkle's default comparator already compares on
  this field and it is already strictly monotonic across releases cut from `main`.

Out of scope (non-goals, v1):
- Automatic or scheduled background update checks (explicitly rejected this round).
- Binary delta updates (Sparkle can generate these from a folder of prior release archives; adds
  ongoing artifact-retention complexity not justified for a personal, manually-checked app).
- A CHANGELOG.md file or any new changelog-maintenance habit — release notes live in the GitHub
  Release body only.
- Any Settings/Impostazioni UI surface for updates.
- Rollback, phased rollout, or update channels (beta/stable).
- Any change to `perg` or `pergamenum-mcp` — Sparkle is app-target-only.
- Any change to the AI connector's network boundary (ADR-0007) — the vault itself still never
  opens a socket.

## Stack

- Sparkle (`https://github.com/sparkle-project/Sparkle`), latest stable release, added via SPM in
  `Tuist/Package.swift`, then `tuist install` / `tuist generate`.
- `SPUStandardUpdaterController` + `SPUStandardUserDriver` (Sparkle's default, no custom UI driver).
- macOS Keychain (via Sparkle's `generate_keys`/`sign_update` command-line tools, run manually once
  and then from `scripts/release.sh` at release time).
- GitHub Releases + GitHub Pages on `istefox/Pergamenum` (private repo, GitHub Pro/Team plan) for
  appcast + binary hosting. `gh` CLI (already a project dependency for release/PR workflows).

## Architecture

- A thin `SparkleUpdateController` (or similarly named) type in the app target owns one
  `SPUStandardUpdaterController` instance, created once at app launch, `startingUpdater: true`,
  `updaterDelegate`/`userDriverDelegate: nil` (stock behavior — no custom delegate needed for a
  manual-only, no-telemetry setup beyond what `Info.plist` keys already declare).
- No `VaultSession`/`VaultController` involvement whatsoever — Sparkle knows nothing about vaults,
  notes, or the connector. This keeps the "file over app" and "rebuildable index" principles
  untouched: nothing about the update mechanism is persisted vault state.
- The `Info.plist` keys (`SUFeedURL`, `SUPublicEDKey`, `SUEnableAutomaticChecks: false`,
  `SUSendsSystemProfile: false`) are added via `Project.swift`'s existing `infoPlist` mechanism —
  the same place `CFBundleShortVersionString`/`CFBundleVersion` are already wired.
- `scripts/release.sh` grows a new stage after the existing "Applico il ticket" (staple) step,
  described in Scope above.

## Data model

None. No new persisted state anywhere in the app (no index field, no frontmatter key, no `.canvas`
property). The only new artifact is `appcast.xml`, which lives outside the app entirely (on GitHub
Pages), generated and published exclusively by `scripts/release.sh`.

## API

None internal — this feature exposes no `VaultAPI` capability, no CLI flag, no MCP tool. It is a
GUI-app-only integration; consistent with the existing precedent that EventKit access is
deliberately absent from both connectors.

External surface, all one-directional (Pergamenum → appcast host, never the reverse):
- `GET <appcast-url>/appcast.xml` — triggered only by the user choosing "Cerca Aggiornamenti…".
- `GET <github-release-asset-url>` — triggered only if the user chooses to download/install an
  offered update.

## UI flows

1. Stefano opens the `Pergamenum` app menu → clicks "Cerca Aggiornamenti…".
2. Sparkle's stock UI takes over: a small progress/status window appears while it fetches
   `appcast.xml` and compares `CFBundleVersion`.
3. **No update available:** Sparkle shows "You're up to date!" and the window dismisses.
4. **Update available:** Sparkle shows its standard alert (version, release notes rendered from the
   GitHub Release page linked via `sparkle:releaseNotesLink`) with "Install Update" / "Remind Me
   Later" / "Skip This Version".
5. On "Install Update": Sparkle downloads the signed zip, verifies the EdDSA signature against
   `SUPublicEDKey`, verifies Gatekeeper/notarization on the unpacked bundle, then offers
   "Install and Relaunch".
6. Any network failure (offline, appcast unreachable, download interrupted) surfaces Sparkle's own
   standard error alert — no custom error handling needed in Pergamenum's own code.

## Edge cases

- **Stapled-vs-notarized zip mismatch (pre-existing script behavior).** Today `scripts/release.sh`
  notarizes `$OUTPUT/$BUILD.zip` (built from the bundle *before* stapling) and only staples the
  standalone `.app` bundle afterward — the notarized zip on disk never receives the ticket. The
  zip Sparkle publishes and signs **must** be re-created from the already-stapled bundle, or
  Gatekeeper can refuse the unpacked app on a machine with no network access at first launch. This
  is a real, pre-existing correctness gap the new release stage must close, not carry forward.
- **Repo visibility.** `istefox/Pergamenum` is private; GitHub Pages for a private repo requires
  GitHub Pro/Team — confirmed available on this account during this interview. If that plan ever
  lapses, Pages serving stops silently (404) and update checks fail closed (Sparkle reports "no
  appcast found", never a crash or a downgrade).
- **Old builds with no `SUFeedURL`.** Any build shipped before this feature has no Sparkle
  awareness at all and cannot self-update — Stefano installs the first Sparkle-enabled build
  manually one last time, exactly as today.
- **Downgrade attempts.** Sparkle's default comparator never offers a version with a lower/equal
  `CFBundleVersion` than the running one — no explicit downgrade-prevention code needed.
- **User declines/skips a version.** Sparkle persists "skip this version" in its own
  `UserDefaults` keys; re-triggering "Cerca Aggiornamenti…" manually still always checks fresh
  regardless of a prior skip (skip only suppresses a version from being offered again
  automatically — moot here since checks are manual-only anyway, but Sparkle's own behavior, not
  something this feature needs to build).
- **App not signed/notarized correctly.** `scripts/release.sh` already fails loud
  (`fail "..."`) before reaching the new Sparkle stage if hardened runtime, Developer ID signing,
  or notarization/stapling verification fail — the new stage inherits that safety net for free by
  running strictly after those checks.

## Success criteria

- [ ] R-01 — Sparkle is added as an SPM dependency in `Tuist/Package.swift`, linked only into the
      `Pergamenum` app target (verified: `perg` and `pergamenum-mcp` targets build unaffected).
- [ ] R-02 — The app menu has a "Cerca Aggiornamenti…" item next to "Informazioni su Pergamenum"
      that triggers Sparkle's standard update-check UI.
- [ ] R-03 — No automatic or scheduled update check ever fires; `SUEnableAutomaticChecks` is `false`
      and no periodic timer/background task exists anywhere in the app for this feature.
- [ ] R-04 — `SUSendsSystemProfile` is `false`; no telemetry beyond the unavoidable HTTP request
      itself is ever sent as part of an update check.
- [ ] R-05 — The EdDSA signing keypair is generated via Sparkle's own `generate_keys` tool with the
      private key stored in the login Keychain; no private key material appears in the repo, in
      `scripts/release.sh`, or in any committed file (verified by a repo-wide search for key
      material before commit — (no-test: verified by manual repo search and Keychain inspection,
      not something a unit test can assert)).
- [ ] R-06 — `scripts/release.sh`, run end-to-end, re-packages the **stapled** bundle (not the
      pre-staple notarization zip) into the artifact that gets signed and published.
- [ ] R-07 — `scripts/release.sh`, run end-to-end, publishes a GitHub Release with the signed zip
      attached, regenerates `appcast.xml` with a correct `<item>` (version, build, URL, EdDSA
      signature, length, minimum system version, release-notes link), and pushes it to GitHub
      Pages on `istefox/Pergamenum`.
- [ ] R-08 — `SUFeedURL` in the built app's `Info.plist` resolves to the published `appcast.xml`
      URL and a manual "Cerca Aggiornamenti…" against a real published release successfully offers
      the update, downloads it, verifies its EdDSA signature, and installs/relaunches
      (no-test: end-to-end verified by hand against a real GitHub Pages appcast, not something a
      unit test can assert).
- [ ] R-09 — No feature outside the updater gains network access as a result of this chain; the
      vault, Workspace, tasks and calendar code paths are unchanged (no-test: verified by diff
      review confirming the changeset touches only the updater controller, `Info.plist`/
      `Project.swift` keys, and `scripts/release.sh` — not something a unit test can assert).
- [ ] R-10 — The ADR produced from this SPEC explicitly records the Principle 2 network exception,
      its scope, and the reasoning above (no-test: a documentation obligation, not something a unit
      test can assert).
