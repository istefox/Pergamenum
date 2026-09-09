# ADR-0037: The reveal unit shrinks from the paragraph to the span

- Status: accepted
- Date: 2026-09-08
- Topic slug: `word-grained-markdown-reveal-on-caret-in`
- Amends **ADR-0018 §D2** ("Reveal is a rule about a paragraph, and it has four triggers") for
  three marker kinds only — emphasis, strikethrough and link — and only while a new,
  off-by-default setting is on. ADR-0018 §D1's length-preserving substitution, §D3's embed
  exception, §D5's caret rules and §D7's single governing setting are untouched.
- Amends **ADR-0028 §D1** (the note editor and the Workspace `.text` card share
  `EditorDecorationDelegate`) by adding a seventh input the card also carries, and nothing else.
- Does not reopen **ADR-0029 §D17** (the card's own span switch is the seam that keeps this
  chain's constructs out of a card), **ADR-0033 §D4** (a fence's reveal is keyed on its whole
  source range, not on a paragraph) or **ADR-0009** (query grammar).
- Depends on **PG-084** (`MarkdownStyler`'s inline-span parser is recursive for nested spans,
  `MarkdownStyler.swift:305-317`), which is what makes R-05 free rather than a new parser.

## Context

ADR-0018 §D2 chose the paragraph as the reveal unit and said why, in a sentence this ADR has to
answer rather than ignore:

> Rejected: **reveal per token, by comparing the caret to each delimiter's range** — muya's
> `checkConflicted()`. It is finer, it flickers less, and it is a second state machine that has
> to be kept in step with the parse. The paragraph is the unit the SDK's own invalidation works
> in, and matching the mechanism's granularity is what keeps the reveal from needing state at
> all.

Three things have changed since that was written, and together they are the whole case for
reopening it.

**C1 — the parse already produces the spans.** In August 2026 `MarkdownStyler` emitted the
delimiters and nothing that says which run they belong to. It does not any more.
`inlineSpans(in:absolute:)` emits a `.bold`/`.italic`/`.strikethrough` `StyledRange` covering the
**whole run, delimiters included**, and only then the two delimiter markers on top of it
(`MarkdownStyler.swift:292-319`); `wikilinkSpans` emits one `.linkSyntax` over the whole
`[[Curva]]` before painting `.linkTarget` on the title (`:509-519`). PG-084 then made the walk
recurse into a run's own inner slice (`:305-317`), so `**bold con *italic* dentro**` yields the
outer run **and** the inner one, in one pass, today, with no new code. The "second state machine
that has to be kept in step with the parse" is not needed: the construct extents come out of the
same walk the delimiters come out of, which is exactly the rule ADR-0018 §D1 set for the
delimiters themselves.

**C2 — the reveal is no longer stateless anyway.** ADR-0033 §D4 already keys one construct's
reveal on a **source range** rather than on a paragraph, because a fence's body lines are out of
the layout and a paragraph-keyed reveal loops. `NoteTextView+Coordinator.revealedViewBlock(in:
selection:)` is a pure `nonisolated static func` over `(String, NSRange)`, and `applyReveal`
already keeps a `lastRevealed` value to avoid re-invalidating. A range-keyed reveal beside a
paragraph-keyed one is a shape this codebase runs in production.

**C3 — the delegate's other inputs are all finished values pushed in from the view.** Seven of
them now (`hiddenLineOffsets`, `tableRowOffsets`, `viewBlockLineOffsets`, `foldedHeadings`,
`renditions`, `embedRenditions`, `hiddenMarkers`, plus the four pushed colours and two pushed
fonts). `EditorDecorationDelegate` cannot be `@MainActor` (Swift 6 refuses both conformances),
holds no text view and calls nothing back. Anything this feature needs at layout time has to
arrive the same way, and that constraint decides most of the design below.

### What the SPEC says that the source does not

Verified against the working tree at `98c7dac`, by grep, at the line. Each of these changes the
plan.

