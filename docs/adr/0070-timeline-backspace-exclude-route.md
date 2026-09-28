# ADR-0070: Backspace in the pratica timeline runs the row's own «Escludi», on a route chosen by measuring who holds the key

- Status: **accepted**. Merged to `main` via PR #653 (`b373bade`, 2026-09-28), closing `PG-298`/#642.
- Date: 2026-09-28. Written before the implementation, against `2300f752` (`origin/main`). The
  branch it was read on, `chore/todo-sync-635` at `2a41306a`, has the same tree. Every line number
  below was read from that tree.
- **Numbering note.** `0069` is the highest ADR on `origin/main`. No local or remote-tracking
  branch holds a `docs/adr/007*` file, and `git log --all -- 'docs/adr/0070*'` is empty (checked
  2026-09-28). Check again immediately before the merge (`docs/adr/README.md` §1).
- Source: the `PG-298` entry in `TODO.md` (#642), which is the brief. There is no SPEC: the
  repo-root `SPEC.md` belongs to `PG-257`'s chain and is not this chain's input. Plan:
  `docs/plans/pg-298-timeline-backspace-exclude.md`, which declares R-01 to R-10.
- **Extends ADR-0036 (R-31's «Escludi», and the pratiche plan's rule that Backspace maps to it
  only while the timeline has key focus) and ADR-0023 §D1 (a command is named once and every
  surface runs the same body). Amends none.** ADR-0068 §D12 (the exclusion's own order of writes)
  and ADR-0069 (the chip's AppKit menu) are untouched. No on-disk format, frontmatter key,
  `IndexCache.schemaVersion` (stays 5) or protected interface changes.

## Context

### The defect

With a message row selected in a pratica's timeline, Backspace is answered with the system beep
and nothing is excluded, on a collapsed and on an expanded row alike. «Escludi dalla pratica» from
the row's context menu works. It was found as M9 of ADR-0069's hand checks and reproduced by hand
on the installed 1.9.2, so it predates ADR-0069's overlay.

### Evidence (facts)

- **F1.** `PraticaTimelineView.swift:77-84` binds `.focused($isListFocused)` on the `List`, then
  `.onKeyPress(.delete) { guard isListFocused, excludeSelectedRow() else { return .ignored }; return .handled }`.
- **F2.** The `List`'s selection is a `Binding` over `PraticheController.selectedEntryID`
  (`PraticaTimelineView.swift:90-95`, `PraticheController.swift:211`). Its only other writer in
  `Sources/` is `resetVaultScopedState` (`PraticheController.swift:635`).
- **F3.** `excludeSelectedRow` (`PraticaTimelineView.swift:100-110`) looks the id up in
  `filteredTimeline`, requires `.message`, and calls `actions.exclude(_:detail:)` directly. The
  context menu calls `actions.run(.exclude, on:detail:)` instead (`PraticaMenuItems.swift:50`,
  `PraticaCommandActions.swift:157,174-175`). Both reach the same `exclude` (`:199`).
- **F4.** The timeline carries a Quick Look host: `.quickLook(urls: previewURLs, isPresented:
  $isPreviewing)` (`PraticaTimelineView.swift:54`). `previewURLs` (`:34`) starts empty. A chip
  click or «Anteprima allegato» sets it (`preview(_:)`, `:294-297`), and nothing ever clears it.
- **F5.** That host takes first responder twice over. `makeNSView` makes it first responder
  unconditionally, one run-loop turn after the timeline appears (`QuickLookPresenter.swift:94`).
  `updateNSView` makes it first responder again on every update while `urls` is non-empty and the
  first responder is not an `NSText` (`:105-108`). The host accepts first responder and hands
  every key but space to `super.keyDown` (`:26-37`), which ends in the beep when nothing up the
  chain wants it.
- **F6.** An expanded message's body is selectable text (`MarkdownBlocksView.swift:56,123`,
  `.textSelection(.enabled)`), so a text view can hold focus inside the `List`.
- **F7.** Apple's documentation (read through context7, `/websites/developer_apple_swiftui`,
  2026-09-28): `onKeyPress` acts "when the view has focus"; `onDeleteCommand(perform:)` acts on
  "the system's Delete command, or pressing either the backspace or forward delete keys while the
  view has focus". Two reports from the macOS of 2020 and 2021 (Apple Developer Forums thread
  667366, Swift Dev Journal, 2021-07-01) say that `onDeleteCommand` on a `List` enabled Edit ▸
  Delete but did not answer the key. No newer source was found either way.
