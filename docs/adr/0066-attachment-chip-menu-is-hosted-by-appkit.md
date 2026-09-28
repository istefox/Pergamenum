# ADR-0066: The attachment chip's context menu is an AppKit menu, because the `List` row's own `.contextMenu` takes every right-click inside the row

- Status: **proposed**, 2026-09-26. The implementation is not on `main`. The status flips to
  `accepted` with the PR and the merge hash once it lands (`docs/adr/README.md` §2).
- Date: 2026-09-26. Written before the implementation, against `1e09448e` (`main`, equal to
  `origin/main`, clean tree). Every line number below was read from that tree.
- **Numbering note.** `0065` is the highest ADR on `origin/main`. `git log --all --oneline --
  'docs/adr/0066*'` is empty, and no local or remote-tracking branch has a `docs/adr/0066*` file
  (checked branch by branch). Check again immediately before the merge (`docs/adr/README.md` §1).
- Source: the `PG-285` entry in `TODO.md`, which is the brief. There is no SPEC: the repo-root
  `SPEC.md` belongs to ADR-0065's chain and is not this chain's input. Plan:
  `docs/plans/pg-285-attachment-chip-context-menu.md`, which declares R-01 to R-06.
- **Extends ADR-0036 (R-27, the chip's menu), ADR-0023 §D1 (one catalogue per command set) and
  ADR-0023 §D9 (an `NSMenu` from `menu(for:)` where a SwiftUI `.contextMenu` cannot reach).
  Amends none.** Reopens nothing: no on-disk format, no frontmatter key, no
  `IndexCache.schemaVersion` change (stays 5), no protected interface.

## Context

### The defect

Right-clicking an attachment chip in a pratica's timeline opens the message row's menu («Apri in
Mail», «Anteprima allegato», «Escludi dalla pratica», «Sposta in…») instead of the chip's own
(«Anteprima», «Apri», «Mostra nel Finder», «Copia»). «Mostra nel Finder» and «Copia» exist only on
the chip, so they cannot be reached at all.

### Evidence (facts)

- `UITests/AttachmentChipContextMenuUITests.swift:57-73` is red. The log of the 2026-09-26 run
  (`pergamenum-uitests-20260926-193441.log` under `$TMPDIR`, partial verdict `322b578…`, `red`)
  shows the right-click synthesized on the chip itself: `Check for interrupting elements affecting
  "pratiche-attachment-4b96b80a3b5fce56-0" Button`, then «Mostra nel Finder» never appears in 5 s.
  The TODO entry records that the failure's UI snapshot shows the message menu open over the chip.
- The test has had no green run since it was added (`b78aee8c`, PR #502, 2026-09-25).
- Both menus are as old as Pratiche. The chip's `.contextMenu` is already in `530e29cc` and the
  row's `.contextMenu { menu(for: entry) }` in `dddd1401`, both 2026-09-10. So the chip's menu has
  never opened in the timeline. PG-134 corrected the titles of a menu nobody could open.
- The chip has exactly one host. `rg 'AttachmentChip\('` over `Sources/` finds only
  `PraticaMessageRow.attachments` (`PraticaMessageRow.swift:135-164`). `PraticaMessageRow` is
  built only by `PraticaTimelineView.row(_:)` (`PraticaTimelineView.swift:124`). No inspector,
  message detail or editor surface builds a chip. The defect has one site.
- `scripts/uitests.sh:147-148` maps `Sources/Features/Pratiche/*` to `PraticheUITests` only. A
  change to the chip therefore never selects `AttachmentChipContextMenuUITests` under
  `--affected`. The class runs only in a full run, which is where PG-284 found it red.

### Root cause: what is established and what is not

Established: inside the timeline's `List`, a right-click on the chip opens the menu of the row the
chip sits in. The chip's own `.contextMenu` (`AttachmentChip.swift:60-68`) never gets the event.
The same behaviour is widely reported: on macOS, a SwiftUI `List` applies a context menu to the
whole row, not to the view that declares it. The `ViewBoundContextMenu` package exists to work
around exactly that. Its macOS implementation is an `NSView` that shows an `NSMenu` from
`rightMouseDown`.

Not established: the mechanism inside SwiftUI (whether it lifts the row's menu into the backing
table view, or merges the nested modifiers). Apple's documentation for `contextMenu(menuItems:)`
and `contextMenu(forSelectionType:menu:primaryAction:)` states no precedence between nested
menus (checked 2026-09-26 through Context7, `/websites/developer_apple_swiftui`).

The decision below does not depend on that mechanism. It takes the right-click away from SwiftUI's
menu resolution before that resolution happens. AppKit hands a mouse-down to the view its
`hitTest` returns, before any ancestor sees it.

## Decision

### §D1 — The chip's menu comes from an AppKit view laid over the chip

A new file, `Sources/Features/Pratiche/AttachmentChipMenuHost.swift`, holds two types:

- `AttachmentChipMenuView`, an `NSView` subclass that answers the context click with an `NSMenu`.
- `AttachmentChipMenuHost`, the `NSViewRepresentable` that places it.

The chip's `.contextMenu` (`AttachmentChip.swift:60-68`) is deleted and replaced by
`.overlay { AttachmentChipMenuHost(...) }`. Two placement rules:

- It is applied **last** in the chip's modifier chain, after `.accessibilityIdentifier(identifier)`
  (`:53`). The representable is then not a descendant of the identified view. On macOS an
  identifier reaches its descendants (ADR-0023's Context, CLAUDE.md), and the UI test finds the
  chip by that identifier.
- It is marked `.accessibilityHidden(true)`.

This is ADR-0023 §D9's move, for the same reason: a SwiftUI `.contextMenu` cannot reach this spot,
so the menu is AppKit's.

### §D2 — The overlay claims the context click and nothing else

`AttachmentChipMenuView.hitTest(_:)` returns the view only when `NSApp.currentEvent` is one of:

- `.rightMouseDown`, or
- `.leftMouseDown` with `.control` in its modifier flags.

For anything else it returns `nil`. A click, a double-click, a hover, a tooltip, a drag or a scroll
therefore finds no overlay and takes exactly today's path: Quick Look on click
(`AttachmentChip.swift:39`), the default app on double-click (`:54`), the `.help` tooltip (`:51`),
the pending popover (`:55-59`) and row selection in the `List`. The pattern of an overlay that
returns `nil` from `hitTest` is already in the tree at `EmbedResizeOverlay.swift:68`.

Implementation rules:

- **A pure predicate.** The decision is a static, pure
  `claimsContextClick(type: NSEvent.EventType, modifierFlags: NSEvent.ModifierFlags) -> Bool`,
  and `hitTest` calls it. The tested function is the production path: no test-only door
  (ADR-0053 §D1).
- **The view shows the menu itself.** `rightMouseDown(with:)`, and `mouseDown(with:)` for the
  Control case, call `NSMenu.popUpContextMenu(_:with:for:)` with the menu `menu(for:)` builds.
  This is the shape `FormattingTextView.swift:194-210` and
  `CompletingTextView+Pasteboard.swift:135` already use. AppKit's implicit dispatch is not
  relied on.
- **The catalogue decides enablement.** `menu(for:)` sets `autoenablesItems = false`, so each
  item's `isEnabled` comes from the catalogue (§D3), not from AppKit's responder validation.
- **Entries are read when the menu opens.** They are a closure the view calls in `menu(for:)`, not
  a value captured at render time, so enablement reflects the file on disk at the moment of the
  right-click.

**Fallback, authorised in advance.** Two observations trigger it:

- hand check M1 or the GUI test (plan Task 7) shows the overlay does not win the right-click, or
- M2, M3 or M5 shows a left click no longer reaches the chip.

In either case the same decision ships in the container shape instead. The AppKit view holds the
chip's SwiftUI label in its own `NSHostingView`, with `\.theme` injected again, and answers the
context click from `menu(for:)`/`rightMouseDown`. This is `ViewBoundContextMenu`'s shape. §D3 to
§D7 are unchanged. The implementation notes record which shape shipped and why. Container sizing
(the chip's intrinsic width against a squeezed header line) is the known cost of the fallback,
and is why it is not the first choice.

### §D3 — One catalogue for all four entries

`AttachmentChipModel.swift` gains three things:

- `AttachmentChipModel.Command`: `preview`, `open`, `reveal`, `copy`. Each has a `title` and an
  `identifier` (`pratiche-attachment-command-<rawValue>`).
- `AttachmentChipModel.MenuEntry`: `command`, `title`, `isEnabled`.
- `AttachmentChipModel.menuEntries(for:state:) -> [MenuEntry]`.

`reveal.title` and `copy.title` are `contextMenuTitles[0]` and `[1]` by identity. This is the
`CalendarDayCommand` pattern (ADR-0023 §D10). `contextMenuTitles` (`AttachmentChipModel.swift:104`)
and its test (`Tests/AttachmentChipTests.swift:171-173`) stay unchanged.

The enablement rules are today's, carried over verbatim from `AttachmentChip.swift:61-67`:

| Command | Enabled when |
|---|---|
| `preview` | `previewURL != nil` |
| `open` | `openURL != nil` |
| `reveal` | `revealURL != nil` |
| `copy` | always |

The four titles, «Anteprima», «Apri», «Mostra nel Finder», «Copia», are declared once there. Two
of them are string literals in the view today.

**Why not `MessageCommand`.**

- The subject is different: one attachment, not one message.
- The rules are different: per-file state, not per-message state.
- A message command such as «Escludi dalla pratica» means nothing on a chip.

**Not reopened.** UX-BLUEPRINT's «Apri con ▸» (`UX-BLUEPRINT.md:73`) is absent today and stays
absent. The wording question in ROADMAP item 6 («Anteprima» on the chip against «Anteprima
allegato» on the row) is not this chain's either. That item's "hand-kept" half closes here.

### §D4 — The row's menu is untouched

These do not change:

- `PraticaTimelineView.row(_:)`'s `.contextMenu { menu(for: entry) }` (`:167`);
- `menu(for:)` (`:175-183`), «Inserisci qui» included;
- `MessageMenuItems` and `MessageCommand`.

A right-click anywhere on the row outside a chip opens the message menu exactly as it does today.
The row's own «Anteprima allegato» stays. One exception, pre-existing and not this chain's: the
expanded body is drawn by `MarkdownBlocksView`, whose text view answers a right-click with its own
standard text menu (Cut/Copy/Paste/Font/Spelling) before the row's menu is asked. That was already
so before this change; §D1's overlay is laid over chips only and does not reach the body.

### §D5 — The chip's commands keep a route that does not need the pointer

Deleting the SwiftUI `.contextMenu` removes whatever "show menu" accessibility action VoiceOver had
on the chip. Whether it had one is not measured: SwiftUI's accessibility tree is not readable
in-process (ADR-0053).

The chip therefore gains `.accessibilityActions`, built from the same `menuEntries`, enabled
entries only. That is one more rendering of the §D3 catalogue, never a second list. It is checked
by hand with VoiceOver (plan M8).

### §D6 — What is tested where

**In-process, in `PergamenumTests` (the merge gate):**

- `menuEntries` over each content and state: a usable file, a missing file, an unusable file, a
  store reference, a pending chip, and a usable script that PG-123 refuses to open.
- `AttachmentChipMenuView.menu(for:)`, called directly with a synthesized `.rightMouseDown`. This
  is the `WikilinkContextMenu` precedent (`Tests/WikilinkClickNavigationTests.swift:190-279`):
  no `sendEvent`, so ADR-0053's R-15 holds. The test covers titles, order, enabled flags and
  identifiers, and checks that each item's action reaches `perform` with its own command.
- The `claimsContextClick` truth table.
- **Only if the harness allows it:** a hosted `AttachmentChip` whose AppKit menu view is found in
  the hosting view's subviews. This is the check that fails if someone puts a SwiftUI
  `.contextMenu` back. A hosted `PraticaMessageRow` carrying one menu view per chip, each narrower
  than the row, is the R-02 guard. Whether `HostedView` instantiates a representable offscreen is
  measured in plan Task 1, not assumed. No test in `Tests/` does this today. If it does not, these
  two tests are not written. No test asserts that the harness cannot do something (ADR-0053's
  rule), and the measurement goes into this ADR's implementation notes.

**GUI only:** which menu a real right-click opens inside a real `List`. The in-process harness
cannot deliver a pointer event (`Tests/HostedViewSupport.swift:75-79`).
`AttachmentChipContextMenuUITests` keeps its test and it is strengthened: all four titles present,
«Escludi dalla pratica» absent. It gains one method for R-02: a right-click on the subject, in the
same header line as the chip, opens the message menu and not the chip's.

**GUI budget (CLAUDE.md: at most two or three per feature, each justified in its ADR).** That
makes three GUI tests for this fix. The first two halves are the precedence between two menus in a
live `List`, the one fact no test here can observe in-process. Both halves regressed with nothing
noticing for sixteen days. The third, `testLeftClickOnPendingChipOpensThePendingPopover`, closes the
one gap the plan itself named and left open (F11, §D2's own "Negative" consequence): whether the
overlay's `hitTest` really lets a plain left click through to the chip once every chip in the
timeline carries one. Nothing in-process drives a pointer event at all (`Tests/HostedViewSupport
.swift:75-79`), so the pass-through is either witnessed here or nowhere, and it is the one
mechanism this chain shipped without verifying in advance. A `.pending` chip's own popover
(`AttachmentChip.isShowingPendingExplanation`) is the cheapest observable proof: it needs nothing
but a click and a static text, no Quick Look panel or `NSWorkspace` launch to reconcile with.

**`--affected` mapping.** `scripts/uitests.sh`'s `classes_for_path` maps
`Sources/Features/Pratiche/*` to `PraticheUITests AttachmentChipContextMenuUITests`. The merge-time
`--affected` run then selects the witness of the code it changed.

### §D7 — The rule for the next nested menu

The rule: a view inside a `List` row that carries its own `.contextMenu` cannot have a working
SwiftUI `.contextMenu` of its own. It gets an AppKit-hosted menu in this ADR's shape. It is
recorded as a CLAUDE.md working agreement beside the `DisclosureGroup` one (plan Task 6, a human
approval).

The types stay in `Sources/Features/Pratiche/` while they have one consumer. A second consumer
moves them to `Sources/DesignSystem/` and generalises the entry type. That is not done now: there
is no second consumer, and `Sources/DesignSystem/**` maps every change to a full UI run.

The rest of the app was not audited exhaustively. Spot checks found this shape nowhere else:

- `DayReferences.swift:96` and `LinkedTasksPanel.swift:96` put their menu on the row itself.
- `DayTimeline.swift:61` sits beside `TimelineBlockBox`, not around it.
- `NoteListPane.swift:344` is the reverse nesting (a menu on the `List`, menus on its rows).
  With folders shown and no filter (`NoteListPane.swift:166`), `SidebarDeleteUITests` right-clicks
  a `note-row-*` element (`NoteTreeRow.swift:234`) and reaches the row's own «Elimina…». That
  suggests a `List`-level menu yields to a row's; it is not measured separately here.

The remaining sites are filed as a follow-up ticket rather than left unmentioned.

## Alternatives considered

**A1: rebuild the timeline as `ScrollView` plus `LazyVStack`.** This is the workaround most reports
suggest. Rejected. The timeline depends on:

- `List(selection:)`, whose selection binding the row commands share (`PraticaTimelineView.swift:90-95`);
- `.focused` and `.onKeyPress(.delete)` for «Escludi» (`:77-84`);
- `.defaultScrollAnchor(.bottom)` (`:76`);
- the day `Section` headers and the `List`'s row culling.

Rebuilding all of that to fix one menu puts more at risk than the defect does.

**A2: one row menu whose content follows the chip under the pointer.** The chips would publish a
hover state, and the row menu, the one the `List` honours, would draw the chip catalogue while a
chip is hovered. Rejected for three reasons:

- The choice would rest on a hover state, not on the click's own location.
- A hover state goes stale when content scrolls under a still pointer, and a stale one opens the
  wrong menu over the wrong element.
- Every chip hover would change a timeline-wide `@State`, and with it the whole `List` body.

**A3: move the message menu off the row.** Either onto the `List` through
`contextMenu(forSelectionType:)`, or onto a sibling background layer. Rejected:

- The evidence that the row's menu wins says nothing about whether a `List`-level menu would
  yield to a nested one.
- Apple documents no precedence.
- The reports describe a nested `.contextMenu` being applied to the whole row. Without the row's
  own menu, the chip's menu risks taking over the whole row instead.

A design whose correctness rests on an undocumented precedence rule has the same shape as the
defect.

**A4: fold the chip's commands into the row menu, as one submenu per attachment** («nota.txt ▸
Anteprima / Apri / …»). Rejected:

- It fails R-01 as stated: a right-click on the chip must open the chip's menu.
- A message with five attachments would carry five submenus in a menu that already has eight
  entries.

**A5: draw the whole chip in AppKit.** Rejected. It loses the token-driven SwiftUI drawing
(`themedText`, `theme.color`), which CLAUDE.md's design-system rule binds, along with the chip's
`.popover` and `.help`. §D2's fallback keeps SwiftUI drawing the chip if the overlay fails.

**A6: keep the SwiftUI `.contextMenu` beside the AppKit menu, for accessibility.** Rejected. A
second rendering nobody can open with the pointer is exactly how PG-134's fix went unobserved.
§D5 gives the non-pointer route explicitly instead.

## Consequences

### Positive

- The chip's four commands are reachable, and «Mostra nel Finder» and «Copia» become reachable
  for the first time since 2026-09-10.
- Enablement is evaluated at the right-click, against the file on disk then, not at the last
  render.
- All four titles have one naming site. ROADMAP item 6's "hand-kept context menu" closes.
- A revert, or a drift of the catalogue, is caught by the unit suite. The GUI suite is not needed
  for that.
- `--affected` at merge now selects the chip's witness for any Pratiche change.

### Negative

- The fix is an AppKit shim that reads `NSApp.currentEvent` inside `hitTest`. It relies on AppKit
  setting the current event for every event it dispatches.
- A future SwiftUI change to how representables are hit-tested could break the left-click
  pass-through. `testLeftClickOnPendingChipOpensThePendingPopover` (§D6) now witnesses it for a
  plain left click; the double-click (M3) stays a hand check.
- A right-click on a chip no longer draws the `List`'s clicked-row ring. The menu is about the
  chip, so the ring was never correct there.
- `AttachmentChipContextMenuUITests` holds three tests, which means three app launches, and it now
  runs on every Pratiche change.
- `.accessibilityActions` calls `menuEntries` in `body`, which adds four file-state probes per
  render beside the six the chip already makes. Each probe reads a prefix and a suffix, never the
  whole file (ADR-0040 §D8).

### Neutral

- The row's menu, `MessageCommand`, every on-disk format, `IndexCache.schemaVersion` and every
  protected interface are unchanged.
- UX-BLUEPRINT's «Apri con ▸» is still not implemented.

## Implementation notes

- **Shape: the overlay ships.** The overlay shape (§D1, §D2) is implemented; the container
  fallback is not needed. On 2026-09-27/28 `AttachmentChipContextMenuUITests` ran green through
  `scripts/uitests.sh` (all three tests). The plan's hand checks were automated in a throwaway GUI
  class run through the same script and then deleted, never committed. Outcomes:
  - green: M1 (usable chip, four entries enabled), M1b (pending chip, only «Copia» enabled), M1c
    (store reference with a missing `storePath`, only «Copia» enabled), M2 (left click opens Quick
    Look), M5 (left click on a pending chip opens its popover, now permanent), M6 on the subject,
    sender, footer and note slot (message menu, «Inserisci qui» included), M7 (Ctrl+click opens the
    chip's menu);
  - M6 on the expanded body: the text view's own menu opens, pre-existing and outside the overlay
    (§D4's exception); the plan's expectation for the body was wrong, not the code;
  - M9 (select a row, then Backspace): the row was selected and the timeline held key focus, yet
    nothing was excluded, on a message with no attachment, so no overlay in its row and no file
    this chain touched. Not caused by this change: reproduced by hand on the installed 1.9.2,
    which predates it, on a collapsed and on an expanded message alike. The key is answered with
    the system beep, so `PraticaTimelineView`'s `.onKeyPress(.delete)` returns `.ignored` and
    `exclude` is never reached; «Escludi» from the row's menu works. Tracked as `PG-287`;
  - not run: M3 (double-click opens the default app), M4 (tooltip), M8 (VoiceOver actions).
- **Hosting a representable offscreen: measured positive.** `HostedView` (`Tests/HostedViewSupport.swift`)
  does instantiate an `NSViewRepresentable` offscreen. After `settle()`, an
  `AttachmentChipMenuView` is found in `host.hosting`'s subview tree: exactly one for a hosted
  `AttachmentChip`, and exactly three for a hosted `PraticaMessageRow` with one file, one store
  reference and one pending chip, each narrower than half of an 800 pt row. Before Task 3 wired
  the overlay, the same lookup found none, so the hosted tests are the ones that fail if a
  SwiftUI `.contextMenu` replaces the AppKit menu. F8's "no test has ever found a representable's
  `NSView` inside a `HostedView`" was a gap, not a limit. Both hosted groups (plan Task 1, groups
  3 and 4) are written, in `Tests/AttachmentChipMenuTests.swift`
  (`AttachmentChipHostedMenuTests`).
- **Line drift.** The chip's deleted `.contextMenu` was `AttachmentChip.swift:60-68`. In the new
  tree, `.accessibilityIdentifier(identifier)` is at `:62`, `.accessibilityActions` (§D5) at
  `:64`, the overlay at `:77` and `run(_:)` at `:171`. `AttachmentChipModel.contextMenuTitles`
  stays at `:104`; `Command` is at `:109` and `menuEntries(for:state:)` at `:137`.
- **Additions beyond the plan's list.** One in-process test the plan did not list,
  `entriesAreReadWhenTheMenuOpensNotWhenTheViewIsBuilt`, pins §D2's "entries are read when the
  menu opens" rule. The `claimsContextClick` truth table also covers `.rightMouseDown` with
  Control, `.leftMouseDown` with Control and Shift, and `.leftMouseUp`.

## References

- ADR-0023 §D1, §D9, §D10: one catalogue; an `NSMenu` from `menu(for:)`; titles by identity.
- ADR-0036 R-27; ADR-0040 §D8: the chip's decisions live in `AttachmentChipModel`.
- ADR-0053 §D1 and R-15: no test-only door; no `sendEvent` in-process.
- PG-134 (PR #502, `b78aee8c`): added the GUI test that exposed this defect.
- PG-284: the run that found it red.
- `ViewBoundContextMenu` (github.com/MrAsterisco/ViewBoundContextMenu), read 2026-09-26. Its
  README describes the whole-row behaviour; its `AppKit/NSContextInteractableView.swift` shows the
  container shape §D2's fallback uses.
