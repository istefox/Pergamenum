Status: Approved (2026-10-03)

# SPEC — Pratiche timeline: a rail that ties anchored entries to their message, and an excluded message takes its entries with it

## Destination

A SPEC handed to `/workplan`, closed in one PR. Closes issue #824 (ledger `PG-369`), the
follow-up ADR-0076 left after PR #761 and PR #814. Facts re-read on `origin/main` @ `72d05143`
on 2026-10-03.

## Objectives

- A manual entry anchored to a message reads as belonging to that message at a glance. Today
  the only signals are a 24 pt indent from the lane's edge and a small `↪` glyph in the entry's
  heading. Stefano's words on the Debug build, 2026-10-01: «si capisce poco che è collegata…
  bisogna trovare un sistema differente».
- An entry anchored to a message the person excluded leaves the timeline with that message, and
  comes back when the exclusion is undone. Today the message disappears, its entries stay behind
  as orphans with the caption «Il messaggio non è più in questa pratica», and Cmd+Z re-anchors
  them. Stefano's words, 2026-10-01: «se sparisce l'email anche la nota collegata ha poco senso».
- An anchored entry written on a different day from its message says which day. Today an entry
  written at 20:22 on 3 October and anchored to a message of 9 June shows only «20:22», under
  the 9 June header.

## Scope and non-goals

In: how an anchored entry is drawn in the app's timeline (a connecting rail, its colour, the
heading's date label, the `↪` glyph removed); the placement rule shared by the app and both
connectors (a new "excluded" placement); the connectors' `anchorState` value for it; two new
colour tokens.

Out, one line each (detail below):
- folding or selecting a message's entries as a group;
- a summary row or count for hidden entries;
- moving entries into the side margin beside the message;
- any write to `pratica.md` or to the dossier;
- other reading surfaces of `pratica.md` (export, transclusion, hover preview).

## Decisions

- **One SPEC, one PR for both halves.** The visual link and the exclusion rule both act on the
  same placement rule (ADR-0076 §D2/§D3) and on the same rows. Rejected: two SPECs (exclusion
  first, then the visual link). It would touch the same rule and the same tests twice.
  Rejected: the visual link alone. Stefano asked for both on 2026-10-01.
- **The link is a connecting rail.** A vertical line runs in the anchored indent, from the
  message card's inner bottom edge down to the last entry anchored to it, with a short hook into
  each entry's card. Every entry stays its own `List` row, so selection, the context menus,
  Backspace (ADR-0070), the double-click/Return toggle and «Inserisci qui» keep working
  unchanged. Rejected: one card for the message and its entries (joined corners, no gaps). It
  reads more strongly, but the `List` still sees separate rows, so corners, spacing and the
  selection outline would have to be faked row by row (the trap ADR-0049 §D8 and PG-366
  measured). Rejected: entries in the side margin beside the message. That space has been the
  linked note's column since PR #814 (ADR-0049, at most 190 pt in the readable column), so
  entries would fight the note for it or stack into a narrow column. Rejected: a coloured bar on
  the entry. It needs the least work, but the link stays implicit, which is the defect being
  fixed.
