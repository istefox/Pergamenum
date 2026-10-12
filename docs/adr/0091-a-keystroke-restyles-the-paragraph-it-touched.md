# ADR-0091: A keystroke restyles the paragraph it touched, and a structural change restyles the note

- Status: **planned**. It reached `main` with its plan (`docs/plans/per-paragraph-restyle.md`) ahead
  of the code, in PR #966 (merge `86f1cb49`, 2026-10-11), where it still read `proposed`
  (`docs/adr/README.md` rule 2). The implementation is on `feature/per-paragraph-restyle`; the record
  flips to `accepted`, naming that PR, its merge commit and the date, in the first docs change after
  the merge.
- Date: 2026-10-10. Written against `da38099d` (`origin/main` at the same commit). Every line number
  below was read there.
- Number: `0091` is the highest number on `origin/main` (0090) plus one. No local or remote-tracking
  branch holds a `docs/adr/0091*` file (checked 2026-10-10 with `git ls-tree` over every ref;
  `gh pr list --state open` was empty). Uncommitted files in other worktrees were out of this
  session's reach, so check again immediately before the merge (rule 1).
- Source: root `SPEC.md` (Approved 2026-10-10), "Per-keystroke restyle cost proportional to the
  edited paragraph (follow-up of PG-385 N2)", R-01 to R-16. This record registers the SPEC's seven
  decisions and does not reopen them.
- Relations:
  - Extends ADR-0082 §D2: one grammar, now also read over a fragment.
  - Extends ADR-0082 §D5/§D9: the keystroke budget gains printed fallback rows, and new ceilings
    are fixed at a gate.
  - Closes the "restyle only the edited paragraph" follow-up that §D9 left open.
  - Keeps §D6's scoped renumber, and scopes the restyle it triggers.
  - Leaves §D7 withdrawn: the layout is not re-scoped here.
  - Extends §D8: Oggi and Diario inherit the path through `NoteTextView`.
  - Touches ADR-0077 §D1: the shared parsers gain fragment entries, Foundation-only, and the
    exporter's projections do not change.
  - Keeps ADR-0074's pass order and its rule that each controller owns its state.

## Context

**C1. What a keystroke does today.** `NoteTextView.Coordinator.textDidChange(_:)`
(`Sources/Features/Editor/NoteTextView+Coordinator.swift:191-226`) writes the binding, then calls
`applyStyling(to:theme:)` (`:253-398`), which rewrites every attribute of the note:

- `setAttributes` over `0..<length` (`:288-291`);
- `MarkdownStyler.spans(in:)` over the whole text (`:292`);
- the per-span loop that builds attributes, unspellable ranges, hidden markers and the embed,
  table and view-block runs (`:293-321`);
- `ProseParagraphSpacing.apply` over every line (`:326`);
- the table and view-block passes over every run (`:375-380`);
- a whole-dictionary `decorations.apply(hiddenMarkers:)` (`:381`).

`endEditing()` (`:387`) then invalidates the layout of the whole document. `applyTransclusions`
rescans the whole text with `Transclusion.occurrences(in:)` and reserves space for every rendition.
The binding write schedules a SwiftUI update, whose `runPasses(on:coordinator:)`
(`NoteTextView+Update.swift:54-72`) runs `applyStyling` and the transclusion scan a second time.

Every selection change also runs `ViewBlockController.selectionCrossedFence(in:)`
(`NoteTextView+ViewBlocks.swift:95-100`). That calls `viewBlockRanges(in:)`
(`NoteTextView+ViewBlockEditing.swift:119-129`), which is a whole-text `CodeFence.regions` whenever
the note spells `pergamenum-view`. It runs inside `insertText`, so it is part of the measured
keystroke.

**C2. What it costs.** ADR-0082 §D9 measured this on 2026-10-10, in Debug, as thread CPU per key
(prose/fences):

| Note | Today | Whole-document layout restored |
| --- | --- | --- |
| 50 KB | 198 / 225 ms | 288 / 299 ms |
| 200 KB | 911 / 1067 ms | 1166 / 1367 ms |
| 1 MB | 6309 / 11844 ms | 7961 / 12725 ms |

The profile there splits the cost as 46% inline parse, 15% wikilinks, 13% block tokenizer and 10%
transclusion scan, plus the second pass. Every term grows with the note, so optimising the parsers
cannot change the slope.

**C3. What the grammar allows.** Read on `da38099d`.

**Line boundaries.** A styler line ends at `"\n"` or `"\r\n"` only (`LineBreak.isTerminator`, which
`MarkdownStyler.swift:145`, `CodeFence.lineRanges` and `ListNesting.levels` all use). A lone `"\r"`
and U+2028 stay inside the line. Swift never joins `"\n"` to the character after it (grapheme rules
GB4/GB5), so a scan of the UTF-16 for U+000A finds every styler-line boundary.
`NSString.paragraphRange` and `lineRange`, which key the hidden markers and the paragraph spacing,
split at a superset of those positions. A range aligned to styler lines is therefore a union of
whole paragraphs and lines of either kind.

**Line-local constructs.**

- the inline tokens (`MarkdownInlineParser.tokens(in:)`, one line at a time, with no reference
  definitions);
- headings, rules, tasks and list markers, everything except the list level;
- quotes: `quoteMarker` reads the level per line, and `EditorDecorationDelegate+QuoteRendering.swift`
  reads no neighbouring line;
- message anchors, embeds (`embedRun(inLine:)`), transclusion lines (`Transclusion.target(ofLine:)`)
  and CommonMark links.

There is no setext heading: a `---` under prose is a `.rule`.

**Six constructs cross lines.**

