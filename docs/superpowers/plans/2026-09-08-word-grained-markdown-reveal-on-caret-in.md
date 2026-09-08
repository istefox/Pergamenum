# Plan — Word-grained markdown reveal-on-caret in the editor

- **ADR:** `docs/architecture/ADR-0037-word-grained-markdown-reveal-on-caret-in.md`
  (the orchestrator relocates it to `docs/adr/0037-word-grained-markdown-reveal-on-caret-in.md`,
  the ADR-0033/ADR-0034 precedent — the architect's write scope is `docs/architecture/`, this
  repo's ADRs live in `docs/adr/`)
- **SPEC:** `SPEC.md` (R-01 … R-11)
- **BRAINSTORM / UX blueprint / Claude Design:** none. Both optional gates were declined —
  this is a rendering change with direct precedent in ADR-0018, ADR-0028 and ADR-0029.
  **Do not go looking for them.**
- **Branch:** `feature/word-grained-markdown-reveal`, worktree
  `/Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal`, base
  `98c7dac` (merge of PR #181, ADR-0035's adaptive view-block height). Everything ADR-0018,
  ADR-0028, ADR-0029, ADR-0033 and PG-084 shipped is present and is the shape every task below
  builds on.
- **Style:** TDD. Red precondition first on every task, per this repo's last nine chains.
- **Nothing in `MarkdownStyler` is edited.** `spans(in:)`, `inlineSpans(in:absolute:)`,
  `wikilinkSpans`, `markdownLinkSpans`, `delimiterMarkers` and the `Span` enum are used exactly as
  merged. If a task looks like it needs a new `Span` case, **stop and report** — that is ADR §D4
  and A4 failing, not a detail.

---

## Before anything: what the SPEC says that the source does not

Verified against the working tree at `98c7dac`, by grep, at the line. **Do not design or code
against the left column.**

| # | SPEC says | Source says | Where |
|---|---|---|---|
| F1 | the feature "applies identically to the note editor and to Workspace `.text` cards" | **A card conceals five marker kinds, not eight.** Its own switch maps `.headingMarker`, `.emphasisMarker`, `.embedRun`, `.listMarker`, `.taskMarker`, then `default: nil`. A card's `~~testo~~` and `[[Nota]]` produce **no `HiddenMarker` at all** — they are visible today and stay visible. R-09 is the mechanism being one; **the card's switch is not widened** (ADR-0029 §D17) | `CardTextView.swift:288-296` |
| F2 | "a per-paragraph scan that locates emphasis/link spans" is needed | Three of four constructs need no scan: `.bold`/`.italic`/`.strikethrough` `StyledRange`s already cover the **whole run including delimiters**, and PG-084's recursion already emits the nested inner run. `wikilinkSpans` already emits one `.linkSyntax` over the whole `[[…]]`. **Only the CommonMark `[testo](url)` form has no whole-construct span** and must be reconstructed by pairing `[` with the next `](…)` | `MarkdownStyler.swift:292-319`, `:305-317`, `:509`, `:621-653` |
| F3 | (unstated) the caret can reach a collapsed span | True, and only because **ADR-0018 §D5's delimiter skip was never built for emphasis** — `NoteTextView+EmbedCaret.swift` claims `moveLeft:`/`moveRight:` for a drawn embed run only. **Do not add a skip**; it would defeat the reveal | `NoteTextView+EmbedCaret.swift:25-28` |
| F4 | (unstated) `revealedParagraphs` has one reader | **Six.** list / checkbox / blockquote each guard on it and return `nil`; the `.rule` fragment branch reads it; the generic path bails on it; `MarkupReveal` produces it. **Only the generic path is edited** | `EditorDecorationDelegate.swift:346`, `:443`; `+ListRendering.swift:26`; `+CheckboxRendering.swift:21`; `+QuoteRendering.swift:24` |
| F5 | the setting "follows the same persistence path as `hidesMarkup` (`VaultSettings`)" | True, **and `Sources/Vault/VaultSettings.swift` is a `sharedSources` file** — the key compiles into `perg` and `pergamenum-mcp`. A `Bool` imports nothing, so `SharedSourcesPurityTests` stays green; **no connector capability is added** | `Project.swift:107` |
| F6 | (unstated) the setting can be pushed with the spans | **It cannot be pushed from `applyReveal`** — that pass early-returns when the computed reveal equals `lastRevealed`, so flipping the toggle without moving the caret would leave the flag unpushed. It is pushed from `applyStyling`, which both `updateNSView`s call unconditionally | `NoteTextView+Reveal.swift:76-77`; `CardTextView+Reveal.swift:43`; `NoteTextView.swift:328`; `CardTextView.swift:138` |
| F7 | (unstated) the generic path sees every marker kind | **It sees four.** `stillSpells` answers `false` for `.embed`, `.list`, `.checkbox`, `.blockquote`, `.table`, `.viewBlock` — each has its own branch. Only `.heading`, `.emphasis`, `.strikethrough`, `.link` and `.rule` reach the collapsing loop | `EditorDecorationDelegate.swift:607-653` |
| — | Out of scope and greppable: `MarkdownStyler.swift`, `EditorDecorationDelegate+ListRendering/+CheckboxRendering/+QuoteRendering/+TableRendering/+ViewBlockRendering.swift`, `NoteTextView+EmbedCaret.swift`, `MarkdownBlocksView.swift`, `NoteExporter.swift`, `Sources/Core/**`, `Sources/Connector/**`, `Sources/CLI/**`, `Sources/MCPServer/**` | **None of these appears in this chain's diff.** Task 8 asserts it | ADR §D2, §D3, §D8 |

**Three constraints the SPEC could not know** (ADR §Context):

1. **`EditorDecorationDelegate` is not `@MainActor` and never will be** — Swift 6 refuses both
   conformances. Every input it holds is a finished value pushed in from the view. The span table
   is the seventh; it is computed on the main actor and handed over, never computed at layout time.
2. **A substituted paragraph must have the same length as the stored one**
   (`NSTextContentManager.h:120`). This chain adds no substitution of its own — it only decides
   *which* markers the existing `collapsedFont` loop is applied to — so the constraint is kept by
   construction. **No task may add, remove or replace a character.**
3. **The invariant the whole design rests on:** every paragraph key in the span table is also in
   `revealedParagraphs` for the same inputs. That is why list/checkbox/blockquote need no edit —
   they return `nil` for a revealed paragraph and can never be handed a span. **Task 7 asserts it.**

---

## Contract changes and their already-grepped call sites

Every row is a stale-assertion site found by grep **before** this plan was written. The coder does
not go looking for these; they are listed, and they are updated in the same task that changes the
contract. **Run the full unit suite after each task, not just the touched file's tests** — a
contract change breaks tests in files that never mention it.

| Contract | Change | Call sites |
|---|---|---|
| `EditorDecorationDelegate.textContentStorage(_:textParagraphWith:)` | its last guard becomes a per-marker filter (ADR §D3) | **Behaviour is gated on a flag that defaults `false`, so every existing test stays green unmodified.** The one that pins today's contract directly is `Tests/MarkupHidingTests.swift:127` (`theHookReturnsNilForARevealedParagraph`) — it must stay green **without being edited**; if it goes red the default is wrong. Also exercised indirectly by `Tests/QuoteRenderingTests.swift`, `Tests/TableRenderingTests.swift`, `Tests/ListNestingTests.swift`, `Tests/CardConcealmentTests.swift`, `Tests/EmbedDrawingTests.swift` |
| `HiddenMarker.Kind` | gains a computed `isInline` (no new case, no stored property) | `Equatable`/`Sendable` synthesis unchanged — a computed property is not part of `==`. Zero breakage. Constructed by hand in `Tests/MarkupHidingTests.swift`, `CardConcealmentTests.swift`, `QuoteRenderingTests.swift`, `EmbedDrawingTests.swift`, `TableRenderingTests.swift`, `ListNestingTests.swift`; **none is edited** |
| `EditorDecorationDelegate` | new `apply(revealedSpans:) -> Set<Int>`, new `apply(revealsInlineSpans:)` | Both new. `apply(hiddenMarkers:hidingMarkup:)` is **not** touched (ADR A8), so its six test call sites stay unmodified |
| `MarkupReveal` | new `inlineSpans(in:selection:markedRange:currentMatch:)` | New. `paragraphs(...)` is unchanged — `Tests/MarkupRevealTests.swift`'s nine tests stay green unmodified |
| `NoteTextView` | new `var revealsInlineSpans = false` (**defaulted**) | **Additive.** Three production sites pass it: `EditorColumn+Text.swift:47`, `DiaryView.swift:88`, `TodayView.swift:192`. Fourteen test construction sites stay **unmodified** (`FoldBadgeClickTests:22`, `NoteFindTests:271`, `EmbedResolutionTests:56`, `ViewQueryEntryPointTests:69/:138/:254`, `EmbedEditorTestSupport:53`, `MarkupHidingTests:970`, `EmbedDrawingTests:178`, `ViewBlockCaretTests:52`, `ViewQueryOutOfScopeTests:25`, `ViewBlockRenderingTests:350/:385`, `NoteListEditingTests:54`, `TranscludedLineTests:36/:117`, `ViewQueryCommitTests:41`) |
| `CardTextView` | new `var revealsInlineSpans = false` (**defaulted**, not a `let`) | **Additive.** One production site: `StickyTextCard.swift:53`. Six test sites stay unmodified (`CardFoldTests:79`, `ViewQueryOutOfScopeTests:57`, `CardConcealmentTests:56`, `CardFormattingTests:286/:490`, `CardRoundTripTests:70`) |
| `WorkspaceController` | new `var revealsInlineSpans = false` | Set in `WorkspaceView.applyBoardSettings()` beside `hidesMarkup` (`WorkspaceView.swift:483`). `Tests/WorkspaceControllerTests.swift` constructs the controller; a defaulted `var` breaks nothing |
| `VaultSettings` | new `revealsInlineSpans: Bool`, `false` in `.default`, defaulted in the memberwise init, `decodeIfPresent` in `init(from:)` | **No call site breaks** — the memberwise parameter is defaulted, `readableWidth`'s exact shape (`VaultSettings.swift:225`). `Tests/VaultTests.swift:680-692` is the pattern the new decode test copies |
| `CardTextView.Coordinator.releaseDecorations()` | clears the span table too | One site, `CardTextView.swift:337-345`. `Tests/CardConcealmentTests.swift:273-277` asserts the clear returns nothing changed — extend, do not replace |
| New file `Sources/Features/Editor/InlineSpanReveal.swift` | new | `tuist generate --no-open` after the task that adds it |
| New file `Tests/InlineSpanRevealTests.swift` | new | same |

**Protected interfaces — none touched, checked one by one:** `IndexCache.schemaVersion` (no index
field, no schema question in this chain), `VaultAPI.LintFinding` (no connector change),
`CompletingTextView+Pasteboard.swift` (no paste path, no drop path, no `Transferable` — that file
is not opened), `ImportNaming.recordingNoteTitle` (unrelated).
**`interface-check.sh` must stay silent for the whole chain.**

---

## Conventions binding on every task

- **The tester owns the interface, the coder owns the body.** Swift is compiled: a batch that
  leaves the target unable to build produces no red tests at all, only a build error. Every new
  type's *declaration* (stored properties, method signatures returning a stub, computed
  properties) is written in the **tester's** task together with the tests that call them. The
  coder fills in bodies.
- **`tuist generate --no-open` after every task that adds a file under `Sources/` or `Tests/`.**
  Also after any `git stash`/`git checkout` that adds or removes a file.
- **Swift Testing (`@Test`/`#expect`) for all new tests.** Never XCTest outside `UITests/`.
- **Every new or extended test suite's header comment cites both `ADR-0037` and this plan's
  basename** (`2026-09-08-word-grained-markdown-reveal-on-caret-in`). That citation is this
  chain's coverage anchor — there is no separate harness script, so the test files are what names
  the plan, exactly as the last two chains did.
- **Nothing under `Sources/Core/**`, `Sources/Connector/**`, `Sources/CLI/**`,
  `Sources/MCPServer/**` is added or edited.** The one shared file this chain touches is
  `Sources/Vault/VaultSettings.swift` (F5), and it gains a `Bool` and nothing else — no import, no
  function, no capability. `SharedSourcesPurityTests` must stay green.
- **`MarkdownStyler.swift` is not edited.** Not one line, not a new `Span` case (ADR A4).
- **No hardcoded colour, font, spacing or radius in any view.** The settings toggle and its
  caption go through `themedText(_:color:)` exactly like the two toggles above them. A view that
  uses a colour without a token does not pass review (CLAUDE.md).
- **UI language is Italian; code, comments, commits and this plan's artefacts are English.**
- **Accessibility identifier, never the words on a control** (CLAUDE.md: prose grows, identifiers
  are the contract). The new one is `settings-reveals-inline-spans`.
- **The unit test command is `.claude/test-cmd` exactly as it stands** — `-only-testing:PergamenumTests`.
  **Do not widen it**: the UI suite in there terminates the app the person at the keyboard is
  using and leaves an instance holding the global hot key exclusively (CLAUDE.md, two hours lost
  once). The UI suite is run once, deliberately, in Task 8, through `scripts/uitests.sh`.
- **The pre-commit `weakening-scan.sh` reports every Swift Testing test as
  `zero-assertion-test`** — systematically wrong for this stack (CLAUDE.md). Read the diff; do not
  act on that finding.

---

## Phase 1 — the pure half (no delegate, no AppKit, no text view)

### Task 1 — `InlineSpanReveal`: what a construct is, and which one the caret is in (R-01, R-02, R-04, R-05, R-10)

New file `Sources/Features/Editor/InlineSpanReveal.swift`, an `enum` namespace with no state and
two static functions, both taking a plain `String` paragraph:

```swift
static func constructs(inParagraph paragraph: String) -> [NSRange]
static func revealed(inParagraph paragraph: String, touchedBy range: NSRange) -> [NSRange]
```

- `constructs` runs `MarkdownStyler.spans(in: paragraph)` and keeps, converted to UTF-16
  `NSRange` with `NSRange(_:in:)`: every `.bold`/`.italic`/`.strikethrough` range as-is; every
  `.linkSyntax` range whose text starts with `[[` as-is; and each `.linkSyntax` range that is
  exactly `[`, joined to the **next** `.linkSyntax` range starting with `](` (F2). Sorted by
  location. Duplicates removed.
- `revealed` applies ADR §D5: for `range.length == 0`, the containing spans are those with
  `s ≤ p ≤ NSMaxRange(span)` (**closed** interval — the SPEC's adjacency edge case) and only those
  of minimum length are returned, ties included; for `range.length > 0`, every span with
  `NSIntersectionRange(span, range).length > 0` is returned, with **no** innermost filtering.

**Tester** writes `Tests/InlineSpanRevealTests.swift` plus both signatures returning `[]`. Red
first. At minimum: `**grassetto**` alone; two bold runs in one line with the caret in the first
(the R-01 multi-span case); `~~barrato~~`; `[[Nota]]`; `[[Nota reale|testo mostrato]]`;
`[testo](https://x.y)` reconstructed whole; **two CommonMark links on one line** revealing only
the one touched (the pairing's real test); `**bold con *italic* dentro**` with the caret in the
inner run returning the inner range only, and with the caret in `bold con ` returning the outer
only (R-05); a caret exactly at the first `*` and exactly after the last `*` both revealing
(adjacency); a selection across two runs returning both (R-04); a line with no construct returning
`[]`; an out-of-bounds and an `NSNotFound` range returning `[]` without crashing.

**Coder** fills both bodies. No `MarkdownStyler` edit.

- Budget: `Sources/Features/Editor/InlineSpanReveal.swift`, `Tests/InlineSpanRevealTests.swift` (~300 lines)

### Task 2 — `MarkupReveal.inlineSpans`: the note-wide table, keyed by paragraph (R-01, R-02, R-04, R-10)

In `Sources/Features/Editor/NoteTextView+Reveal.swift`, beside the untouched
`MarkupReveal.paragraphs`:

```swift
static func inlineSpans(
    in text: String, selection: NSRange, markedRange: NSRange, currentMatch: NSRange?
) -> [Int: [NSRange]]
```

Same three triggers, same `NSNotFound` guard on `markedRange`, same out-of-bounds tolerance as
`add(_:of:to:)`. For each trigger range, walk the paragraphs it touches; for a paragraph
**entirely covered** by a non-empty trigger range, emit one span `NSRange(0, paragraph.length)`
and do not parse (ADR §D5); otherwise call `InlineSpanReveal.revealed` on that paragraph's
substring with the trigger range translated into paragraph-relative coordinates. Values are
paragraph-relative, keyed by paragraph-start offset — `hiddenMarkers`' key space.

**Tester** extends `Tests/MarkupRevealTests.swift` with a second suite and writes the signature
returning `[:]`. Red first. At minimum: a caret in the second paragraph keying only that
paragraph; a selection spanning two paragraphs keying both; a fully-covered middle paragraph
yielding exactly one whole-paragraph span with no parse-dependent content; the find-bar match as a
trigger (R-04's mechanism serving ADR-0018 §D2's fourth trigger); an IME `markedRange` as a
trigger; `NSNotFound` and past-the-end ranges yielding `[:]` and not crashing; and **the
invariant**: for a set of inputs, every key of `inlineSpans` is a member of `paragraphs` for the
same inputs (constraint 3 above — asserted again structurally in Task 7).

**Coder** fills the body.

- Budget: `Sources/Features/Editor/NoteTextView+Reveal.swift`, `Tests/MarkupRevealTests.swift` (~200 lines)

---

## Phase 2 — the delegate

### Task 3 — the per-marker filter, and the two new inputs (R-01, R-02, R-03, R-05, R-06, R-07, R-10)

In `Sources/Features/Editor/EditorDecorationDelegate.swift`:

- `HiddenMarker.Kind.isInline` — a computed `Bool`, `switch` with **no `default`**, `true` for
  `.emphasis`/`.strikethrough`/`.link` and `false` for the other eight (ADR §D2).
- `nonisolated(unsafe) private var revealedSpans: [Int: [NSRange]] = [:]` and
  `func apply(revealedSpans:) -> Set<Int>` returning the symmetric difference of the **keys**, the
  shape `apply(revealedParagraphs:)` has, so the caller invalidates two paragraphs and not a
  document. No logging (this runs on every arrow key).
- `nonisolated(unsafe) var revealsInlineSpans = false` and a guarded
  `func apply(revealsInlineSpans:)`. **`apply(hiddenMarkers:hidingMarkup:)` is not touched.**
- `static func collapsing(among:paragraphIsRevealed:revealedSpans:) -> [HiddenMarker]` — ADR §D3's
  table, `nil` spans meaning the setting is off.
- The hook's last guard rewritten to call it, and `linkTooltips` fed the **collapsed** set rather
  than the survivors. `guard !collapsing.isEmpty else { return nil }` keeps the empty case
  returning `nil` exactly as today.

**Tester** extends `Tests/MarkupHidingTests.swift` with a new `@Suite` (the existing
`displayedParagraph`/`substitutedParagraph` helpers gain a defaulted `spans:`/`revealsInlineSpans:`
parameter rather than being replaced) and writes the declarations. Red first. At minimum:

- setting **off** + revealed paragraph → hook returns `nil` (R-07, and
  `theHookReturnsNilForARevealedParagraph` stays green **unedited**);
- setting **on** + revealed paragraph + one bold span revealed + a second bold span in the same
  paragraph → exactly the second span's two markers carry `collapsedFont`, the first's do not
  (R-01);
- the same for a `.link` marker pair (R-02);
- caret moved out (empty span table, paragraph still revealed) → every inline marker collapsed
  again (R-03);
- nested: outer + inner markers present, inner span revealed → outer's two collapsed, inner's two
  not (R-05);
- **R-06 by kind**: a paragraph carrying a `.heading` marker and a bold run, revealed, setting on
  → the heading marker is **not** collapsed (paragraph rule) while the bold markers are; a `.rule`
  marker is likewise governed by the paragraph;
- `isInline` answers `false` for all eight block kinds (a compile-checked exhaustive switch plus
  one assertion per kind);
- `apply(revealedSpans:)` returns the changed keys and `[:]` twice returns nothing.

**Coder** fills the bodies. **The list, checkbox, blockquote, table, view-block and embed branches
are not edited** (F4, F7) — if one looks like it needs to be, stop and report.

- Budget: `Sources/Features/Editor/EditorDecorationDelegate.swift`, `Tests/MarkupHidingTests.swift` (~260 lines)

---

## Phase 3 — the setting and the two surfaces

### Task 4 — the setting, stored and offered (R-07, R-08)

- `Sources/Vault/VaultSettings.swift`: `revealsInlineSpans: Bool` with a doc comment naming
  ADR-0037 and saying why it is off by default; `false` in `.default`; `revealsInlineSpans: Bool = false`
  in the memberwise initialiser; `decodeIfPresent(…) ?? fallback.revealsInlineSpans` in
  `init(from:)`. Nothing else in that file changes.
- `Sources/Features/Settings/EditorSettings.swift`: a `Toggle` immediately after the
  `hidesMarkup` toggle and its caption, reading and writing through
  `vault.updateSettings { $0.revealsInlineSpans = … }`, `.accessibilityIdentifier("settings-reveals-inline-spans")`,
  `.disabled(!vault.settings.hidesMarkup)` (ADR §D7 — with markup shown the hook is a no-op), and
  an explanatory `Text(...).themedText(.caption, color: .textTertiary)` in Italian saying that
  grassetto, corsivo, barrato and collegamenti show their syntax only where the cursor is, and
  that titoli, elenchi, citazioni e tabelle are unchanged.

**Tester** extends `Tests/VaultTests.swift` copying `readableWidthDefaultsToTrueAndAnOlderSettingsFileStillReadsTrue`
(`:680-692`) exactly: default is `false`; a `settings.json` written before the key exists still
decodes `false`; `{"dailyFolder":"Calendar","revealsInlineSpans":true}` decodes `true`; and a
round trip through `JSONEncoder`/`JSONDecoder` preserves it. Red first.

**Coder** adds the property and the toggle.

- Budget: `Sources/Vault/VaultSettings.swift`, `Sources/Features/Settings/EditorSettings.swift`, `Tests/VaultTests.swift` (~90 lines)

### Task 5 — the note editor wiring (R-01, R-02, R-03, R-04, R-07)

- `NoteTextView`: `var revealsInlineSpans = false`, passed at all three production sites
  (`EditorColumn+Text.swift:47` from `vault.settings`, `DiaryView.swift:88`, `TodayView.swift:192`
  — all three, so the Diario and Oggi editors behave like the main one).
- `NoteTextView+Coordinator.applyStyling`: `decorations.apply(revealsInlineSpans: parent.revealsInlineSpans)`
  beside `apply(hiddenMarkers:hidingMarkup:)` and **before `storage.endEditing()`** (F6, and the
  same placement rule `applyTables`/`applyViewBlocks` already follow).
- `NoteTextView+Reveal.applyReveal`: compute `MarkupReveal.inlineSpans(...)` when
  `parent.revealsInlineSpans` and `[:]` otherwise; keep it in a new `lastRevealedSpans` beside
  `lastRevealed`; the early return now requires **both** to be unchanged; union the two change
  sets and invalidate each changed paragraph once, through the existing
  `storage.edited(.editedAttributes, range: paragraph, changeInLength: 0)` loop. Never the whole
  document.

**Tester** adds a suite driving a real `NoteTextView` coordinator + `NSTextView` (the shape
`Tests/MarkupHidingTests.swift:970` and `Tests/ViewBlockCaretTests.swift:52` already use): with
the flag on and the caret inside one of two bold runs, the delegate's span table names exactly one
paragraph and one range; moving the caret out empties it; flipping the flag off empties it;
`applyReveal` called twice with an unmoved caret invalidates nothing the second time (the early
return still holds). Red first.

**Coder** wires it.

- Budget: `NoteTextView.swift`, `NoteTextView+Coordinator.swift`, `NoteTextView+Reveal.swift`, `EditorColumn+Text.swift`, `DiaryView.swift`, `TodayView.swift`, `Tests/MarkupHidingTests.swift` (~180 lines)

### Task 6 — the Workspace card wiring (R-09)

The route `hidesMarkup` already travels, one property wider (ADR §D8):
`WorkspaceController.revealsInlineSpans` (a plain `var`, default `false`) ←
`WorkspaceView.applyBoardSettings()` (beside `WorkspaceView.swift:483`) → `StickyTextCard.swift:53`
→ `CardTextView.revealsInlineSpans` (**a defaulted `var`, not a `let`** — six test construction
sites must stay unmodified) → `CardTextView.Coordinator.applyStyling`'s
`decorations.apply(revealsInlineSpans:)` and `CardTextView+Reveal.applyReveal`'s span computation,
still gated on `textView.isEditable` exactly as the paragraph reveal is. `releaseDecorations()`
clears the span table with the rest.

**Tester** extends `Tests/CardConcealmentTests.swift`: with the flag on and a card being edited,
a caret in one of two bold runs collapses only the other's markers; a card at rest reveals nothing
regardless of the flag (R-04 of ADR-0028 is not weakened); `releaseDecorations()` leaves the span
table empty; and — **F1, asserted rather than assumed** — a card containing `~~barrato~~` and
`[[Nota]]` produces no `.strikethrough`/`.link` marker at all, so the flag changes nothing for
them. Red first.

**Coder** wires it. **`CardTextView`'s `hiddenKind` switch is not widened.**

- Budget: `WorkspaceController.swift`, `WorkspaceView.swift`, `StickyTextCard.swift`, `CardTextView.swift`, `CardTextView+Reveal.swift`, `Tests/CardConcealmentTests.swift` (~150 lines)

---

## Phase 4 — the fence around what must not move

### Task 7 — the out-of-scope fence and the invariant (R-06, R-09)

No production code unless a fence fails. A new `Tests/InlineSpanRevealFenceTests.swift`:

- **The invariant** (constraint 3): over a table-driven set of notes and selections, every key of
  `MarkupReveal.inlineSpans` is a member of `MarkupReveal.paragraphs` for the same inputs. This is
  what licenses leaving the list/checkbox/blockquote branches untouched.
- **R-06 by construct, end to end**: a note holding a heading, a bulleted list item, a checkbox
  line, a blockquote, a GFM table and a `pergamenum-view` fence renders identically with the flag
  on and with it off, at the same caret position — same substituted-paragraph lengths, same
  `collapsedFont` ranges, same hidden-line sets.
- **R-07 as a whole-file property**: with the flag off, the delegate's answers for a corpus of
  paragraphs are equal to the answers of a delegate that has never heard of the span table.
- **R-09's boundary** (F1): grep-shaped assertion that `CardTextView`'s switch still maps exactly
  five kinds.
- **Out-of-scope diff fence**: `MarkdownStyler.swift`, the five `EditorDecorationDelegate+*Rendering.swift`
  files, `NoteTextView+EmbedCaret.swift`, `MarkdownBlocksView.swift`, `NoteExporter.swift` and
  everything under `Sources/Core`/`Sources/Connector`/`Sources/CLI`/`Sources/MCPServer` do not
  appear in `git diff --stat` for this chain. Report, do not edit, if one does.

- Budget: `Tests/InlineSpanRevealFenceTests.swift` (~180 lines)

### Task 8 — full suite, UI suite, hand check, docs (R-07, R-10, R-11)

1. `tuist generate --no-open`, then the **full unit suite** through `.claude/test-cmd`. Green, and
   green with **no existing test edited** except the two helper signatures named in Task 3.
2. `scripts/uitests.sh` with no arguments, once, before any merge to `main` (CLAUDE.md's rule and
   its price). Kill stale instances first; read the per-test seconds before believing a red — 60.2 s
   names the launch timeout, not the app.
3. **R-11's hand check**, in a Debug build launched with `open -n` on a throwaway vault
   (`-recentVaults '("/path")'`, the plist array form), the newest build found with `ls -dt`:
   with the setting **off**, confirm today's behaviour; with it **on**, walk the caret through
   `**grassetto**`, `[[Nota]]`, `[[Nota reale|testo mostrato]]`, `[testo](https://esempio.it)`,
   `**bold con *corsivo* dentro**` and a two-run paragraph, in the note editor **and** in a
   Workspace `.text` card. Watch specifically for the two named costs (ADR Consequences): the wrap
   point moving as a span reveals, and the caret appearing not to move while crossing a collapsed
   delimiter. Write the result into `PROJECT_BRIEF.md` beside the milestone, the standard
   ADR-0018 §D6 set for a probe that no automated test can answer.
4. Update `CLAUDE.md`: a "Decisions from the word-grained reveal chain (ADR-0037)" section and an
   ADR-0037 line in the chain decision index.

- Budget: `CLAUDE.md`, `PROJECT_BRIEF.md` (~60 lines)

---

## Requirement coverage

| id | tasks |
|---|---|
| R-01 | 1, 2, 3, 5 |
| R-02 | 1, 2, 3, 5 |
| R-03 | 3, 5 |
| R-04 | 1, 2, 5 |
| R-05 | 1, 3 |
| R-06 | 3, 7 |
| R-07 | 3, 4, 5, 7, 8 |
| R-08 | 4 |
| R-09 | 6, 7 |
| R-10 | 1, 2, 3, 8 |
| R-11 | 8 |

Every id the SPEC declares is cited by at least one task; no id is cited that the SPEC does not
declare. The SPEC carries no `(no-test: …)` marker on any criterion; R-11 is a manual verification
by its own wording and is discharged by Task 8's written result, not by an assertion.

---

## Risks and HITL gates

- **The main checkout has uncommitted work in `EditorDecorationDelegate.swift`,
  `EditorDecorationDelegate+CheckboxRendering.swift` and a new `NoteTextView+CheckboxClick.swift`**
  (checkbox-click, in flight on `feature/task-note-board-link-navigation`). This chain rewrites the
  guard at `EditorDecorationDelegate.swift:443`. A textual conflict at merge time is likely and is
  not a defect — but **whoever merges second must re-read D3's filter against the other branch's
  edits**, not resolve by taking one side. Flag it at the merge gate.
- **Typing feel is the acceptance criterion and it has no test.** The wrap point moves more often
  than it did (ADR Consequences), and a reveal that makes the line jump is the failure mode a
  person will report as "it flickers". Only the Task 8 hand check can answer it; if it reads badly,
  the honest outcome is to ship the setting off and say so, not to tune the predicate under time
  pressure.
- **The CommonMark link pairing is the one piece of new grammar** (F2). Two links on one line is
  its real test and it is in Task 1's minimum list. A mispairing reveals the wrong construct or a
  range spanning two of them — visible immediately, but only if someone writes that line.
- **Performance is bounded by argument, not measured.** ADR §D4's case rests on a paragraph being
  one line and on ADR-0018's 5.83 ms/17 KB figure. A pathological single-paragraph note (a
  minified line of tens of KB) would parse that whole line on every arrow key. Unmeasured, named,
  and worth one glance during the hand check on a long note.
- **Phantom spans inside code fences** (ADR §D4). Harmless by construction — a span with no marker
  reveals nothing — but it is a genuine divergence between two parses of the same characters, and
  a future reader assuming they agree will be wrong. Task 1 should include one fenced-`**bold**`
  case documenting the no-op.
- **`VaultSettings` is a shared source** (F5). `SharedSourcesPurityTests` must stay green; if the
  new property ever grows an import, both command-line tool builds break, which is ADR-0001 §D1
  enforcing itself.
- **HITL gates:** commit, push, merge to `main`, and the R-11 hand check itself. No schema change,
  no migration, no deletion, no destructive command, no new dependency anywhere in this chain —
  `Tuist/Package.swift` is not touched.

---

EXTERNAL DEPENDENCY: tuist | binary | provisioned: true
EXTERNAL DEPENDENCY: xcodebuild | binary | provisioned: true

TEST-CMD CANDIDATE: xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -derivedDataPath "/Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/.build/DerivedData" -only-testing:PergamenumTests test
TEST-CMD MODE: brownfield

CODER-MODEL CANDIDATE: opus