- **F8.** ADR-0069's implementation notes (M9): the row showed as selected, the timeline "held key
  focus", nothing was excluded, and the key beeped. The note does not say how focus was judged.
- **F9.** No test exercises Backspace in the timeline (`rg` over `Tests/` and `UITests/`).
- **F10.** The in-process harness cannot deliver this key. `HostedView.key` offers an event to
  `performKeyEquivalent` only (`Tests/HostedViewSupport.swift:164-180`), which neither
  `.onKeyPress` nor `.onDeleteCommand` goes through, and `sendEvent` is refused (ADR-0053 R-15).

### Root cause: what is established and what is not

The ticket names two candidates. Reading adds two more.

- **C1, `@FocusState` never true after a row click** (ticket). No code says either way:
  assumption.
- **C2, the selection never reaches the controller** (ticket). Weakly contradicted, still an
  assumption. M9 saw the row selected, and the highlight is drawn from the binding's getter,
  which reads the controller. A `.tag` dropped by a later modifier would not break it either: the
  `ForEach` identity it would fall back to is the same `String` (`entry.id`), unlike the sidebar
  case CLAUDE.md records for `.badge`.
- **C3, the key never reaches the `List`'s `.onKeyPress`** (not in the ticket). The table behind
  a macOS `List` may send Backspace down AppKit's `interpretKeyEvents` → `deleteBackward:` path,
  where a SwiftUI key-press handler is not asked. Assumption: F7's reports are old and describe a
  different API.
- **C4, the Quick Look host holds first responder when Backspace arrives** (not in the ticket).
  The call is a fact (F5): at appearance, and on every update after the first preview of the
  session (F4). That a row click does not take focus back from it, or that an update runs after
  the click and takes it again, is an assumption. It would explain the beep, both row states and
  the working context menu, and it contradicts only M9's "held key focus" if that meant the
  table was first responder.

C4 is the only candidate with a focus-taking call in the code behind it. None can be settled by
reading, and C1 to C3 depend on SwiftUI behaviour on macOS 27 that no one here has measured.

## Decision

### §D1 — The cause is measured before the route is chosen

A throwaway probe, never committed, records at each Backspace which responder had the key and
which SwiftUI route ran. It logs through `Logger(subsystem: "it.stefer.pergamenum", category:
"pg298")` with `privacy: .public`, since a private interpolation reads `<private>` in `log show`:

1. a local key-down monitor that returns every event unchanged and logs, for key code 51, the
   class of the key window's first responder;
2. the first line of `.onKeyPress(.delete)`: `isListFocused`, `selectedEntryID` and the entry's
   kind, before the guard;
3. a logging-only `.onDeleteCommand` on the same `List`, with the same three values;
4. each of the Quick Look host's two claims (F5), with the first responder it replaced;
5. `.onChange` of `isListFocused` and of `selectedEntryID`.

A probe-only launch argument, `-pg298NoClaim YES`, switches both of the host's claims off. The
plan's Task 1 lists the scenarios (a collapsed row, an expanded row, a row after a Quick Look
preview, each with the claims on and off, the filter field, and selected body text) and the
procedure. The probe's diff is gone before any production change starts.

### §D2 — Backspace runs `PraticaCommandActions.run(.exclude, on:detail:)` on one target door

Whatever the route, its body is the same:

```swift
guard let entry = pratiche.takeDeleteKeyTarget() else { return .ignored }
actions.run(.exclude, on: entry, detail: pratiche.details[entry.id])
return .handled
```

- **The body is the catalogue's.** The key is a third surface for the same command, beside the
  context menu and the footer. ADR-0023 §D1 says a surface calls `run`, never a body it happens to
  share today, which `excludeSelectedRow` does (F3). `excludeSelectedRow` is deleted.
- **One door chooses the target.** `PraticheController.takeDeleteKeyTarget()` applies one pure
  rule, `PraticaTimelineModel.deleteKeyTarget(selectedID:in:)`, to `filteredTimeline`. The target
  is the selected row if it is a message the person can see now. A manual entry, a row the filter
  hides and an id naming no row answer `nil`.