| # | SPEC premise | Source | Where |
|---|---|---|---|
| F1 | "Applies identically to the note editor and to Workspace `.text` cards" | **At plan time, the card concealed five marker kinds, not eight.** `CardTextView`'s own switch mapped `.headingMarker`, `.emphasisMarker`, `.embedRun`, `.listMarker`, `.taskMarker` and ended `default: nil` — `.strikethroughMarker` and `.linkSyntax` produced **no marker at all** in a card, so a card's `~~` and `[[ ]]` were visible and stayed visible. R-09 was about the *mechanism* being one, not about the construct set. **Superseded by D8's 2026-09-09 amendment: the switch now maps all seven kinds, matching the note editor.** | `CardTextView.swift:302-311`; §D8 below |
| F2 | "a per-paragraph scan that locates emphasis/link spans" | Three of the four constructs need no scan of their own — the run span already exists (C1). **The CommonMark `[testo](url)` form is the exception**: `markdownLinkSpans` emits `[` and `](url)` as two separate `.linkSyntax` ranges and never a whole-construct one, so its extent has to be reconstructed by pairing | `MarkdownStyler.swift:621-653` |
| F3 | (unstated) the caret can reach a collapsed span | **True, and only because ADR-0018 §D5's delimiter skip was never built for emphasis.** `NoteTextView+EmbedCaret.swift` claims `moveLeft:`/`moveRight:` for a drawn *embed* run only; a collapsed `**` is walked into character by character, exactly as the 2026-08-17 study measured. Had the skip shipped, this feature would need it removed | `NoteTextView+EmbedCaret.swift:25-28`; grep for `moveLeft` returns three files, none about emphasis |
| F4 | (unstated) `revealedParagraphs` has one reader | **Six.** The list, checkbox and blockquote branches each guard on it and return `nil`; the `.rule` fragment branch reads it at layout time; the generic substitution path bails on it; `MarkupReveal` produces it. Only the generic path changes | `EditorDecorationDelegate.swift:346`, `:443`; `+ListRendering.swift:26`; `+CheckboxRendering.swift:21`; `+QuoteRendering.swift:24` |
| F5 | "This follows the same persistence path as `hidesMarkup` (`VaultSettings`)" | True, **and `Sources/Vault/VaultSettings.swift` is in `sharedSources`** (`Project.swift:107`), so the new key compiles into `perg` and `pergamenum-mcp` as well. The SPEC's "connectors untouched" holds for behaviour and for capability, not for the file list. A `Bool` imports nothing, so `SharedSourcesPurityTests` stays green | `Project.swift:107` |
| F6 | (unstated) the setting can be pushed wherever the spans are | **It cannot be pushed from `applyReveal`**, which early-returns whenever the computed reveal equals `lastRevealed` — flipping the setting without moving the caret would leave the flag unpushed and the whole document drawn under the old rule | `NoteTextView+Reveal.swift:76-77`; `CardTextView+Reveal.swift:43` |

## Decision

### D1. The reveal gains a second unit, `revealedSpans`, and never merges it into the first

`EditorDecorationDelegate` gains one input beside `revealedParagraphs`:

```swift
nonisolated(unsafe) private var revealedSpans: [Int: [NSRange]] = [:]
func apply(revealedSpans: [Int: [NSRange]]) -> Set<Int>   // returns what changed, like apply(revealedParagraphs:)
```

Keyed by paragraph-start offset, values **paragraph-relative** — the exact key space
`hiddenMarkers` already uses, so a marker and a span are compared without a second coordinate
system. A separate table and not a widened `revealedParagraphs`, for the reason
`apply(tableRows:)`'s own header already gives for the fifth input: *"two producers on one setter
is precisely what the delegate's own header forbids"*. Clearing one must never clear the other.

The value is computed on the main actor, from the text and the selection, and handed over
finished. Nothing in the delegate parses anything at layout time.

### D2. Which unit governs a marker is a property of its kind, exhaustively

```swift
extension HiddenMarker.Kind {
    /// Whether this kind's reveal is span-grained under ADR-0037's setting, or stays
    /// paragraph-grained as ADR-0018 §D2 left it.
    var isInline: Bool { switch self { case .emphasis, .strikethrough, .link: true
                                       case .heading, .embed, .list, .checkbox,
                                            .blockquote, .rule, .table, .viewBlock: false } }
}
```

A `switch` with no `default`, so the eleventh kind cannot be added without answering the
question. The partition is not arbitrary: the five kinds with their own substitution branch
(`.embed`, `.list`, `.checkbox`, `.blockquote`, `.table`, `.viewBlock`) are already refused by
the generic path — `stillSpells` answers `false` for every one of them
(`EditorDecorationDelegate.swift:607-653`) — so `.heading` and `.rule` are the only block kinds
the generic path ever sees, and `.emphasis`/`.strikethrough`/`.link` are the only inline ones.
R-06 falls out of the table rather than being enforced by a rule someone has to keep.

