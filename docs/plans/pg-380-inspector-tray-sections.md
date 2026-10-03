# PG-380: the inspector's BACKLINK and LINK NON RISOLTI through `TraySection`

**Requirement set:** none, no SPEC applies. The ledger entry `PG-380` is the only requirement source.
**ADR:** none. One module, no architectural decision: `TraySection` already exists (`Sources/DesignSystem/TraySection.swift`, PG-376) and the board tray and the Pratiche links pane already draw through it. The ledger tags the entry `kind:roadmap`; it is a single-module refactor with no new decision, so it is built from a plan path instead of burn-down mode, which refuses that tag.
**Test command:** `xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -only-testing:PergamenumTests test`

## Entry

`PG-380` **P3** [refactor] The note inspector's `backlinks(_:)` and `unresolved` in `Sources/Features/Editor/VaultBrowser.swift:286-320` each draw the shape `TraySection` owns by hand: a caption header, then «nessuno» or rows. Neither header has an `-header` accessibility identifier nor an accessibility label. `UnlinkedMentionsSection` (`UnlinkedMentionsSection.swift:38`) differs on purpose (count after a `Spacer`, scan states) and stays out of this.

## Tasks

1. `backlinks(_:)` draws through `TraySection`: title `BACKLINK`, `badge: nil`, a spoken label that names the count («Backlink a questa nota: N»), identifier `inspector-backlinks`, `isEmpty: records.isEmpty`, `emptyText: "nessuno"`. The rows are unchanged: the same `Button(record.title)` with `.buttonStyle(.plain)` and `.themedText(.body, color: .accentPrimary)`. The memo lookup stays where it is.
2. `unresolved` draws through `TraySection`: title `LINK NON RISOLTI`, `badge: nil`, a spoken label that names the count («Link non risolti mostrati: N»), identifier `inspector-unresolved-links`, `emptyText: "nessuno"`. The rows are unchanged (text, `.themedText(.caption, color: .textSecondary)`, `.help(...)`).
3. Nothing else in the inspector changes: not the order of the sections, not `UnlinkedMentionsSection`, not the memos, not the spacing between sections. The visible text of both headers and of the empty state is byte-identical to today.
4. A test pins the two identifiers and the header labels, hosted in-process the way `Tests/HostedViewPrototypeTests.swift` and its siblings host a view (no GUI test: the GUI budget for this change is zero). If the inspector cannot be hosted cheaply, a pure test on whatever the coder extracts for the label strings is enough, named in the report.

## Build result (2026-10-03)

BUILD · DONE WITH WARNINGS
Files: Sources/Features/Editor/VaultBrowser.swift, Tests/InspectorSectionLabelTests.swift (new), docs/plans/pg-380-inspector-tray-sections.md
Tests: PergamenumTests green, 5150 passed, 5 known issues; 6 parametrised cases pin `VaultBrowser.InspectorSection` for backlinks (0, 1, 7) and unresolved links (0, 1, 10)
Review: sonnet, safe to merge (round 1 and round 2)
Coverage: not run, the plan's requirement set is not SPEC.md
Dispatch: Round 1: coder — Tests/InspectorSectionLabelTests.swift:11, VaultBrowser.swift:313
WARN: tester phase skipped, the coder added the tests and the full unit suite is green
WARN: ledger entry PG-380 is tagged kind:roadmap, so burn-down mode refused it; built from this plan path, close it with `/project-tasks close PG-380` after the merge

```text
DROP	nit	**NIT** Tests/InspectorSectionLabelTests.swift:12 — tests pin InspectorSection values but not the field-to-TraySection argument mapping at the two call sites; acceptable given the hosted-view accessibility limitation
```
