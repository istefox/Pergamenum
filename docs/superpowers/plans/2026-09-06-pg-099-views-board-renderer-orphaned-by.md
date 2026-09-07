# Plan — A view renders in the editor again (PG-099)

- **ADR:** `docs/adr/0033-views-render-live-in-the-editor.md`
  (the orchestrator relocates it to `docs/adr/0033-views-render-live-in-the-editor.md`, the
  ADR-0029 precedent)
- **SPEC:** `SPEC.md` (R-01 … R-15)
- **BRAINSTORM / UX blueprint / Claude Design:** none. All three optional gates were skipped by the
  user as not applicable — no new window, no new navigation, no net-new visual surface; the
  direction was settled in the interview. **Do not go looking for them.**
- **Branch base:** `main` at `dfcccb8`. ADR-0029 is merged, so `TableAttachment`, `TableGridStore`,
  `EditorDecorationDelegate+TableRendering`, `NoteTextView+Tables` and `NoteTextView+TableCaret`
  all exist and are the shape every task below copies.
- **Style:** TDD. Red precondition first on every task, per this repo's last seven chains.

---

## Before anything: what the SPEC says that the source does not

Verified against the working tree at `dfcccb8`, by grep, at the line. **Do not design or code
against the left column.**

| # | SPEC says | Source says | Where |
|---|---|---|---|
| C1 | R-09: "clicking a row/card … navigates to/opens the linked note" — framed as part of the restoration | **Never existed.** `ViewRowRenderers.swift` and `ViewGridRenderers.swift` contain **zero** hits for `Link`, `Button`, `onTapGesture`, `openURL`, `NSWorkspace`. A row's title is drawn `.accentPrimary`, which looks like a link and has never been one. Lettura did not open a note from a view row either. R-09 is **net-new work**, not a regression fix | grep `Link\|onTapGesture\|Button\|openURL` in both files → no output |
| C2 | R-08: an unparseable fence renders as plain fenced text, no error UI | **ADR-0009 §D1 requires the opposite**: *"A block that does not parse renders as an error naming the line, never as an empty result."* `RenderedViewBlock.failed(_:)` already draws that card. Resolved by ADR-0033 §D7 in the editor's favour, with the error card kept on the transclusion, export and Viste-pane surfaces. **The reason text is lost in the editor and that is a deliberate, recorded cost** | `RenderedViewBlock.swift:126-146`; `docs/adr/0009…:60-64` |
| C3 | Architecture: "the caret enters the fence, the rendered attachment is replaced by the raw fenced text … same reveal-on-caret rule ADR-0018 already applies" | ADR-0018 §D2's revealed set is keyed **by paragraph**. The fence's body lines are out of the layout, so the only paragraph the caret can be in is the opening fence; the instant reveal lets the caret move into the body, the block re-hides *underneath the caret*. **Structural loop, not an edge case.** ADR-0033 §D4 keys reveal on the fence's whole source range instead | `NoteTextView+Reveal.swift:18-33`; `EditorDecorationDelegate.swift:366-368` |
| C4 | Architecture: "the delegate's enumeration hook refuses to lay out the fenced body lines … exactly as the table attachment already does" | True and incomplete: the table ends at its last body row, a fence ends at a **line of backticks**. The closing fence line must be in the hidden set too or it sits under the drawn block as a stray ``` ``` ``` | `EditorDecorationDelegate+TableRendering.swift:107-113` (the table's own end) |
| C5 | (unstated) every fence is a candidate | `CodeFence.regions(in:)` runs an **unclosed** fence to the end of the text, deliberately. Without a closed-fence precondition, typing ``` ```pergamenum-view ``` takes the rest of the note out of the layout mid-keystroke (ADR-0033 §D6) | `CodeFence.swift:44-46` and its own header comment |
| C6 | Architecture: reuse the mechanism "ADR-0029 §D2 introduced for the GFM table grid" | `TableGridStore` keys by **paragraph offset** and prunes per pass, so an edit above the table rebuilds its view. Copying that here rebuilds the `NSHostingView`, which re-runs `.task` and therefore **re-evaluates the query, per keystroke** — forbidden by ADR-0009 §D7. ADR-0033 §D3 keys by **ordinal within the note** instead | `TableGridStore.swift:33-59`; `RenderedViewBlock.swift:61`; `docs/adr/0009…:218-224` |
| C7 | (unstated) `viewQuerySource` needs building | **Already written and unreferenced**, left standing by ADR-0029 §D13 with a comment naming this exact chain: *"whichever surface renders an in-note `pergamenum-view` fence next will want exactly this."* Wire it; do not write it | `EditorColumn+Text.swift:194-213` |
| — | Out of scope: `MarkdownBlocksView`, `TranscludedNoteView`, `NoteExporter`, `ViewsPane` | Free, and checkable by grep: the two new `RenderedViewBlock` inputs are optional with `nil` defaults, and `nil` is today's behaviour. **None of those four files appears in this chain's diff** | Task 9 asserts it |