- **The door clears the selection when it returns a target, and leaves it alone otherwise.** The
  exclusion awaits two writes (`PraticaCommandActions.swift:199-242`), and a key repeat or a
  second press lands inside that window. Read from the code, not observed: two overlapping
  exclusions of one message can interleave so that the one whose trash found nothing writes the
  exclusion back out, while the other's files are already in the Trash. Clearing first makes one
  press one exclusion. Moving the selection to a neighbour instead would turn a held key into a
  run of exclusions (G2).

### §D3 — The route, by measured outcome

| Outcome | Seen in the probe | Cause | Fix |
|---|---|---|---|
| A | At the Backspace, the key window's first responder is `QuickLookHostView` | C4 | §D4, plus whatever the same scenario's claims-off run lands on. E there means nothing else is wrong, and the route stays `.onKeyPress(.delete, phases: .down)` |
| B | The first responder is the `List`'s table; `.onKeyPress` did not run; `.onDeleteCommand` did | C3 | `.onDeleteCommand` replaces `.onKeyPress(.delete)` (G1) |
| B0 | The first responder is the table; neither route ran | C3, and no SwiftUI route | Stop. Re-planned with Stefano; A2 below is the candidate |
| C | `.onKeyPress` ran with `isListFocused == false` | C1 | `.onKeyPress(.delete, phases: .down)` without the `@FocusState` guard |
| D | `.onKeyPress` ran, focused, with `selectedEntryID == nil` | C2 | Stop. The selection wiring is re-planned |
| E | `.onKeyPress` ran, focused, a message selected, no beep | not reproduced, when seen with the claims on in every scenario | Stop. The ticket goes back with the evidence |
| F | With the claims off, the first responder at the Backspace is the window itself: a row click selects but gives focus to nobody, and neither route ran | a macOS `List` row click does not make the table first responder | Added at gate G0 (2026-09-28) after the probe landed here. `.onChange(of: selectedEntryID)` sets `isListFocused = true` when a row is selected; then read the row again (measured: B) |

The rows are read on the claims-on scenarios, which is the app as shipped. A claims-off run is
read only to finish an A: it says what is left once the host stops holding the key. The fix is the
union of the rows the scenarios land on, which is why the probe runs each row scenario both ways.

When both routes run, `.onKeyPress(.delete, phases: .down)` is kept. It is the route already
there, it adds no menu surface, and `.down` alone keeps a key repeat out of the handler.
`.onDeleteCommand` is chosen only when `.onKeyPress` never runs, because it brings a second key
(forward delete) and, per F7's 2020 report, an enabled Edit ▸ Elimina, and nobody asked for
either (G1). The probe build carries `.onDeleteCommand`, so the Edit menu's state is read there
rather than assumed.

**The guard.** `@FocusState isListFocused` and `.focused($isListFocused)` are deleted. Both routes
act only while focus is inside the `List`, by their own definition (F7), and the filter field and
the inspector's editor are not inside it. In outcome C the guard is the defect itself. The one
exception is measured, not assumed: if the probe shows a route running while an expanded body's
selected text holds first responder (F6), the route keeps a guard that the probe showed true for a
clicked row and false for selected text. That is `isListFocused` if it qualifies, otherwise the
key window's first responder being the `List`'s table.

### §D4 — On the timeline, the Quick Look host takes focus only to present (outcome A)

Applies only if the probe lands on outcome A.

- `quickLook(urls:isPresented:)` gains `claimsFocus: Bool = true`, and `QuickLookTarget` carries
  it. With the default, the make and update paths do exactly what `QuickLookPresenter.swift:94`
  and `:105-108` do today.
- With `false`, the host claims nothing at make or update. When `isPresented` turns true, it
  records the window's first responder, takes first responder itself (the panel finds its
  controller through the responder chain), and opens the panel. When its control of the panel
  ends (`endPreviewPanelControl`), it hands focus back to what it recorded, but only if that
  responder is still in the window and the host still holds first responder. A click elsewhere
  while the panel was open is never undone.
- The timeline passes `false`. The Workspace board and the editor keep the default. The board has
  no first responder of its own and its bare-spacebar preview depends on the claim
  (`QuickLookPresenter.swift:92-104`, SPEC §6.6). The editor has not been measured.
- "Claim now?" on update becomes one pure function, so the default's behaviour is pinned
  in-process, not only by review.