- **The rail takes its message's lane colour.** It uses one new token per lane, a stronger tone
  of the received and sent card surfaces, so the rail visibly comes out of its own message.
  Rejected: neutral `textTertiary`. No token needed, but shape alone carries the link. Rejected:
  `accentPrimary`. In the timeline the accent already means "selected" (the card outline from
  PR #814).
- **The `↪` glyph is removed** from an anchored entry's heading. The rail carries the link, and
  the glyph was taking room from the time and the subject. VoiceOver still says «collegata al
  messaggio». Rejected: keeping both, a redundant second signal.
- **Day and time in the heading when the day differs.** An anchored entry whose own heading day
  differs from its message's day shows the day and the time («3 ott 20:22»). When the two days
  match it shows the time alone, as today. A free or orphaned entry is unchanged: it already sits
  under its own day's header. Rejected: always day and time on every anchored entry, which is
  noise on the same day. Rejected: time only, the defect.
- **An entry anchored to an excluded message is hidden in the app.** It is hidden when its anchor
  is in the pratica's own `pergamenum-dossier-excluded` list and no message of the pratica
  carries that anchor. It is not drawn, not counted and not reachable from the keyboard. It
  stays intact in `pratica.md`, still visible and editable in the inspector, and nothing is
  written. Undoing Escludi takes the id out of the list and restores the file, so the entry
  re-anchors by reading, as ADR-0076 §D2 already does. An anchor that names no message and is
  not excluded (a file deleted by hand, a Message-ID typed by hand) stays orphaned with today's
  caption. Rejected: hidden with a discreet summary row («2 voci collegate a messaggi esclusi»),
  more surface for little gain. Rejected: the status quo (orphaned).
- **The connectors list them, as `excluded`.** `perg` and `pergamenum-mcp` keep every entry and
  report `anchorState: "excluded"` with its `anchorMessageID`, placed on the spine by its own
  heading date as an orphan is. A connector is a read of the data, not a view, so it never
  hides content. Both connectors compute this through the one shared rule. Rejected: hiding
  them as the app does, which would leave an assistant blind to text that is still in the file.
  Rejected: unchanged (`orphaned`), which would leave the app and the connectors disagreeing on
  why the entry has no message.
- **Each row stays independent.** Collapsing, expanding or selecting a message does nothing to
  its entries. Rejected: a selected message or entry lighting the whole rail. Rejected: the
  message's chevron folding its entries. Both are a "group" feature of their own.
- **No mockup beyond the approved ASCII sketch.** The ASCII sketch Stefano approved on
  2026-10-03 is the reference. This retouches existing rows and adds no new screen. `/build`
  stops for Stefano's hand check on the Debug build before the merge, as PG-364 to PG-367 did.
  Rejected: an HTML mockup gated at `/workplan`.

Approved sketch (received side; the sent side is its mirror on the trailing edge):

```
┌──────────────────────────┐
│ ↙ Mario Rossi   9 giu    │
│ Oggetto del messaggio... │
└──┬───────────────────────┘
   ├─┌─────────────────────┐
   │ │ ✎ 20:22 Nota · ...  │
   │ └─────────────────────┘
   └─┌─────────────────────┐
     │ ☎ 3 ott 09:10 ...   │
     └─────────────────────┘
```

## Constraints

- **Placement is recomputed on every read, nothing cached, nothing written when a message
  leaves or returns.** Origin: ADR-0076 §D2 (R-05, R-13).
- **One ordering and placement rule in the shared core, read by the app and both
  connectors.** It stays Foundation-only so `perg` and `pergamenum-mcp` compile it. Origin:
  ADR-0076 §D2, ADR-0007.
- **The timeline's rows are read-only; `pratica.md` has one editor, the inspector.** Origin:
  ADR-0036 §D13.
- **Every timeline row is a row of `List(selection:)`.** No custom gesture may compete with the
  list's own selection, and a `DisclosureGroup` may not stand in for rows. Origin: ADR-0024,
  ADR-0025 §D9, ADR-0070.
- **Colours only through tokens, in both themes.** A vault theme without the new keys inherits
  them from the bundled theme of its appearance, as `surface.entryNote`/`entryCall` do. Origin:
  CLAUDE.md design system, PR #814.
- **The row arithmetic stays one pure function.** That function places the card, the note column
  and the anchored indent, and the rail is placed from the same arithmetic. Origin: ADR-0049 §D8,
  PG-366.
- **Layout holds from the 428 pt minimum timeline up to the 720 pt readable column, on both
  sides.** Origin: PR #814 (PG-365, PG-366).
- **At most two or three GUI tests per feature, each justified.** This one adds none. Origin:
  CLAUDE.md merge-gate rule.
- **No on-disk format, schema or protected interface changes.** `IndexCache.schemaVersion` and
  `PraticaEntryAnchor.line(for:)` are untouched. Origin: user mandate in this interview (the
  exclusion data already exists in the dossier), ADR-0076 G2.

## Data model

No new stored data. The exclusion set is the pratica's existing `pergamenum-dossier-excluded`
list of Message-IDs, written today by Escludi and by «Sposta in…» on the source pratica, and
removed by their undos.

The shared placement gains one case. A manual entry's placement is one of:

- `message`, for a message row;
- `free`, an entry with no anchor;
- `anchored(messageID)`, when a message of the pratica carries the anchor;
- `excluded(messageID)`, new: no message carries the anchor and the anchor is in the
  pratica's exclusion list;
- `orphaned(messageID)`, when no message carries the anchor and it is not excluded.

A message present wins over the exclusion list: an excluded id whose message file is still in
the pratica places its entries as `anchored`.

## API / interfaces

- The shared ordering rule takes the pratica's exclusion set as an input beside its rows. A
  caller that passes an empty set gets exactly today's output.
- Connector payload: `anchorState` gains the value `"excluded"`, with `anchorMessageID` set. No
  other field changes, and a message or a free entry still carries neither. The MCP tool's
  description and `perg`'s human-readable line for an entry name the new state in Italian, beside
  today's «il suo messaggio non è più in questa pratica».
- Two new colour tokens, one rail colour per lane (received and sent), defined in the light and
  dark bundled themes.

## UI flows

- **Reading a message with anchored entries.** The rail leaves the message card's bottom edge
  inside the indent, on the lane's own side (leading for a received message, trailing for a sent
  one), and runs down without a break across the gaps between rows. Each entry's card receives a
  hook at its heading. The rail ends in a corner at the last entry. It is drawn the same whether
  the message and each entry are collapsed or expanded.