1. **Frontmatter.** `NoteFrontmatter.range(in:)` (`Sources/Core/Markdown/NoteFrontmatter.swift:11-22`)
   opens when the text starts with `---` and closes at the first later line that starts with
   `---`. `Transclusion.occurrences(in:)` takes its body start from `NoteDocument.parse`
   (`FrontmatterSource`, which also accepts a leading U+FEFF), so a second rule applies.
2. **Code fences.** `CodeFence.regions(in:)` (`Sources/Core/Markdown/CodeFence.swift:44-79`)
   toggles on every line whose trimmed text starts with three backticks. An unclosed fence runs to
   the end. `CodeSyntax.spans(in:language:)` carries block comments and `"""` strings across the
   lines of a body. `WikilinkParser.codeRanges(in:)` (`Sources/Core/Conventions/Wikilink.swift:127-179`)
   toggles on both ` ``` ` and `~~~` and closes only on a bare delimiter; it decides only which `[[`
   count as code.
3. **View blocks.** A closed fence whose language is `pergamenum-view`
   (`MarkdownStyler.viewBlockRuns`, `MarkdownStyler.swift:411-418`).
4. **Tables.** `MarkdownBlockParser.tableLines` (`MarkdownTokens.swift:154-173`) opens a table at a
   line containing `|` when the next line is a delimiter row with as many cells, and continues
   until a blank or pipe-less line. `GFMTable.alignments` also accepts a pipe-less `---` or `:-:` as
   a one-column delimiter row (`GFMTable.swift:158-174`).
5. **List levels.** `ListNesting.levels(in:)` (`Sources/Core/Editor/ListNesting.swift:47-77`) folds
   one stack forward over every line, frontmatter and fences included:
   - a list line pops the entries deeper than its indent and then pushes its content column;
   - a blank or indented non-list line changes nothing;
   - a non-blank, non-list line at column 0 clears the stack.
6. **Wikilinks.** `WikilinkParser.links(in:)` (`Wikilink.swift:84-116`) pairs each `[[` with the next
   `]]` anywhere, across lines. It skips an opener inside code, restarts after an opener whose inner
   text holds another `[[`, and stops at an opener with no `]]` after it.

**C4. What the platform allows.** Read in the MacOSX27.0 SDK on 2026-10-10.

- **Order.** `processEditing` "Sends `-textStorage:willProcessEditing`, fixes the attributes, sends
  `-textStorage:didProcessEditing`, and notifies the text storage observer" (`NSTextStorage.h:84-88`);
  `textStorage(_:willProcessEditing:range:changeInLength:)` is "Sent inside `processEditing` right
  before fixing attributes" (`:133-136`). Both callbacks run before the observer, which here is
  `NSTextContentStorage`.
- **Why `willProcessEditing`.** Attribute fixing, between the two callbacks, widens the reported
  range: a character typed at offset 10 of a one-paragraph note arrives as `{10, 1}` at
  `willProcessEditing` and as `{10, 27}`, to the end of its paragraph, at `didProcessEditing`
  (measured 2026-10-11 in the hosted fixture). The old range read from the widened one would be
  wrong, so the edit is recorded at `willProcessEditing`. A deletion reports the same `{10, 0}`,
  delta -3, at both. `IncrementalRestyleHosted.theStorageReportsAKeystrokeAsItsRangeAndDelta` pins
  the raw range.
- **Range semantics.** `editedRange` is "the range of text that contains changes", in the text as
  it now is, and `changeInLength` is the difference (`:54-60`). A test in the plan's Task 3 pins
  those semantics, rather than this sentence.
- **The delegate slot is free.** No file under `Sources/` assigns `textStorage.delegate` (grep,
  2026-10-10). `NSTextContentStorage` takes part as the `textStorageObserver` (`:124`), not as the
  delegate.
- **No main-actor annotation.** `NSTextStorageDelegate` has none (`:129-142`, inside
  `NS_HEADER_AUDIT_BEGIN(nullability, sendability)`), while `NoteTextView.Coordinator` is
  `@MainActor`.
- **Attribute changes keep the length.** An attribute change rewrites attributes and nothing else.
  That keeps the constraint ADR-0081 §D4 and the code cite as `NSTextContentManager.h:120`: a custom
  paragraph's attributed string must have the stored range's length. In the MacOSX27.0 SDK that
  sentence sits at `NSTextContentManager.h:282-283`. The line number moved; the constraint did not.

**C5. What the SPEC settled, registered here and not reopened:**

- dirty-range restyle, with offset-keyed state shifted by the edit's delta;
- a structural signature, falling back to a full restyle otherwise, with local blocks widening to
  the block;
- the edited range taken from the text storage;
- whole-document layout in `growToFitTheText`;
- the card left on the whole-text path;
- a hidden kill switch;
- the bench contract.

It leaves two questions to this record:

- the signature's members and the widening rule per block type (D3);
- whether the unspellable ranges and the paragraph spacing are shifted or recomputed (D5).

## Decision

### D1. Where the code goes, and what stays free of SwiftUI

**Grammar facts go into the shared sources**, Foundation-only, beside the parsers they restate, so
that one grammar answers both the full read and the fragment read (ADR-0082 §D2):

- **`Sources/Core/Markdown/MarkdownLineSignature.swift`** (new): a line's structural signature (D3).
- **`ListNesting`** (`Sources/Core/Editor/ListNesting.swift`) gains:
  - `role(of:)`, the classification `levels(in:)` already makes, returned as a value;
  - `folding(_:_:)`, one step of that fold;
  - `levels(in:seed:)` and `level(in:lineStart:indent:seed:)`, the forward and backward reads
    started from a given stack.

  `levels(in:)` and `level(in:lineStart:indent:)` stay and keep their meaning.
- **`MarkdownBlockParser.lineTokens(in:readsFrontmatter:endsLine:listSeed:)`**
  (`Sources/Core/Markdown/MarkdownTokens.swift`) gains a `listSeed: [Int] = []` parameter and hands
  it to those two reads. Every existing caller passes nothing and gets today's tokens.
- **`Transclusion.occurrences(inFragment:offset:)`** (`Sources/Core/Markdown/Transclusion.swift`).

**The editor-only pieces go beside the styler**, in `Sources/Features/Editor/`, each importing
Foundation and nothing else:

- `MarkdownStyler+Incremental.swift`, the fragment entry (D4);
- `StorageEdit.swift` and `StructureMap.swift` (D2);
- `RestyleScope.swift` (D2, D3);
- `EditorRestyleSwitch.swift` (D8).

They are not shared sources, because `MarkdownStyler` itself is not one: it lives in the app target
and calls the app-side `embedRun(inLine:)` (`Sources/Features/Editor/EmbedRun.swift`).

**This deviates from one sentence of the SPEC**, and is stated here so that nobody "fixes" it. The
SPEC's API section says the incremental entry point is "kept in the shared sources", but the styler
it extends is not in them. Moving `MarkdownStyler` into `Sources/Core` would take with it its `Span`
vocabulary (`.embedRun`, `.viewBlockRun` and `.tableRun`, which no connector reads) and
`EmbedRun.swift`. That would compile editor-only code into `perg` and `pergamenum-mcp`, where
nothing uses it. The constraint the SPEC actually binds, that the shared sources stay free of
SwiftUI (ADR-0001 §D1), holds either way. Every new file here is Foundation-only, so if the styler
ever moves into the shared sources, these files move with it unchanged.

### D2. The edit, the dirty range and the structure map

**Recording.** The coordinator becomes the text storage's delegate the first time it runs a full
restyle on that storage. It records every `textStorage(_:willProcessEditing:range:changeInLength:)`
(not `didProcessEditing`, whose range attribute fixing has already widened, C4) whose mask contains `.editedCharacters`, as a `StorageEdit(range:delta:)`:

- `range` is in the text as it now is;
- `delta` is the change in length;
- the replaced old range is `range.location ..< range.location + range.length - delta`.

Edits that change only attributes are ignored, every edit the restyle makes included.

The protocol is not main-actor annotated (C4), so the callback is `nonisolated`. It enters the main
actor with `MainActor.assumeIsolated`, the pattern already at `NoteTextView+Coordinator.swift:582`.
The editor never edits its storage off the main thread.

These all arrive by this one route:

- an undo or a redo;
- a paste;
- IME marked text;
- the renumber's `replaceAtomically`;
- a `pushInputs` assignment.

`shouldChangeTextInRanges` keeps recording for the renumber only (ADR-0082 §D6).

**The structure map (`StructureMap`)** is the offset-keyed derived state the decision needs, kept
for the whole note. It holds:

- one `MarkdownLineSignature` per styler line, with that line's start offset;
- the code-fence regions (range, language, closed or not);
- the table runs;
- the closed view-block runs;
- the frontmatter zone.

**How the map stays current:**

- `StructureMap(text:)` builds it at every full restyle.
- At `willProcessEditing`, the map is shifted, and then the signatures of the lines the edit
  touched are recomputed from the new text:
  - a line or run after the old range moves by `delta`;
  - one before it stays;
  - one that contains it stretches;
  - one that lies partly inside it is dropped.
- At the restyle, the runs inside the dirty range are replaced by the runs the fragment produced.

Invariant, proven by the property test: after any edit and its restyle, the map equals
`StructureMap(text:)` of the new text.

**Shifting the rest.** In the same callback, before `NSTextContentStorage` processes the edit (C4),
every offset-keyed holder applies the same rule (D6). Nothing is parsed and nothing in AppKit is
called.

**The dirty range** is the union of the edits recorded since the last restyle, each mapped through
the edits after it and aligned outward to styler lines, then grown by D3's widening. The next pass
sequence in `textDidChange` consumes it, or `runPasses` does when the edit arrived outside a
keystroke.

**A full restyle**, exactly today's `applyStyling(to:theme:)`, runs when:

- the kill switch is on (D8);
- there is no baseline: the coordinator never fully styled this storage, or the storage changed
  identity;
- an edit's old range covers the whole old text: a note switch, an external change,
  `textView.string =`, Enter in a list and the whole-text renumber, which both replace
  `0..<length`;
- `textDidChange` is called directly with nothing recorded (`EditorHeightTests.swift:133` does
  this);
- D3 decides `.full`.

`applyStyling(to:theme:)` keeps its name and its meaning, a full restyle. It serves the direct
callers in 32 test files and `selectionCrossedFence`'s commit, and it also clears the record and
rebuilds the map.

### D3. The structural signature and the widening rule (the SPEC's first open question)

**The signature.** `MarkdownLineSignature.of(_ line: Substring)` has four members, each read with the
parser it restates:

- **`fenceMark`**: the trimmed line starts with ` ``` ` (`CodeFence.marks`) or with `~~~`
  (`WikilinkParser.codeRanges`' second fence).
- **`tableCapable`**: the trimmed line contains `|`, or `GFMTable.alignments(in:)` reads it as a
  delimiter row.
- **`listRole`**: `ListNesting.role(of:)`, with the forward walk's own column arithmetic (a tab
  counts as 4). It is one of:
  - `.blank`;
  - `.item(indent:contentColumn:)`;
  - `.continuation`, an indented line that is not a list line;
  - `.reset`, a non-blank line at column 0 that is not a list line.
- **`brackets`**: the line's `[[`, `![[` and `]]` tokens in order, found the way
  `WikilinkParser.links` finds them. Each opener records whether an inline backtick span on the
  same line covers it.

**The decision.** `RestyleScope` takes each edit, the map before it and the new text, and decides
between `.full(reason)` and `.lines(range)`. Below, `S` is the start of the first line the edit
touches, and `E` the end of the last, in the new text. `E_old` is that same end in the old text.
The rules apply in this order:

| Construct | Condition | Result |
| --- | --- | --- |
| Frontmatter | The dirty range starts at or before the end of the frontmatter zone, or it includes offset 0 while the old or new first line starts with `---` (a leading U+FEFF allowed). The zone runs from 0 to the later of the two parsers' closing lines (C3 item 1), and is the whole text when a note opens with `---` and either parser finds no closing line. | Full restyle. |
| Fence lines | Any old or new line in the range has `fenceMark`. | Full restyle. |
| Fence bodies | The range intersects a fence region. | Widen to the whole region; an unclosed region runs to the end of the note. |
| View blocks | A view block is a fence, so the two fence rules above cover it. | Full on a fence line, the whole fence otherwise. |
| Tables | A line in the range is `tableCapable` in the old or new text, or the line just before `S` or just after `E` is. | Widen over every maximal run of consecutive `tableCapable` lines it touches or adjoins. A table is a contiguous part of such a run, and nothing outside the run decides it. A run that holds a `fenceMark` line is a full restyle (`tableFence`): the block tokenizer reads that line as a row or as a fence depending on the table above it. |
| Lists | Fold the map's roles, with no text read: from the last `.reset` line before `S` up to `S`, then the old lines' roles for the stack at `E_old` and the new lines' roles for the stack at `E`. | Equal stacks: no widening. Different stacks: move `E` down one line at a time, folding both over the same following lines, until they are equal. A `.reset` line clears both, so it stops the walk at the latest. |
| Wikilinks: tokens | The old lines' bracket tokens differ in order from the new lines'. | Full restyle. |
| Wikilinks: pending | The nearest bracket token before `S`, or before `E` in the new text, is an opener outside code with a `]]` somewhere after it. Openers in code are ignored, as the parser ignores them. | Full restyle. |
| Everything else | Line-local constructs (C3). | The edited lines. |

**Why the wikilink rules are enough.** Pairing is a function of the bracket-token sequence and of
which brackets are in code. Inline code is per line, and a fence region changes only through a
fence line, which is already a full restyle. So:

- unchanged tokens inside the range leave every pairing outside it unchanged;
- a link that crosses an edge of the range shows up as a pending opener.

**The cost of the wikilink rules.** They are coarse on purpose:

- typing or deleting `[[` or `]]` costs one full restyle each time;
- an unpaired `[[` with a `]]` far below it makes every keystroke between the two a full restyle.
  This is rare, and it is listed under Consequences.

**A follow-up, not part of this decision.** A clean-boundary widening, extending the range to the
nearest line where no opener is pending, would be exact and would keep link typing local. It is
left as a follow-up for two reasons: the SPEC's rule for anything other than a local block is the
full restyle, and the property test would have to prove the extension.

**The blockquote has no row of its own**, even though R-04 lists it. In this grammar `quoteMarker`
reads a quote's level per line, nothing joins two quote lines, and the quote rendering reads no
neighbour. A change in whether a line is a quote is therefore a line-local change. R-04's
blockquote case asserts this decision, and the property test asserts the result equals a full
restyle.

### D4. Styling a fragment

**The fragment entry.** The fragment is the dirty range's text, copied once into a `String`.
`MarkdownStyler.spans(inFragment:context:)` runs the same steps as `spans(in:)` over it.
`FragmentContext` carries the only two differences:

- `readsFrontmatter`: the frontmatter is read only when the fragment starts at offset 0;
- `listSeed`: the list stack starts from the stack D3 folds at `S`.

The SPEC also names fence state and frontmatter bounds as context. Those are guaranteed rather than
passed: after the widening, no fence, table run, view block or pending wikilink crosses the
fragment's edges, and the fragment stays out of the frontmatter zone.

**One span loop for both paths.** The returned spans carry fragment indices, in the order
`spans(in:)` uses, and the coordinator turns them into storage ranges by adding the fragment's
UTF-16 start. The span loop of `applyStyling` (`:293-321`) becomes one function, called by both
paths with a text and an offset. So the same code produces the attributes, the unspellable ranges,
the runs, and the hidden markers. The markers are keyed by the start of `paragraphRange`, which
inside an aligned fragment is the note's own paragraph start.

**The storage edit:**

1. `beginEditing`.
2. `setAttributes(context.base)` over the dirty range only.
3. The spans' attributes.
4. `ProseParagraphSpacing` over the dirty range's lines.
5. The table and view-block passes for the runs inside the dirty range.
6. The hidden markers, spliced into the delegate.
7. `endEditing`.

The attributes outside the dirty range are never written, so `NSTextStorage` keeps them and shifts
them itself. TextKit invalidates the layout of the dirty paragraphs and nothing else.

**Invariant (R-02).** After any sequence of edits, the storage's attributes and every holder of
derived state equal what a full restyle of the same text produces. The "later spans win" overlap
rule gives the same result on both paths, for two reasons:

- no span crosses the dirty range's edges, which is what the widening is for;
- inside the range, the spans keep the full pass's relative order, because each of `spans(in:)`'s
  steps emits in document order.

### D5. Unspellable ranges and paragraph spacing (the SPEC's second open question)

**Unspellable ranges are shifted and spliced**, never recomputed outside the dirty range.

- At the edit, a range after the old range moves by `delta`, and one containing it stretches. One
  inside it is dropped, and one crossing an end is cut down to its outside part.
- At the restyle, the dirty range is cut out of the list, the fragment's ranges go in, and
  `MarkdownStyler.merged` runs at the two seams only.

`merged` joins ranges that touch, so a merged range can cross the dirty range's edge only by
touching it, never because a span crosses it. Cutting at the edge and re-merging at the seams
therefore gives exactly the full pass's list.

**Paragraph spacing is recomputed over the dirty range's lines only**, with no neighbour.
`ProseParagraphSpacing.paragraphRanges` decides a line by whether a line-shaping span intersects the
line's content (`excluded.intersects(integersIn:)`: an intersection, not an adjacency). No span
crosses the dirty range's edge, so every line outside it gets the same answer before and after the
edit, and the spacing the storage holds there is already correct. `ProseParagraphSpacing` gains a
ranged entry that takes a fragment and an offset.

### D6. Offset-keyed state is shifted where it lives

Each holder gets one `shift(by:)`, applied at `willProcessEditing` with the D2 rule. Its writes at
restyle time become splices over the dirty range, so nothing outside the range is ever rebuilt.

The holders:

- **`EditorDecorationDelegate`**:
  - `hiddenMarkers`, keys only, because the marker ranges are relative to their paragraph;
  - `hiddenLineOffsets` and `foldedHeadings`;
  - `tableRowOffsets` and `viewBlockLineOffsets`;
  - `renditions` and `embedRenditions`;
  - `revealedParagraphs` and the keys of `revealedSpans`;
  - `tableViews` and `viewBlockHosts`.

  `apply(hiddenMarkers:hidingMarkup:)` keeps its whole-dictionary meaning for the full path. A
  splice entry replaces only the keys inside the dirty range, so the whole-dictionary comparison at
  `EditorDecorationDelegate.swift:339` no longer runs on every keystroke. The stores are `private`
  to that file, so the shift, the splice and a test snapshot live in the same file, and no store is
  widened.
- **`NoteTextView.Coordinator`**: `unspellableRanges` (D5) and `embedRuns`.
- **`TableBlockController`** (`drawn`, `hiddenRows`, `pendingCaret`) and **`TableGridStore`**
  (`grids`, keyed by header offset). A table outside the dirty range keeps its `TableGridView`, the
  same object. Only the runs inside the range are parsed and refreshed again.
- **`ViewBlockController`** (`drawn`, `hiddenLines`, `pendingCaret`, `lastRevealed`). Hosts stay
  keyed by ordinal (ADR-0033 §D3), and no edit outside a fence changes an ordinal.
  `selectionCrossedFence` reads the map's view-block runs instead of
  `viewBlockRanges(in: textView.string)`.
- **`EmbedTable`** (`renditions`, `pending`).
- **`TransclusionController`** (`lastRenditions`).
- **`FoldController`** (`lastFoldLayout`). After an edit whose shift changed the layout, a fold
  pass that finds the new layout equal to the shifted one still rescues the caret, because the
  unshifted comparison would have differed: the full path's rescue is kept.
- **`RevealController`** (`lastRevealed`, `lastRevealedSpans`).
- **`StructureMap`** (D2).

A holder added later that keys by offset must get the same method, or it is a defect. The hosted
R-05 test compares every holder named here with a twin that was fully restyled.

`hiddenMarkers`, the coordinator's two range lists and `StructureMap` move a step since
ADR-0094 §D1; the other holders keep this section's tables, with ADR-0094 §D8's bounds.

### D7. The passes after the styling

**Transclusions (R-09).** The styling pass hands `applyTransclusions` a one-shot token that names the
dirty range.

- **With the token**, `TransclusionController`:
  - scans only that range with `Transclusion.occurrences(inFragment:offset:)`;
  - merges what it finds into its shifted table;
  - resolves renditions only for those occurrences;
  - reserves space only inside the range. Outside it, the storage kept the reservation, because
    nothing reset those attributes.
- **Without the token** (a direct call, a full pass), it scans the whole note as today.
- **When the rendition generation changes** (a transcluded note changed on disk), it resolves every
  occurrence again from the shifted table, with no rescan of the text.

**Embeds** are scoped the same way, from the spliced `embedRuns`.

**Folding keeps its own rule.** With nothing folded it does nothing. With something folded it runs
`NoteFolding.layout` over the whole note, as today; that cost is named under Consequences.

**Renumbering, reveal, matches and grow-to-fit are unchanged.** `renumberLists(in:touching:)`
re-enters `textDidChange` with its own small edit, and the record turns that edit into its own
dirty range.

### D8. The second pass and the kill switch

**`runPasses` skips a styling that has nothing to do (R-08).** The coordinator keeps the inputs of
its last completed styling:

- the storage's identity;
- a counter of the character edits the delegate has recorded;
- the theme (`Theme` is `Equatable`);
- `hidesMarkup`;
- `revealsInlineSpans`.

**This extends the plan's fingerprint by four inputs**, stated here so that nobody trims it back
to the five above. `StylingInputs` also keeps the note path, the vault root and the thumbnail
store's identity, which an embed is resolved through, and the text container's width, which a
transcluded note is measured at. The passes after the styling read these off the whole note, and a
skipped styling hands them no scan: if one of them changed and the styling were skipped, the embeds
and transclusions would keep what they resolved against the old value until the next full restyle.

`runPasses` calls `applyStylingIfNeeded(to:theme:)`:

- inputs equal and nothing recorded: no styling and no transclusion scan;
- an edit recorded: the incremental path;
- anything else: the full path.

A flipped toggle changes the inputs, so the styling still runs where ADR-0037 §D7 needs it: the
comment at `NoteTextView+Coordinator.swift:382-386` relies on `applyStyling` running on every
`updateNSView` for a toggle flip. `RestyleLog` is the test seam: counts of full, incremental and
skipped passes, plus the last dirty range.

**The kill switch (R-10).** `EditorRestyleSwitch.key` is `editorFullRestyle`, a `UserDefaults` Bool
that Impostazioni does not show. `-editorFullRestyle YES` on the command line sets the same key
through the arguments domain, the way `-disableCalendar YES` already works.

- **When it is read.** `EditorRestyleSwitch.forcesFullRestyle(arguments:defaults:)` is read when the
  coordinator is made, and a test can set the coordinator's `forcesFullRestyle` directly.
- **What it does.** With the switch on, the coordinator records nothing and shifts nothing, and
  every pass is the full restyle, the second pass included. That is today's path, byte for byte.

### D9. Surfaces

The path lives in `NoteTextView.Coordinator`, so three surfaces take it: the note editor, Oggi
(`Sources/Features/Today/TodayView.swift`) and Diario (`Sources/Features/Diary/DiaryView.swift`).
They use the inputs that ADR-0082 §D8 already made equal.

The card (`CardTextView`, `CardTextView+Styling.swift:35`) stays on its whole-text
`applyStyling(to:)`, and its tests do not change. That is a SPEC decision. Parity comes from the
property test: the incremental result equals the same styler's full result.

### D10. Layout and fence crossing stay as they are

Its layout half is amended by ADR-0093 §D4.

`growToFitTheText` still calls `ensureLayout(for: documentRange)`, because ADR-0082 §D7 stays
withdrawn. With the attributes outside the dirty range untouched, TextKit has only the dirty
paragraphs to lay out again. The bench will report what the whole-document call still costs.

A caret crossing a view-block fence still triggers a full `applyStyling`
(`NoteTextView+Coordinator.swift:161`). Only the question "did it cross" is answered from the map.

### D11. The bench

**The six rows** keep their cases and their method (ADR-0082 §D5). They stay asserted, against
ceilings that gate G-ceiling-2 fixes from the measured "after" (the SPEC proposes 20 ms CPU). Until
that gate, ADR-0082 §D9's ceilings stay in force.

**Three fallback rows are added:**

- a keystroke that opens a fence: the third backtick, at the start of a line that already holds two;
- a keystroke in a table cell;
- Enter at the end of a list item.

They print as
`restyle-budget-fallback size=<bytes> variant=<prose|fences> path=<fence-open|table|list-enter> cpu_ms=<min> wall_ms=<min> runs=<K>`
and are never asserted. They run only when `RESTYLE_BUDGET_FALLBACK=1`, which
`scripts/editor-restyle-bench.sh` sets, so the per-turn suite does not pay for them.

The table row inserts its table before the measurement starts, so the six rows' synthetic notes do
not change. Under this design a keystroke in a cell widens to its table instead of restyling the
note, and the row prints what that costs.

### D12. Tests restated (R-13)

**Restated at the time of writing: none.** What was read:

- the 32 test files that call the coordinator's `applyStyling(to:theme:)` directly, which still get
  the full restyle they always got (D2);
- the 5 card test files, untouched (D9);
- the 7 files that type through `insertText` or `textDidChange`;
- a sample of the 63 files that edit an editor's text programmatically.

None pins whole-note styling after a keystroke:

- `EditorHeightTests` types into a storage the coordinator never styled, and calls `textDidChange`
  with nothing recorded, so both are full restyles (D2);
- `ViewBlockQuerySourceTests.swift:200-245` and `ViewBlockCaretTests.swift:366` edit and then read
  state elsewhere, which is the shifted state D6 keeps.

The full unit suite, run with the incremental path on, settles the rest. If it turns a test red,
that test's reason is written into this section first, in a commit before the one that changes the
test.

**Proved by the run of 2026-10-11** (`xcodebuild ... -only-testing:PergamenumTests test`, the default
settings, the kill switch off): 6185 tests in 372 suites, none red, and the five known issues are
`HostedViewPrototypeTests.theHarnessWindowRefusesFocusAndEveryCallThatWouldShowIt`'s, which this change
does not touch. No test that existed before this change was red, so none is restated, and the line
above stays «none». The suite also holds the 32 files that call `applyStyling(to:theme:)` directly and
still get the full restyle.

**Tests this change wrote and then corrected are not restated tests**, and are listed so that nothing
passes unsaid. They were red in the coder's first full run for reasons that lay in the test, never in
the production code, and each reason is in the file beside the line it changed:

- `OffsetShiftTests.shiftingByTheRecordedEditEqualsARestyleOfTheNewText`: the raw `replaceCharacters`
  moves the caret, and the selection change already reruns `applyReveal` over the new text, so the test's
  own hand call to `shiftDerivedState` shifted the two paragraph-offset reveal sets a second time. They
  are left out of the comparison; every other field, `revealedSpans` and `revealedSpanKeys` included,
  is still compared. The same test also drew its «edited paragraph» too narrowly for an insert that ends
  in a newline: the remainder of the split line is a line of the dirty range, so it is not the shift's to
  produce, and the boundary now includes the paragraph the edit's end lands in.
- `TransclusionScopeTests.aFenceLineKeystrokeScansTheWholeNote`: moving the caret onto the fence is a
  view-block crossing, a full restyle of its own by §D10, so the test counted two. The caret is put on
  the fence before the count is taken.
- `IncrementalStylerPropertyTests.randomLineLocalEditsAreRestyledByLines`: the failing expectation was
  the shared one, «most texts held no span», not the 95% share of `.lines`. The prose run started from an
  empty text and drifted to 40 to 100 bytes of plain letters. It now starts from a prose note with a
  heading, emphasis, a tag, nested lists and a quote (`EditGenerator.proseStart`). The shared floor is
  unchanged (at least half of the restyles compare a text that holds a span) and now holds with room:
  171 to 200 of 200 per seed, against fewer than 100 on five seeds before. The 95% share of line-local
  edits restyled by lines never failed and is unchanged; it reads 200 of 200 on each of the ten seeds.

### D13. Merge coordination

The SPEC asks for coordination with PG-219 (branch `docs/spec-pg-219-cursor-feedback`) through
`sync_operation`, because `textDidChange` and `growToFitTheText` live in the file that branch
restructures. On 2026-10-10:

- that branch has no commit beyond `main` (`git log origin/main..docs/spec-pg-219-cursor-feedback`
  prints nothing);
- PG-219 closed on 2026-10-06;
- ADR-0090 records it as merged through PR #920.

The coordination step stays in the plan as a one-command check that does nothing when nothing is in
flight.

## Alternatives considered

- **A shadow copy of the previous text, instead of a stored signature per line.** By
  `willProcessEditing` the old lines of an edit are gone. Keeping the last text (the binding write
  already makes that copy) and reading the old lines from it would avoid the per-line table.
  **Rejected:** the decision also needs the list stack at the edit and the nearest bracket token
  before it. Against the text, both are walks bounded only by the note: a note with no `[[` above
  the caret walks back to the top. The map answers both with an array walk, and doubles as the
  derived state the property test compares.
- **An `NSTextStorage` subclass that captures the replaced characters.** It would give the old text
  exactly, at the primitive. **Rejected:** it replaces the backing store of `NSTextContentStorage`
  under TextKit 2 with an app subclass on the hottest path, where ADR-0074 keeps the platform's own
  setup. The delegate callback already gives the decision what it needs.
- **Moving `MarkdownStyler` into the shared sources**, so the entry point is shared as the SPEC's
  sentence says. **Rejected in D1:** it compiles editor-only span vocabulary and `EmbedRun.swift`
  into both tools, for a constraint (no SwiftUI) that holds without the move.
- **Widening wikilinks to the nearest clean line boundary**, instead of a full restyle when
  brackets change. It is exact and would keep link typing local. **Not chosen now:** the SPEC's
  rule for anything other than a local block is the full restyle. It is left as a follow-up (D3).

**Registered from the SPEC, not argued again:** a per-line span cache; always widening and never
falling back; an idle full-restyle reconciliation; re-scoping the layout; sharing the incremental
path with the card.

## Consequences

### Positive

- A keystroke on a line-local construct costs the edited lines, plus the shift of the offset-keyed
  tables (linear, no parsing), plus whatever TextKit's whole-document `ensureLayout` still walks.
  The bench will say how large that last term is.
- The second pass after the binding write is gone, and so is the whole-note transclusion scan on
  every key.
- "Did the selection cross a view-block fence" is a lookup in the map.

### Negative

- A full restyle still happens for:
  - any edit to a fence line;
  - an edit in the frontmatter;
  - `[[` or `]]` typed or deleted;
  - Enter in a list (`claimsListCommand` replaces `0..<length`);
  - an undo whose renumber has no recorded range (`renumberLists(in:)` reads the whole text);
  - a pending `[[` with a `]]` far below it;
  - a note that opens with `---` and has no closing line.
- Typing inside an unclosed fence costs the rest of the note on every key, because the region runs
  to the end.
- In a note that is one list with no column-0 prose line, the seed is folded from the top. That is
  an array walk, not a parse.
- Every holder of offset-keyed state now has a shift that must stay correct. A new holder that
  forgets it diverges until the next full restyle. The R-05 hosted test and the property test guard
  this.
- The full restyle gains the map's build pass, one signature per line.
- Still proportional to the note on every key:
  - `parent.text = textView.string`, a copy;
  - `ensureLayout(for: documentRange)`;
  - `NoteFolding.layout`, while something is folded;
  - the spell checker's walk over `unspellableRanges`, once per question.

### Neutral

- No span changes meaning, and the golden corpus is untouched (R-03).
- No on-disk format, schema, protected interface or connector changes, and no GUI test is added.

## Measured after

Taken on 2026-10-11 by `scripts/editor-restyle-bench.sh` on the uncommitted tree of
`feature/per-paragraph-restyle` (on `48af9815`), Mac `Mac17,7` (Apple M5 Max), macOS 27.0.1 (build 26A434),
Xcode 27.0, Debug build: milliseconds of main-thread CPU per keystroke, the minimum of K runs after one
warm-up. The first run is `--large` (K = 5, and 3 at 1 MB); the second is `--large --runs 9`, started
after a quiet window of the Mac: another session's bench, run from a sibling worktree, was on the machine
around the first run (the script's guard looks once, at the start). The two agree within 7% on every row,
so the first run was not visibly disturbed. The ceilings in `RestyleBudget.ceilings` are ADR-0082 §D9's and are **not**
changed here: the person fixes the new ones at G-ceiling-2.

The six rows, against ADR-0082 §D9's "after" (the full restyle with the `wikilinkSpans` fix):

| Size | Variant | Before this change | After, K = 5 (3) | After, K = 9 | Under 20 ms |
| --- | --- | --- | --- | --- | --- |
| 50 KB | prose | 198.43 | 6.05 | 5.81 | yes |
| 50 KB | fences | 225.34 | 7.90 | 7.35 | yes |
| 200 KB | prose | 911.37 | 22.57 | 22.55 | no, by 2.6 ms |
| 200 KB | fences | 1066.64 | 39.54 | 37.59 | no, by 17.6 ms |
| 1 MB | prose | 6308.79 | 124.19 | 121.96 | no |
| 1 MB | fences | 11843.73 | 536.49 | 522.68 | no |

That is 28 to 34 times less at 50 KB, 27 to 40 times at 200 KB and 22 to 51 times at 1 MB, and the six rows
pass ADR-0082 §D9's ceilings with room (596, 677, 2735, 3200, 18927 and 35532 ms). The proposal of 20 ms
holds at 50 KB only, in a Debug build; the Release app is faster, and G-type (R-15) is the hand check of
that.

**The rows that miss 20 ms, and where the time goes.** A profile (`sample`, 1 ms, of the 1 MB fences row
while it ran; the process was sampled for the whole of a `--runs 60` measurement) puts a keystroke's
10,220 main-thread samples in four places, none of them the restyle of the paragraph:

| Where | Share | Which of the plan's hints |
| --- | --- | --- |
| `NSTextView.insertText` → `NSTextStorage.processEditing` → `NSTextContentStorage.updateRangesForTextElement:locationDelta:` over every cached element (32%), plus `synchronizeTextLayoutManagers:` (7%) | 39% | none: TextKit's own range update, proportional to the number of paragraphs in the note |
| `growToFitTheText` → `NSTextLayoutManager.ensureLayoutForRange:` over the document range (`enumerateTextLayoutFragmentsFromLocation:`, `__NSTextLayoutManagerFillSoftInvalidationToLocation`) | 25% | `ensureLayout(for: documentRange)` |
| `willProcessEditing` → `recordStorageEdit` → `shiftDerivedState`: `shiftStyledRanges` (the unspellable and embed ranges, 9.5%) and `EditorDecorationDelegate.shift` (4.7%) | 15% | the linear shift of §D6, as designed |
| `textDidChange` → `renumberLists(in:touching:)` → `ListContinuation.renumbered(_:touching:)` (`codeFenceFlags`, `LineScan.lines`, 10.6%), and the incremental restyle itself (8.8%) | 19% | **not in the plan's hints** |

The `renumberLists(in:touching:)` term is new: it walks the whole text on every keystroke
(`LineScan.lines` and the code-fence flags), whatever it renumbers, and so it is the one that this design
could still remove without touching the layout. It is reported, not changed here. The `parent.text` copy
and `NoteFolding.layout` do not appear among the heavy frames of this profile (no fold is active in the
bench note). Re-scoping the layout stays out of scope (D10) and is a new decision with its own G-grow.

**The fallback rows** (printed, never asserted; the two runs agree within 13%; K = 9 below, ms of CPU):

| Size | Variant | `fence-open` | `table` | `list-enter` |
| --- | --- | --- | --- | --- |
| 50 KB | prose | 227.64 | 7.06 | 322.11 |
| 50 KB | fences | 255.09 | 8.28 | 334.01 |
| 200 KB | prose | 934.07 | 27.88 | 1376.05 |
| 200 KB | fences | 1215.37 | 43.70 | 1549.27 |
| 1 MB | prose | 5268.33 | 147.68 | 9033.04 |
| 1 MB | fences | 11688.01 | 504.31 | 13605.01 |

`fence-open` and `list-enter` cost what a full restyle costs, as the SPEC says they must (the "before"
column above is 198 to 11,844 ms for the same sizes), and `list-enter` more, because the Return also
rewrites the whole text and renumbers. A keystroke in a table cell restyles the table run only and costs
about what the plain keystroke costs. In the same profile the structure map's build pass is about 16% of
a full restyle (`RestyleScope.init(text:)` against `MarkdownStyler.spans(in:)` and the attribute writes):
the "full restyle gains the map's build pass" of the Consequences, measured.

## Gates

- **G-ceiling-2** (the person): look at the six "after" measurements and the three fallback rows,
  then fix the six ceilings (the SPEC proposes 20 ms CPU). The numbers are in "Measured after"
  (2026-10-11), and four of the six rows miss 20 ms in a Debug build; until the gate answers,
  `RestyleBudget.ceilings` holds ADR-0082 §D9's.
- **G-grow** (the person, R-14): on a Release build with a 1 MB note, type at the end and in the
  middle, press Cmd+Down, scroll to the end, and click low in the pane.
- **G-type** (the person, R-15): on a Release build with a 50 KB note, a typed sentence shows no
  perceptible lag.
- **Not decided here, left to the person:** narrowing `claimsListCommand`'s write and the
  whole-text renumber from `0..<length` to the span that changes. That would make Enter in a list
  restyle the list run instead of the note.

## References

- Root `SPEC.md` (Approved 2026-10-10) and the plan `docs/plans/per-paragraph-restyle.md`.
- ADR-0082 §D2 and §D5 to §D9; ADR-0077 §D1 and §D7; ADR-0074; ADR-0081 §D4; ADR-0033 §D3;
  ADR-0037 §D7; ADR-0001 §D1; ADR-0090.
- `PG-385`/#887 and PR #956 (`558db01c`).
- MacOSX27.0 SDK: `NSTextStorage.h:54-60`, `:84-88`, `:124`, `:129-142`, `:133-136` and `:138-141`;
  `NSTextContentManager.h:282-283`.