If `endPreviewPanelControl` turns out not to be sent when Esc closes the panel, the hand-back moves
to the panel's own close callback; the GUI witness in §D5 is what shows it either way.

### §D5 — What is tested where, and the two GUI tests

- **In-process, the merge gate.** `Tests/PraticaDeleteKeyTests.swift` pins §D2's rule and door: a
  visible message, a manual entry, no selection, a filtered-out row, a stale id, the selection
  cleared on a target and kept on a refusal, and a second call finding nothing. For outcome A,
  `Tests/QuickLookFocusTests.swift` pins §D4: the claim policy's truth table (the default's
  answers included) and the record-and-hand-back rule, in a never-shown `NSWindow`, the shape
  `NoteFindTests.swift:280-293` already uses.
- **GUI, two tests in `UITests/PraticheUITests.swift`.** A real key in a key window, through a
  live `List`'s focus and the responder chain, is observable nowhere in-process (F10). So:
  - `testBackspaceExcludesTheSelectedMessageCollapsedAndExpanded`: R-01 and R-02, one launch.
  - `testBackspaceStillExcludesAfterAQuickLookPreview`: R-08. It stays whatever the probe
    finds, because it witnesses the only focus hand-off between two components (the Quick Look
    host and the `List`) that no other test observes.

  `PraticheUITests` is where the pane's selection wiring is already witnessed, and a change under
  `Sources/Features/Pratiche/` already selects it in `scripts/uitests.sh --affected`
  (`:148-149`), so no mapping changes. `AttachmentChipContextMenuUITests` is not touched.
- **By hand.** The beep (R-03), a held key (R-06), the filter field, the inspector and selected
  body text (R-05), and the Workspace and editor previews (R-09). None of these is observable
  from either harness.

### §D6 — The record

The probe's outcome, a short log excerpt and the route chosen go into this ADR's implementation
notes. If the outcome is A or B, the trap is general and CLAUDE.md's working agreements gain one
entry, written for the row measured and no other:

- A: "A Quick Look host that claims first responder takes the keyboard from every `List` beside
  it." Name `claimsFocus: false` as the way out.
- B: "`.onKeyPress(.delete)` on a macOS `List` never sees Backspace." Name `.onDeleteCommand`.
- F (measured together with A and B): "A click on a macOS `List` row selects it but does not make
  the table first responder." Name setting the list's `@FocusState` on selection change.

## Alternatives considered

**A1: a hidden button with `.keyboardShortcut(.delete, modifiers: [])`,** the shape the crop's Esc
and Enter use (`WorkspaceView.swift:365-380`). Rejected. A key equivalent reaches the window's
views before the first responder sees the key, so while enabled it takes Backspace from the filter
field and the inspector's editor. Disabling it outside the timeline needs the very focus signal
whose reliability is the question.

**A2: an AppKit local key monitor,** the shape `ShortcutSettings.swift:144` uses, acting when the
key window's first responder is the timeline's table. Rejected as the first choice. It sits outside
SwiftUI's focus system, the `List` offers no public handle on its table (it would be found by
walking views), and a monitor that outlives its view takes Backspace app-wide. It stays the
escalation for outcome B0.

**A3: drop the key and leave «Escludi» to the menu and the footer.** Rejected. The pratiche plan
(Task 7) and `selectedEntryID`'s own doc comment (`PraticheController.swift:209-210`) promise the
key. And if the cause is C4, the same focus loss also takes the timeline's arrow keys after a
preview, so dropping the key would hide the defect, not remove it.

**A4: for C4, clear `previewURLs` when the panel closes,** so the host stops claiming on update.
Rejected. The claim at appearance (`QuickLookPresenter.swift:94`) would remain, and nothing tells
the timeline that the panel closed: the panel's delegate is the host.

**A5: for C4, change the host's default for every surface.** Rejected. The board's bare-spacebar
preview exists because of the claim, and the editor is unmeasured. Changing two surfaces to fix a
third is outside this ticket.

ADR-0069's A1, rebuilding the timeline as `ScrollView` plus `LazyVStack`, is not reconsidered. Its
rejection holds, and the selection binding this key needs is one of the things it would lose.

## Consequences

### Positive

