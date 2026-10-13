Status: Approved (2026-10-12)

# SPEC — No term proportional to the note on the SwiftUI path of a keystroke (PG-406)

## Destination

A SPEC to hand to `/workplan`. Reaching the end of the work it describes: a keystroke in a 1 MB note on a Release build is usable, because nothing on the SwiftUI update path that follows the editor's binding write (view-input diffing, change detection, outline, dirty flag) costs time proportional to the note, and a bench row that goes through that path says so.

## Objectives

PG-401 and PG-405 made the editor's own work per keystroke independent of the note's size, and measured it with a bench that never goes through SwiftUI. The G-hand-405 check on a Release build with a 1 MB note failed anyway (2026-10-12): the main thread sat in SwiftUI's diff of `VaultController.OpenNote`, whose derived `==` compares the whole `text` through the slow foreign-string path, 50% of 3,214 main-thread samples, 75% inside the graph's value comparison. This SPEC removes that term and the ones that sit beside it in the same path, and puts the path under a measurement so the next regression is caught by a test rather than by a hand check. The person types faster than five keys a second; the per-key cost must stay well under 20 ms regardless of the note's size.

Reading the code (not the profile, which attributes only the top 75%) the same update path also holds these whole-note terms per keystroke: the derived `==` of `NoteTab` (the tab chip takes the tab by value), the backlinks and unresolved-links sections (each takes the open note by value and reads its path and title only), the find modifier's `onChange(of: text)`, the outline parse (`NoteOutline.entries(in:)` plus the `NSRange` conversion) and `foldedOrdinals`, both re-run on every body evaluation, the sidebar outline pane's own parse, and `hasUnsavedChanges` (`text != savedText`), read by the tab chip on every render.

## Scope and non-goals

In:
- Every term above, on the surfaces that share the editor column (Nota, Oggi, Diario).
- A text revision on the open-note buffer and its use for equality and change detection.
- Narrow inputs for the views that read only some of the note's fields.
- An incremental outline store replacing the per-body parse.
- A dirty flag that stops comparing the whole text on the keystroke path.
- A bench row and deterministic counter tests on the real SwiftUI update path.

Out: listed under Out of scope.

## Decisions

- **Perimeter: the whole family of whole-note terms on the update path, not only the `OpenNote` compare.** The measured term is half the profile and the code shows its siblings. Rejected: fix `OpenNote ==` alone — the next hand check would surface the next term and fail again, repeating PG-405's pattern of fixing what the profile named. Rejected: outline and fold in a separate entry — they are per-body parses of the same shape, and the person asked for the typing to be usable now.
- **Mechanism: a text revision on `OpenNote`, plus narrow view inputs.** The revision changes whenever `text` is assigned (bumped where the property is set, so no call site can forget) and is unique per buffer value, so two different buffers never share one. Equality and change detection (`onChange`) use it instead of the `String`. The tab chip, backlinks and unresolved-links sections receive the fields they read, not the note or the tab. Rejected: narrow inputs only — leaves the find modifier and every future compare of `text`. Rejected: revision only — views would keep diffing fields they do not read.
- **Outline: an incremental store, in the shape of ADR-0094's holders.** The heading list shifts by a step on an edit and is replaced only over the dirty range; a structural change (fence, frontmatter, the cases ADR-0091's invalidation rule already names) rebuilds it whole, and `-editorFullRestyle YES` rebuilds it whole every time. Behaviour is identical to today's. The folded-offset to ordinal translation and the sidebar outline pane read the same store. Rejected: reparse deferred to idle — the current-heading highlight and the pane would lag while typing. Rejected: lazy parse on caret change — the caret moves on every keystroke, so the cost stays linear.
- **Dirty flag: exact, verified when typing pauses.** `hasUnsavedChanges` is true as soon as the revision differs from the saved revision (no text compare on the keystroke path); the exact `text == savedText` compare runs when typing pauses, and at save, close and quit, so an undo back to the saved text returns to clean after the pause, as today. The flag may read dirty late; it must never read clean while the text differs from the saved text. Rejected: dirty by revision alone — an undo back to the saved text would stay dirty until saved, which changes ADR-0073's departure 15 and the quit review. Rejected: exact on every keystroke — needs the compare to be constant-time by construction (a native, non-bridged text), which was not shown possible and would need a spike.
- **Acceptance: a bench row through the real SwiftUI update path, plus deterministic counter tests, plus the hand check.** The row runs a keystroke through a real editor column in a hosted window that is never shown, printed for 50 KB, 200 KB and 1 MB, prose and fences; the ceilings are fixed by the person at a gate, as in PG-401. The hand check G-hand-405 is repeated on a Release build. Rejected: counters and hand check only — no number would guard the path. Rejected: hand check only — it is what let this term hide behind a bench that never calls `updateNSView`.
- **The find bar open keeps its linear recompute.** Matches over the note change when the note does; that is the bar's job and it is an explicit mode. With the bar closed a keystroke does no find work.