- **Escludi.** The message and every entry anchored to it leave the timeline together. The day
  header goes too when nothing visible is left in that day. Cmd+Z brings the message and its
  entries back, under the message, with the rail.
- **«Sposta in…».** Entries are carried to the destination as today (ADR-0076 §D6). If the
  carry is refused or the message note did not move, the verb already reports why. Any entry
  left in the source whose anchor the source now excludes is hidden there by the same rule.

## Edge cases

- **Excluded id whose message file is still in the pratica** (Escludi's trash failed, or a
  file restored by hand): the entry is `anchored` and visible.
- **The person removes an id from `pergamenum-dossier-excluded` by hand in the inspector while
  the message stays in the Trash**: its entries become `orphaned` and visible with today's caption.
- **Text filter matching a hidden entry**: it stays hidden. An excluded message is not in the
  timeline at all, and its entries follow it.
- **«Inserisci qui» and day sections**: computed on the visible rows only. A hidden entry is
  never a neighbour, and a day holding only hidden entries draws no header.
- **A message whose anchored entries are all hidden or filtered out** draws no rail.
- **A message filtered out by the sender or attachments filter**: its anchored entries are
  already hidden with it (ADR-0076 R-06), so no rail is drawn without its message.
- **A selected entry**: the selection outline (PR #814) is drawn on the card, and the rail's
  hook meets the card's edge without covering the outline.
- **Narrow timeline (428 pt) and sent side**: the rail sits inside the existing 24 pt indent and
  takes no width from the card or the note column.
- **An anchored entry exactly at midnight, or in another zone offset than the reader's**: the
  "same day" test compares the entry's instant and its message's instant as calendar days in the
  reader's current calendar, the same calendar that draws the day headers.

## Test seams

Five existing seams, no new one, zero GUI tests:

1. **The ordering rule's own tests**, in the shared core: the `excluded` placement, its
   precedence below a present message and above `orphaned`, and an empty exclusion set reproducing
   today's output.
2. **The timeline model's pure tests**: which rail piece each row draws (none, start, through, a
   hook, the last corner), the heading's date label rule, and hidden entries removed before day
   sections, «Inserisci qui» neighbours and filters.
3. **The hosted `List` layout tests** at 428, 800 and 1600 pt, with and without a scroller: the
   rail is continuous from the message card to the last entry across row gaps, mirrored on the
   sent side, inside the indent, and overlapping neither the card nor the note column.
4. **The connector payload tests**: `anchorState: "excluded"` with its message id, and spine
   placement by heading date.
5. **The design-system tests**: the two tokens exist in both bundled themes, are inherited by a
   vault theme that lacks them, and meet 3:1 non-text contrast against the timeline's background.

The rail's continuity across `List` rows is the only real layout risk, and only a hosted `List`
can measure it. That is why seam 3 carries it, not a GUI test.

## Success criteria

