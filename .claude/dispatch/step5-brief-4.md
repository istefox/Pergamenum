<!-- step5-brief: plan=/Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-09-pratiche.md tasks=5,6 lines=267-319 -->
# Step 5 Batch Brief -- 2026-09-09-pratiche.md -- tasks 5-6

## Task text (verbatim, plan lines 267-319)

### Task 5 — controller, triggers, Full Disk Access, and the isolation guarantees (R-17, R-18, R-19, R-38)

- Budget: `Sources/Features/Pratiche/PraticheController.swift`, `PraticaWatcher.swift`,
  `FullDiskAccessProbe.swift`, `Sources/App/PergamenumApp.swift` (one `@State` + two
  `.environment`), `Tests/PraticheControllerTests.swift`, `Tests/PraticheIsolationTests.swift`,
  `Tests/SharedSourcesPurityTests.swift` (one case), `UITests/**` (19 files) (~700 lines)
- Tester writes: `PraticheController` (`@Observable`: list, selection, timeline, tray, sync
  progress, expansion set, banner state), `PraticaWatcher` (FSEvents + window-key + vault-open
  triggers), `FullDiskAccessProbe.state()`.
- Tests (red): sync runs for `status-active`/`status-waiting` on vault open, on window-key throttled
  to one per 60 s, and on an FSEvents pulse debounced 10 s, and a closed pratica syncs **only**
  through «Aggiorna ora» (R-17); the probe reads `EPERM` as not-granted and the controller exposes
  the banner state, and a later grant clears it on the next trigger with no restart (R-18);
  `MailStoreLocation` honours `-mailStoreRoot` and returns the fixture under xctest regardless
  (R-19); **no file under `Sources/Core` or `Sources/Connector` added by this chain imports AppKit
  or SwiftUI**, and no file under `Sources/Connector`, `Sources/CLI` or `Sources/MCPServer` names
  `MailStore`, `EMLXReader` or `SQLite3` (R-38, ADR §D19).
- **The 19 UI-test files** gain `-mailStoreRoot`, `<fixture>` beside their existing
  `-disableCalendar YES -disableUpdater YES`.
- Coder: bodies. Then build **both** connectors deliberately (`xcodebuild -scheme perg` and
  `-scheme pergamenum-mcp`), because `.claude/test-cmd` builds neither.
- `tuist generate --no-open`; full unit suite; both connector builds.

### Task 6 — the pane, the timeline, the lanes, the tokens (R-23, R-24, R-25, R-26, R-27, R-32, R-33, R-39; screens 1a, 1b, 1c, 1g)

- Budget: `Sources/DesignSystem/TokenKeys.swift` (3 cases), `Resources/Themes/pergamenum-light.json`,
  `pergamenum-dark.json`, `Sources/Features/Pratiche/PratichePane.swift`,
  `PraticheListColumn.swift`, `PraticaTopBar.swift`, `PraticaTimelineView.swift`,
  `PraticaMessageRow.swift`, `PraticaEntryRow.swift`, `AttachmentChip.swift`,
  `FullDiskAccessBanner.swift`, `Sources/App/Navigation.swift`, `Sources/App/SidebarItem.swift`,
  `Sources/App/RootView.swift`, `Tests/PraticaTimelineTests.swift`, `Tests/SidebarTests.swift`,
  `Tests/DesignSystemTests.swift` (~1100 lines)
- Tester writes: the timeline model's ordering function, the filter function, the lane/direction
  function, and the three `ColorToken` cases; view declarations with their accessibility
  identifiers.
- Tests (red): entries sort by `pergamenum-mail-date` with the received date as fallback,
  interleaved with manual entries by heading timestamp, ascending, grouped into day sections (R-23);
  a row is collapsed by default and its expansion state is per-window and not persisted, and
  Opt+click expands or collapses all (R-24); direction decides lane and is carried by glyph and
  label as well as colour (R-25, R-39); the subject resolves to a `message://` URL through the one
  builder, and to plain text plus «non più in Mail» when the ledger says so (R-26); the three new
  tokens exist in **both** theme JSONs and the completeness check passes (R-39); the text/sender/
  attachments filters narrow messages and hide manual entries **only** under the text filter (R-32);
  the sidebar row sits in LAVORO immediately before «Registrazioni», the pane list groups by client
  with flat rows, badges count messages since `lastOpenedAt`, a dot marks a non-empty tray, and
  «Chiuse» collapses `archived`/`final` (R-33, C3).
- Coder: bodies, composed as `VaultBrowser` is — top bar above an `HSplitView` of list · timeline ·
  inspector (ADR §D13). **`.badge` before `.tag`**, client rows carry no `.tag`, no
  `DisclosureGroup` anywhere. Attachment chips call the existing `QuickLookPresenter`; expanded
  bodies render with `MarkdownBlocksView` (R-27).
- Screens: 1a (light), 1b (dark), 1c (banner + inspector), 1g (empty state).
- `tuist generate --no-open`; full unit suite.

## File map (from Budget: declarations, tasks 5-6)

- (none declared -- no task in this range carries a parseable Budget:)

No parseable Budget: for task(s): 5 6 (absent is not zero -- consult the task text above)

## Excluded tasks (not in this batch)

- Task 1 -- see /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-09-pratiche.md
- Task 2 -- see /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-09-pratiche.md
- Task 3 -- see /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-09-pratiche.md
- Task 4 -- see /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-09-pratiche.md
- Task 7 -- see /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-09-pratiche.md
- Task 8 -- see /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-09-pratiche.md
- Task 9 -- see /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-09-pratiche.md
- Task 10 -- see /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-09-pratiche.md

Full plan: /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-09-pratiche.md

## Context documents (open only for the reason stated -- not read unconditionally)

- ADR: docs/adr/0036-pratiche.md -- D8 (MailStoreLocation test-awareness, -mailStoreRoot in all 19 UITests files), D10 (Full Disk Access probed per trigger with open(2), never at launch), D11/D12 (connector isolation, SharedSourcesPurityTests case), D13 (pratica.md edited only in the inspector, timeline rows read-only), D16/D17 (two-lane timeline, tokens) and all three Follow-up sections bind Task 5's controller/triggers/isolation and Task 6's pane/timeline
- SPEC: SPEC.md -- requirement IDs R-17, R-18, R-19, R-38 (Task 5) and R-23..R-27, R-32, R-33, R-39 (Task 6), plus screens 1a, 1b, 1c, 1g
- CLAUDE.md: CLAUDE.md -- design-token binding rule (no hardcoded colors or fonts in views), List(selection:) vs DisclosureGroup trap (ADR-0024), UI tests find controls by accessibilityIdentifier only, every UITests file passes -disableCalendar/-disableUpdater (and now -mailStoreRoot), sharedSources rule, tuist generate after adding files
