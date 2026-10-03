Status: Approved (2026-09-30)

# SPEC — Pratiche: manual entries anchored to a message (PG-338)

## Destination

An approved SPEC handed to `/workplan`: a manual entry in `pratica.md` can be anchored to one
message of the pratica by its Message-ID, and the timeline draws it directly under that message,
the last row included. `/workplan` decides the ADR (expected: new, extending ADR-0036 and amending
its §D5) and how many PRs this takes.

## Objectives

Stefano wants to annotate a specific email of a pratica («ho chiamato dopo questa mail», «confermano
la consegna») and see the note next to that email, not at the moment he happened to write it. Today
every manual entry is placed by its heading timestamp, which is the time of writing: a note written
today about last week's email lands at the bottom of the pratica, and «Inserisci qui» cannot reach
the space after the last message at all.

## Scope and non-goals

In:
- Creating a Nota or Telefonata anchored to a message, from every message row, the last one
  included.
- Anchoring an existing manual entry to a message, re-anchoring it, and unanchoring it.
- Timeline placement, filter visibility and orphan fallback of anchored entries.
- What Escludi, «Sposta in…», «Aggiungi anche a…», their undos and «Rigenera» do to anchored
  entries.
- Concealing the anchor line in the editor of `pratica.md`.
- Connector parity: one parser, one ordering rule, the anchor exposed read-only.

Out (detail in Out of scope): connector writes, drag-to-anchor, copying entries on «Aggiungi anche
a…», migrating existing files, the same-minute midpoint collision of «Inserisci qui», the
unimplemented click-to-jump on entry rows.

## Decisions

- **The anchor is a comment line under the heading carrying the Message-ID** — the line
  `<!-- pergamenum-message: <Message-ID> -->` is the first line after the entry's heading. The
  Message-ID is already the identity the ledger and the dossier's included/excluded lists use, it
  survives «Rigenera», a file rename and a move, and keeping it off the heading keeps the heading
  and the outline clean. Rejected: a wikilink to the message file as first body line — clickable
  and rename-safe through ADR-0049 §D2, but a title is ambiguous after «Aggiungi anche a…», and a
  file renamed outside the app breaks it. Rejected: both carriers — two sources of truth that can
  disagree and need a precedence rule.
- **The heading keeps the time of writing** — an anchored entry's heading timestamp records when
  the note was written, as for any entry; its position comes from the anchor alone, and the
  daily-note mirror (R-29 of the Pratiche spec) goes to the day of writing. Rejected: copying the
  message's minute into the heading — a reader without anchor support would see it nearly in place,
  but the record of when the note was written is lost and the mirror line would land in the
  email's day.
- **Drawn in the message's lane** — an anchored entry sits under its message in the same lane
  (left for received, right for sent) at the lane's width, indented, in the manual-entry colour.
  Rejected: full width like free entries — the link to the email would show only through position.
- **Created from every message row, as Nota or Telefonata** — «Aggiungi nota» and «Aggiungi
  telefonata» on every message row's context menu and expanded footer, through the message command
  catalogue (ADR-0023). Rejected: Nota only — the composer already supports both kinds at no extra
  cost.
- **Escludi leaves the entries in place, orphaned** — no text is ever removed; the anchor line
  stays, the entry falls back to its heading timestamp with a caption, and undoing Escludi
  re-anchors it with no write. Rejected: asking first — same outcome, more friction. Rejected:
  removing the entries with the message — a command must never delete handwritten text.
  *Amended 2026-10-03 (ADR-0079): the entries are hidden while the message is excluded, not
  shown as orphaned with a caption; undoing Escludi still anchors them again with no write.*
- **«Sposta in…» carries the entries, «Aggiungi anche a…» does not** — a move is usually a
  correction (the email was in the wrong pratica), so every entry anchored to the moved message is
  removed from the source `pratica.md` and appended to the destination's, and the undo carries
  them back. A copy leaves them only in the source. Rejected: entries always stay — the note
  separates from its email. Rejected: copy duplicates them too — two copies of one note diverge.