## Constraints

- **Under 20 ms CPU per keystroke, independent of note size, on the 50 KB, 200 KB and 1 MB synthetic notes** — origin: user mandate (PG-401 and this task), the ceilings themselves fixed by the person at a gate.
- **Typing, caret, undo, IME and marked text, list renumbering and the reveal of markup under the caret behave exactly as today** — origin: user mandate (PG-401).
- **The stored paragraph's length is kept** (a displayed paragraph changes attributes only) — origin: platform (the text content manager's contract), ADR-0082.
- **The golden styler corpus stays byte-identical** — origin: ADR-0082.
- **`ModelSync` (ADR-0094 §D9) stays, and keeps its meaning**: it answers "the view holds what the model holds" without comparing the note. The revision must not make it say yes when the model was replaced from outside — origin: ADR-0094.
- **The 1 MB hand check is done by the person on a Release build, not Debug** — origin: ADR-0082 §D7.
- **A new file under `Sources/Core` must not import SwiftUI**; the new types sit with the editor or the vault layer — origin: ADR-0001 §D1.
- **A test that asserts the old behaviour is restated with the reason said first, never weakened silently** — origin: user mandate (project working agreements).
- **ADR needed**: it extends ADR-0094 §D9 (the compare after the binding write), touches ADR-0073's departure 15 (the dirty flag) and ADR-0091's invalidation rule (the outline store). It stays `planned` until the gates below are answered — origin: `docs/adr/README.md`.

## Stack

Swift 6, SwiftUI and AppKit as today. Swift Testing. The hosted-window harness of the existing in-process tests for the bench row. No dependency added.

## Data model

- **Text revision**: an opaque, equatable value carried by the open-note buffer, changed by every assignment to its text and unique per buffer value; two buffers constructed separately never compare equal by it. The buffer also keeps the revision at which it was last saved.
- **Dirty flag**: derived from the two revisions on the keystroke path; made exact by a check that runs on a pause and at save, close and quit.
- **Outline store**: the note's headings (level, range, ordinal) held as an offset-keyed store with the step-and-splice behaviour of ADR-0094's stores; the fold translation reads it. Its equality to `NoteOutline.entries(in:)` over the same text is the invariant.

## API / interfaces

- The tab chip, the backlinks section and the unresolved-links section take value types holding only the fields they read.
- The find modifier takes the revision, not the text.
- The editor's outline input is the store (or its read interface), not a parsed list rebuilt in the column's body.

## UI flows

Unchanged. The unsaved-changes dot lights on the first keystroke and clears after the pause when an undo returns to the saved text.

## Edge cases

- An external replacement of the text (reload, undo from outside, a catch-up after a write in another column) changes the revision and falls through to the full compare in `ModelSync`, as today.
- Two columns showing one note: each buffer has its own revision; a catch-up assigns the text and therefore bumps it.
- A tab opened or switched: the revision is new, the outline store is built whole.
- A keystroke that opens or closes a fence, touches frontmatter or a setext heading rebuilds the outline whole, like the styler's structural fallback.
- Quit and close ask on the exact dirty state, never the flag alone: a buffer whose pause check has not yet run is verified at that moment.
- A very fast sequence of keystrokes never runs the pause check between keys; the flag stays dirty until the typing stops.

## Test seams

- **Real SwiftUI update path (new row, highest level)**: a keystroke through a real editor column in the hosted window, in the bench with the other rows, printing CPU ms per keystroke for the six cases. Also hosts the deterministic counters: whole-text compares and whole-note outline parses per keystroke are zero.
- **Pure value logic (existing style)**: unit tests on the buffer (revision bump on every assignment, uniqueness across buffers, `==`, the dirty flag with an injected pause), and a property test that after any sequence of random edits the outline store equals `NoteOutline.entries(in:)` of the same text, structural edits included. The pause is injected so no test waits on a timer.
- **Existing**: the styler golden corpus, `ModelSyncTests`, the restyle property test and the quit-review tests keep running unchanged.