- The key does what the pratiche plan promised, through the same body as the menu and the footer.
- The key's target rule is pinned in the merge gate, including the filtered-out and repeat cases.
- Outcome A: keyboard focus in the timeline survives a Quick Look preview. That the arrow keys
  come back too is expected, not measured.

### Negative

- Two more app launches in `PraticheUITests`. Each exclusion moves fixture files into the real
  Trash, as `SidebarDeleteUITests` already does.
- Every accepted press clears the selection, including one whose exclusion then fails (for
  example an unparseable dossier, ADR-0068 §D12). The person clicks the row again.
- Outcome A: `Sources/Features/QuickLook/` is unmapped in `scripts/uitests.sh --affected`, which
  therefore answers the whole suite at the merge.
- Outcome B: forward delete excludes too, and Edit ▸ Elimina may become an «Escludi» (G1).

### Neutral

- `PraticaCommandActions.exclude`, `MessageCommand`, the row's menu, the chip's menu, every
  on-disk format and every protected interface are unchanged.
- The Workspace board's and the editor's Quick Look keep the default path.

## Open for Stefano

1. **G1, only for outcome B.** With `.onDeleteCommand`, forward delete also excludes, and Edit ▸
   Elimina may be enabled on a focused timeline and run «Escludi». Recommended: accept. It is
   Mail's own convention for a selected message, and «Annulla Escludi» undoes it.
2. **G2.** After an exclusion the selection is cleared, not moved to the neighbouring message as
   Mail does. Recommended: clear, because a moved selection plus a held key excludes a run of
   messages.
3. **G3.** §D6's CLAUDE.md entry edits a binding instruction file. Its wording is approved at the
   plan's Task 6.

## Implementation notes

**Task 1, the measured outcome (2026-09-28, four probe runs through `scripts/uitests.sh`).**
With the claims on, S1, S2 and S3 land on **A**: at the Backspace the key window's first
responder is `QuickLookHostView`, claimed by `makeNSView` when the timeline appears (it replaced
the window itself), and a row click never takes it back. Neither `.onKeyPress(.delete)` nor
`.onDeleteCommand` ran, and Edit ▸ Delete was disabled. With the claims off, S1', S2' and S3'
land on a row the table did not have, added as **F** at gate G0: the first responder is the window
(`AppKitWindow`), `selectedEntryID` changes on the click but `isListFocused` stays false, and
neither route runs. With the claims off plus `isListFocused = true` set on the selection change,
the first responder becomes the `List`'s table (`SwiftUIOutlineListView`) in all three scenarios,
the Quick Look one included, and at the Backspace **only `.onDeleteCommand` runs** (**B**);
Edit ▸ Delete is enabled. S4: the filter field reads `a`, nothing excluded. S5: with a word of an
expanded body double-clicked, the first responder is `AppKitTextInteractionView`, `isListFocused`
turns true, and no route runs even with `.onDeleteCommand` present, so no guard is kept.

```
[S1] P1 keyDown 51 firstResponder=QuickLookHostView superview=AppKitPlatformViewHost<…QuickLookTarget>
[S1p] P1 keyDown 51 firstResponder=AppKitWindow superview=nil
[S1f] P6 after hop: isListFocused=true firstResponder=SwiftUIOutlineListView
[S1f] P1 keyDown 51 firstResponder=SwiftUIOutlineListView superview=ListCoreClipView
[S1f] P3 onDeleteCommand ran isListFocused=true selectedEntryID=…/email/messaggio-semplice.md kind=message
```

Two probe defects were fixed and rerun, never read as outcomes: the claims-off ids `S1'` to `S3'`
carried an apostrophe, which the argument domain parses as an old-style plist quote, swallowing
`-pg298NoClaim YES`; and one S3f run lost its key lines to the `Stop` hook's unit run overlapping
the GUI run.

**The route chosen (gate G0, Stefano, 2026-09-28): A + F + B.** §D4 as written (the timeline
passes `claimsFocus: false`); `.onChange(of: pratiche.selectedEntryID)` sets `isListFocused =
true` when the new value is non-`nil` (the `@FocusState` stays as a setter, no longer a guard);
`.onDeleteCommand` replaces `.onKeyPress(.delete)`, its body §D2's door plus `run(.exclude)`. G1
accepted: forward delete and Edit ▸ Delete exclude too while the timeline has focus. G2 accepted:
clear the selection.