**Four constraints the SPEC could not know** (ADR-0033 §Context):

1. **A displayed paragraph may not change length** (`NSTextContentManager.h:120`). The opening fence
   line is *substituted*, one character out and one in.
2. **A `\n` at 0.01pt still breaks the line**, measured in this project — so the body and closing
   lines must be *un-enumerated*, never collapsed (`EditorDecorationDelegate.swift:17-18`).
3. **`EditorDecorationDelegate` cannot be `@MainActor`** and owns no view. The `NSHostingView` is
   built and owned by the Coordinator and handed over as a finished value — the crossing
   `renditions`, `embedRenditions` and `tableViews` already make.
4. **`NSHostingView` inside `NSTextAttachmentViewProvider` is untried in this repo.** ADR-0029 §D16
   probe 2 answered the question for a plain `NSView`; SwiftUI with `@State`, `.task` and
   `.draggable` is a strictly larger claim. **Task 3 is a real gate on Tasks 4 and 8, not a
   formality.**

---

## Contract changes and their already-grepped call sites

Every row is a stale-assertion site found by grep **before** this plan was written. The coder does
not go looking for these; they are listed, and they are updated in the same task that changes the
contract. **Run the full unit suite after each task, not just the touched file's tests** — a
contract change breaks tests in files that never mention it.