## Success criteria

- [ ] R-01 — A keystroke through the real SwiftUI update path of an editor column in a never-shown hosted window is measured for 50 KB, 200 KB and 1 MB, prose and fences, and printed with the bench; the ceilings are fixed by the person at a gate, and the measured cost is under 20 ms CPU per keystroke at every size.
- [ ] R-02 — Per keystroke on that path, the number of whole-text compares and of whole-note outline parses is zero outside the structural fallback, asserted by a counter, not by time.
- [ ] R-03 — Two open-note buffers that differ in text never compare equal by revision, and any assignment to a buffer's text changes its revision, including assignments made by a catch-up from disk or from another column.
- [ ] R-04 — The tab chip, the backlinks section and the unresolved-links section receive inputs that do not include the note text; an edit that changes only the text leaves those inputs equal in constant time.
- [ ] R-05 — With the find bar closed a keystroke does no find work and no text compare; with the bar open the matches are recomputed from the revision change and equal the matches over the same text.
- [ ] R-06 — After any sequence of random edits, including the structural ones (opening and closing a fence or a `pergamenum-view` fence, frontmatter, setext headings), the outline store equals `NoteOutline.entries(in:)` over the same text; with `-editorFullRestyle YES` it is rebuilt whole every time.
- [ ] R-07 — The fold translation (offsets to ordinals) and the sidebar outline pane read the outline store and give the same result as `foldedOrdinals(ofOffsets:in:)` and the pane's former parse over the same text.
- [ ] R-08 — The unsaved-changes flag is true after the first edit without comparing the text; it never reads clean while the text differs from the saved text; after a pause it equals `text != savedText`, so an undo back to the saved text returns to clean; save, close and quit decide on the exact compare.
- [ ] R-09 — Typing, caret, undo, IME and marked text, list renumbering and the reveal of markup under the caret behave as before: the golden corpus (119 cases) is byte-identical and the existing hosted and unit tests pass, any test restated for a new semantic being named with its reason before it changes.
- [ ] R-10 — Oggi and Diario, which host the same editor column, get the same behaviour; one test covers a surface other than Nota; cards keep the whole-text path and are unchanged.
- [ ] R-11 — G-hand-405 passes on a Release build with the 1 MB fences note (type at the end and in the middle, Enter, a wrapping sentence, Cmd+Down, scroll to the end, click low in the pane, undo and redo, an IME composition, near the top then at the end three times), done by the person; a `sample` of the typing shows no frame in a whole-note compare or parse under SwiftUI's update.
- [ ] R-12 — A new ADR records the decisions above, extends ADR-0094 §D9, names the effect on ADR-0073's departure 15 and ADR-0091's invalidation rule, and stays `planned` until R-01's ceilings and R-11 are answered by the person. (no-test: documentation obligation)
- [ ] R-13 — The ledger entry PG-406 is closed by the code PR, and the entry that records the not-passed G-hand-405 is updated to name the repeat. (no-test: process obligation, a ledger edit with no code to test)

## Not yet specified

- How the revision is made unique across buffers in a `Sendable` struct (a process-wide counter, a UUID, a per-buffer identity plus a counter): a plan matter, constrained by R-03.
- How the pause check is scheduled (a restartable timer on the main actor, a run-loop idle hook) and its interval; the SPEC fixes only that it is injectable and that save, close and quit do not depend on it.
- Whether the profile after the fix shows another whole-note term in the 25% of the G-hand sample the existing profile did not attribute. If it does, it is filed as a ledger entry, not folded in here.

## Out of scope

- **PG-408, the first keystroke after a far caret jump** (TextKit's layout of the owed range): a separate cost, profiled and recorded in ADR-0094.
- **PG-407, the whole-note transclusion scan the first keystroke after an open owes**: recorded as closed, not a per-keystroke term.
- **The find bar's recompute while open**: bounded by the bar being an explicit mode (see Decisions).
- **Cards (`CardTextView`)**: they keep the whole-text path, as in PG-401.
- **The acceptance of ADR-0091, ADR-0093 and ADR-0094**: unblocked by this work but flipped in their own docs change after the gates.
- **Any change to the ceilings of PG-401's rows**: G-ceiling-4 is the person's and separate.

## Domain terms

- **Revision**: the buffer-level change marker of this SPEC, not the version history of ADR-0011.
- **Update path**: the sequence that follows the editor's binding write: SwiftUI's diff of view inputs, the column's body, change detection, and `updateNSView`.