### D3. The generic path stops bailing on the paragraph and filters marker by marker

`textContentStorage(_:textParagraphWith:)`'s last guard

```swift
guard !revealedParagraphs.contains(range.location), let markers = hiddenMarkers[...] else { return nil }
```

becomes a filter over the survivors, expressed as one pure static function so it is testable
without a text view:

```swift
static func collapsing(
    among survivors: [HiddenMarker],
    paragraphIsRevealed: Bool,
    revealedSpans: [NSRange]?          // nil == the setting is off
) -> [HiddenMarker]
```

- `revealedSpans == nil` → `paragraphIsRevealed ? [] : survivors`. **Byte-for-byte today** (R-07).
- otherwise → a marker is collapsed unless (`kind.isInline` and its range is contained in one of
  `revealedSpans`) or (not `kind.isInline` and `paragraphIsRevealed`).

An empty result returns `nil` from the hook exactly as an empty `survivors` does today, so a
revealed paragraph holding only a heading marker still returns `nil` and no substituted paragraph
is built. The tooltip pass (`linkTooltips`) is fed the **collapsed** set rather than the
survivors: a revealed link shows its own brackets and does not need a hover telling it where it
goes.

### D4. The construct extents come from `MarkdownStyler`, over one paragraph, never from a second parser

A new pure type, `InlineSpanReveal` (`Sources/Features/Editor/InlineSpanReveal.swift`), with two
functions and no state:

```swift
static func constructs(inParagraph paragraph: String) -> [NSRange]
static func revealed(inParagraph paragraph: String, touchedBy range: NSRange) -> [NSRange]
```

`constructs` runs `MarkdownStyler.spans(in: paragraph)` and keeps:

- every `.bold`, `.italic`, `.strikethrough` range — the whole run, delimiters included, nested
  runs included (C1);
- every `.linkSyntax` range whose text starts with `[[` — a wikilink's whole run;
- each `.linkSyntax` range that is exactly `[`, joined to the next `.linkSyntax` range starting
  with `](` — the CommonMark form's reconstructed extent (F2). `markdownLinkSpans` walks left to
  right and jumps past each closing paren, so the pairing is unambiguous by construction.

**Over one paragraph and not over the note**, which is what keeps this affordable: `applyReveal`
runs on every arrow key, and ADR-0018 measured `MarkdownStyler.spans` at 5.83 ms on a 17 KB note
against a 0.89 ms reveal round trip. A paragraph here is one line (`NSString.paragraphRange`
splits on `\n`), so the parse is bounded by the line the caret is on.

Parsing a paragraph in isolation can see markdown the whole-note pass does not — a `**bold**`
inside a code fence, a `[a](b)` in the frontmatter. **This is safe by construction and not by
care:** a span only ever *reveals a marker that exists*, and the whole-note pass produced no
marker there, so a phantom span reveals nothing. The failure mode of this design is a no-op, never
prose collapsed by mistake.

### D5. The predicate: a caret reveals the innermost span, a range reveals every span it meets