**Departures from the record (Task 5, 2026-09-28).**

- **§D3's "The guard" paragraph is not followed to the letter.** It deletes `@FocusState
  isListFocused` and `.focused($isListFocused)`. Both stay, as a setter only: row F showed that
  nothing else hands the table the keyboard. Nothing reads `isListFocused` as a guard, and S5
  showed no route running on selected body text, so §D3's one exception does not apply.
- **§D4's record names a text field, not its field editor.** When the responder being recorded is
  a field editor (`NSTextView.isFieldEditor`), `claimFocusForPresentation()` records the editor's
  delegate view instead. The field editor leaves the view hierarchy once the field stops editing,
  so a recorded editor would always fail the "still in the window" check. The record is `weak`,
  and "still in the window" means a view whose `window` is this window, or the window itself (the
  first responder row F measured).
- **§D4, a second claim keeps the first record.** If the host already holds first responder when
  `isPresented` turns true (a second chip click while the panel is open), the earlier record is
  kept, so the hand-back still reaches the `List`.
- **The hand-back is one call in `endPreviewPanelControl(_:)`, on every surface.** It is a no-op
  unless `claimFocusForPresentation()` recorded something, which only `claimsFocus == false` does,
  so the default path is unchanged. That Esc sends `endPreviewPanelControl` is still unmeasured;
  `testBackspaceStillExcludesAfterAQuickLookPreview` is what shows it (§D4's last paragraph).
- **Not named by this ADR: the timeline loses its bare-spacebar re-preview.** Under the old claim,
  once a chip had been previewed the host held the keyboard and a bare space reopened the last
  attachment. With `claimsFocus: false` a space goes to the `List`. The chip click and «Anteprima
  allegato» are unchanged. Read from the code, not observed. Restored after the merge by
  `PG-307`: when nobody held the keyboard before a preview (the window itself was first
  responder, what a chip click leaves), `claimFocusForPresentation()` records nothing, so the host
  keeps first responder once the panel closes and a bare space reopens it; a row click still hands
  the `List` the keyboard (route F). An `.onKeyPress(.space)` on the `List` was tried first and
  never saw the key, since the hand-back went to the window, not the list.
  `testBackspaceStillExcludesAfterAQuickLookPreview` presses the space after the panel closes.
- **Not measured: a Backspace the door refuses.** `.onDeleteCommand` has no handled/ignored
  result, so a refused press (a manual entry, a filtered-out row, a repeat) is a silent no-op.
  Whether SwiftUI still beeps there is left to the hand checks.

**Line drift, against the tree this ADR was written on.** `PraticaTimelineView.swift`: F1's
`:77-84` is now `.focused` `:79`, the selection `.onChange` `:80-82` and `.onDeleteCommand`
`:83-91`; the selection binding `:90-95` is `:97-102`; `excludeSelectedRow` (`:100-110`) is
deleted; `previewURLs` `:34` is `:35`; `.quickLook` `:54` is `:56`, now with `claimsFocus:
false`; `preview(_:)` `:294-297` is `:286-289`. `PraticheController.swift`: `selectedEntryID`
`:211` is `:213`, its doc comment `:209-210` is `:209-212`, `resetVaultScopedState`'s writer
`:635` is `:637`. `QuickLookPresenter.swift`: `keyDown` `:26-37` is unchanged; the make-path
claim `:94` is `:155-157`, the update-path claim `:105-108` is `:168-175`, the board's comment
block `:92-104` is `:150-175`; `endPreviewPanelControl` is `:60-65`; the record and hand-back are
`:67-107`; `claimsFocusOnUpdate` is `:144-148`. The door is
`PraticheController+DeleteKey.swift:17-23`, the rule `PraticaTimelineModel.swift:230-238`.

## References

- ADR-0023 §D1: one catalogue, every surface runs the same body.
- ADR-0036 R-31 and `docs/superpowers/plans/2026-09-09-pratiche.md` Task 7: «Escludi», and
  Backspace only while the timeline has key focus.
- ADR-0053 R-15: no `sendEvent` in-process; `HostedView` reaches `performKeyEquivalent` only.
- ADR-0068 §D12: the exclusion records first and trashes second; untouched here.
- ADR-0069, implementation notes M9: where the defect was seen, and the precedent for a throwaway
  GUI probe class.
- `PG-298` / #642.
