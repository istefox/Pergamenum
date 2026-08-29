# Plan — Unificare Nota e Testo in un solo strumento del Workspace, con formattazione ricca del testo

- **ADR:** `docs/architecture/ADR-027-unificare-nota-e-testo-in-un-solo-strume.md`
  (the orchestrator relocates it to `docs/adr/0027-unificare-nota-e-testo-in-un-solo-strume.md`)
- **SPEC:** `/Users/stefer/Developer/Pergamenum/SPEC.md` (R-01 … R-12)
- **Branch base:** `fix/workspace-editable-note-text-cards` (holds `8c6405c`, the `TextEditor`
  this chain replaces — **not** `main`)
- **Style:** TDD. Red precondition first on every task, per this repo's last four Workspace
  chains.

---

## Before anything: what the SPEC says that the source does not

Verified against the working tree. Do not design or code against the left column.

| # | SPEC says | Source says | Where |
|---|---|---|---|
| C1 | Nota and Testo "differ only in whether `node.color` is pre-set" | They also differ in default size (220×120 vs 220×60) and in rendering: placeholder string, font token (`.heading` vs `.body`) and the whole padding/background/shadow branch are all keyed off `node.color != nil` | `WorkspaceController.swift:588`, `:598`; `StickyTextCard.swift:23`, `:26-38`, `:51`, `:65` |
| C2 | "`let tool: Tool = .note` call sites (`addStickyNote`, `WorkspaceView+Creation.swift`) collapse into `addFreeText`" | No such call site exists. `addStickyNote` **must survive** — `Tool.todo` is its other caller. The `.note` in `WorkspaceView+Creation.swift:72` is `NewCanvasItemSheet.Kind.note`, an unrelated enum reached from `Tool.document` | `WorkspaceController+Tools.swift:32` (only `.note` reference), `:33` (todo) |
| C3 | "That binding has no notion of a text selection, which is why selection-based formatting **requires** an NSTextView" | False as stated. macOS 26.5 ships `TextEditor(text: Binding<String>, selection: Binding<TextSelection?>)` and `TextSelection.Indices.selection(Range<String.Index>)`. NSTextView is still right, but for *styling* and *selection geometry*, not for selection access | `MacOSX26.5.sdk/…/SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface` |
| C4 | A floating mini-toolbar, presented as new work | Already shipped at M8 for the note editor: `FormatBar.swift`, `FormatBarPanel.swift`, `CompletingTextView+FormatBar.swift`, `Sources/Core/Editor/InlineFormat.swift`. Bold/italic/strikethrough/code toggling is done and tested, `****text**` nesting guard included | `InlineFormat.swift:123-139` (`isLongerMarker`) |
| C5 | The two new keys are "read/written in `CanvasNode`/`JSONCanvas.swift`" | Contradicts the precedent it cites. ADR-0020 §D2 keeps `pergamenum-crop` out of the codec entirely — it lives on `CanvasNode.unknown` and is read by `CanvasCrop.read(from:)` | `CanvasCrop.swift:44-47`; `JSONCanvas.swift:187-189`, `:193` |
| C6 | "No new persisted schema needed" for lists | True for persistence, incomplete for rendering: `MarkdownStyler` has **no list span at all**. A list prefix will be stored and drawn as plain text | `MarkdownStyler.swift` — "list" appears once, in a comment at `:381` |
| — | Cmd+B / Cmd+I unbound, no collision | **Confirmed.** Only `b`/`i` bindings are `newBoard` (Cmd+Shift+B) and `toggleInspector` (Cmd+Opt+I) | `ShortcutCommand.swift:215`, `:276` |
| — | `.text` keeps "Testo" / `textformat` / `t` | **Confirmed** | `WorkspaceController.swift:29`, `:45`, `:59` |

**Constraint the SPEC could not know:**
`Sources/Features/Editor/CompletingTextView+Pasteboard.swift` is a **declared protected
interface** (`.claude/protected-interfaces` line 3). No task in this plan edits any file under
`Sources/Features/Editor/`. If a task looks like it needs to, stop and report — do not edit.