- **Carrying is append-then-remove** — the entries are appended to the destination first and
  removed from the source only after that write landed. A refused destination write leaves the
  message moved and the entries orphaned in the source, and says so; a refused source write leaves
  the entries in both files, and says so. Text is never lost; the worst case is a declared
  duplicate. Rejected: all-or-nothing — a note would block moving an email.
  *Amended 2026-10-03 (ADR-0079): the entries left in the source are hidden there, not orphaned,
  because the source excludes the moved message; the reported sentences are unchanged.*
- **The anchor line is concealed in the editor** — with «Nascondi markup» on, the line collapses to
  a small marker and reveals its raw text when the caret enters it, like every other concealed
  construct (ADR-0029); with the setting off it stays raw. Rejected: raw but dimmed, and raw
  unchanged — a long technical line would sit in view in every anchored entry.
- **An anchored entry follows its message through filters** — it is visible only when its message
  is visible; under the text filter, an entry that matches brings its message with it. Rejected:
  the current free-entry rule (hidden only by the text filter) — under «Solo con allegati» or the
  sender filter a note would float with its email gone.
- **Connectors expose the anchor and share the ordering** — the timeline payload gains the anchor's
  Message-ID, anchored entries are ordered as in the app, and the tie-break that differs today (the
  app puts a manual entry before a message at an equal instant, the connector the reverse) is made
  one rule. Rejected: order only, no field — a reader sees the position but not the link. Rejected:
  no change — the connector would place anchored entries at their writing time.
- **Existing entries can be anchored, re-anchored and unanchored** — «Collega a un messaggio…» on
  any manual entry (free, anchored or orphaned) opens a picker of this pratica's messages and
  writes or replaces the anchor line; «Scollega dal messaggio» on an anchored or orphaned entry
  removes it. Rejected: out of scope — the user wants old entries reachable. Rejected: manual
  unanchoring by deleting the line — the line is concealed, and ADR-0023 wants each verb named.
- **The picker is a list, not a drag** — a message picker shaped like the pratica link picker
  (ADR-0049 §D10): date, sender, subject, a text filter, keyboard reachable. Rejected: dragging an
  entry onto a message row — no drag exists in the timeline today, it would have to coexist with
  the list's own selection, and it has no keyboard path. Rejected: both — twice the surface.
- **Equal-instant tie-break: the message first** — at an exactly equal instant, a message sorts
  before a free manual entry, in the app and in the connectors (a note usually reacts to mail).
  Chosen by the author of this SPEC, not asked; see Assumptions in the approval gate.

## Constraints

- **`pratica.md` frontmatter is untouched** — the anchor lives in the body; `Dossier`, its owned
  keys and `Dossier.render` do not change — origin: ADR-0036, ADR-0049 §D1, `.claude/protected-interfaces`.
- **Message files are untouched** — no key is added to message files and ADR-0036 §D6's rewrite
  triggers stay four — origin: ADR-0036 §D6, ADR-0049 §D6.
- **The timeline's writes widen, and that is an amendment** — ADR-0036 §D5 says the timeline's only
  writes are inserting one heading and the daily-note line. This SPEC adds: writing, replacing and
  removing an anchor line, and moving entry blocks between two `pratica.md` files on «Sposta in…»
  and its undo. The single-editor rule of §D5 stays: the timeline still never binds a live text
  view to a range — origin: ADR-0036 §D5 (to be amended by the new ADR).
- **Every body write is guarded** — through the session's single write door with the `expecting:`
  hash precondition, and refused while that `pratica.md` is dirty in an editor tab — origin:
  ADR-0043 §D8, ADR-0057 §D3, ADR-0067.
- **State read before an `await` is re-read after it** — origin: CLAUDE.md working agreement,
  ADR-0043 §D7.
- **No new frontmatter key, no `IndexCache.schemaVersion` bump** — the timeline and the connectors
  read `pratica.md` off disk — origin: ADR-0049 §D4, CLAUDE.md closed-schema rule.
- **Every colour and font through a token; an approved mockup before the view is built** — origin:
  CLAUDE.md design system.
- **Connectors stay read-only for pratiche** — origin: ADR-0036 §D20, `PG-115`.
- **Nothing under `Sources/Core` or `Sources/Connector` imports AppKit or SwiftUI** — origin:
  ADR-0001 §D1, ADR-0007.

## Stack

