# Burn-down: PG-265, PG-263 (residue after #871)

**Mode:** burn-down (`~/.claude/skills/build/references/burn-down.md`)
**ADR:** none. `kind:fix`, no architectural decision.
**Test command:** xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -only-testing:PergamenumTests test

Out of scope on purpose: the four SPEC-pinned sheets, the File menu, «attività vs task», the font-without-token sites (decisions), and the UI-test lookups of fixture content and dialog buttons (not sidebar rows). Both entries stay unticked.

## Entries

- [ ] `PG-265` -> #579 **P3** residue: (1) `CapturePanelView.swift` `folderPicker` (~99) and `notePicker` (~181) read only the name to VoiceOver: give each an `accessibilityLabel` that says what the control does («Cartella della nota nuova: <name>», «Nota a cui aggiungere: <name>»), keeping `accessibilityIdentifier`s; (2) the four near-identical private pane-opening helpers in `TaskCategoriesUITests`, `ComposerUITests`, `HistoryNavigationUITests`, `WorkspaceIntegrationUITests` become one `openSidebarRow(_:timeout:)` in `PergamenumUITestCase` (wait for the row by `sidebarRow`, then click, one failure message naming `sidebar-<id>`); (3) `WorkspaceBoardUITests` (~95) waits for the Workspace row instead of clicking it only if present
- [ ] `PG-263` -> #577 **P3** residue: `PraticaMessageRow.swift` `shortDayFormatter` (~384) sets no locale, unlike its neighbours; pin `uiLocale` like them (it feeds `dayAndTime`, ~345); add or extend a test in `Tests/PraticaItalianFormatTests.swift` that fails on a non-Italian machine locale

## Build result (2026-10-04)

BUILD · DONE WITH WARNINGS

Files: Sources/Features/Capture/CapturePanelView.swift, Sources/Features/Pratiche/PraticaMessageRow.swift, Tests/PraticaItalianFormatTests.swift, Tests/PraticaEntryHeadingTests.swift, UITests/PergamenumUITestCase.swift, UITests/TaskCategoriesUITests.swift, UITests/ComposerUITests.swift, UITests/HistoryNavigationUITests.swift, UITests/WorkspaceIntegrationUITests.swift, UITests/WorkspaceBoardUITests.swift
Tests: unit suite green, 5189 tests in 300 suites, 5 known issues; GUI run of the 5 touched classes green after a rerun of 2 first-pass reds.
Review: sonnet, safe to merge.
Entries: PG-265 partial (picker labels, `openSidebarRow`, Workspace row wait done), PG-263 partial (`shortDayFormatter` pinned to `uiLocale`). Both stay unticked.
Dispatch: Round 0: coder only; one NIT (test rename) applied by the orchestrator.
WARN: first GUI pass had 2 reds that went green on rerun, with focus-taken / external-monitor signals present (PG-188); not a code defect.
INFO: the stop-gate turned red twice on tests outside the diff (hosted-view tests, `registeringWithTheSystemReportsWhatTheSystemSaid`) while a GUI or second xcodebuild run was live; a standalone unit run was green.
DROP nit: `.claude/test-timeout` is per-machine, not committed.
