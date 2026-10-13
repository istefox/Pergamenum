Status: Approved (2026-10-07)

# SPEC — Note workflow N3, Links (PG-386, #888)

## Destination

Milestone N3 of `docs/20261003_Pergamenum_NoteWorkflowRoadmap.md` reaches `main` in three sessions,
behind an approved mockup: a link can be peeked at, followed from the keyboard, opened in a tab or the
other column, disambiguated and created from when dangling; the inspector says why a note is linked,
what it fails to link, and where it appears. ADR-0083 and ADR-0084 (already on `main` as `planned`,
written against `48a2d912`) are the decision records: this SPEC re-checks them on current `main` and
names the places they are amended. PG-386 closes, #888 closes.

Reconciliation: this restores the N3 half of the chain SPEC approved 2026-10-04 (R-20..R-28, since
archived under another name when PG-219's SPEC took the root). The criterion numbers are kept because
ADR-0083, ADR-0084 and `docs/plans/note-workflow-n3.md` cite them.

## Objectives

- Follow a link without the mouse, and open it where the person chooses (same tab, new tab, other column).
- Never open a wrong note silently when a title is shared; never lose a typo'd link's intent: offer to create it.
- The inspector gives backlinks their reason (the line, a count, a «strutturale» badge), shows the
  open note's own unresolved links, links an unlinked mention after a diff, removes a structural link
  from both notes, and lists the boards and pratiche that reference the note.

## Scope and non-goals

In: roadmap §N3 tasks 1 to 11 (findings L-1..L-5, L-8, L-9, I-7, and the decision of PG-233); the two
ADRs flipped to `accepted` after the code PR; connector parity for link-mention and structural unlink.
Out: see Out of scope.

## Decisions

Decided 2026-10-04 and re-confirmed 2026-10-07 unless marked **new**.

- **Reuse the planned ADRs and plan, reconcile against `main`** (2026-10-07) — ADR-0083/0084 and
  `docs/plans/note-workflow-n3*.md` already exist. Rejected: rewriting from scratch (discards a
  reviewed decision set).
- **The preview is an `NSPopover`, not a `NeverKeyPanel`** (**new**, 2026-10-07) — the person's
  constraint (PG-258 orphan-window lesson) and the roadmap's wording. This reverses ADR-0083 §D7's
  panel. Rejected: `NeverKeyPanel` (non-key by type, but contradicts the constraint). The cost is
  named: "never first responder" is proved by a test over the popover's behaviour and a presenter
  seam, not guaranteed by the type, and the popover is anchored to the link's rect so it never covers
  the link a Cmd+click is aimed at.
- **The preview appears on Cmd + hover, after a 250 ms dwell, never on plain hover** — the pointer
  resting over text pops nothing; the gesture matches Cmd+click. Rejected: plain hover at 400 ms
  (the roadmap's wording): popovers while reading.
- **One open-link door with a "how"** (`replace`, `newTab`, `otherColumn`): Cmd+click follows;
  Cmd+Shift+click opens in a new tab; Cmd+Opt+click in the other column; Cmd+Opt+Return follows the
  innermost link at the caret and is remappable; the two variants are in Vista with no default key.
  Rejected: Shift+click (extends the selection in a text view).
- **A shared title is a choice, never `.first`** — a menu at the click, a sheet from the keyboard,
  on every surface (editor, Oggi, structural-link sheet, Quick Open). Rejected: a heuristic (same
  folder, most recent): a silent first match with better odds.
- **A dangling link offers «Crea «X»» through the composer**, folder = the source note's; the `[[`
  popup gains the same row when nothing matches. Rejected: creating silently (a typo becomes a file).
- **Backlinks carry the linking line, a count, a «strutturale» badge and a row menu**; the index
  keeps paths only, the line is read on demand and memoised by index generation.
- **Unresolved links are the open note's own**; the vault-wide list becomes a seventh sample view;
  `perg note unresolved` and the MCP tool are unchanged.
- **«Collega» writes only what the diff showed**, `[[Titolo]]` or `[[Titolo|testo]]` when the matched
  text differs from the title (case and accents included); a name inside code is not a mention.
- **«Scollega» is two guarded writes**, `addStructuralLink` inverted, a half-done result named.
- **PG-233 stays as decided 2026-10-03**: a dirty source raises the conflict prompt; the roadmap's
  task 9 "save the buffer first" and report L-5 are not adopted (ADR-0058 Alternative 5, rejected).
- **«Dove compare» is asked for, read-only**, behind a button (it reads every message file).
  Rejected: automatic (a vault-wide read on every note change).
- **Connector parity**: `perg note link-mention`, `perg note unlink-related` and MCP tools
  `link_mention`, `remove_structural_link` ship (writes behind `--allow-write`, `dryRun` default
  true). The roadmap called link-mention "optional"; it is not.
- **Three sessions, three PRs after the mockup PR**: A = pure units, session and connector writes;
  B = the editor (ADR-0083); C = the inspector and the GUI tests (ADR-0084).

## Constraints

- **No cache change**: no new field, `IndexCache.schemaVersion` stays — origin: user mandate, CLAUDE.md principle 3.
- **Every write through `VaultSession` with `expecting:`**; state read before an `await` is re-read
  after it — origin: user mandate, ADR-0043 §D7/§D8, ADR-0057 §D3.
- **No `NeverKeyPanel` for the preview** — origin: user mandate (PG-258).
- **Section row menus hosted outside `List` rows** — origin: ADR-0069 (the inspector is a `ScrollView`,
  so a SwiftUI menu is enough; any `List` row uses the AppKit-hosted menu).
- **The protected pasteboard file is called, never edited** (`linkCharacterIndex(at:)`) — origin: `.claude/protected-interfaces`.
- **Tokens only; file formats untouched; offline** — origin: CLAUDE.md.
- **At most three GUI tests, all on `PergamenumUITestCase`**, each justified in its ADR — origin: user mandate, CLAUDE.md merge-gate rule.
- **A mockup is approved on the Debug build before any view code** — origin: SPEC §11.1, the chain's mockup-first decision.
- **New code goes in new files where `CommandActions.swift` and `VaultController+Tabs.swift` sit at the file-length warning.**
- **The tools' build stays green**: `Sources/Core/Links/` and the connector link writes compile into `perg` and `pergamenum-mcp`; the appearances reader stays app-only.

## Stack

Swift 6, SwiftUI with AppKit for the editor (`NSPopover`, tracking area and a scoped local event
monitor), Swift Testing, the shared connector layer. No new dependency.

## Data model

No new storage. Backlink lines, per-note unresolved targets and «Dove compare» are derived on demand
and memoised by index generation (appearances by path and generation, re-asked by «Cerca di nuovo»).

## API / interfaces

- Open-link door taking a how, used by clicks, the follow command and the backlink menu.
- `ShortcutCommand`: `followLink`, `followLinkInNewTab`, `followLinkInOtherColumn`.
- Session: `linkMention(in:to:expecting:)` with outcomes linked / noMention / movedOn / failed;
  `removeStructuralLink(from:toNoteAt:)`; `addStructuralLink` takes the target as a path.
- Index snapshot: `unresolvedTargets(of:)`, one derivation shared with the query field and the connector read.
- Connectors: link-mention and structural-unlink in the shared layer, exposed by `perg` and MCP.

## UI flows

- **Editor**: Cmd+hover → popover (the target's first twelve lines, its heading section, a board's
  name, a «N note si chiamano» list, or «Nessuna nota…»); Cmd+click / Cmd+Shift+click /
  Cmd+Opt+click / Cmd+Opt+Return; a shared title shows a folder-path choice; a dangling link offers «Crea».
- **Inspector**: BACKLINK rows (title, line, count, «strutturale» badge, menu: Apri, Apri nell'altra
  colonna, Rendi strutturale / Scollega); LINK NON RISOLTI for this note («Crea nota», «Vai al link»);
  unlinked mentions with «Collega» and a diff sheet; «Dove compare» behind «Cerca dove compare».

## Edge cases

- Preview: never takes first responder; closes on Cmd release, pointer leave, Esc, any key, scroll,
  window resign, text change, note change; none for an external URL or a file embed; the event
  monitor exists only while the pointer is inside and its removal is asserted (PG-258).
- Cmd+Opt+Return may collide with a system shortcut: measured before binding, stop if taken.
- Follow with the caret in no link: the command is disabled, not a no-op.
- «Collega» on a note that moved on: refused, the diff recomputed in place; on a vanished mention: dropped.
- «Scollega» whose second write is refused: the first stays, the result names what landed.
- A target not creatable (`[[X.md]]`): «Vai al link» only. A draft parked in the composer is kept and the offer says so.
- Ambiguous pratica references are claimed by neither note in «Dove compare»; an unreadable board is skipped and footnoted.

## Test seams

Existing seams, highest level possible, fewest:

1. Pure units in `PergamenumTests` (Core and connector layer): backlink line finder, unresolved
   derivation (three callers over one corpus), mention rewrite, preview trigger and content, reverse-reason mirror.
2. Session and connector tests: `linkMention`, `removeStructuralLink`, `perg`; `scripts/mcp-smoke.py` after the MCP change.
3. Hosted-view tests for the popover (presenter spy; never-key and monitor lifecycle), the link
   commands and variants, the inspector sections.
4. GUI, three at most: follow from the keyboard then Cmd+[; the preview appears and goes; «Collega» a mention end to end.

## Success criteria

Sessions: **A** = mockup PR, R-29, pure units and writes (R-24..R-28 logic, R-22 choice rule, connectors R-26/R-27);
**B** = R-20..R-23; **C** = R-24..R-28 UI, R-30.

- [ ] R-20 — Cmd+hover over a wikilink shows a preview popover with the target's opening lines (or heading section; a board link shows the board name); it closes on Cmd release, pointer leave and Esc, never takes first responder, leaves no event monitor or window behind, and is never shown for an external URL.
- [ ] R-21 — With the caret inside `[[Nota]]`, Cmd+Opt+Return opens it and Cmd+[ returns; Cmd+Shift+click opens in a new tab, Cmd+Opt+click in the other column; both variants are in Vista and bindable.
- [ ] R-22 — A title resolving to several notes shows a choice of folder paths (a menu at the click, a sheet from the keyboard) in the editor, Oggi, the structural-link sheet and Quick Open; nothing opens the first match silently.
- [ ] R-23 — Cmd+click on an unresolved `[[X]]` offers «Crea «X»» with the composer prefilled in the source note's folder; the `[[` popup shows a «Crea «X»» row when nothing matches and the typed text is a valid title.
- [ ] R-24 — The inspector's backlinks show, per note, the line that links, a count when above one, a «strutturale» badge when the source's `related` names this note, and a row menu (Apri, Apri nell'altra colonna, Rendi strutturale); the index still stores paths only.
- [ ] R-25 — The inspector lists the open note's own unresolved links, each with «Crea nota» and «Vai al link»; the vault-wide list is a sample view; `perg note unresolved` and its MCP tool are unchanged.
- [ ] R-26 — «Collega» on an unlinked mention writes `[[Titolo]]` (or `[[Titolo|testo]]`) in the other note after a diff confirmation, in one guarded write refused when the note moved on; `perg` and MCP expose the same operation.
- [ ] R-27 — The structural-link sheet pre-fills the reverse reason as an editable mirror; «Rendi strutturale» from a backlink row preselects the target; «Scollega» removes the link from both notes in two guarded writes with a half-done result named; a dirty source still raises the conflict prompt (PG-233); `perg` and MCP expose the removal.
- [ ] R-28 — «Dove compare» lists the boards whose nodes point at the note and the pratiche that link it, read-only, each row opens its target; no cache or schema change.
- [ ] R-29 — The N3 mockup (preview popover, backlink rows with badge, per-note unresolved rows, «Dove compare») is approved on the Debug build before any view code is written (no-test: human approval gate on the Debug build, nothing a test can assert).
- [ ] R-30 — No more than three GUI tests, all on `PergamenumUITestCase`; `IndexCache.schemaVersion` unchanged; `PergamenumTests`, `perg` and `pergamenum-mcp` build and pass, `scripts/mcp-smoke.py` passes.
- [ ] R-31 — ADR-0083 §D7 is rewritten for the `NSPopover` and both ADRs flip to `accepted` naming the merge commit, in the first docs change after the code PR (no-test: documentation obligation).

## Not yet specified

_none_

## Out of scope

- **Plain hover preview** — rejected for reading-time popovers; a later ledger entry if wanted.
- **«Rendi strutturale» from the `[[` popup (L-5's Cmd+Shift+K)** — the backlink row covers the gesture.
- **A graph view, block references, table formulas** — as in the chain SPEC.
- **Saving the dirty buffer before «Collega» (L-5)** — PG-233 decided otherwise.
- **Any index-schema or on-disk format change.**

## Domain terms

- **Structural link** — recorded in both notes' `related` with a reason (W-04), as opposed to an inline wikilink.
- **Mention** — an unlinked occurrence of a note's title or alias in another note's prose.
