# ADR-0016: The journal records a gesture, and a gesture may move a file

- Status: accepted
- Date: 2026-08-21. Four questions were put to Stefano before this was written - what the
  journal's unit is, what undoing a deletion means, what happens when a rename fails halfway,
  and which of the three verbs the connectors get. All four are recorded below as answered.
- Supersedes: nothing. **Amends ADR-0007 §D6**, whose journal records one text write per entry,
  and whose "Not in either connector, on purpose" list excludes `note rename|move|trash` for
  exactly the reason this ADR removes.
- Depends on: ADR-0007 (the single write door, the three guardrails, and the exclusion this
  lifts), ADR-0011 §D2 (the per-note history, which is a different net and stays).

## Context

`NoteFileOperations` renames, moves and trashes notes, and rewrites the wikilinks and the board
cards that pointed at them. **It writes with `store.write` directly, so none of it passes through
`VaultSession.write`** - no journal entry, no dry run, no diff. `PG-005` has said so since
2026-08-16, and ADR-0007 drew the only conclusion available at the time: the three verbs are
absent from both connectors, because a write the journal cannot undo is a write a model must not
make.

The journal cannot record them, and the reason is structural rather than an omission.
`WriteJournal.Entry` holds one `path`, one `textBefore`, and two hashes. Three things follow that
it cannot say:

- **A file that moved.** `path` is one string. Undoing a rename means putting a file back where
  it was, which is not a text replacement at any path.
- **A set of files changed by one gesture.** Renaming `Vibrofer` touches the note, every note
  that linked to it, and every board card that pointed at the file. Undoing half of that is
  worse than not undoing at all: the vault ends in a state nobody ever chose, with no record of
  how it got there.
- **A file that is gone.** `textBefore` could hold the text, but there is no entry kind that
  means "this file stopped existing", and `undo` currently refuses even to delete a file that a
  write created.

So the work is not "route three functions through the door". The door is the right shape for a
text write and the wrong shape for a gesture, and this ADR changes the shape.

`PG-019` - dragging a heading in the index to move its section - is in this milestone for a
different reason: it is an ordinary single-file text rewrite that also happens to bypass
`VaultSession.write`. It needs the door, not the transaction. It is named here so it is not
mistaken for a fourth verb.

## Decision

**D1. A journal entry gains an operation id, and the id is the unit `undo` acts on.**

One additive field, `operation: String?`. A gesture opens a transaction, every write inside it
stamps the same id, and `undo <id>` reverses all of them, newest first. Newest-first is not a
detail: `rename` moves the file and then rewrites the links, so the reversal has to restore the
texts before it moves the file back, and the journal's own order already says so.

`operation` is optional and every existing entry has none, which is exactly right - an entry
written before this ADR describes a single write that was its own whole gesture, and
`undo <entry-id>` on it keeps meaning what it meant. **The journal on disk stays readable and no
migration is written.** The alternative - one fat entry carrying a list of files - was refused for
that reason: it is more compact to read and it invalidates every journal already on disk.

A second log file mapping entries to gestures was also refused. Two files that must agree are
two files that will eventually disagree, and the disagreement would surface as an undo that
restores the wrong set.

**D2. An entry says what kind of change it was, because "the text before" cannot describe a move
or a deletion.**

Three kinds, additive in the same way, defaulting to the text replacement every existing entry
already is:

- **a text replacement** - what the journal has always recorded. Undone by writing `textBefore`
  back.
- **a move** - the file went from one path to another and its bytes did not change. Carries the
  path it came from. Undone by moving it back.
- **a removal** - the file went to the Finder's trash. Carries the whole text. Undone by writing
  that text at the path it came from.

A rename is not a fourth kind. It is a move plus a set of text replacements, sharing one
operation id, which is the whole point of D1: the kinds describe what happened to *one file*, and
the id describes the gesture.

**D3. Undoing a removal writes the file back from the journal, and refuses if anything now
occupies that path.**

The file itself is in the Finder's trash and outside this app's control - the trash can be
emptied, and a promise that depends on it is a promise this app cannot keep. So the journal keeps
the text, exactly as it already does for a write, and `undo` recreates the file.

**The refusal is the important half.** If something exists at that path now, the most likely
explanation is that the person already restored it by hand from the Finder, and writing over it
would destroy the thing they recovered. Refusing and saying so is the only correct answer; the
Finder's trash stays the independent human path, and the two nets do not have to know about each
other.

This is the same shape as the guard `undo` already applies to a write, and the reason is the
same: the journal restores only what it wrote, over what it left behind.

