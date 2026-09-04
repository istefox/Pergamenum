<!-- step5-brief: plan=/Users/stefer/Developer/Pergamenum_worktrees/feat-add-sparkle/docs/superpowers/plans/2026-09-04-sparkle-auto-update-integration.md tasks=1,2 lines=113-171 -->
# Step 5 Batch Brief -- 2026-09-04-sparkle-auto-update-integration.md -- tasks 1-2

## Task text (verbatim, plan lines 113-171)

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

## File map (from Budget: declarations, tasks 1-2)

- (none declared -- no task in this range carries a parseable Budget:)

No parseable Budget: for task(s): 1 2 (absent is not zero -- consult the task text above)

## Excluded tasks (not in this batch)

- Task 3 -- see /Users/stefer/Developer/Pergamenum_worktrees/feat-add-sparkle/docs/superpowers/plans/2026-09-04-sparkle-auto-update-integration.md
- Task 4 -- see /Users/stefer/Developer/Pergamenum_worktrees/feat-add-sparkle/docs/superpowers/plans/2026-09-04-sparkle-auto-update-integration.md
- Task 5 -- see /Users/stefer/Developer/Pergamenum_worktrees/feat-add-sparkle/docs/superpowers/plans/2026-09-04-sparkle-auto-update-integration.md
- Task 6 -- see /Users/stefer/Developer/Pergamenum_worktrees/feat-add-sparkle/docs/superpowers/plans/2026-09-04-sparkle-auto-update-integration.md
- Task 7 -- see /Users/stefer/Developer/Pergamenum_worktrees/feat-add-sparkle/docs/superpowers/plans/2026-09-04-sparkle-auto-update-integration.md
- Task 8 -- see /Users/stefer/Developer/Pergamenum_worktrees/feat-add-sparkle/docs/superpowers/plans/2026-09-04-sparkle-auto-update-integration.md
- Task 9 -- see /Users/stefer/Developer/Pergamenum_worktrees/feat-add-sparkle/docs/superpowers/plans/2026-09-04-sparkle-auto-update-integration.md
- Task 10 -- see /Users/stefer/Developer/Pergamenum_worktrees/feat-add-sparkle/docs/superpowers/plans/2026-09-04-sparkle-auto-update-integration.md

Full plan: /Users/stefer/Developer/Pergamenum_worktrees/feat-add-sparkle/docs/superpowers/plans/2026-09-04-sparkle-auto-update-integration.md

## Context documents (open only for the reason stated -- not read unconditionally)

- ADR: /Users/stefer/Developer/Pergamenum_worktrees/feat-add-sparkle/docs/adr/0031-sparkle-auto-update-integration.md -- D1 (binaryTarget, no productTypes entry, embed verified), D2 (single import Sparkle file + purity test), D6 (UpdaterConfiguration shape and the four SU* keys)
- SPEC: /Users/stefer/Developer/Pergamenum_worktrees/feat-add-sparkle/SPEC.md -- requirement IDs R-01, R-03, R-04, R-08 for this batch's tests
- CLAUDE.md: /Users/stefer/Developer/Pergamenum_worktrees/feat-add-sparkle/CLAUDE.md -- sharedSources/AI-connector boundary, tuist generate rule, working agreements on the test-cmd and DerivedData