---

## Contract changes and their already-grepped call sites

Every row below is a stale-assertion site found by grep *before* writing this plan. The coder
does not go looking for these; they are listed, and they are updated in the same task that
changes the contract. **Run the full unit suite after each, not just the touched module's
tests** — a contract change breaks tests in files that never mention it.

| Contract | Change | Call sites that break |
|---|---|---|
| `WorkspaceController.Tool` | remove `case note` | **Sources:** `WorkspaceController.swift:16` (decl), `:26` (`shortcut`), `:42` (`title`), `:58` (`symbol`); `WorkspaceController+Tools.swift:32` (`tapBehaviour`). These four are the *complete* set of exhaustive switches — confirmed by `grep -rn "case .todo" Sources/ Tests/ UITests/`, which returns exactly those four arms. **Tests:** `Tests/CanvasTests.swift:677` (`allCases.count == 11` → `10`), `:679` (`filter(\.isAvailable).count == 10` → `9`), `:680` (`filter { $0.shortcut != nil }.count == 10` → `9`). **UITests:** none — `grep -rn "Nota" UITests/` returns only note-file and composer strings, no Workspace tool. |
| `CardCommand` | add `.textColor`, `.textAlign` | **Sources:** decl `CardCommand.swift:14-24`, `title` `:33-42`, `symbol` `:62-71`, `available(for:isCroppable:hasCrop:)` `:95`; submenu wiring `BoardCardMenu.swift:69`, `:181`, `:191-194`. **Tests:** `Tests/CardCommandTests.swift:38` (`allCases.count == 10` → `12`); the three exhaustive `expected` dictionaries — title (~`:90-100`), symbol (~`:125-135`), identifier (~`:172-190`) — each fails on an uncovered case because `expected[command]` returns `nil`; every `available(...)` equality assertion from `:96` onward that must now include the new commands in menu order. |
| `StickyTextCard` | `TextEditor` + static `Text` pair → one `CardTextView` | **Sources:** single use site `NodeCard.swift:16`. Doc comments that name the `TextEditor` and go stale: `BoardContentLayer.swift:31-34`, `:227`. |
| `CanvasNode.unknown` | two new keys | **No code change to `JSONCanvas.swift`.** `CanvasNode.init?` (`:187-189`) already funnels unrecognised keys in and `rawValue` (`:193`) already re-emits them. Touching the codec is a design violation (ADR §D4), not an optimisation. |

---

## Conventions binding on every task

- **The tester owns the interface, the coder owns the body.** Swift is compiled: a batch that
  leaves the target unable to build produces no red tests at all, only a build error. So every
  new type's *declaration* (the `enum` cases, the `struct`'s stored properties, the method
  signatures returning a stub value) is written in the **tester's** task, together with the
  tests that call them. The coder fills in bodies.
- **`tuist generate --no-open` after every task that adds a file under `Sources/`.** The
  generated project lists files explicitly; a new file that Tuist has not seen fails the build
  naming the compiler rather than the cause.
- **Swift Testing (`@Test`/`#expect`) for all new tests.** Never XCTest.
- **Every new test file's header comment cites both** ADR-0027 and this plan's basename
  (`2026-08-28-unificare-nota-e-testo-in-un-solo-strume`).
- **One principal type per file** (`~/.claude/rules/swift.md`).
- **No new harness script.** This repo has none of that kind; `scripts/` holds
  release/uitests/mcp-smoke and stays as it is.
- **`scripts/uitests.sh` runs once, in Task 8, before merge** — never per task. Running the UI
  suite mid-chain terminates the app the person at the keyboard is using (CLAUDE.md).
- **The unit test command is `.claude/test-cmd` as it stands** —
  `-only-testing:PergamenumTests`. Do not widen it.