- **Collapsed caret at `p`**: a span `[s, e)` contains it when `s ≤ p ≤ e` — a **closed**
  interval, so a caret immediately before the opening delimiter or immediately after the closing
  one is inside (the SPEC's first edge case). Of the containing spans, only those of **smallest
  length** reveal; ties reveal together. Smallest-length *is* R-05: in
  `**bold con *italic* dentro**` the inner run is shorter than the outer, so a caret in the italic
  reveals `*…*` alone, and a caret in `bold con ` is contained only by the outer, which then
  reveals.
- **Non-empty range** (a selection, an IME marked range, the find bar's current match): every
  span it intersects with non-zero length reveals, innermost rule **not** applied. This is R-04,
  and it is also how ADR-0018 §D2's other three triggers survive the change of unit: *"what is
  copied must be what is seen"* stays true, an IME composing inside a collapsed run still sees it
  (probe 1), and a find match landing inside a collapsed run is still 7.8 points wide rather than
  0.01 (§D2's fourth trigger).

A paragraph **entirely covered** by a non-empty range contributes one span covering the whole
paragraph, with no parse at all. That is what bounds a Cmd+A to O(paragraphs) arithmetic instead
of O(note) parsing, and it needs no second set: "every inline marker in this paragraph reveals" is
expressible in the one table D1 introduces.

### D6. `MarkupReveal` gains a sibling function; its existing one is untouched

```swift
static func inlineSpans(
    in text: String, selection: NSRange, markedRange: NSRange, currentMatch: NSRange?
) -> [Int: [NSRange]]
```

beside `MarkupReveal.paragraphs(in:selection:markedRange:currentMatch:)`, in the same file, taking
the same four inputs and reading the same triggers. Both surfaces call both, and neither
reimplements the other — the reason `CardTextView+Reveal` calls the note editor's pure function
today rather than copying it.

**Invariant, asserted rather than assumed:** every paragraph key in `inlineSpans`' answer is also
in `paragraphs`' answer for the same inputs. That is what keeps D3's change confined to the
generic path: the list, checkbox and blockquote branches all return `nil` for a paragraph in
`revealedParagraphs` (F4), so they can never be handed a paragraph that has revealed spans, and
they need no edit.

### D7. The setting is a `VaultSettings` Bool, default false, pushed from `applyStyling`

`VaultSettings.revealsInlineSpans: Bool`, defaulted `false` in `.default`, in the memberwise
initialiser and in `init(from:)`'s `decodeIfPresent` fallback — `readableWidth`'s exact shape
(`VaultSettings.swift:194-195`, `:225`), so a `settings.json` written before today reads as off
and no vault changes behaviour on update (R-07).

Pushed to the delegate in **`applyStyling`**, beside `apply(hiddenMarkers:hidingMarkup:)` and
before `storage.endEditing()`, through its own small setter `apply(revealsInlineSpans:)`. Never
from `applyReveal`, for F6's reason: that pass early-returns when the selection has not moved, and
a settings flip moves nothing. `applyStyling` is called unconditionally from both `updateNSView`s
(`NoteTextView.swift:328`, `CardTextView.swift:138`) and its `endEditing()` fires the
document-wide `.editedAttributes` that re-invokes the hook, so flipping the toggle redraws the
open note with no further plumbing.

In Impostazioni the toggle sits directly under "Nascondi i marcatori mentre scrivi" and is
`.disabled` while that one is off — with `hidesMarkup` false the substitution hook returns `nil`
on its first line and this setting cannot do anything at all. Label, caption and identifier follow
the section's existing shape (`themedText(.caption, color: .textTertiary)`, so every colour and
font goes through a token; identifier `settings-reveals-inline-spans`, never the words on it).

### D8. The card carries the setting down the route the card's settings already travel

`vault.settings.revealsInlineSpans` → `WorkspaceView.applyBoardSettings()` →
`WorkspaceController.revealsInlineSpans` → `StickyTextCard` → `CardTextView` → its coordinator →
the shared delegate. The same route `hidesMarkup` takes, and for the same stated reason: a
`@Environment(VaultController.self)` read inside a card crashes a card built in a preview or a
test (ADR-0028 §D10).

`releaseDecorations()` clears the new table with the others: a span offset surviving its text is
the same stale-offset defect as a marker surviving it.

**Amendment, 2026-09-09 (R-11 hand check).** At plan time, D8 stopped here: a card got bold and
italic only (F1), because `CardTextView`'s marker switch is ADR-0029 §D17's seam against a live
`NSView` table grid ever landing in a card whose text view is deallocated on culling-rect
crossings, and this chain did not widen it.

During the R-11 hand check, seeing the card leave `[[wikilink]]`, `[testo](url)` and `~~barrato~~`
uncollapsed while the note editor concealed all three was judged wrong on sight, and the decision
is reversed by explicit instruction: **the card now conceals strikethrough and link/wikilink
syntax identically to the note editor.** `CardTextView.Coordinator.applyStyling` widens its switch
to the same seven `HiddenMarker.Kind` cases `NoteTextView.Coordinator.hiddenKind(for:)` maps
(`+strikethrough`, `+link`), and reuses `NoteTextView.Coordinator.linkDelimiters(in:of:)` unchanged
for the `.link` case — a link's whole run is never one marker, only its bracket/paren delimiters
are, exactly as the note editor already does.

This does not reopen ADR-0029 §D17's actual seam: that seam exists to keep a table's live
`NSView` grid out of a culling-deallocated card view, and `.strikethrough`/`.link` involve no
`NSView` at all, only the same length-preserving character substitution `.emphasis` already uses
in a card. The risk the seam protects against is untouched; only its `default: nil` catch-all,
which had been drawn wider than that risk required, is narrowed back to the two kinds it was
actually protecting (`.table`, and any future construct needing a live view provider).

The reveal-on-caret half needed no change: `CardTextView+Reveal.swift`'s `applyReveal` already
called `MarkupReveal.inlineSpans` unconditionally, which computes spans for every inline
`HiddenMarker.Kind` generically — it was only ever starved of `.link`/`.strikethrough` markers to
compute spans *from*, not written to exclude them.

## Alternatives considered

**A1 — carry the construct's range on `HiddenMarker` itself** (a third field, `owner: NSRange`,
paragraph-relative, equal to the marker's own range for block kinds). The delegate would then
answer the whole question locally.
*Rejected:* `HiddenMarker` is an `Equatable` value constructed at three production sites and read
by five delegate files, and built by hand in at least six test files
(`MarkupHidingTests`, `CardConcealmentTests`, `QuoteRenderingTests`, `EmbedDrawingTests`,
`TableRenderingTests`, `ListNestingTests`). Adding a field changes `==` for every one of them.
And it buys nothing: the delegate would still need the caret and the selection pushed in to
compare against, which is the very input D1 adds — one new input either way, and this way the
existing struct does not move.

**A2 — reconstruct the spans inside the delegate by pairing consecutive markers of the same
kind.** `[openBold, closeBold, openItalic, closeItalic]` is the order the recursive walk appends
them in, so pairing by position would work today.
*Rejected:* it is an ordering contract nobody wrote down, over an array that mixes kinds and that
`survivors` has already filtered — one marker gone stale against the live characters and every
pair after it shifts by one, silently, at layout time. `linkTooltips` already pairs brackets this
way (`+LinkRendering.swift:48-57`) and can afford to, because a mispaired tooltip is a wrong
hover; a mispaired *reveal* is prose collapsed to nothing.

**A3 — push the selection into the delegate and compute the reveal at layout time.**
*Rejected:* the hook is called once per paragraph per layout pass, so a parse in there is a parse
per drawn paragraph rather than per caret move — the opposite of the bound D4 buys. The delegate
is also not `@MainActor`, holds no text view and calls nothing back; every other input it has is
a finished value, and this would be the first that is not.

**A4 — a dedicated inline parser (`InlineConstruct.spans(in:)`) written for this feature.**
*Rejected:* ADR-0018 §D1's own rule — *"the delimiter ranges come from `MarkdownStyler` … and not
from a second parser … it also makes disagreement impossible: the characters that are hidden and
the characters that are coloured come out of one pass over one string"*. A separate grammar for
*where a construct begins* would reintroduce exactly the disagreement that rule exists to
prevent, and PG-084 has already paid for the recursion this would have to re-derive.

**A5 — replace `revealedParagraphs` with `revealedSpans` outright, one unit for everything.**
*Rejected:* R-06 requires the heading, list, blockquote, checkbox, table, fence and rule
constructs to keep paragraph granularity, and four of them read `revealedParagraphs` at their own
guard (F4). A single unit would mean teaching six branches a new coordinate system to get today's
behaviour back, and the `.rule` fragment branch has no span to speak of at all — a thematic break
*is* its paragraph.

**A6 — ship it on by default, or with no setting at all.**
*Rejected* by R-07 and by ADR-0018 §D7's reasoning, which applies unchanged: this changes what the
editor looks like while someone types, and *"a ruling that has to be reverted in code if the
reveal rule does not convince is a ruling nobody will test honestly."* Off by default also makes
the whole chain's regression surface a single boolean, which is what lets the existing
`MarkupHiding` suite stay green unmodified.

**A7 — recompute the spans over the whole note on every selection change.** Simpler: one call,
no paragraph keying, no fully-covered shortcut.
*Rejected* on the measurement ADR-0018 already took: `MarkdownStyler.spans` costs 5.83 ms on a
17 KB note, `applyReveal` runs on every arrow key, and the reveal round trip it replaces is
0.89 ms. Multiplying the cost of a keypress by seven for a feature whose only stated budget is
"no perceptible typing lag" is a bad trade when the caret is provably inside one paragraph.

**A8 — extend `apply(hiddenMarkers:hidingMarkup:)` with a third parameter instead of adding a
setter.** *Rejected:* the existing signature is called from both surfaces and from six test
files; a defaulted third parameter would keep them compiling but would also make the guard
inside it (`markers != hiddenMarkers || hides != hidesMarkup`) silently swallow a flag-only
change. A four-line setter with its own guard is cheaper to read and impossible to get wrong.

## Consequences

**Positive**

- A long paragraph stops flashing every marker it holds when the caret enters it. That is the
  whole feature, and it is the thing NotePlan and Typora are actually judged on.
- R-05 is free rather than expensive: PG-084's recursion already emits the inner run, so
  "innermost" is `min(by: length)` over ranges that exist.
- The regression surface is one boolean. With the setting off, `collapsing(among:…)` returns
  `paragraphIsRevealed ? [] : survivors`, which is character-for-character today's guard, so the
  whole existing `MarkupHiding`, `CardConcealment`, `QuoteRendering`, `TableRendering` and
  `ListNesting` suites stay green **unmodified** — and the one test that pins today's contract
  directly, `theHookReturnsNilForARevealedParagraph`, keeps passing on the delegate's own default.
- The out-of-scope list is enforced by an exhaustive `switch` on `HiddenMarker.Kind` rather than
  by six branches each remembering to opt out.
- No persisted change of any kind: no frontmatter key, no index field, no `.canvas` property, no
  migration, `IndexCache.schemaVersion` stays 3, and no protected interface is touched.

**Negative**

- **Text moves under the caret more often.** Arrowing along a line now re-wraps the paragraph
  each time a span is entered or left, where before it re-wrapped once on entering the paragraph.
  ADR-0018's probe 5 (word wrap) is re-opened at a higher frequency, and it is a hand check, not a
  test. Smaller jumps, more of them; this is the cost the SPEC's own UI flow describes and accepts.
- **A collapsed span inside the caret's own paragraph is now reachable by the caret**, which the
  paragraph rule made impossible. The caret visits the same visual position twice crossing a
  collapsed `**` (measured 2026-08-17, `moveLeft` from offset 3 visited 2, 1, 0, 0). Nothing is
  wrong with the file; it looks like a dead keypress. ADR-0018 §D5's delimiter skip was never
  built for emphasis (F3) and this ADR does not build it either — it would defeat the reveal it
  is meant to serve.
- **A card got less than the note editor at plan time** (F1, D8) — reversed 2026-09-09: the card
  now conceals and reveals strikethrough and link/wikilink syntax identically to the note editor,
  so the SPEC's original "identically" claim now holds for the construct set as well as the
  mechanism.
- **A phantom span inside a code fence is possible** (D4). Harmless by construction, but it is a
  real difference between what `InlineSpanReveal` sees and what the note's own styling pass sees,
  and a future reader who assumes the two agree will be wrong.
- **`Sources/Vault/VaultSettings.swift` is a `sharedSources` file** (F5). The key travels into
  `perg` and `pergamenum-mcp` binaries that will never read it. Zero behaviour, one line of
  compiled code, and the alternative — a settings home the app and the connectors do not share —
  is worse.

**Neutral**

- The delegate gains its seventh independently-set table and its second boolean. Both follow the
  pattern the other six already set, including the returns-what-changed shape of
  `apply(revealedParagraphs:)` so the caller invalidates two paragraphs and not a document.
- `MarkupReveal` grows a second entry point rather than a second file. It is the same rule asked
  two ways, and the file's own header already says reveal is a self-contained concern.
- The new setting is per-vault, not per-user, on ADR-0012 §D6's question and `hidesMarkup`'s
  precedent — how a vault is read is a fact about the vault.
- Nested reveal is asymmetric between a caret (innermost only) and a selection (all intersected).
  Deliberate, stated in D5, and the asymmetry is the SPEC's: R-05 speaks of the caret, R-04 of the
  selection.

## References

- `SPEC.md` (this chain) — R-01 … R-11
- ADR-0018 `docs/adr/0018-the-editor-hides-the-syntax-it-can-draw.md` — §D1 substitution, §D2 the
  four triggers and the rejected per-token reveal, §D5 caret rules, §D7 the one setting
- ADR-0028 `docs/adr/0028-wysiwyg-markdown-in-workspace.md` — §D1 the shared delegate, §D10 the
  settings route into a card
- ADR-0029 `docs/adr/0029-editor-wysiwyg-unification.md` — §D1 strikethrough/link/rule markers,
  §D17 the card's exclusion seam
- ADR-0033 `docs/adr/0033-views-render-live-in-the-editor.md` — §D4 a reveal keyed on a source
  range, §D5 the crossing guard
- ADR-0030 §D5 — values pushed into the delegate because it cannot read a `Theme`
- PG-084 — `MarkdownStyler.swift:305-317`, the recursive inline walk this ADR depends on
- `docs/20260817_TextKit2_live_editing.md` — the 5.83 ms parse and 0.89 ms reveal measurements