| Contract | Change | Call sites that break |
|---|---|---|
| `MarkdownStyler.Span` | add `.viewBlockRun` | **Compile errors (exhaustive, no `default`):** `MarkdownStyler.suppressesSpellCheck(_:)` (`:143-158`, add beside `.tableRun` on the `true` shelf), `MarkdownAttributedText.colorToken(for:)` (`:148`, `.tableRun` is at `:176`), `CardTextAttributes.colorToken(for:)` (`:183`, `.tableRun` at `:195` — **a colour only, never a kind mapping**, ADR-0029 §D17). **Safe, have a `default`:** `MarkdownAttributedText.attributes(for:)` (`:51`, default at `:132`), `CardTextAttributes.attributes(for:)` (`:106`, default at `:162`). **Compiles and stays correct:** `Coordinator.hiddenKind(for:)` (`NoteTextView+Coordinator.swift:397-421`) — `.viewBlockRun` maps to **nil**, like `.tableRun` at `:418`, for the same reason. **Left alone on purpose:** `CardTextView.swift:289-296`'s kind switch (`default: nil` is ADR-0029 §D17's seam). **Tests:** `Tests/MarkdownStylerTests.swift` — the only full-array assertions are `:54` (`# Titolo`) and `:100` (`*corsivo*`); neither text contains a fence, so both stay green unmodified. If one goes red, the span is being emitted where it must not be. |
| `HiddenMarker.Kind` | add `.viewBlock` | **Compile error (exhaustive, no `default`):** `EditorDecorationDelegate.stillSpells(_:_:at:)` (`:530-570`) — returns **`false`**, like `.table` at `:564`, because the re-read is a whole-block question the drawing branch owns. **Additive, no break:** `Tests/EmbedDrawingTests.swift:42`, `:309`; `Tests/MarkupHidingTests.swift:101`, `:162`; `Tests/CardConcealmentTests.swift:114`, `:118`, `:123-124`, `:143`, `:251` all name a kind explicitly when constructing a `HiddenMarker`. |
| `EditorDecorationDelegate` | add `apply(viewBlockLines:)` — a **sixth** input, never merged into `hiddenLineOffsets` or `tableRowOffsets` | No existing caller breaks; `textContentManager(_:shouldEnumerate:options:)` (`:241-251`) changes to consult the union of **three** sets. `Tests/MarkupHidingTests.swift` and `Tests/TableRenderingTests.swift` build the delegate directly and pass no view-block lines — the new set defaults empty. `Tests/TableRenderingTests.swift:65-69`'s `laidOutOffsets(text:tableRows:)` helper must stay green **unmodified**. |
| `EditorDecorationDelegate` | add `apply(viewBlockHosts:)` (`[Int: NSView]`) | New; mirrors `apply(tableViews:)` (`:208-210`). No existing caller. |
| `RenderedViewBlock` | add `onEditSource: (() -> Void)? = nil` and `onOpenNote: ((String) -> Void)? = nil` | **Additive with defaults, so no call site breaks.** The one existing caller, `MarkdownBlocksView.swift:70-76`, passes neither and **is not edited**. `Tests/ViewRenderingTests.swift` constructs the block — check it still compiles; it will, defaults being defaults. |
| `ViewTableRenderer` / `ViewListRenderer` / `ViewGalleryRenderer` / `ViewCalendarRenderer` | add `var onOpenNote: ((String) -> Void)? = nil`, and a row/cell click target when it is non-nil | **Additive with defaults.** Existing construction sites are `RenderedViewBlock.rows(_:_:)` (`:108-122`) only. `Tests/ViewRenderingTests.swift` may name these types — additive defaults keep it green. |
| `NoteTextView` | add `var queries: ViewQuerySource? = nil` | **Additive with a default.** Three construction sites: `EditorColumn+Text.swift:47` (**passes `viewQuerySource`**), `DiaryView.swift:98` and `TodayView.swift:191` (**pass nothing, keep today's behaviour** — ADR-0033 Consequences). `Tests/EmbedEditorTestSupport.swift:53-57` constructs it too and stays unmodified. |
| `EditorColumn+Text.swift:194-198` | the comment declaring `viewQuerySource` **unreferenced** stops being true | Rewrite the comment in the same task that wires it (Task 7). A comment that says a live thing is dead is worse than no comment. |

**Protected interfaces — none touched, checked one by one:** `IndexCache.schemaVersion` (presentation-layer
feature, no index field), `VaultAPI.LintFinding` (no connector change of any kind),
`CompletingTextView+Pasteboard.swift` (no paste path involved; the block's mouse handling is inside
the hosted view, not on the text view), `ImportNaming.recordingNoteTitle` (unrelated).
**`interface-check.sh` must stay silent for the whole chain.**

---

## Conventions binding on every task

- **The tester owns the interface, the coder owns the body.** Swift is compiled: a batch that leaves
  the target unable to build produces no red tests at all, only a build error. Every new type's
  *declaration* (enum cases, stored properties, method signatures returning a stub) is written in the
  **tester's** task together with the tests that call them. The coder fills in bodies.
- **`tuist generate --no-open` after every task that adds a file under `Sources/` or `Tests/`.** Also
  after any `git stash`/`git checkout` that adds or removes a file — the generated project still
  lists what is no longer there and the build fails naming the compiler rather than the cause.
- **Swift Testing (`@Test`/`#expect`) for all new tests.** Never XCTest, except inside `UITests/`,
  which is an XCTest bundle and stays one.
- **Every new test file's header comment cites both `ADR-0033` and this plan's basename**
  (`2026-09-06-pg-099-views-board-renderer-orphaned-by`). That citation is this chain's coverage
  anchor — there is no separate harness script (below), so the test files are what names the plan.
- **One principal type per file** (`~/.claude/rules/swift.md`). `EditorDecorationDelegate` will cross
  `type_body_length` again: the new branch goes in
  `Sources/Features/Editor/EditorDecorationDelegate+ViewBlockRendering.swift`, beside the existing
  `+TableRendering` / `+QuoteRendering` / `+ListRendering` / `+CheckboxRendering`.
- **Nothing new under `Sources/Core/**`.** That is a `sharedSources` glob (`Project.swift:73`) and an
  `import AppKit`/`import SwiftUI` there breaks both connector builds. Every file this chain adds is
  under `Sources/Features/`.
- **`CardTextView.swift` is not edited** (ADR-0033 §D13 / ADR-0029 §D17). The one exception the
  compiler forces is `CardTextAttributes.colorToken(for:)` learning a colour for `.viewBlockRun`. If a
  task looks like it needs to map a *kind* there, **stop and report**.
- **`CompletingTextView.swift` and every `CompletingTextView+*.swift` stay untouched.** If a task
  looks like it needs one, stop and report.
- **No hardcoded colour, font or spacing in any view.** The hosted root view gets the theme through
  `.environment(\.theme, theme)`; `RenderedViewBlock` and its renderers already read every token from
  it. A view that uses a colour without going through a token does not pass review (CLAUDE.md).
- **The unit test command is `.claude/test-cmd` exactly as it stands** — `-only-testing:PergamenumTests`.
  **Do not widen it**: the UI suite in there terminates the app the person at the keyboard is using
  and leaves an instance holding the global hot key exclusively (CLAUDE.md, two hours lost once).
- **`scripts/uitests.sh` runs once, in Task 10, before merge** — never per task. An argument
  *replaces* the selection rather than adding to it.
- **No new harness script.** This repo has none of that kind; `scripts/` holds
  release / uitests / mcp-smoke / install-cli / appcast / fetch-sparkle-tools and stays as it is.
  Coverage for this chain is `.claude/test-cmd` plus `scripts/uitests.sh` plus the per-task test files
  named below, each citing this plan's basename in its header. Any throwaway helper written for a
  hand-check must be **Bash 3.2-clean**: no `mapfile`, no associative arrays, no `${x^^}`/`${x,,}`;
  collect array output with `arr=(); while IFS= read -r x; do arr+=("$x"); done < <(cmd)`.
- **`weakening-scan.sh` reports every Swift Testing test as `zero-assertion-test`** because its body
  scanner treats `#expect` as a comment. Expected, systematically wrong for this stack, advisory
  (CLAUDE.md). A genuinely assertion-free test still has to be caught by reading the diff.
- **The secret scanner's `assigned-secret` heuristic fires on design-token lines** (`token` followed
  by `:`/`=` and 16+ identifier characters). Expected false positives; read each hit before dismissing
  it.