Swift 6, SwiftUI with the existing AppKit editor (TextKit 2). No new dependency.

## Data model

A manual entry is the block from its `## YYYY-MM-DD HH:MM <Kind> · <Controparte>` heading up to the
line before the next `## ` heading or the end of the file (unchanged from the Pratiche spec).
*Amended 2026-10-01 (PG-367):* the heading may carry a `±hh:mm` offset after the time, as the
Pratiche spec now states.

An entry is **anchored** when the first line after its heading is exactly, allowing surrounding
whitespace:

```
<!-- pergamenum-message: <Message-ID> -->
```

- `<Message-ID>` is written in the same form as the message file's `pergamenum-mail-message-id`,
  angle brackets included, and compared byte for byte.
- An anchor line anywhere else in the entry is ordinary body text and anchors nothing.
- The anchor line is never part of the entry's rendered body, its preview or the connector's body.

Placement states of an entry:

| State | Condition | Placed |
|---|---|---|
| free | no anchor line | by heading timestamp (as today) |
| anchored | anchor names a message file present in this pratica | directly under that message |
| orphaned | anchor names no message file present in this pratica | by heading timestamp, with a caption |

*Amended 2026-10-03 (ADR-0079): a fourth state, excluded: the anchor names no message file present
in this pratica and the pratica's `pergamenum-dossier-excluded` lists that Message-ID. It is placed
by heading timestamp, hidden in the app's timeline (not drawn, not counted, no caption; its text
stays in `pratica.md` and the inspector) and reported `anchorState: "excluded"` by the connectors.
Orphaned keeps its row for an anchor the
pratica does not exclude.*

## API / interfaces

- The timeline entry the app and the connectors share gains an optional anchor (the Message-ID),
  absent for messages and free entries, present for anchored and orphaned entries, plus a way to
  tell anchored from orphaned.
  *Amended 2026-10-03 (ADR-0079): the anchor is present for excluded entries too, and the way to
  tell the states apart tells `excluded` from anchored and orphaned.*
- One parser of manual entries (heading, kind, counterpart, anchor, body) and one ordering rule
  serve the app and both connectors, replacing the connector's duplicate parser and its divergent
  tie-break.
- The message command catalogue gains «Aggiungi nota» and «Aggiungi telefonata»; a manual-entry
  command catalogue gains «Collega a un messaggio…» and «Scollega dal messaggio», driving both the
  context menu and the accessibility actions.

## UI flows

1. **Note on an email**: message row → context menu or expanded footer → «Aggiungi nota» (or
   «Aggiungi telefonata») → a heading with the current time plus the anchor line is appended to
   `pratica.md` → the entry appears under the message → the inspector opens `pratica.md` with the
   caret in the entry's body (the existing hand-off) → the daily note of today gets its line when
   the mirror setting is on.
2. **Anchor an existing entry**: manual-entry row → «Collega a un messaggio…» → picker of this
   pratica's messages (the current anchor marked, if any) → choose → the anchor line is written or
   replaced → the entry moves under the chosen message.
3. **Unanchor**: anchored or orphaned entry → «Scollega dal messaggio» → the anchor line is removed
   → the entry returns to its heading timestamp.
4. **Escludi**: the message leaves as today; its entries stay, shown at their heading timestamp
   with a caption saying their message is no longer in this pratica. Annulla: they return under the
   message.
   *Amended 2026-10-03 (ADR-0079): while the message is excluded its entries are hidden in the app's
   timeline, with no caption, and reported `excluded` by the connectors; they stay in `pratica.md`
   and the inspector. Annulla still returns them under the message with no write.*
5. **Sposta in…**: the message and its entries move to the destination; the destination shows them
   under the message. Annulla: both come back.

## Edge cases

- **Several entries on one message**: all directly under it, in heading-timestamp order, file order
  on a tie; a free entry never sits between a message and its anchored entries.
- **The last row**: a message with no following row gets «Aggiungi nota»/«Aggiungi telefonata» like
  any other; its entries are drawn under it at the end of the timeline.