- `Sources/Core/**` is a `sharedSources` glob (`Project.swift:73`): a new file there is
  compiled into `perg` and `pergamenum-mcp`. **Foundation only** — an `import AppKit` or
  `import SwiftUI` there breaks both connector builds.
- The `weakening-scan.sh` pre-commit hook reports every Swift Testing test as
  `zero-assertion-test` because it treats `#expect` as a comment. Expected, systematically
  wrong for this stack, advisory (CLAUDE.md).

---

## Task 1 — Remove `.note` from `Tool` and repair the stale count assertions (R-01, R-02)

- Budget: `Sources/Features/Workspace/WorkspaceController.swift`,
  `Sources/Features/Workspace/WorkspaceController+Tools.swift`, `Tests/CanvasTests.swift`
  (~60 lines)

**Red first.** In `Tests/CanvasTests.swift`, update `excludesTheFormsToolFromV1` (`:674-681`)
to the post-change numbers — `11`→`10`, `10`→`9`, `10`→`9` — and add a new test asserting the
positive requirement rather than only the count:

- exactly one `Tool` case produces a `.text` node from a tap on empty board, and it is `.text`
  with title `"Testo"`, symbol `"textformat"`, shortcut `"t"` (R-01);
- no `Tool` case has shortcut `"n"` (R-01, "the `n` shortcut is freed and assigned to nothing");
- `Tool.todo.tapBehaviour` is still `.createSticky("- [ ] ")` — the guard against C2's mistake
  taking `addStickyNote` with it;
