# Burn-down: PG-263, PG-265 (residue after PR #867)

**Mode:** burn-down (`~/.claude/skills/build/references/burn-down.md`)
**ADR:** none. Both entries are `kind:fix`: no architectural decision. Continues `docs/plans/burn-down-2026-10-03-pg-263.md`.
**Test command:** xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -only-testing:PergamenumTests test

Scope is the residue PR #867 left that needs no product decision. Out of scope on purpose: the four SPEC-pinned sheets, the File menu, «attività vs task», the font-without-token sites (needs-spec), and PG-265's prose-based UI-test lookups (the PG-128 harness consolidation, #228, is rewriting those files; verified with `scripts/uitests.sh --affected` after it lands). Both entries therefore stay unticked.

## Entries

- [ ] `PG-263` -> #577 **P3** residue: route `ViewGridRenderers.swift:159` and `MonthView.swift:139` weekday arrays through `MonthGrid.weekdayHeaders`; pin `PraticheSettingsTab.swift:315` and `NodeCard.swift:110` dates with `PraticaRowFormat.uiLocale`; replace the hand-typed «Incolla come testo puro», «Trova nella nota», «Sostituisci» in `MenuCommands.swift:291,305,307` with the `ShortcutCommand` titles
- [ ] `PG-265` -> #579 **P3** residue: give every icon-only `Button` an `accessibilityLabel` (and an `accessibilityIdentifier` where a UI test or the catalogue needs one) in `Sources/Features/**`; a heuristic recount lists about 36 (`CapturePanelView.swift:98,145,181`, `BoardTray.swift:172,226`, `TranscludedNoteView.swift:125,140`, `FindBar.swift:144,146`, `FormatBar.swift:84`, `TagBrowserView.swift:147`, `StarredPane.swift:70`, `OutlinePane.swift:219`, `NoteListPane.swift:291,307`, `MiniCalendar.swift:56,60`, `CategorySidebarSection.swift:187,188,229`, …); labels reuse the button's `.help` text or the catalogue title, in Italian, sentence case

## Build result (2026-10-03)

BUILD · DONE WITH WARNINGS
Files: 10 changed (8 Sources, 2 Tests: MonthGridTests.swift, new BurnDownResidueTests.swift)
Tests: 5187 passed, 0 failed, 5 known issues, 0 (coverage)
Review: sonnet, safe to merge
Entries: PG-263 not fixed, partial: weekday rows through MonthGrid.weekdayHeaders (MonthView, ViewCalendarRenderer), it_IT pins on the Pratiche settings and NodeCard dates, three Edit-menu titles from ShortcutCommand done; four SPEC-pinned sheets, File menu, attività vs task and font-without-token sites still need a decision; PG-265 not fixed, partial: a recount found no icon-only button left without a text or label, two colour swatch pickers (Contenitore inspector, diary sheet) labelled with a selected trait; prose-based UI-test lookups wait for the PG-128 harness consolidation
Dispatch: Round 1: coder — BurnDownResidueTests menu guard (MINOR)
WARN: PG-263 not fixed (partial), left unticked
WARN: PG-265 not fixed (partial), left unticked
INFO: weekday row in the view-block calendar now reads «lun mar …» like the Month view, coder's choice, reversible
INFO: stage docs/plans/burn-down-2026-10-03-pg-263-residual.md at the commit gate, /project-tasks reads its ticks after the merge

```text
DROP	nit	**NIT** .claude/test-timeout is an untracked stray file outside the plan
DROP	out-of-diff	- **MINOR** Sources/Features/Capture/CapturePanelView.swift:99 — folder and note pickers read only the name to VoiceOver, not what the control does (follow-up: coder)
DROP	out-of-diff	- **MINOR** Sources/Features/Pratiche/PraticaMessageRow.swift:384 — shortDayFormatter sets no locale, unlike its neighbours (follow-up: coder)
DROP	out-of-diff	- **MINOR** Sources/Features/DesignGallery/WeekMockup.swift:164 — fourth hand-typed weekday list, probably deliberate in a mockup (follow-up: tester)
DROP	out-of-diff	- **NIT** Tests/PlaudIsolationTests.swift:20 — guard block indented four spaces too far (follow-up: coder)
```