- **«Inserisci qui» next to an anchored entry**: the midpoint is computed from the neighbours'
  placement times (an anchored entry counts at its message's time), never from an anchored entry's
  writing time.
- **Anchor naming a message that is not here**: excluded, moved away with a refused carry, deleted
  by hand, or mistyped — all orphaned, same caption, never an error.
  *Amended 2026-10-03 (ADR-0079): an anchor naming an excluded message, or one moved away with a
  refused carry (the source then excludes its Message-ID), is hidden in the app's timeline and
  reported `excluded` by the connectors; an anchor whose message was deleted by hand, or that is
  mistyped, stays orphaned with the caption. Never an error in any case.*
- **Undo of Escludi, or the message coming back by any route**: the entry is anchored again with no
  write.
- **«Rigenera»**: the Message-ID does not change, so the anchor holds; `pratica.md` is not written.
- **«Non più in Mail»**: the message file stays, so the anchor holds.
- **Destination already holds entries anchored to the same message** (e.g. after an earlier
  «Aggiungi anche a…»): the carried entries are appended; all of them are drawn under the message.
- **`pratica.md` dirty in a tab**: anchoring, unanchoring, and a «Sposta in…» that would carry
  entries are refused with a sentence, before anything moves. A «Sposta in…» with no anchored
  entries behaves exactly as today.
- **Line breaks**: carried and written lines take the target file's own line break (CRLF kept).
- **Hand-edited anchor line**: edited to another existing Message-ID, the entry follows; broken, it
  becomes free or orphaned per the table above.
  *Amended 2026-10-03 (ADR-0079): edited to a Message-ID the pratica excludes, it becomes excluded
  per the table's note, hidden in the app.*

## Test seams

Four existing seams, no new one, no GUI test.

1. **Pure core (primary)** — the entry parser, anchor render and parse, anchored insertion,
   anchor/replace/unanchor as text transformations, block extraction and append for a carry, and
   the ordering and filter rules. Most criteria are asserted here.
2. **Commands over a temporary vault** — «Sposta in…» carrying entries and its undo, both refused
   writes, Escludi and its undo, «Rigenera», «Aggiungi anche a…», the dirty-tab refusal.
3. **Connector** — the anchor field, the shared ordering and tie-break.
4. **Editor, in process** — concealment and reveal of the anchor line.

The look is verified against the approved mockup; placement is covered by the model.

## Success criteria

- [ ] R-01 — An entry whose first line after the heading is `<!-- pergamenum-message: <Message-ID> -->` is parsed as anchored to that Message-ID; the line elsewhere in the entry anchors nothing; the anchor line never appears in the entry's rendered body, preview or connector body.
- [ ] R-02 — «Aggiungi nota» and «Aggiungi telefonata» exist on every message row's context menu and expanded footer, the last row included, through the message command catalogue, and appear in the row's accessibility actions.
- [ ] R-03 — Creating an anchored entry appends to `pratica.md`, in one guarded write, a heading with the current time, the kind, and the message's counterpart, followed by the anchor line and an empty body line; the caret lands in the body through the existing hand-off, and the daily-note mirror writes today's line when the setting is on.
- [ ] R-04 — An anchored entry is placed directly after its message; several entries on one message follow it in heading-timestamp order, file order on a tie; no other row sits between a message and its anchored entries.
- [ ] R-05 — An entry whose anchor names no message file present in the pratica is placed by its heading timestamp and shows a caption saying its message is no longer in this pratica; it is anchored again, with no write, as soon as that message is present. *Amended 2026-10-03 (ADR-0079): unless the pratica excludes that Message-ID; then the entry is hidden in the app and reported `excluded` by the connectors.*
- [ ] R-06 — An anchored entry is visible only when its message is visible under the current filters; under the text filter an entry that matches shows together with its message. Free and orphaned entries keep the current rule.
- [ ] R-07 — «Inserisci qui» computes its midpoint from the neighbours' placement times, an anchored entry counting at its message's time.
- [ ] R-08 — At an exactly equal instant a message sorts before a free manual entry, in the app and in both connectors.
- [ ] R-09 — An anchored entry is drawn in its message's lane at the lane's width, indented, with the manual-entry colour and symbol, every colour and font through a token, in light and dark themes. *Amended 2026-10-01 (ADR-0076 follow-up): its message's lane width less the indent, taken on the lane's own edge, and coloured by its kind (`surface.entryNote`, `surface.entryCall`).*
- [ ] R-10 — The anchored-entry row matches a mockup approved before the view is built. (no-test: design approval, checked by reading the approved mockup and the ADR's gate record)
- [ ] R-11 — «Collega a un messaggio…» on any manual entry opens a picker of this pratica's messages (date, sender, subject, text filter, keyboard reachable, current anchor marked) and writes or replaces the anchor line in one guarded write.
- [ ] R-12 — «Scollega dal messaggio» on an anchored or orphaned entry removes the anchor line in one guarded write and nothing else of the entry; it is absent on a free entry.
- [ ] R-13 — Escludi on a message leaves every entry anchored to it byte-identical in `pratica.md`; they show as orphaned; undoing Escludi shows them anchored again without writing `pratica.md`. *Amended 2026-10-03 (ADR-0079): they are hidden, not shown as orphaned; undoing Escludi shows them anchored again.*
- [ ] R-14 — «Sposta in…» appends every entry anchored to the moved message to the destination `pratica.md`, then removes them from the source; the rest of both files is byte-identical; the undo carries them back the same way.
- [ ] R-15 — When the destination write is refused, the message still moves, the entries stay in the source as orphaned, and a named problem is reported; when the source removal is refused, the entries stay in both files and a named problem says so. No entry text is lost in either case. *Amended 2026-10-03 (ADR-0079): entries left in the source by either refusal are hidden in the source timeline, not orphaned, because the source excludes the moved Message-ID; the named problems are unchanged.*
- [ ] R-16 — «Aggiungi anche a…» leaves both `pratica.md` bodies unchanged.
- [ ] R-17 — «Rigenera» on a message with anchored entries leaves `pratica.md` unwritten and the entries anchored.
- [ ] R-18 — Anchoring, unanchoring and a «Sposta in…» that would carry entries are refused with a sentence, before anything changes, while the involved `pratica.md` is dirty in an editor tab or changed on disk since it was read; a «Sposta in…» with no anchored entries behaves as before this SPEC.
- [ ] R-19 — Carried and written lines use the target file's own line break; a CRLF `pratica.md` stays CRLF.
- [ ] R-20 — With «Nascondi markup» on, the anchor line is concealed in the editor to a small marker and revealed as raw text when the caret enters it; with the setting off it is shown raw.
- [ ] R-21 — The app and both connectors parse manual entries through one shared parser and order the timeline through one shared rule; the connector's duplicate parser is gone.
- [ ] R-22 — The connectors' timeline payload carries the anchor's Message-ID for anchored and orphaned entries and tells the two apart; `scripts/mcp-smoke.py` still passes; no connector gains a pratiche write. *Amended 2026-10-03 (ADR-0079): and tells `excluded` apart too.*
- [ ] R-23 — `pratica.md` frontmatter, message files, `Dossier.render`, `IndexCache.schemaVersion` and every protected interface are unchanged; nothing added under `Sources/Core` or `Sources/Connector` imports AppKit or SwiftUI, and `perg` and `pergamenum-mcp` build.
- [ ] R-24 — The new ADR records the amendment of ADR-0036 §D5 (the timeline's writes) and the relation to ADR-0049's «manual entries stay unlinkable», and `CLAUDE.md`'s chain decision index gains its line. (no-test: documentation, checked by reading the ADR and CLAUDE.md)

## Not yet specified

_none_

## Out of scope

- **Connector writes** (creating or anchoring entries from `perg`/MCP) — pratiche connectors are
  read-only by decision; tracked as `PG-115`.
- **Drag-to-anchor** — rejected in favour of the picker; see Decisions.
- **Copying entries on «Aggiungi anche a…»** — rejected; see Decisions.
- **Migrating existing files** — no file changes shape; old entries stay free until anchored by hand.
- **The same-minute collision of «Inserisci qui»** (a midpoint truncated to the minute can read back
  before a neighbour with seconds) — pre-existing, and anchoring answers the common case; to be
  filed in `TODO.md` if still wanted.
- **Click on an entry row jumping to its heading** — ADR-0036 §D5 specifies it and the code does not
  implement it (a click only selects the row); a separate defect, to be filed in `TODO.md`, not
  folded in here.