- `addFreeText` still produces a node with `color == nil` and size 220×60 (R-02, "exactly
  today's behavior"), and `setColor` on it afterward still sets the background (R-02, "the
  existing Colore command still changes its background").

These are red because `.note` still exists. Then delete `case note` and its four arms.

**Do not delete `addStickyNote`** (C2). **Do not change `addFreeText`'s 220×60 default** — ADR
§D8; it is cramped, that is recorded as a follow-up, it is not this chain's business.

Full unit suite must be green at the end of this task before Task 2 starts.

---

## Task 2 — `LineFormat`: the pure line-prefix arithmetic (R-05)

- Budget: `Sources/Core/Editor/LineFormat.swift`, `Tests/LineFormatTests.swift` (~260 lines)

**Tester writes the declaration and the tests together** (compiled-language rule). The
declaration, in `Sources/Core/Editor/LineFormat.swift`, **Foundation only** — modelled on
`InlineFormat.swift`'s own shape and its header warning about `sharedSources`:

```
enum LineFormat: Equatable, Sendable {
    case bullet
    case numbered
    case heading(level: Int)          // 1...3, per SPEC scope

    static func isApplied(_ format: Self, in text: String, over range: NSRange) -> Bool
    static func toggled(_ format: Self, in text: String, over range: NSRange)
        -> (text: String, selection: NSRange)
}
```

Tests to write red (all pure, no window, no theme, no AppKit):

- a bullet applied to one line inserts `- ` and the selection still covers the same words;
- a bullet applied to three selected lines prefixes all three;
- a bullet applied to lines that already carry `- ` **removes** it (toggle round-trips);
- a numbered list over three lines writes `1. `, `2. `, `3. ` and renumbers from 1 regardless
  of what preceded the run;
- `.heading(level: 2)` over a line already at `# ` **replaces** it with `## `, never stacks to
  `### `;
- `.heading` applied twice at the same level removes the prefix;
- a mixed selection (one line prefixed, one not) applies rather than removes — one press makes
  the whole selection consistent;
- an empty selection is a no-op on the caret's own line's *text* only if that matches
  `InlineFormat`'s precedent — assert the chosen behaviour explicitly either way;
- **the interaction that matters:** a line carrying inline markup (`- **bold** item`) toggles
  its prefix without disturbing the `**`.

`isApplied` is what lights the bar's button in Task 6; it must agree with `toggled`'s own
decision, so assert the pair round-trips rather than testing them independently.

---

## Task 3 — `CardTextStyle`: the two prefixed properties, read and written (R-06, R-07, R-10)

- Budget: `Sources/Features/Workspace/CardTextStyle.swift`, `Tests/CardTextStyleTests.swift`
  (~230 lines)

**Do not touch `Sources/Core/Canvas/JSONCanvas.swift`** (C5, ADR §D4). Model the new file on
`CanvasCrop.swift` line for line: key constants, a non-mutating `read(from:)`, a `formatted`
string.

Declaration the tester writes:

```
struct CardTextStyle: Equatable, Sendable {
    static let colorKey = "pergamenum-textColor"
    static let alignKey = "pergamenum-textAlign"

    enum Alignment: String, Equatable, Sendable { case left, center, right, justify }

    var color: CanvasColor?
    var alignment: Alignment?

    static func read(from node: CanvasNode) -> CardTextStyle
    // preset 1...6 → fixed sRGB, .hex verbatim; nil → nil (caller substitutes .textPrimary)
    static func rgba(for color: CanvasColor) -> RGBA?
}
```

Tests, red:

- a node with neither key reads `color == nil`, `alignment == nil` — **R-07's whole content**;
- a node with `"pergamenum-textColor": "3"` reads `.preset(3)`; with `"#A03060"` reads `.hex`;
- an out-of-range preset (`"9"`) and a malformed hex read as `nil` and — critically — the read
  **does not remove or rewrite the key**, matching `CanvasCrop.read`'s documented rule;
- each of the four alignment strings decodes; an unknown string decodes to `nil`;
- **round-trip through the codec**: build a `CanvasDocument` holding a `.text` node with both
  keys plus an unrelated `pergamenum-somethingElse` key and an unknown top-level key, run
  `encoded()` → `CanvasDocument(data:)` → `encoded()`, and assert the two `Data` are byte-equal
  (R-06 "survives save/close/reopen", R-10 "no corruption or unexpected keys");
- **a node this feature never touched is byte-identical after a round trip** — take a
  realistic Obsidian-authored `.canvas` fixture with `.text`, `.file`, `.group` nodes and edges,
  round-trip it, assert byte equality (R-10);
- writing: setting alignment on a node adds exactly one key and leaves `pergamenum-crop` and
  every other `unknown` entry untouched; clearing it **removes** the key rather than writing a
  default, the `endCrop`/`isWhole` precedent at `WorkspaceController+Crop.swift:121-125`.

---

## Task 4 — `FormattingTextView` + `CardTextView`, and `StickyTextCard` moved onto them (R-08, R-09, R-02)

- Budget: `Sources/Features/Workspace/FormattingTextView.swift`,
  `Sources/Features/Workspace/CardTextView.swift`,
  `Sources/Features/Workspace/CardTextAttributes.swift`,
  `Sources/Features/Workspace/StickyTextCard.swift`, `Tests/CardTextViewTests.swift`
  (~420 lines)

This is the task the ADR's §D1, §D2 and §D3 are about. Read them before starting.

**Step 4a — geometry probe, before any of the rest.** The board wraps its content in
`.scaleEffect(workspace.zoom, anchor: .topLeading)` (`WorkspaceView.swift:354`). Build the
smallest possible `NSViewRepresentable` NSTextView, put it in a card, and check by hand at
zoom 0.4, 1.0 and 2.5: does clicking place the caret where the pointer is; does drag-select
select what was dragged over; is the text legible. SwiftUI's own `TextEditor` already lives in
that same transform and works today (`8c6405c`), which is the reason to expect a pass — but it
is an expectation, not a measurement, and it is cheap to settle now and expensive to discover
in Task 6. **If the caret is offset by the zoom factor, stop and report** — the whole component
choice is back open and the ADR needs revisiting, not patching.

Verify manually (`open -n` a fresh Debug build with `-recentVaults '("/path")'`; find the
build with `ls -dt`, never plain `ls -d`, per CLAUDE.md).

**Step 4b — the component.** Three files:

- `CardTextAttributes.swift` — the card's own attribute table, keyed on
  `MarkdownStyler.Span`. **Do not call `MarkdownAttributedText.attributes(for:theme:)`**: its
  `.bold` arm returns `NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)`
  (`MarkdownAttributedText.swift:56`), the note's source-mode look, wrong on a card. Bold is
  bold, italic is oblique, strikethrough is a line. Colours come from theme tokens (the
  design-system rule holds here — this table *is* a view choosing a colour). Links are styled
  but **not** made clickable: no `.link` attribute, no navigation surface.
- `FormattingTextView.swift` — `final class FormattingTextView: NSTextView`, built
  `usingTextLayoutManager: true`, `isRichText = false`, the same automatic-substitution
  suppressions the note editor uses (`NoteTextView.swift:115-123` — smart quotes and dashes
  would rewrite `- [ ]` and `>2026-08-15` into characters the task parser rejects). Exposes
  `selectionFrameInView() -> CGRect?`, computed with
  `textLayoutManager.enumerateTextSegments(in:type:.selection)` plus `textContainerOrigin` —
  **view-local, never a screen coordinate** (ADR §D5).
- `CardTextView.swift` — `struct CardTextView: NSViewRepresentable` plus its `Coordinator`.

Three things the `Coordinator` must get right, each with a named reason:

1. **Its own `UndoManager`**, returned from `NSTextViewDelegate.undoManager(for:)`. Not the
   window's (ADR §D2). A card's text view is deallocated every time the card leaves the culling
   rect; an action left on the window's stack targeting it is the `EXC_BAD_ACCESS` in
   `-[_NSUndoStack popAndInvoke]` that `a853e8e` fixed for the note editor.
2. **`static func dismantleNSView`** purging actions targeting the view and its `textStorage`,
   mirroring `NoteTextView.swift:331-337`. Redundant given (1); kept because the cost of being
   wrong about (1) is a crash.
3. **`updateNSView` must not reset the text while editing.** The text binding is
   `editingTextDraft`; colour and alignment come from `node`. Guard the assignment with
   `textView.string != text`, the `NoteTextView.swift:252-259` pattern, or every keystroke
   resets the caret.

**Step 4c — swap `StickyTextCard`.** Replace the `TextEditor`/static-`Text` pair
(`StickyTextCard.swift:46-70`) with one `CardTextView`, `isEditable` the only difference
between the two states (R-08). Keep: the `.onChange(of: isFocused)` commit, the `Esc` handler,
the `node.color != nil` branch for padding/background/shadow. Apply `CardTextStyle`'s colour
and alignment from Task 3 to the whole text view.

Update the stale doc comments at `BoardContentLayer.swift:31-34` and `:227`, which name the
`TextEditor` by hand.

Tests (what is testable without a window — be honest about the split, the way ADR-0025 §D9 was
about the double-click gesture):

- `CardTextAttributes` returns a non-monospaced bold font for `.bold` (the regression this task
  exists to avoid);
- a To Do card's `"- [ ] "` prefix produces the same attribute run for a `**bold**` span as a
  plain card's does — **R-09's "no special-casing that excludes it"**, asserted as the absence
  of a difference rather than as a claim in a comment;
- the read-only and editing configurations produce the same attributed string for the same
  source (**R-08**), which is what "no static/editing visual divergence" reduces to once one
  component draws both.

Everything involving a real window, caret placement or focus is verified by hand in 4a and
again in Task 8, not asserted.

`tuist generate --no-open` at the end. Both connector builds still compile (nothing new under
`Sources/Core` in this task, but `Project.swift`'s Vault globs are named file-by-file and this
repo has been bitten by that before).

---

## Task 5 — Selection formatting inside the card, plus Cmd+B and Cmd+I (R-03, R-04, R-05)

- Budget: `Sources/Features/Workspace/FormattingTextView.swift`,
  `Sources/Features/Workspace/CardTextView.swift`, `Tests/CardFormattingTests.swift`
  (~240 lines)

Wire the two pure engines into the view. `InlineFormat.toggled` for bold/italic/strikethrough
(reused verbatim — **do not reimplement**, C4), `LineFormat.toggled` from Task 2 for
bullet/numbered/heading.

Both go through **one** edit path, so one press is one undo step:
`shouldChangeText(in:replacementString:)` → `textStorage.replaceCharacters` → `didChangeText()`
→ `setSelectedRange`, over the whole text. This is the four-line idiom at
`CompletingTextView+FormatBar.swift:103-109`. **Copy the idiom, do not extract the method** —
extracting means editing a file in `Sources/Features/Editor/`, which this chain does not do
(ADR §D1). Cite the source file in a comment so the duplication is deliberate rather than
accidental.

Cmd+B and Cmd+I: `performKeyEquivalent(with:)` on `FormattingTextView`, returning `true` only
when the view is editable and the modifier set is exactly `.command`. Verified unbound
elsewhere (`ShortcutCommand.swift:215`, `:276`) — R-04.

Note the neighbouring contract that must keep working: `BoardChrome.swift:125-130` already
suppresses the bare-key tool shortcuts while `editingTextNodeID != nil`, because a bare `n`
would otherwise switch tools while someone types "nota". Cmd+B/Cmd+I carry a modifier so they
are a different path, but the suppression must not regress.

Tests, red:

- bold over a selection wraps exactly that selection and leaves the rest of the card's text
  byte-identical (**R-03**);
- bold over an already-bold selection unwraps it, in **both** shapes — markers inside the
  selection (drag) and markers outside it (double-click) — which is `InlineFormat`'s own
  contract and the reason it is reused;
- bold over a selection whose neighbour is already `**` does not produce `****text**` (the
  SPEC edge case; `isLongerMarker` handles it, assert it at this level too);
- Cmd+B and Cmd+I resolve to the bold/italic actions (**R-04**) — assert against the key-event
  → action mapping, not against a real keystroke;
- a list and a heading applied to a multi-line selection insert the right prefixes through the
  same single-edit path (**R-05**);
- after any format action the selection still covers the same words, so pressing the same
  button twice round-trips.

---

## Task 6 — `CardFormatBar` and its board-space placement (R-03, R-05)

- Budget: `Sources/Features/Workspace/CardFormatBar.swift`,
  `Sources/Features/Workspace/BoardFormatBar.swift`,
  `Sources/Features/Workspace/BoardOverlays.swift`, `Tests/BoardFormatBarTests.swift`
  (~300 lines)

**Do not reuse `FormatBarPanel`** and **do not edit `FormatBar.swift`** (ADR §D5, §D6, A4, A5).
The note editor's bar is a screen-coordinate `NSPanel` and the board lives inside a
`scaleEffect`; and `FormatBar.swift:9-11` records a deliberate decision to carry no lists and
no headings, which this chain does not overrule for the note editor's benefit.

- `CardFormatBar.swift` — the pill: bold, italic, strikethrough, bullet, numbered, heading.
  Same visual language as `FormatBar` (theme tokens, `Capsule`, `.themedShadow(.raised)`, the
  `.contentShape(Rectangle())` fix at `FormatBar.swift:95` for hit-testing a `.clear`
  background — copy that, it was found by a person having to aim at a glyph). Buttons light
  from `InlineFormat.isApplied` / `LineFormat.isApplied`. **No colour and no alignment
  button** — those are Task 7's card-wide commands (ADR §D7).
- `BoardFormatBar.swift` — the placement. A SwiftUI sibling of `BoardContentLayer`, **outside**
  the `scaleEffect`, positioned with the board's own documented transform `p * zoom + pan`,
  exactly as `BoardMarquee` and `BoardGuides` do (`BoardOverlays.swift:16-19`, `:44`). Board
  point = the card's origin (`node.x`, `node.y`) plus the view-local selection frame from
  Task 4's `selectionFrameInView()`.
- Visibility: shown only while `editingTextNodeID == node.id` **and** the selection is
  non-empty. An empty selection (plain caret movement) hides it — the SPEC edge case, and the
  same rule `refreshFormatBar` already applies at `CompletingTextView+FormatBar.swift:16-19`.

Tests — the arithmetic is a static function precisely so it can be tested without a window:

- a selection frame at card-local `(x, y)` on a card at board `(bx, by)`, at zoom `z` and pan
  `p`, lands at `((bx + x) * z + p.width, …)`;
- the same input at zoom 1 with zero pan is the identity;
- the pill's own size does **not** scale with zoom (constant on-screen size);
- placement flips below the selection when there is no room above, or clamps to the viewport —
  pick one, assert it, and say which in a comment;
- visibility is false for an empty selection and false when the card is not being edited.

---

## Task 7 — Card-wide text colour and alignment as `CardCommand` cases (R-06)

- Budget: `Sources/Features/Workspace/CardCommand.swift`,
  `Sources/Features/Workspace/BoardCardMenu.swift`,
  `Sources/Features/Workspace/WorkspaceController.swift`, `Tests/CardCommandTests.swift`,
  `Tests/CardTextStyleTests.swift` (~280 lines)

Two new cases, `.textColor` and `.textAlign`, each with a submenu — the shape `.color` and
`.resize` already use (`BoardCardMenu.swift:191-194`). Both are available **only** on a `.text`
node.

The write path is `mutate`, mirroring `setColor(_:forNodeIDs:)` (`WorkspaceController.swift:529`):
one `mutate` writing at most the two keys, removing a key rather than writing a default when
the value is cleared. **`editingTextDraft` stays a `String`, `endTextEdit(commit:)` and
`setText` are unchanged** — ADR §D7 answers the SPEC's open question with "no change needed",
and that is the whole point of putting these on the command catalogue instead of in the draft.

**Update every stale assertion listed in the contract table above, in this task:**
`Tests/CardCommandTests.swift:38` (`10`→`12`), the three exhaustive `expected` dictionaries
(title, symbol, identifier), and every `available(...)` equality assertion that must now list
the new commands in menu order. Then run the **full** unit suite.

Also confirm by hand: the command surface must be reachable while a card is being edited.
`.contextMenu` is attached outside `selectionGestures(enabled:)` (`BoardContentLayer.swift:70`
vs `:60`), but a first-responder `NSTextView` claims the secondary click for its own menu — so
while editing, the route is `BoardCardControls`. If it turns out not to be reachable at all
while editing, say so in the report rather than adding a bar button that ADR §D7 argued against.

Tests, red:

- setting colour on a `.text` node writes `pergamenum-textColor` and nothing else changes;
- setting alignment then clearing it leaves the node's `unknown` exactly as it started —
  no leftover key, no default written;
- **the SPEC edge case:** deleting all of a card's text leaves both properties in place
  (they describe the card, not its content) — assert via `setText("")` then re-read;
- setting either on a node that also carries `pergamenum-crop` leaves the crop untouched;
- both survive a `CanvasDocument.encoded()` → decode → `encoded()` round trip (**R-06**,
  "survives a save/close/reopen of the board");
- neither command is offered on a `.file`, `.link` or `.group` node.

---

## Task 8 — Full suite, UI suite, and the Obsidian round trip by hand (R-10, R-11, R-12)

- Budget: no source files expected; `PROJECT_BRIEF.md` status line if a milestone moved
  (~20 lines)

1. **Full unit suite**, the project's own command, unmodified:
   `xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -derivedDataPath "$PWD/.build/DerivedData" -only-testing:PergamenumTests test`.
   Green, all 124+ files, not just the new ones (**R-12**). Run it in the background — a
   foreground call is killed at 2 minutes with exit 143.
2. **Both connector builds**: `perg` and `pergamenum-mcp`. `Sources/Core/Editor/LineFormat.swift`
   is inside the `sharedSources` glob, so a stray `import AppKit` there breaks these two rather
   than the app. This is ADR-0001 §D1 enforcing itself and it is worth one build each.
3. **`scripts/uitests.sh`**, whole bundle, no argument (an argument *replaces* the selection).
   Once, here, before merge (**R-11**). Twelve minutes. If a failure appears, read the seconds
   the script prints beside it before calling it a defect — a launch timeout is not one.
   Note that `-disableCalendar YES` is passed to every UI-test file for a reason; if this chain
   adds a UI-test file, it wants the flag too.
4. **Manual Obsidian round trip (R-10)** — the criterion no automated test in this repo can
   stand in for:
   - open the real "Labs" vault's existing boards; nothing renders differently except the
     styling changes ADR Consequences names (a `#tag`, a `[[Nota]]` and a `- [ ] ` in a card
     are now styled where they were plain);
   - `git diff` the vault, or `md5` the `.canvas` files before and after: **a board that was
     opened and not edited must be byte-identical on disk**;
   - create a card, bold a word, set a colour and a right alignment, save, open the same
     `.canvas` in Obsidian: the text reads as markdown with `**` visible, the two
     `pergamenum-*` keys survive an Obsidian edit-and-save, and no node is lost.
5. Update `PROJECT_BRIEF.md`'s Status section only if a milestone actually moved.

---

## Risks, dependencies and HITL gates

**Risks, highest first.**

1. **An `NSTextView` inside the board's `scaleEffect`.** Caret placement, drag-selection and
   text crispness at zoom ≠ 1 are the unknown this whole component rests on. Mitigated by
   Task 4a probing it first and by the fact that SwiftUI's own `TextEditor` already lives in
   that transform today. If 4a fails, the ADR reopens — do not patch around it.
2. **Undo-stack pollution and the dangling-target crash.** `a853e8e` fixed exactly this for the
   note editor eleven hours before this plan was written, and a card's text view is
   deallocated far more often. The private `UndoManager` (§D2) is the fix; the `dismantleNSView`
   purge is the second line. Getting this wrong is a crash, not a glitch, and it will present
   as an unrelated Cmd+Z somewhere else in the app.
3. **Two contract changes with exhaustive test fixtures.** `Tool` (three assertions) and
   `CardCommand` (four fixtures). All are listed above with line numbers; the risk is not
   finding them, it is running only the touched module's tests and shipping a red suite.
4. **Performance:** one `NSTextView` per visible text card, where today a card at rest is a
   static `Text`. `BoardGeometry.drawsPlaceholder(at:)` caps the worst case below quarter zoom.
   Watch it on a board with many cards during the Task 8 hand-check; if it is bad, the
   fallback is a static rendering at rest, which costs R-08 and needs a decision, not a patch.
5. **Visible change to existing boards.** Cards now go through `MarkdownStyler`, so tags,
   wikilinks and To Do prefixes gain styling they never had. Expected, named in the ADR, and
   the thing to look at first during the Task 8 Labs-vault check.
6. **Branch base.** This chain builds on `fix/workspace-editable-note-text-cards`, not `main`.
   Branching from `main` gets a `StickyTextCard` without the `TextEditor` and half of Task 4
   stops making sense.

**Dependencies.** None external. No new package, no `Tuist/Package.swift` change, no
`tuist install`. Everything used is already in the repo or in the macOS 26.5 SDK.

**HITL gates.**

- **Gate 2 (now):** approve this ADR and plan. Two proposals below need an explicit answer —
  the protected-interface entry and the audit profile.
- **After Task 4a:** if the geometry probe fails, that is a design gate, not a coding problem.
  Stop and report.
- **Before every commit** (CLAUDE.md, global): human approval. Feature branch only, never
  `main`, Conventional Commits.
- **Before the merge to `main`:** `scripts/uitests.sh` green (Task 8) plus the manual Obsidian
  round trip. Both are human-gated.
- **No schema change, no migration, no deletion, no deploy** in this chain — none of those
  gates apply.

---

TEST-CMD CANDIDATE: none
TEST-CMD MODE: brownfield

CODER-MODEL CANDIDATE: opus