**D4. A gesture that fails halfway reports what failed and leaves undo as the remedy. There is no
automatic rollback.**

`NoteFileOperations.Outcome.failures` already exists and already reports the notes whose links
could not be rewritten. That stays, and it is never swallowed: a link left behind is a broken
link, and one nobody was told about is a broken link nobody will find.

**A rollback is code that runs precisely when the disk has already refused something**, and a
rollback that fails in turn leaves a state worse than the one it was fixing, with no record of
how it got there. The transaction from D1 is the better answer to the same problem: everything
that did land is journalled under one id, and `undo` is a deliberate command a person types after
reading what happened, rather than a reflex firing inside a failure.

A pre-flight - checking every target is writable before touching anything - was considered and
refused as a false comfort: it narrows the window between the check and the write, and it cannot
close it.

**D5. Undo is all-or-nothing, and it checks before it moves anything.**

The counterpart to D4, and the one place a pre-flight *is* right. `undo` reads every entry in the
operation and verifies each one's guard **before performing any of them**: the file is still
there, its hash still matches what the journal wrote, and for a removal nothing occupies the
path. If any member fails, the whole undo is refused, naming the file and the reason.

The asymmetry with D4 is deliberate and is the reason both are decisions. A rollback fires inside
a failure, with the machine already misbehaving, and cannot be trusted to complete. An undo is a
command a person typed on a healthy machine; it can afford to look first, and half an undo is the
exact state D1 exists to prevent.

**D6. `VaultSession` grows a transaction scope and two recorded primitives, and everything goes
through them.**

`write(_:to:)` stays as it is. Beside it:

- `transaction(_ command: String, _ body: () throws -> T)` - opens an operation id, stamps every
  write made inside it, closes it. Nested transactions are not a thing; a second call inside an
  open one is a programming error, not a feature.
- `moveFile(from:to:)` and `trashFile(at:)` - the two shape-changing primitives, journalled as
  D2's kinds.
- The board rewrite in `repointBoards` needs a third: a `.canvas` file is not a note and
  `write(_:to:)` reads a `NoteRecord`. It is journalled as a text replacement like any other,
  through whatever primitive that ends up being - the point is that it is journalled, not that it
  reuses the note door.

**`isDryRun` covers all of it or it covers nothing.** A dry run that computes the link rewrites
and then really moves the file is worse than no dry run, because it looks like the safe one. The
diff a dry run produces has to name the move and the removal too, not only the texts.

**D7. All three verbs go to both connectors, with the two locks ADR-0007 already built.**

Absent from `tools/list` without `--allow-write`; `dryRun` defaults to **true**, so a model that
omits it gets a diff and not a change. Plus the journal from D1 and, for `trash`, the Finder's
trash underneath: four nets under the most destructive verb in the app.

The reason ADR-0007 excluded them was never that renaming is too dangerous to automate - it was
that these three "rewrite links across many notes outside `VaultSession.write` and so are not
covered by the journal". This ADR removes that clause, and the exclusion goes with it. Leaving it
in place afterwards would be a rule kept for the shape of its sentence rather than for its
reason.

Stated plainly rather than left implicit: **`trash` reachable by a model is the sharpest edge
this app has**, and it is being handed over deliberately, with the locks named above, not because
it came along with the other two.

## Consequences

- **The journal stops being a list of writes and becomes a record of gestures.** That is a
  bigger claim than it sounds: `journal_log` in the connectors currently prints one line per
  file, and a rename will print several under one id. The reader has to group, or a single
  rename will look like a burst of unexplained writes.
- **`undo` grows a second meaning without changing its name.** Given an entry id it does what it
  always did; given an operation id it reverses a gesture. Two behaviours behind one word, chosen
  over a second command because the person typing it is asking the same question either way.
- **A dry run gets more expensive.** Computing a rename without performing it means reading every
  note that links to the old title, which is the same work the real operation does minus the
  writes. That is the price of a diff that tells the truth.
- **`NoteFileOperations` stops being a struct that writes and becomes one that describes.** Its
  three methods compute what would change; the session performs it inside a transaction. That
  split is what makes `isDryRun` honest rather than a flag each method has to remember.
- **The app arms none of this, as ever (ADR-0007 §D6).** A person editing their own notes gets no
  undo log, and this does not change - except that the three verbs now *can* be journalled, so
  the choice not to is a choice, and the drag of `PG-019` is the first place worth revisiting it.
- **Nothing new is written into a note.** Principle 1 is untouched; the journal lives under
  `.pergamenum/` with the rest of the disposable state, and deleting it still loses nothing the
  vault does not hold.