- **Never disable or delete a test to make the suite pass.** If one must change, say why in chat first.

---

## Phase 1 — the recognition layer (no new mechanism, no view in the text)

### Task 1 — `MarkdownStyler` learns `.viewBlockRun`, closed fences only (R-01, R-02, R-03, R-04, R-08)

- **Tester** writes `Tests/ViewBlockSpanTests.swift` and adds the `case viewBlockRun` declaration to
  `MarkdownStyler.Span` plus the three exhaustive-switch arms (compile-forced, listed in the contract
  table) so the target builds. Assertions, all red against a `viewBlockRuns(in:outside:)` stubbed to
  return `[]`:
  - a closed ```` ```pergamenum-view … ``` ```` fence yields exactly one `.viewBlockRun` covering the
    opening backticks through the closing ones inclusive (R-01);
  - a closed fence with `render: gallery` / `render: calendar` / `render: board` yields one too — the
    span does not read `render:` at all (R-02, R-03, R-04);
  - an **unclosed** ```` ```pergamenum-view ```` at the end of a note yields **no** span (ADR §D6, C5);
  - a ```` ```swift ```` fence yields no span; a ```` ```pergamenum-view ```` fence nested inside an
    outer fence follows `CodeFence.regions`' own alternating grammar and is asserted to whatever that
    grammar answers, **documented in the test rather than asserted from intuition** (ADR Consequences);
  - two fences in one note yield two spans, in document order (SPEC Edge cases);
  - a fence whose body does **not** parse still yields a span here — R-08's refusal happens in Task 5,
    not in the styler, because the styler must not run the query grammar on every keystroke (R-08).
- **Coder** implements `viewBlockRuns(in:outside:)` beside `tableSpans(in:from:outside:)`
  (`MarkdownStyler.swift:441-452`), fed by the `fences` array `spans(in:)` already computes at `:114`,
  appended **after** the `.codeBlock` spans so it wins on overlap (ADR §D14).
- **Contract-staleness:** re-run `Tests/MarkdownStylerTests.swift` in full. `:54` and `:100` must stay
  green **unmodified**; a red there means the span is emitted outside a fence.
- Budget: `Sources/Features/Editor/MarkdownStyler.swift`, `Sources/Features/Editor/MarkdownAttributedText.swift`, `Sources/Features/Workspace/CardTextAttributes.swift`, `Tests/ViewBlockSpanTests.swift` (~180 lines)

### Task 2 — the delegate gains a sixth hidden-line input and a `.viewBlock` marker kind (R-01, R-06)

- **Tester** writes `Tests/ViewBlockRenderingTests.swift`, modelled line for line on
  `Tests/TableRenderingTests.swift` (its `substitutedParagraph` and `laidOutOffsets` helpers are the
  shape to copy, not to import). Declares, so the target builds: `HiddenMarker.Kind.viewBlock`, the
  `stillSpells` arm returning `false`, `apply(viewBlockLines:)`, `apply(viewBlockHosts:)`, and
  `viewBlockParagraph(at:storage:)` **stubbed to return `nil`**. Assertions:
  - with `apply(viewBlockLines:)` given the body and closing-fence offsets, a real offscreen layout
    pass lays out neither (R-01, R-06) — measured through `laidOutOffsets`, the way folding and tables
    already are;
  - **the closing fence line is in the set and is not laid out** (C4) — its own assertion, because
    this is the one place the arithmetic differs from a table's;
  - `apply(viewBlockLines:)` with an empty set clears **only** its own set: a fold registered through
    `apply(hiddenLines:foldedHeadings:)` and a table registered through `apply(tableRows:)` both
    survive it, and each of the other two clears only its own (ADR §D1, the delegate's own header
    rule). Three assertions, one per pair;
  - with `hidesMarkup` false, `viewBlockParagraph(at:storage:)` returns nil (ADR §D12) — **green with
    the stub**, and stays green after Task 5;
  - a `.viewBlock` marker whose recorded range no longer spells a fence draws nothing.
- **Coder** implements `apply(viewBlockLines:)` and `apply(viewBlockHosts:)` on
  `EditorDecorationDelegate`, and widens
  `textContentManager(_:shouldEnumerate:options:)` (`:241-251`) to the union of the three sets. The
  `viewBlockParagraph` body is **Task 5's**, not this one's.
- Budget: `Sources/Features/Editor/EditorDecorationDelegate.swift`, `Tests/ViewBlockRenderingTests.swift` (~200 lines)

---

## Phase 2 — the gate

### Task 3 — tracer-bullet probe: SwiftUI inside a text attachment (ADR §D16 probes 1–3) (R-01, R-04)

**This is a gate, not a checkpoint. Tasks 4 and 8 are not planned in detail until it has an answer,
and a negative on probe 2 changes Task 8's shape rather than being worked around inside it.**

- Build the smallest real thing: a `ViewBlockAttachment` whose provider's `loadView` assigns an
  `NSHostingView` over a throwaway SwiftUI view holding a `@State` counter, a `Button`, and a
  two-column `.draggable`/`.dropDestination` pair — inside a real `CompletingTextView` inside a real
  `NSWindow`, reached from a fixed trigger word with no grammar behind it (the exact shape ADR-0029's
  Step 4.5 probe used before `EditorDecorationDelegate+TableRendering.swift` replaced it).
- **Probe 1 passes** when the host draws at the size `attachmentBounds` returned, the button responds
  to a click, and the `@State` counter survives a keystroke typed elsewhere in the note (i.e. the host
  instance was not rebuilt).
- **Probe 2 passes** when a card lifts on drag, the destination column highlights, the drop fires with
  the payload, and the text view does not treat the gesture as a text-selection drag.
- **Probe 3 passes** when either the text view keeps first responder through a click on the host, or
  the host takes it and `Esc` / a click in the note return it with a sane caret — never a state where
  keystrokes go nowhere. `TableGridStore.resignToTextView` (`:36-39`) is the wiring to copy if the
  host takes focus.
- **Write the result down**, per probe, in `PROJECT_BRIEF.md` beside the phase — ADR-0010's standard.
  A probe with no written result did not happen.
- **On a probe-2 failure:** report and stop. Task 8 switches to ADR §D16's named fallback (a per-card
  context menu on `ViewBoardRenderer`, offered only when `queries?.move != nil`, writing through the
  identical `ViewQuerySource.move` closure). That is a plan revision at Gate 2, not a coder decision.
- The probe scaffold is deleted in Task 4, exactly as ADR-0029's was — it is a slice of the production
  path, not a parallel one.
- Budget: not estimable — this is an investigative task whose footprint depends on what the first
  probe answers.

---

## Phase 3 — the attachment

### Task 4 — `ViewBlockAttachment` and `ViewBlockHostStore`, keyed by ordinal (R-01, R-02, R-03, R-06)

- **Tester** writes `Tests/ViewBlockHostStoreTests.swift` and declares `ViewBlockHostStore`
  (`@MainActor`, `host(for ordinal: Int, in textView: NSTextView) -> NSHostingView<…>`,
  `hosts(for ordinals: [Int], in:) -> [Int: NSHostingView<…>]`, `update(_ root:, forOrdinal:)`) and
  `ViewBlockAttachment` with its `height` constant, all stubbed. Assertions:
  - **the same host instance comes back for the same ordinal across calls** (ADR §D3) — the property
    that keeps the query from re-running, asserted by identity (`===`), not by equality;
  - **the host survives a changed paragraph offset** — ask for ordinal 0, then ask again after the
    note gained a line above the fence, and get the same instance. This is the assertion that
    distinguishes this store from `TableGridStore` and it is the one that must never be relaxed
    (C6, ADR §D3);
  - **`hosts(for:in:)` prunes**: an ordinal absent from the array is dropped, and a note that loses a
    fence does not accumulate a host;
  - **two identical fences in one note get two distinct hosts** (ADR §D3's rejection of a source-text
    key) — an `NSView` has one superview;
  - `attachmentBounds(…)` returns `proposedLineFragment.width` × the constant height, **independent of
    the content** (R-06, ADR §D8) — asserted at two different proposed widths and with two different
    stub result sets.
- **Coder** implements both, plus the provider (`tracksTextAttachmentViewBounds = true`,
  `loadView` assigning the host **it was given**), copying `TableAttachment.swift` for shape and
  diverging only where D3 and D8 say to. The root view is
  `ScrollView { RenderedViewBlock(…) }.environment(\.theme, theme)` — **the `ScrollView` lives here,
  never inside `RenderedViewBlock`** (ADR §D8, and R-10/R-11 depend on it).
- Deletes the Task 3 probe scaffold.
- Budget: `Sources/Features/Editor/ViewBlockAttachment.swift`, `Sources/Features/Editor/ViewBlockHostStore.swift`, `Tests/ViewBlockHostStoreTests.swift` (~260 lines)

### Task 5 — the Coordinator's `applyViewBlocks` pass, and the caret rescue (R-01, R-02, R-03, R-08, R-13)

- **Tester** extends `Tests/ViewBlockRenderingTests.swift` and adds
  `Tests/ViewBlockCaretTests.swift`. Declares `Coordinator.applyViewBlocks(to:runs:markers:&)`,
  `Coordinator.clearViewBlocks()`, `EditorDecorationDelegate.viewBlockRun(in:atParagraphStart:)`
  (`static`, `NSString`, UTF-16 — the `tableRun(in:atParagraphStart:)` shape, usable from both a
  non-actor drawing pass and a `@MainActor` one), all stubbed. Assertions:
  - **attachment creation from a valid fence** (R-13's first named case): after a styling pass, the
    opening fence paragraph's substituted copy carries a `ViewBlockAttachment` at offset 0 and
    `collapsedFont` over the rest, and the paragraph's **length is unchanged** (R-01, R-02, R-03 —
    one assertion per renderer keyword, since the pass must not read `render:`);
  - **fallback to raw text on an unparseable fence** (R-13's second named case): a fence whose body
    fails `ViewBlock.parse` produces **no marker, no attachment and no hidden lines** — the paragraph
    is returned `nil` and the body stays in the layout (R-08, ADR §D7);
  - an unclosed fence produces nothing at all (C5);
  - with `hidesMarkup` false the pass registers nothing **and clears what it registered before**
    (ADR §D12 — the `clearTables()` trap, which reaches the enumeration refusal too);
  - `Tests/ViewBlockCaretTests.swift`: a caret placed programmatically inside a body line that the
    pass then hides is moved to the opening fence line's offset, after the storage transaction
    closes, never inside it (ADR §D15, `tableCaretRescue`'s twin).
- **Coder** writes `Sources/Features/Editor/NoteTextView+ViewBlocks.swift` (the `applyTables` shape:
  `markers` `inout`, its own guard, its own change check on the hidden-line set, its own
  `apply(viewBlockLines:)`/`apply(viewBlockHosts:)` calls, called from `applyStyling` **before**
  `storage.endEditing()`) and
  `Sources/Features/Editor/EditorDecorationDelegate+ViewBlockRendering.swift` (the substitution branch
  and the static re-read). The host refresh and the caret rescue run **after** the transaction closes,
  beside `refreshTableGrids`.
- Budget: `Sources/Features/Editor/NoteTextView+ViewBlocks.swift`, `Sources/Features/Editor/EditorDecorationDelegate+ViewBlockRendering.swift`, `Sources/Features/Editor/NoteTextView+Coordinator.swift`, `Tests/ViewBlockRenderingTests.swift`, `Tests/ViewBlockCaretTests.swift` (~420 lines)

### Task 6 — reveal on the fence range, and the re-render on exit (R-05)

- **Tester** extends `Tests/ViewBlockCaretTests.swift` and declares
  `Coordinator.revealedViewBlock(in:) -> NSRange?` stubbed to `nil`. Assertions, the reveal predicate
  first as a **pure** test against a plain `String` (the `MarkupReveal.paragraphs` precedent):
  - a caret on the opening fence line reveals the block (R-05);
  - a caret on a **body** line reveals it too — the assertion C3 exists for, and the one a
    paragraph-keyed reveal cannot satisfy;
  - a caret on the closing fence line reveals it;
  - a caret on the line immediately above and immediately below reveals nothing;
  - a **selection** spanning from outside into the fence reveals it (ADR-0018 §D2 trigger 2 arriving
    by range);
  - a revealed fence produces **no** marker, **no** hidden lines and **no** host — the raw source is on
    screen and the body lines are laid out (R-05);
  - moving the caret back out re-registers all three against the **edited** source: edit the query in
    the revealed state, move out, and the re-rendered block reflects the new `render:` (R-05's second
    half);
  - two fences: revealing one leaves the other drawn (SPEC Edge cases, no shared state).
- **Coder** implements the predicate, wires `applyViewBlocks` to skip a revealed fence, and adds to
  `textViewDidChangeSelection` — after the existing `applyReveal(to:)` — a guarded
  `applyStyling(to:theme:)` when `revealedViewBlock(in:)`'s answer changed since the last call
  (ADR §D5). The guard is a stored `NSRange?`; a note with no fence pays one comparison per arrow key.
- **Watch for re-entrancy:** `applyStyling` sets `isStyling` around its own edit. Confirm no recursion
  through `textDidChange`, and say so in the task report.
- Budget: `Sources/Features/Editor/NoteTextView+ViewBlocks.swift`, `Sources/Features/Editor/NoteTextView+Coordinator.swift`, `Tests/ViewBlockCaretTests.swift` (~220 lines)

---

## Phase 4 — the vault behind the block

### Task 7 — wire `viewQuerySource`, live refresh, and click-to-open (R-07, R-09, R-13)

- **Tester** writes `Tests/ViewBlockQuerySourceTests.swift`. Declares `NoteTextView.queries` and the
  two new optional inputs on `RenderedViewBlock` plus `onOpenNote` on the four renderers, all
  defaulted `nil`. Assertions:
  - **live refresh on an index update** (R-13's third named case, R-07): bumping
    `ViewQuerySource.generation` changes the id `RenderedViewBlock`'s `.task(id:)` is keyed on, and the
    store pushes an updated root view carrying it — asserted on the composed id string and on the
    store's `update(_:forOrdinal:)` having been called, without needing a live SwiftUI render;
  - **a keystroke that does not change the fence's source does not change that id** — the assertion
    ADR-0009 §D7 turns into a test, and the one C6/ADR §D3 exist to make possible;
  - a text edit **above** the fence leaves both the host identity and the id unchanged (the same
    property from the store's side, asserted here from the pass's side);
  - **R-09**: with `onOpenNote` non-nil, a table row, a list line, a gallery item and a calendar entry
    each expose a click target carrying the row's title; with it `nil`, none of them do — which is
    today's rendering and is what keeps R-10/R-11 true (four assertions plus four negatives);
  - `NoteTextView` built with no `queries` (the `DiaryView`/`TodayView`/test default) renders the fence
    as source and creates no host.
- **Coder** adds `queries` to `NoteTextView`, passes `viewQuerySource` from
  `EditorColumn+Text.swift:47`'s `editing(_:)`, **rewrites the now-false "unreferenced" comment at
  `:194-198`**, threads `onOpenNote` through `RenderedViewBlock` into the four renderers as an
  optional click target, wires `onEditSource` into the block header beside the existing refresh button
  (ADR §D10), and wires `onOpenNote` in the editor to the same `onFollowLink` door a wikilink uses.
- **`DiaryView.swift` and `TodayView.swift` are not edited.** They keep the `nil` default deliberately
  (ADR Consequences). If a task looks like it needs to edit them, stop and report.
- Budget: `Sources/Features/Editor/NoteTextView.swift`, `Sources/Features/Editor/EditorColumn+Text.swift`, `Sources/Features/Views/RenderedViewBlock.swift`, `Sources/Features/Views/ViewRowRenderers.swift`, `Sources/Features/Views/ViewGridRenderers.swift`, `Tests/ViewBlockQuerySourceTests.swift` (~340 lines)

### Task 8 — the board writes from inside the attachment (R-04)

**Shape depends on Task 3's probe 2. Do not start before its written result exists.**

- **Probe 2 green — the planned path.** `ViewBoardRenderer` is used **unmodified**: its existing
  `.draggable`/`.dropDestination` pair runs inside the host, its `queries.move` closure reaches
  `vault.moveOnBoard` → `VaultSession.write`, journalled, undoable and vocabulary-checked exactly as
  ADR-0009 §D5 already specifies, and its `onWrite` bumps `RenderedViewBlock`'s own `reloads` so the
  card does not spring back. **The task is then a test task plus a hand-check**, not a code task:
  `Tests/ViewBlockBoardTests.swift` asserts that the editor's `ViewQuerySource` carries a non-nil
  `move` and `undo` (the surface *can* write), that a source built without them offers neither, and
  that a drop outcome refused by the differential lint guard leaves the note untouched — all against
  `VaultSession.BoardDropOutcome`, which `Tests/BoardDropTests.swift` already exercises and which must
  stay green unmodified.
- **Probe 2 red — the named fallback** (ADR §D16). Add a per-card context menu to `ViewBoardRenderer`,
  offered only when `queries?.move != nil`, listing the other columns and writing through the
  identical `move` closure. Additive: the transclusion path passes no `queries` and so offers neither
  gesture, and the drag code is left in place rather than removed. **Report the switch before writing
  it.**
- Either way: **the write path itself is not modified**, and no test in `Tests/BoardDropTests.swift`
  changes.
- Budget: `Tests/ViewBlockBoardTests.swift` (~120 lines) on the green path; not estimable on the
  fallback path.

---

## Phase 5 — the fence around what must not move

### Task 9 — regression fence: transclusion, export and the Viste pane are untouched (R-10, R-11, R-12)

- **Tester** writes `Tests/ViewBlockOutOfScopeTests.swift`:
  - **R-10** — `MarkdownBlocksView`'s `view(for:)` still routes a `code(language: ViewBlock.language, …)`
    block to `RenderedViewBlock` with **neither** new input, and a `TranscludedNoteView` drawing a
    note containing a fence produces the same rendition it does today (assert on the block's inputs,
    not on pixels);
  - **R-11** — `NoteExporter`'s HTML for a note containing a fence is byte-identical to the pre-change
    output. Capture the expected string in the test, not from a golden file this chain writes;
  - **R-12** — `ViewCatalogue`'s cataloguing of a note with one valid and one invalid fence is
    unchanged: names, renderer types, match counts and block locations, including the
    `lineIndex`/`heading` `ViewsPane` opens a note at. `Tests/SidebarTests.swift:65-110` already covers
    part of this and **must stay green unmodified**;
  - the error card still renders on the transclusion path for an unparseable fence — ADR §D7's
    "the error card keeps the surfaces it already has", asserted rather than asserted-by-absence.
- **Coder**: nothing to implement if the design held. The task's real deliverable is the
  **grep evidence** in its report: `MarkdownBlocksView.swift`, `TranscludedNoteView.swift`,
  `NoteExporter.swift`, `ViewsPane.swift` and `ViewCatalogue.swift` appear in `git diff --stat` for
  the whole chain **zero times**. If any of them does, stop and report — the design leaked.
- Budget: `Tests/ViewBlockOutOfScopeTests.swift` (~180 lines)

### Task 10 — full suite, UI suite, hand-check, brief update (R-13, R-14, R-15)

- **R-15** — `.claude/test-cmd` exactly as it stands, whole `PergamenumTests` bundle, green. Not the
  touched files' tests: a contract change breaks tests in files that never mention it.
- **R-13** — confirm the three named coverage cases exist and are green, by name: attachment creation
  from a valid fence (Task 5), fallback to raw text on an unparseable fence (Task 5), live refresh on
  an index update (Task 7). If one is missing, it is written here, not waived.
- **`scripts/uitests.sh`** with no arguments, once, before merge. Kill every stale instance first and
  read the per-test seconds it prints: **60.2 s names the launch timeout, not a defect** (CLAUDE.md).
  Any new UI-test file wants `-disableCalendar YES` and `-disableUpdater YES` and must find controls
  by `accessibilityIdentifier`, never by the words on them.
- **R-14 — Stefano's hand-check, and it is the acceptance gate for this chain.** In a real vault, all
  four renderers drawn inline (`table`, `gallery`, `calendar`, `board`), the board's drag-to-write
  performed and its `Cmd+Z` confirmed, the caret moved in and out of a fence, a `status-*` tag changed
  in another note with the first still open (R-07 on screen), and an unparseable fence left as source.
  TextKit 2 attachment layout and interaction is this repo's documented XCUITest blind spot — the
  `firstRect`-not-laid-out-yet trap means a positional assertion there can pass by accident.
- Update `PROJECT_BRIEF.md`: the Status section, and the D16 probe results beside the phase.
- **Update `CLAUDE.md`**, which every prior chain in this repo does and which is how the next session
  learns this decision exists: one line in the **Chain decision index** (`ADR-0033 — …`) and one
  **"Decisions from the …" section** carrying the four or five decisions a reader must not
  re-litigate — the ordinal host key (§D3), the range-keyed reveal (§D4), the closed-fence
  precondition (§D6), the fail-closed-to-source rule (§D7), and the fact that R-09 was net-new
  rather than restored (C1).
- **HITL gate before commit.** Feature branch `feature/pg-099-views-in-editor`, Conventional Commits,
  never a direct commit to `main`, never a force-push.
- Budget: `PROJECT_BRIEF.md`, `CLAUDE.md` (~60 lines) plus test-run reports; no source change expected.

---

## Requirement coverage

| Id | Tasks |
|---|---|
| R-01 | 1, 2, 3, 4, 5 |
| R-02 | 1, 4, 5 |
| R-03 | 1, 4, 5 |
| R-04 | 1, 3, 8 |
| R-05 | 6 |
| R-06 | 2, 4 |
| R-07 | 7 |
| R-08 | 1, 5 |
| R-09 | 7 |
| R-10 | 9 |
| R-11 | 9 |
| R-12 | 9 |
| R-13 | 5, 7, 10 |
| R-14 | 10 |
| R-15 | 10 |

Every id the SPEC declares is cited by at least one task; no id is cited that the SPEC does not
declare.

---

## Risks and HITL gates

- **Gate — probe 2 (Task 3).** SwiftUI drag-and-drop inside an `NSHostingView` inside an
  `NSTextAttachmentViewProvider` is unproven in this repo. A negative result costs R-04 its gesture
  and switches Task 8 to the context-menu fallback. Report before switching.
- **Query cost on a real vault.** ADR-0009 §D7's numbers were measured on a two-note vault. A view now
  evaluates when a note is *opened in the editor*, and a `text()` term reads every candidate file
  synchronously on the main actor. Unmeasured, named in the ADR's Consequences, worth watching during
  the R-14 hand-check.
- **`applyStyling` re-entrancy from `textViewDidChangeSelection`** (Task 6). Guarded, but new.
- **Comment staleness at `EditorColumn+Text.swift:194-198`.** A comment declaring a live thing dead is
  worse than none; it is rewritten in the same task that wires it.
- **HITL gates:** commit, push, merge to `main`, and the R-14 hand-check itself. No schema change, no
  migration, no deletion, no destructive command anywhere in this chain.
- **No new dependency.** `Tuist/Package.swift` is not touched; nothing goes through the Xcode UI.

---

EXTERNAL DEPENDENCY: tuist | binary | provisioned: true
EXTERNAL DEPENDENCY: xcodebuild | binary | provisioned: true

TEST-CMD CANDIDATE: xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -derivedDataPath "/Users/stefer/Developer/Pergamenum/.build/DerivedData" -only-testing:PergamenumTests test
TEST-CMD MODE: brownfield

CODER-MODEL CANDIDATE: opus
