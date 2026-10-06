Status: Approved (2026-10-05)

# SPEC — A conflicted board or diary is asked about at quit (PG-336)

## Destination

A SPEC handed to `/workplan`, which derives the ADR PG-336 asks for ("needs its own ADR") and the
plan. Reaching the end means: on any termination, a Workspace board or a diary day that is in
conflict is named in the quit question like a conflicted note is, and the app never exits over its
unsaved edits without the person having chosen to lose them. Closes the ledger entry `PG-336`
(issue #729) and ADR-0073's gap G-c.

## Objectives

Today Cmd+Q, the red button on the last window, a logout or a restart over a board or a diary in
conflict exits at once and the edits held in memory are gone, with no question. The conflict was
reported when it began (a problem line), but a person who did not read it loses the work on the way
out. The aim is the same promise ADR-0073 makes for notes: no termination drops unsaved work
without asking.

## Scope and non-goals

In: the quit path only (everything that reaches the application's terminate hook): the open
Workspace board and the diary day, when each is in `.conflicted`.
Out, one line each: window close and vault switch; "Chiudi la colonna"; any recovery copy of
discarded text; writing over the other writer's bytes at quit; changing the buttons or the words
for notes; the blind Cmd+S write (ADR-0073 G-d). Detail under Out of scope.

## Decisions

- **Option B of PG-336: a conflicted board or diary joins the quit review.** The question names it
  next to the dirty notes and schede, and the quit waits for the answer before anything replies.
  Rejected: **C, write a conflict copy at quit** — it puts a file nobody asked for into the vault
  (or beside the diary's day files) and needs a naming rule, a way to find it again and a cleanup,
  to rescue text the person can also choose to keep. Rejected: **A, keep the exit silent and record
  the loss durably** — it documents the loss and does not prevent it, and the existing problem line
  already does the documenting.
- **The conflict rule for notes is the rule for these two.** A conflicted note is named, is never
  written by the bulk answer, cancels the quit when «Salva» leaves it, and is let go only by
  «Non salvare» (ADR-0073 §D5, F5). The board and the diary take that exact treatment, so a person
  learns one behaviour. Rejected: **«Salva» overwriting the other writer's bytes** — it contradicts
  ADR-0054 §D5 ("quitting does not overwrite the other writer's bytes") and is what the banner's
  «Mantieni le mie modifiche» is for, chosen deliberately on the banner, not implied by a quit.
- **«Non salvare» is a plain discard, with no safety copy.** The question already says the edits are
  lost, as for a note or a vanished scheda. Rejected: **a copy under the app's state directory** —
  it is option C moved out of the vault, with the same naming, expiry and discoverability costs.
- **The three buttons stay, also when only a conflicted board or diary is in the review.** «Salva»
  then writes nothing, cancels the quit and shows the banner, the way a lone conflicted note
  behaves today. Rejected: **hiding «Salva» when nothing is saveable** — it changes the alert for
  notes too, which widens the work beyond PG-336.
- **Only the quit passes them to the review.** The vault switch and "Chiudi la colonna" build the
  same review without a board or a diary, as the Contenitore schede are passed by the quit alone.
  Rejected: **extending the rule to window close and vault switch** — it reopens ADR-0054 §D5's
  stated reason for not blocking a window close over a conflict, and G-a, each a decision of its
  own.
- **This is not a reversal of ADR-0054 §D5 or ADR-0066 §D5.** The board is still not flushed over a
  conflict at quit and `detach()` is untouched; what changes is that the quit asks before the edits
  are dropped. The block is one click deep: «Non salvare» lets the app go. The ADR records this as
  extending ADR-0073 and ADR-0066 §D5, amending neither.
- **Where the person is taken on a cancel.** The first unresolved item, in this order: the board,
  then dirty notes, then the diary (amended 2026-10-05 at /workplan, gate G1: the open board's
  controller lives only while the Workspace pane is on screen, so revealing the Note pane first would
  destroy the very board the question protected). A board opens the Workspace pane on its banner; a
  diary opens the Diario pane on its banner. A cancel with nothing else unresolved reveals the item
  the question named first, and the question lists items in the same order.

## Constraints

- **Nothing is written over a conflicted file at quit** — origin: existing ADR-0054 §D5, ADR-0057 §D6.
- **One reply, one door** — origin: existing ADR-0073 §D1: the question is asked inside
  `QuitCoordinator`, never from the willTerminate notification.
- **No timer runs while the question is on screen; the fail-safe note-save cap (10 s) and the
  fail-open diary cap (2 s) are unchanged** — origin: existing ADR-0073 §D6, ADR-0060 §D2.
- **No on-disk format, schema, frontmatter key or protected interface changes** — origin: user
  mandate for this ledger entry (a fix, not a new format) and the binding principles in CLAUDE.md.
- **Foundation-only shapes stay out of `Sources/Core`** — origin: ADR-0073 §D9: the review is
  app-only because it reads app types.

## Stack

Swift 6 strict concurrency, SwiftUI/AppKit, Swift Testing. No new dependency.

## Data model

No stored data. The quit review gains two optional items beside its notes and schede: the open
board when its save state is conflicted, and the diary day when its save state is conflicted. Each
carries what the question names (the board's name, the day) and what the last check compares (see
Edge cases). Nothing is persisted.

## API / interfaces

- The review is built from the notes, the schede and now the two conflicts; only the quit passes the
  two new inputs (the others default to none, like the schede).
- The coordinator asks the board and the diary controller whether each is conflicted, through the
  same closures it already receives for them, and reveals through two new reveal closures (board,
  diary), required rather than defaulted, as the Contenitore's is.
- The words of the question (`QuitReview.copy`) name each item and say, for each, that the file
  changed on disk, that «Salva» keeps the app open to choose a version, and that «Non salvare» loses
  the edits.

## UI flows

1. Cmd+Q with a conflicted board and/or diary (and possibly dirty notes): one app-modal question
   lists everything unresolved, then the three buttons.
2. «Annulla»: the quit is cancelled and the first unresolved item is shown on its banner.
3. «Salva» / «Salva tutto»: notes that can be saved are saved; the conflicted board and diary are
   not written; the quit is cancelled, a problem line names what was left, the first unresolved item
   is shown.
4. «Non salvare»: the app quits, the conflicted board's and diary's files are untouched on disk.
5. No conflicted board or diary, no dirty note, no scheda owed: the quit is exactly as before, no
   question.

## Edge cases

- A diary write refused while «Salva tutto» is settling the diary turns the diary conflicted during
  the quit; the last check treats it as uncovered, cancels and shows the Diario pane.
- Covered means the snapshot's conflict: an item conflicted in the snapshot and still the same is
  covered by «Non salvare»; a board or day that became conflicted after the question, or whose
  in-memory content differs from the snapshot, is uncovered and cancels the quit (ADR-0073 §D7's
  rule, applied to the two new items).
- A conflicted diary day whose day file is also open in a dirty note tab: both are named, each by
  its own noun; the existing order (diary settles before the notes) is unchanged.
- No board open, or a board that is not conflicted: nothing for the board. A diary that is
  conflicted without a vault open cannot happen (the vault-less diary reads as saved).
- A conflicted note, a vanished scheda and a failed scheda write keep their words and behaviour.

## Test seams

Existing seams only, no GUI test (CLAUDE.md caps GUI tests at two or three per feature and this one
needs none):
- `QuitReview` (pure): names, counts, copy and coverage of the two new items; the vault-switch and
  column-close reviews unchanged.
- `QuitCoordinator` (every AppKit effect already a closure): the question being asked, the three
  answers, the last check, the reveal order and the cap behaviour.
- The conflict state of the board and of the diary is read through their existing observable
  save-state; its tests are the ones already beside them (the diary's conflict tests and the
  board's conflict tests).

## Success criteria

- [ ] R-01 — A quit with the open board in conflict builds a review that names the board; it is not empty and the question is asked.
- [ ] R-02 — A quit with the diary in conflict builds a review that names the diary day; it is not empty and the question is asked.
- [ ] R-03 — With no dirty note, no owed scheda, and neither board nor diary in conflict, the quit behaves exactly as before: no question, same reply (ADR-0073 R-10 holds).
- [ ] R-04 — The question's text says, for each conflicted board or diary, that the file changed on disk, that «Salva» keeps Pergamenum open to choose a version, and that «Non salvare» loses the edits; the counted noun in the message covers boards and diaries beside notes and schede.
- [ ] R-05 — «Annulla» cancels the quit and reveals the first unresolved item: the board's banner first, then the notes, then the diary's banner (order amended at /workplan, gate G1).
- [ ] R-06 — «Salva» and «Salva tutto» never write a conflicted board or diary; with either left, the quit is cancelled, a problem line names it, and the first unresolved item is revealed.
- [ ] R-07 — «Non salvare» lets the app quit with the conflicted board's and diary's files byte-identical on disk and creates no file anywhere.
- [ ] R-08 — The last check before letting go cancels the quit and reveals the item when a board or diary is conflicted that the answered snapshot did not cover (conflict entered during the quit, or content changed since the question).
- [ ] R-09 — The vault switch and "Chiudi la colonna" reviews are unchanged: they never contain a board or a diary item.
- [ ] R-10 — Every existing quit test for conflicted notes, vanished schede and failed scheda writes passes unchanged.
- [ ] R-11 — No timer runs while the question is on screen; the 10 s note-save cap and the 2 s diary cap behave as before.
- [ ] R-12 — The new ADR extends ADR-0073 and ADR-0066 §D5, amends none; ADR-0073's gap G-c is marked closed with a pointer, and CLAUDE.md's chain index gains its line. (no-test: documentation obligation)

## Not yet specified

_none_

## Out of scope

- **Window close and vault switch over a conflicted board** (`detach()`, ADR-0054 §D5; G-a): that
  decision's stated reason is about refusing to close a window, a different cost from asking at
  quit. Left as is.
- **"Chiudi la colonna"**: already handled by PG-335 for dirty notes; it never touches the board
  or the diary.
- **A recovery copy of discarded text** (option C, or a state-directory copy): rejected above.
- **Writing the in-memory version over the other writer at quit**: the banner's verb, not the
  quit's.
- **The words and buttons for conflicted notes**: unchanged; only the new items are added.
- **Cmd+S over a waiting banner** (ADR-0073 G-d): existing behaviour, a separate ledger matter.

## Domain terms

- **Conflict** (board, diary): the file on disk changed under the edits held in memory, so the
  guarded write was refused and the edits wait in memory, with a banner offering «Mantieni le mie
  modifiche» or «Ricarica dal disco» (ADR-0054 §D5, ADR-0057 §D6). Not the same as a dirty buffer:
  a conflicted item cannot be saved without the person choosing a version.