- [ ] R-01 — An entry whose anchor no message of the pratica carries, and whose anchor is in the
  pratica's `pergamenum-dossier-excluded` list, is placed `excluded` by the shared rule.
- [ ] R-02 — A message present in the pratica wins over the exclusion list: its entries are
  `anchored`, even when its id is listed as excluded.
- [ ] R-03 — An anchor that no message carries and the exclusion list does not hold stays
  `orphaned`, with today's caption, unchanged.
- [ ] R-04 — With an empty exclusion set the shared rule's output is identical to today's for
  every existing ordering test.
- [ ] R-05 — The app's timeline does not draw an `excluded` entry: no row, no day header of its
  own, no «Inserisci qui» neighbour, not revealed by the text filter, not reachable by keyboard
  selection.
- [ ] R-06 — Escludi followed by Cmd+Z brings the message and its anchored entries back, anchored
  under it, with no write to `pratica.md` beyond the dossier change the verbs already make.
- [ ] R-07 — `perg` and `pergamenum-mcp` list an `excluded` entry with
  `anchorState: "excluded"` and its `anchorMessageID`, placed by its own heading date. `perg`'s
  line and the MCP tool description name the state.
- [ ] R-08 — A message with at least one visible anchored entry draws a rail. The rail leaves the
  card's bottom edge inside the anchored indent, on the lane's own side, and runs without a gap
  across the row boundaries to the last anchored entry, with a hook to each entry's card. It is
  measured in a hosted `List` at 428, 800 and 1600 pt, received and sent.
- [ ] R-09 — The rail lies inside the existing anchored indent. The card widths, the note
  column's width and position, and the indent itself are unchanged from PR #814's arithmetic
  (the existing layout tests stay green as they are).
- [ ] R-10 — The rail draws in its message lane's own new rail token, defined in both bundled
  themes and inherited by a vault theme without it, at least 3:1 against the timeline background
  in light and dark.
- [ ] R-11 — The `↪` glyph is gone from an anchored entry's heading. Its accessibility label
  still includes «collegata al messaggio».
- [ ] R-12 — An anchored entry whose heading day differs from its message's day shows day and
  time in its heading. One on the same day shows the time alone. Free and orphaned entries are
  unchanged.
- [ ] R-13 — Selection, the context menus, Backspace/«Escludi» on a selected message, the
  double-click/Return toggle and «Inserisci qui» behave as before on rows that carry a rail (the
  existing tests for each stay green).
- [ ] R-14 — Stefano's hand check on the Debug build passes before the merge: light and dark,
  428 pt and a wide window, a received and a sent message with two anchored entries (one on
  another day), Escludi then Cmd+Z. (no-test: a human visual acceptance gate, recorded in the
  ADR's implementation notes)
- [ ] R-15 — The decisions above are recorded in an ADR, or as an amendment to ADR-0076, which
  `/workplan` decides. That record amends ADR-0076 R-05/R-13 for the excluded case, and the
  CLAUDE.md chain index line is updated. (no-test: documentation obligation)

## Not yet specified

_none_

## Out of scope

- **Folding a message's entries with its chevron, or lighting the whole rail on selection.**
  That is a group feature with its own questions (a count on the collapsed card, keyboard
  behaviour), so it gets its own ledger entry if wanted.
- **A summary row or count for hidden entries.** Stefano chose plain hiding. The text stays in
  `pratica.md` and in the inspector.
- **Entries in the side margin.** Since PR #814 the margin belongs to the linked note
  (ADR-0049).
- **Other reading surfaces of `pratica.md`.** Export, transclusion and hover preview show the
  anchor line raw today (ADR-0076 §D12) and are not touched.
- **Changing what Escludi or «Sposta in…» write.** Both already maintain the exclusion list this
  SPEC reads.

## Domain terms

- **Anchored entry**: a manual «Nota»/«Telefonata» entry of `pratica.md` whose first line names a
  message's Message-ID (ADR-0076 §D1).
- **Excluded message**: a Message-ID listed in the pratica's `pergamenum-dossier-excluded`,
  written by Escludi or by «Sposta in…» on the source pratica.
- **Rail**: the connecting line this SPEC adds between a message card and its anchored entries.
