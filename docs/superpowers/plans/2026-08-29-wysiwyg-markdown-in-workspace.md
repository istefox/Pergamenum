# Plan — WYSIWYG markdown rendering (lists + concealment) unified across Nota and Workspace

- **ADR:** `docs/architecture/ADR-0028-wysiwyg-markdown-in-workspace.md`
  (the orchestrator relocates it to `docs/adr/0028-wysiwyg-markdown-in-workspace.md`)
- **SPEC:** `/Users/stefer/Developer/Pergamenum/SPEC.md` (R-01 … R-12)
- **Branch base:** `main` at `4623c7d` — ADR-0027 is merged (PR #111), so `FormattingTextView`,
  `CardTextView`, `CardTextAttributes` and `LineFormat` all exist on `main`.
- **Style:** TDD. Red precondition first on every task, per this repo's last five Workspace
  chains.

---

## Before anything: what the SPEC says that the source does not

Verified against the working tree at `4623c7d`. Do not design or code against the left column.

| # | SPEC says | Source says | Where |
|---|---|---|---|
| C1 | «Nota always shows the markers, dimmed»; concealment is «partial» | Concealment is **on by default**: `VaultSettings.hidesMarkup` defaults to `true`, is user-settable, and already hides `#`/`*`/`**` outside the caret's paragraph. What is missing is a list span to conceal, not the mechanism | `VaultSettings.swift:140`, `:215`; `EditorSettings.swift:19-20`; `EditorDecorationDelegate.swift:191-231` |
| C2 | «`LineFormat` already renumbers an ordered run at toggle time — auto-continuation reuses that arithmetic» | `LineFormat.toggled(.numbered)` numbers **the touched selection**, from 1, by position in the selection (`ordinal: offset + 1`). No notion of a run's extent or its start number. Nothing to reuse for R-08 | `LineFormat.swift:62`, `:87` |
| C3 | UI flow 5: «click the disclosure control of a heading (mirroring Nota)» | Nota has **no in-text disclosure control**. Fold is triggered from `OutlinePane`'s chevron; the only in-text interaction is a click on the badge of an already-folded heading, which unfolds | `OutlinePane.swift:66`, `:72`; `NoteTextView+Transclusion.swift:161-173` |
| C4 | R-06: a checkbox line «shows only its existing checkbox glyph» | **There is no checkbox glyph.** `- [ ]` is drawn as its own characters, coloured via `.taskMarker(done:)`. R-06 is satisfied by emitting no list span on a checkbox line, so the line stays exactly as today | `MarkdownStyler.swift:405-412`; `MarkdownAttributedText.swift:126`; `CardTextAttributes.swift:191` |
| C5 | The card «needs an equivalent concealment mechanism» | The card is missing a **delegate**, not a mechanism: its text view is already TextKit 2 with a live `NSTextContentStorage`. Wiring is two lines, and the note editor shows which two | `CardTextView.swift:46`; `NoteTextView.swift:148-149` |
| C6 | Fold uses «the same transient model Nota already uses» | True, and keyed differently: Nota's set lives on the **tab**, by outline-entry ordinal. A card has no tab — the equivalent is a `[nodeID: Set<Int>]` on `WorkspaceController`, cleared in `attach`, which is what actually enforces «resets on board reopen» | `EditorColumn+Text.swift:95`; `NoteTextView.swift:96`; `WorkspaceController.swift:174-202` |
| — | `MarkdownStyler` has no list span | **Confirmed.** «list» appears once, in a comment | `MarkdownStyler.swift:381` |
| — | `EditorDecorationDelegate` is not a protected/fenced file | **Confirmed.** The editor entry is `CompletingTextView+Pasteboard.swift`, a different file | `.claude/protected-interfaces` line 3 |

**Three constraints the SPEC could not know** (ADR §Context):

1. **The displayed paragraph may not change length.** A bullet can only *replace* a character,
   never be inserted (`EditorDecorationDelegate.swift:283-285`, `NSTextContentManager.h:120`).
2. **The note editor's Enter is already claimed twice** — completion panel first, then a
   `claimsCommand` closure set at `NoteTextView.swift:207` and consulted at
   `CompletingTextView.swift:239-241`. That closure is the seam; `CompletingTextView.swift` is
   not edited.
3. **A card's text view is deallocated on every culling-rect crossing.** Anything added to it
   (delegate, tables) inherits that lifetime — R-11, and the `a853e8e` crash class.

---

## Contract changes and their already-grepped call sites

Every row is a stale-assertion site found by grep **before** this plan was written. The coder
does not go looking for these; they are listed, and they are updated in the same task that
changes the contract. **Run the full unit suite after each task, not just the touched module's
tests** — a contract change breaks tests in files that never mention it.

| Contract | Change | Call sites that break |
|---|---|---|
| `MarkdownStyler.Span` | add `case listMarker(kind:level:)` | **Compile errors (no `default`):** `MarkdownStyler.suppressesSpellCheck` (`:112-123`), `MarkdownAttributedText.colorToken(for:)` (`:106-130`), `CardTextAttributes.colorToken(for:)` (`:181-195`). **Compiles but is wrong until updated:** `NoteTextView+Coordinator.swift:265-270` (`switch styled.span { … default: nil }` — needs `.listMarker → .list`). **Safe, have a `default`:** `MarkdownAttributedText.attributes(for:)` (`:44+`), `CardTextAttributes.attributes(for:)` (`:92+`). **Tests:** grepped — `Tests/MarkdownStylerTests.swift` asserts full span arrays only at `:54` («# Titolo») and `:100-102` («*corsivo*»), neither containing a list marker, so nothing breaks; `:150-158`'s checkbox assertions are the R-06 guard and **must stay green**. |
| `HiddenMarker.Kind` | add `case list` | **Compile error (no `default`):** `EditorDecorationDelegate.stillSpells(_:_:at:)` (`:353-363`). **Additive, no break:** `Tests/MarkupHidingTests.swift`, `Tests/EmbedDrawingTests.swift`, `Tests/EmbedAttachmentProbeTests.swift` all name kinds explicitly when constructing a `HiddenMarker`. |
| `CardCommand` | add `case foldHeadings` | **Sources:** decl (`CardCommand.swift:14-31`), `title` (`:38-52`), `symbol` (`:62-78`), `available(for:isCroppable:hasCrop:)` (`:102`); submenu arm in `BoardCardMenu.swift:200-210` beside `.textColor`/`.textAlign` (`:204-207`). **Tests:** `Tests/CardCommandTests.swift:43` (`allCases.count == 12` → `13`); the three exhaustive `expected` dictionaries — title (`:103-117`), symbol (`:139-153`), identifier (`:188-202`) — each fails on an uncovered case because `expected[command]` returns `nil`; every `available(...)` order assertion from `:48` onward that must now include the new command in menu order (`:58`'s `.text` case above all). |
| `CardTextView` | gains `hidesMarkup: Bool`, `foldedEntries: Set<Int>`, `onToggleFold: (Int) -> Void` | **Sources:** one construction site, `StickyTextCard.swift:53`. **Tests:** none — grepped, no test constructs `CardTextView` (`Tests/CardFormattingTests.swift:28` constructs a bare `FormattingTextView`, which is unaffected). |
| `WorkspaceController` | gains `hidesMarkup: Bool` and `foldedHeadings: [String: Set<Int>]` | **Sources:** set from `WorkspaceView.applyBoardSettings()` (`:473-477`, already re-run by `onChange(of: vault.settings)` at `:380`); cleared in `attach`/`detach` (`WorkspaceController.swift:174-202`). No test asserts the controller's property list. |

**Not touched, checked one by one (ADR §D12):** `IndexCache.schemaVersion` (`.canvas` files are
not in the index at all), `VaultAPI.LintFinding` (no connector change of any kind),
`CompletingTextView+Pasteboard.swift` (Enter is taken through `claimsCommand`, not through that
file). All three are the declared protected interfaces; `interface-check.sh` must stay silent.

---

## Conventions binding on every task

- **The tester owns the interface, the coder owns the body.** Swift is compiled: a batch that
  leaves the target unable to build produces no red tests at all, only a build error. Every new
  type's *declaration* (enum cases, stored properties, method signatures returning a stub) is
  written in the **tester's** task together with the tests that call them. The coder fills in
  bodies.
- **`tuist generate --no-open` after every task that adds a file under `Sources/`.** The
  generated project lists files explicitly; a new file Tuist has not seen fails the build naming
  the compiler rather than the cause.
- **Swift Testing (`@Test`/`#expect`) for all new tests.** Never XCTest.
- **Every new test file's header comment cites both** ADR-0028 and this plan's basename
  (`2026-08-29-wysiwyg-markdown-in-workspace`).
- **One principal type per file** (`~/.claude/rules/swift.md`).
- **No new harness script.** This repo has none of that kind; `scripts/` holds
  release/uitests/mcp-smoke/install-cli and stays as it is. Any helper written for a hand-check
  is throwaway and must be Bash 3.2-clean (no `mapfile`, no associative arrays, no `${x^^}`).
- **The unit test command is `.claude/test-cmd` exactly as it stands** —
  `-only-testing:PergamenumTests`. Do not widen it; the UI suite in there terminates the app the
  person at the keyboard is using (CLAUDE.md).
- **`scripts/uitests.sh` runs once, in Task 8, before merge** — never per task.
- `Sources/Core/**` is a `sharedSources` glob (`Project.swift:73`): a new file there is compiled
  into `perg` and `pergamenum-mcp`. **Foundation only** — an `import AppKit`/`import SwiftUI`
  there breaks both connector builds.
- `Sources/Features/Editor/` **is** in scope for this chain (ADR §D5), with one exception:
  `CompletingTextView.swift` and every `CompletingTextView+*.swift` stay untouched. If a task
  looks like it needs to edit one, stop and report.
- The `weakening-scan.sh` pre-commit hook reports every Swift Testing test as
  `zero-assertion-test` because it treats `#expect` as a comment. Expected, systematically wrong
  for this stack, advisory (CLAUDE.md).
- The secret scanner's `assigned-secret` heuristic fires on design-token lines. Expected;
  read each hit before dismissing it.

---

## Task 1 — `MarkdownStyler` learns lists, and the exhaustive switches learn the span (R-01, R-06)

- Budget: `Sources/Features/Editor/MarkdownStyler.swift`,
  `Sources/Features/Editor/MarkdownAttributedText.swift`,
  `Sources/Features/Workspace/CardTextAttributes.swift`, `Tests/MarkdownStylerTests.swift`
  (~180 lines)

**Tester writes the declaration and the tests together** (compiled-language rule). The
declaration, in `MarkdownStyler.Span`:

```
enum ListKind: Equatable, Sendable { case bullet, ordered }
case listMarker(kind: ListKind, level: Int)
```

**Red first**, in `Tests/MarkdownStylerTests.swift`:

- `- primo`, `* primo`, `+ primo` each yield exactly one `.listMarker(kind: .bullet, level: 1)`
  whose styled text is the marker **and its trailing space** (`"- "`), using the file's existing
  `styled(_:_:)` helper (R-01);
- `1. uno`, `12. dodici`, `12) dodici` yield `.listMarker(kind: .ordered, level: 1)` with styled
  text `"1. "` / `"12. "` / `"12) "` (R-01);
- `  - sotto` yields level 2, `    - sotto` level 3, `\t- sotto` level 3 (tab = 4 columns), and
  a 20-space indent is capped at level 6 (R-01, R-05's precondition);
- **`- [ ] Da fare`, `- [x] Fatto`, `- [>] Rimandato`, `- [-] Annullato` and
  `    - [ ] Annidato` yield NO list span at all** while keeping their existing `.taskMarker`
  span — the R-06 guard, asserted both ways;
- a list marker inside a fenced code block yields no span (the fence filter at `:93` already
  does this — assert it so the new recogniser cannot regress it);
- `-` alone, `-nodash`, `1.no-space` and `1.` at end of line yield no list span (a marker needs
  its trailing space);
- `MarkdownStyler.suppressesSpellCheck(.listMarker(kind: .bullet, level: 1)) == true`.

These are red because the case does not exist. Then implement: recognise the marker in
`spans(inLine:at:in:)` **after** `taskMarker(in: trimmed)` is computed and only when it is nil
(§D2), reusing the existing `indent`/`trimmed` locals; add the arm to `suppressesSpellCheck`;
add `.listMarker` to `MarkdownAttributedText.colorToken(for:)` and
`CardTextAttributes.colorToken(for:)` — `.textTertiary` in both, the shelf `.headingMarker` and
`.emphasisMarker` already sit on. Neither `attributes(for:)` needs an arm: the glyph, not the
colour, is what makes a list look like a list (Task 3).

Do **not** touch `LineFormat` (C2). Do **not** add a `.listItem` span for the item's text — the
view derives the paragraph, as the ADR §D1 says.

Full unit suite green before Task 2 starts.

---

## Task 2 — `ListContinuation`: Enter and run renumbering, pure (R-07, R-08)

- Budget: `Sources/Core/Editor/ListContinuation.swift`, `Tests/ListContinuationTests.swift`
  (~320 lines)

**Tester writes the declaration and the tests together.** The declaration, in
`Sources/Core/Editor/ListContinuation.swift`, **Foundation only**, modelled on
`LineFormat.swift`'s shape and its header warning about `sharedSources`:

```
enum ListContinuation {
    static func newline(in text: String, at selection: NSRange) -> (text: String, selection: NSRange)?
    static func renumbered(_ text: String) -> String?
}
```

**Red first**, in `Tests/ListContinuationTests.swift`:

*`newline` (R-07)*

- caret at end of `- secondo` in `- primo\n- secondo` → text gains `\n- `, selection is a caret
  after the new marker;
- same for `* ` and `+ ` (the marker's own character is preserved, not normalised to `-`);
- caret at end of `2. due` in a `1./2.` run → new line is `3. ` **and the rest of the run is
  already renumbered in the returned text** (one edit, one undo step — R-12's precondition);
- caret at end of `- [ ] fai` → new line is `- [ ] ` (empty checkbox, never `- [x] `);
- caret on an item whose text is empty (`- `, `1. `, `- [ ] `) → the prefix is **removed**, the
  line becomes empty, no new line is inserted (R-07's exit rule);
- indentation is carried over: caret at end of `  - annidato` → new line is `  - `;
- caret in the **middle** of an item → the item splits and the second half keeps the marker;
- a non-list line, an empty document, and a caret inside a fenced code block all return `nil`;
- a non-empty selection returns `nil` (Return over a selection is a replace, not a continuation).

*`renumbered` (R-08)*

- `1. a\n3. b\n7. c` → `1. a\n2. b\n3. c`;
- **`3. a\n9. b` → `3. a\n4. b`** — a run is renumbered from its own first ordinal, never from 1
  (ADR §A6). This is the test that pins the rule;
- an already-contiguous run returns `nil` (no edit, no undo step, no fight with the typist);
- `1. uno\n- due` is two runs of one item each — `- due` is untouched and `1. uno` stays `1.`
  (the SPEC's adjacent-lists edge case);
- a blank line between two ordered runs separates them; each restarts from its own first
  ordinal;
- nested items renumber within their own level: `1. a\n  1. x\n  5. y\n2. b` → the inner run
  becomes `1./2.` and the outer stays `1./2.`;
- `1) a\n5) b` keeps the `)` delimiter it was written with;
- a checkbox line is never renumbered and never breaks a run's contiguity check in a way that
  rewrites it (`- [ ]` is not an ordered item);
- text with no ordered list at all returns `nil`.

These are red because the file does not exist (the tester writes stub bodies returning `nil` so
the target still builds — the compiled-language rule). Then implement, reusing nothing from
`LineFormat` but the idea; the marker-scanning duplication between the two files is accepted and
recorded in ADR §Consequences.

Full unit suite green before Task 3 starts.

---

## Task 3 — The delegate renders a list: substitution, indent, concealment (R-02, R-03, R-05)

- Budget: `Sources/Features/Editor/EditorDecorationDelegate.swift`,
  `Sources/Features/Editor/ListMarkerRendering.swift` (new),
  `Sources/Features/Editor/NoteTextView+Coordinator.swift`, `Tests/MarkupHidingTests.swift`
  (~340 lines)

**Red first**, extending `Tests/MarkupHidingTests.swift` with its existing windowless harness
(`frames(text:markers:hidesMarkup:revealed:)`, `:16-55`) — no window, no board, no UI test:

- **length invariance, first and loudest:** for every case below,
  `content.textStorage?.length` equals the source string's length. The file must not gain or
  lose a character (R-10's structural half);
- with `hidesMarkup: true` and nothing revealed, a `.list` marker on `- primo` produces a
  displayed paragraph whose first character is `•` and whose length is unchanged (R-02);
- an ordered marker `1. uno` is displayed **verbatim** — the digits are the ordinal (R-02, ADR
  §D4);
- a level-2 marker's displayed paragraph carries an `NSParagraphStyle` whose `headIndent` and
  `firstLineHeadIndent` are strictly greater than a level-1 marker's, and level-1's are greater
  than zero (R-05);
- the leading indent characters are drawn in `EditorDecorationDelegate.collapsedFont` (R-05's
  «no double indentation» half);
- with the paragraph **revealed**, the hook returns `nil`: the raw source, no substitution, no
  paragraph style (R-03);
- with `hidesMarkup: false`, the hook returns `nil` regardless of the revealed set (ADR §D10);
- a stale marker — the table says `.list` at an offset whose characters no longer spell one —
  is skipped and the other markers in the same paragraph still render (the `stillSpells`
  re-check contract, `:216-223`);
- a paragraph carrying a list marker **and** an emphasis marker (`- **grassetto** elemento`)
  renders both: the bullet substituted, the `**` collapsed, one paragraph, unchanged length
  (the SPEC's coexistence edge case).

Then implement:

- `HiddenMarker.Kind` gains `case list`; `stillSpells` gains its arm — a list marker still
  spells one when the characters at its range are an optional indent run followed by
  `-`/`*`/`+`/digits with the delimiter and the trailing space, and **not** a checkbox;
- a new `listParagraph(at:storage:)` branch in `textContentStorage(_:textParagraphWith:)`,
  written beside the embed branch and under the same length rule: indent → `collapsedFont`,
  unordered marker character → `•` via `replaceCharacters(in: oneChar, with: "•")`, ordered
  marker untouched, trailing space kept, paragraph style applied over the whole displayed
  paragraph;
- `Sources/Features/Editor/ListMarkerRendering.swift` holds the two things both attribute tables
  and the delegate must agree on — `glyph(for kind:)` and `paragraphStyle(level:font:)` — so the
  indent step is stated once;
- `NoteTextView+Coordinator.swift:265-270` maps `.listMarker` → `.list`, so Nota's existing
  styling walk populates the table with no other change (the marker range is already made
  paragraph-relative there).

**Ordering note for the coder:** the marker range recorded for a `.list` kind must start at the
**paragraph's start** (indent included), not at the marker character, or the indent cannot be
collapsed. This differs from `.heading`/`.emphasis` and is the one place this task is not a copy
of an existing arm.

Full unit suite green before Task 4 starts.

---

## Task 4 — Nota: lists reveal on caret, and Enter continues a list (R-03, R-07, R-08, R-12)

- Budget: `Sources/Features/Editor/NoteTextView.swift`,
  `Sources/Features/Editor/NoteTextView+Coordinator.swift`, `Tests/MarkupRevealTests.swift`,
  `Tests/NoteListEditingTests.swift` (new) (~220 lines)

**Red first:**

- in `Tests/MarkupRevealTests.swift`, the caret's paragraph is revealed and the neighbouring
  list paragraph is not, for a three-item list — asserting `MarkupReveal.paragraphs` needs no
  change for lists (it is offset arithmetic and already correct). If it does need one, that is a
  finding to report, not a silent edit;
- in a new `Tests/NoteListEditingTests.swift`, driven through a real `CompletingTextView` built
  offscreen the way `Tests/CardFormattingTests.swift:28` builds a `FormattingTextView`:
  - `insertNewline(_:)` inside `- primo` produces `- primo\n- ` in the storage (R-07);
  - a second `insertNewline` on the now-empty item produces `- primo\n` (R-07's exit);
  - `insertNewline` at the end of `2. due` in a `1./2./3.` run leaves a contiguous
    `1./2./3./4.` (R-08);
  - **one `undoManager.undo()` restores the text to exactly what it was before the press**
    (R-12) — for both the plain continuation and the renumbering one;
  - `insertNewline` on a non-list line inserts a plain newline and nothing else.

Then implement: extend the closure at `NoteTextView.swift:207` (already assigned to
`CompletingTextView.claimsCommand`) to claim `#selector(insertNewline(_:))` when
`ListContinuation.newline` returns non-nil, applying the result as one
`shouldChangeText`/`replaceCharacters`/`didChangeText` edit. Add the post-edit renumber pass to
the coordinator's existing `textDidChange` (`:186-215`), applying `ListContinuation.renumbered`
only when it returns non-nil, after the styling passes and before `applyReveal`.

**Do not edit `CompletingTextView.swift`.** The seam is the closure, and the panel keeps first
refusal on Return by construction (`:239-241`).

**Watch:** the renumber pass runs on every keystroke. If it ever rewrites text the user is
mid-word on, the rule in `renumbered` is wrong, not the call site — go back to Task 2's tests.

Full unit suite green before Task 5 starts.

---

## Task 5 — The card gets the delegate: concealed at rest, revealed on caret (R-02, R-03, R-04, R-11)

- Budget: `Sources/Features/Workspace/CardTextView.swift`,
  `Sources/Features/Workspace/StickyTextCard.swift`,
  `Sources/Features/Workspace/WorkspaceController.swift`,
  `Sources/Features/Workspace/WorkspaceView.swift`, `Tests/CardConcealmentTests.swift` (new)
  (~260 lines)

**Red first**, in a new `Tests/CardConcealmentTests.swift`, built on the same windowless
`NSTextContentStorage` harness as `MarkupHidingTests` plus a bare `FormattingTextView`:

- a card's styling pass over `# Titolo\n- primo\n**grassetto**` produces a hidden-marker table
  containing a `.heading`, a `.list` and two `.emphasis` entries, each paragraph-relative
  (R-04's precondition, and the assertion that the card's walk matches the note's);
- with `isEditable == false` the published revealed set is **empty** — every marker concealed
  (R-04);
- with `isEditable == true` and the caret on line 2, the revealed set is exactly that
  paragraph's start offset (R-03);
- with `hidesMarkup == false` nothing is concealed on the card either (ADR §D10);
- `CardTextView.dismantleNSView` leaves the delegate's tables empty and the undo manager with no
  actions targeting the view or its storage (R-11) — extending the existing purge assertions
  rather than replacing them.

Then implement:

- `CardTextView.makeNSView` assigns `textView.textContentStorage?.delegate` and
  `textView.textLayoutManager?.delegate` to a delegate owned by the `Coordinator`
  (`NoteTextView.swift:148-149`'s two lines);
- the coordinator's `applyStyling` walk fills `hiddenMarkers` from `MarkdownStyler.spans`
  exactly as `NoteTextView+Coordinator.swift:255-282` does, calls
  `decorations.apply(hiddenMarkers:hidingMarkup:)` **before** `endEditing()` (the ordering that
  file documents at `:293-295`), and sets `badgeColor`/`badgeBackground` from theme tokens;
- a card-side `applyReveal` calls `MarkupReveal.paragraphs(in:selection:markedRange:
  currentMatch: nil)` while editable and publishes the empty set otherwise;
- `CardTextView` gains `hidesMarkup: Bool`; `StickyTextCard` passes
  `workspace.hidesMarkup`; `WorkspaceView.applyBoardSettings()` sets it from
  `vault.settings.hidesMarkup` (`:473-477`, already re-run on `onChange(of: vault.settings)`);
- `dismantleNSView` clears the delegate's tables alongside the existing undo purge.

**Do not** give the card a second `hidesMarkup` switch, and do not read `VaultController` from
inside `StickyTextCard` via `@Environment` — a card built in a preview or a test would crash.
The value travels the route board settings already travel.

Full unit suite green before Task 6 starts.

---

## Task 6 — The card's Enter, its renumbering, and one undo step per press (R-07, R-08, R-12)

- Budget: `Sources/Features/Workspace/FormattingTextView.swift`,
  `Sources/Features/Workspace/CardTextView.swift`, `Tests/CardFormattingTests.swift`
  (~160 lines)

**Red first**, extending `Tests/CardFormattingTests.swift` (which already builds a
`FormattingTextView` offscreen at `:28`):

- `insertNewline(_:)` inside `- primo` gives `- primo\n- ` and leaves the caret after the marker
  (R-07);
- the second press on the empty item strips the prefix (R-07);
- a press inside a `1./2./3.` run renumbers the whole run in the same edit (R-08);
- `- [ ] fai` continues as `- [ ] ` (R-07);
- **one `undo()` on the coordinator's private `UndoManager` restores the pre-press text**, for
  the plain and the renumbering case alike (R-12, and the ADR-0027 §D2 stack is the one that
  must answer);
- deleting a middle item of an ordered run through `replaceCharacters` renumbers the rest, and
  **one** `undo()` restores both the deletion and the renumbering (R-08 + R-12's
  `groupsByEvent` claim — this is the assertion that turns the ADR's «AppKit groups them» into a
  fact; if it fails, group explicitly with `beginUndoGrouping`/`endUndoGrouping` and record it);
- a press on a non-list line falls through to `super` (assert the text gains exactly `\n`).

Then implement: `FormattingTextView.insertNewline(_:)` calling `ListContinuation.newline` and
applying through the existing `replaceWholeText(with:selecting:)` (`:110-117`); the renumber
pass in the coordinator's `textDidChange` (`:147-155`), before `applyStyling`.

Full unit suite green before Task 7 starts.

---

## Task 7 — Fold on a card: the command, the submenu, the badge (R-09, R-11, R-12)

- Budget: `Sources/Features/Workspace/CardCommand.swift`,
  `Sources/Features/Workspace/BoardCardMenu.swift`,
  `Sources/Features/Workspace/WorkspaceController.swift`,
  `Sources/Features/Workspace/CardTextView.swift`,
  `Sources/Features/Workspace/FormattingTextView.swift`, `Tests/CardCommandTests.swift`,
  `Tests/CardFoldTests.swift` (new) (~300 lines)

**Red first:**

- in `Tests/CardCommandTests.swift`, the four fixtures listed in the contract table above —
  count `12` → `13`, the three `expected` dictionaries, and `available(...)` order: `.foldHeadings`
  is offered on a `.text` node and **never** on a file, link or group node (mirroring
  `:66`'s existing `.textColor`/`.textAlign` assertion);
- in a new `Tests/CardFoldTests.swift`:
  - `NoteFolding.layout(in: cardText, foldedEntries: [0])` over a card's own markdown hides the
    right lines and reports the right count — asserting the note's pure type answers for a card
    with no adaptation (R-09);
  - toggling `foldHeadings` for a node id twice returns the controller to an empty set, and the
    table is keyed by node id so two cards fold independently (R-09);
  - `WorkspaceController.attach(to:…)` clears the fold table — the line that enforces «resets
    when the board is reopened» (R-09, C6);
  - a fold table entry for a node that no longer exists is never resurrected after a
    dismantle/rebuild cycle (R-11);
  - one `undo()` after a fold toggle leaves the **text** untouched — folding is a view state and
    must register no text edit at all, which is what keeps R-12 true for it (assert the storage
    string is identical and the undo manager has no action for the view).

Then implement: `CardCommand.foldHeadings` (title `"Ripiega titoli"`, symbol
`"chevron.up.chevron.down"`, offered only on `.text`), its `BoardCardMenu` submenu built from
`NoteOutline.entries(in:)` over the node's own text with a check per folded entry;
`WorkspaceController.foldedHeadings[nodeID]` cleared in `attach`; `CardTextView` passing the set
down and calling `NoteFolding.layout` into `decorations.apply(hiddenLines:foldedHeadings:)` plus
the `edited(.editedAttributes,…)` + `invalidateLayout` re-read `NoteTextView+Coordinator.swift:
148-166` documents; `FormattingTextView.mouseDown` claiming a click on a
`FoldedHeadingFragment`'s `badgeFrameInContainer` **while editable only**, re-stating the ~12
lines of `decoration(at:in:claimedBy:)` rather than extracting them from
`NoteTextView+Transclusion.swift` (ADR §D9).

`FoldedHeadingFragment` and `NoteFolding` are used **unchanged**. If either needs an edit, stop
and report — that is a design finding, not a coding one.

Full unit suite green before Task 8 starts.

---

## Task 8 — Round trip, the UI suite, and the hand-check (R-04, R-10, R-12)

- Budget: `Tests/CardRoundTripTests.swift` (new), `CLAUDE.md`, `TODO.md`,
  `PROJECT_BRIEF.md` (~120 lines)

**Red first**, in a new `Tests/CardRoundTripTests.swift`:

- a `.md` note and a `.canvas` node whose text contains every construct this chain renders —
  `# Titolo`, `- primo`, `  - annidato`, `1. uno`, `- [ ] fai`, `**grassetto**` — are written,
  read back through `NoteStore`/`CanvasStore`, and compared **byte for byte** with what was
  written (R-10's automatable half);
- the same text run through a full styling + concealment cycle leaves the storage string
  identical (R-10 again, from the other side).

Then, in order:

1. `xcodebuild … -only-testing:PergamenumTests test` — the full unit suite, green.
2. `scripts/uitests.sh` with no arguments — the whole bundle, once, before the merge (CLAUDE.md;
   an argument *replaces* the selection, so never pass one to «add» a file). Compare failures
   against the three pre-existing intermittent ones tracked in `TODO.md` (`3476bee`) and do not
   silence anything.
3. **Manual pass (human, at the keyboard):** open a Debug build on the Labs vault
   (`ls -dt …/Pergamenum-*/Build/Products/Debug/Pergamenum.app | head -1` — `-t`, or you get a
   stale build), and check, in this order: a card at rest shows bullets and no `-` (R-02); a
   double-click into it reveals only the caret's line (R-03, R-04); heading and `**` markers
   conceal on a card (R-04); nesting looks deeper, not merely different (R-05); a To Do card
   still shows `- [ ]` and no bullet (R-06); Enter continues and exits a list (R-07); deleting a
   middle item renumbers (R-08); the fold submenu collapses a section and the badge unfolds it
   while editing (R-09); Cmd+Z takes back each of those in one press (R-12).
4. **Manual Obsidian round trip (human):** open the same vault in Obsidian and confirm the
   source of a note and of a `.text` node is character-identical to before — the half of R-10
   the SPEC itself marks `no-test` and which no assertion here can cover.
5. Update `CLAUDE.md`'s chain decision index and add an ADR-0028 section beside ADR-0027's;
   record in `TODO.md` the two follow-ups this chain names and declines: a real checkbox glyph
   (C4) and CommonMark's content-column nesting rule (ADR §Consequences); update
   `PROJECT_BRIEF.md`'s Status if a milestone moved.

---

## Risks, dependencies and HITL gates

**Risks, highest first.**

1. **The displayed-paragraph length rule.** Every rendering decision in Task 3 rests on
   `NSTextContentManager`'s constraint that a substituted paragraph keeps its length. The
   length assertion is the **first** test in Task 3 for that reason. If a substitution ever
   changes length the failure is not visual — it is offsets drifting between the storage and the
   layout, which presents as a caret in the wrong place and a crash later.
2. **The note editor is in the blast radius.** Five files under `Sources/Features/Editor/`
   change (ADR §D5). The protected `CompletingTextView+Pasteboard.swift` and every other
   `CompletingTextView*` file are out of bounds; `interface-check.sh` blocks if that is wrong.
   The other danger is subtler: `EditorDecorationDelegate` also serves embeds, transclusions and
   folding in Nota, so a mistake in the new branch presents as an *embed* regression. Task 3
   must leave `MarkupHidingTests`, `EmbedDrawingTests` and `TransclusionLayoutTests` green.
3. **A per-keystroke full-text renumber pass on both surfaces.** `renumbered` returns `nil` when
   there is nothing to do, which is the common case, but it scans the whole text to find that
   out. If typing feels heavy after Task 4, this is the first suspect; the fallback is to run it
   only when the edit changed the line count, which is a smaller change than it sounds.
4. **Three exhaustive fixtures on `CardCommand`.** Listed with line numbers above. The risk is
   not finding them, it is running only the touched module's tests and shipping a red suite.
5. **Fold on a card is the least-precedented piece.** Nota's fold is driven from a sidebar that
   does not exist here (C3), so Task 7 is the one task assembling something rather than
   extending it. If `FoldedHeadingFragment` or `NoteFolding` turn out to need edits, that is a
   design gate, not a patch.
6. **Visible change to every existing board and note.** Lists that have always looked like text
   will look like lists, and markers that have always been visible on cards will vanish. Expected
   and named in the ADR; it is the first thing to look at in the Task 8 hand-check, and
   `hidesMarkup` off is the complete rollback for the rendering half.

**Dependencies.** None external. No new package, no `Tuist/Package.swift` change, no
`tuist install`. Everything used is already in the repo or in the macOS 26 SDK.

**HITL gates.**

- **Gate 2 (now):** approve this ADR and plan. One proposal below needs an explicit answer (the
  audit profile); no protected-interface entry is proposed.
- **After Task 3:** if the substitution cannot keep the paragraph's length, the rendering model
  changes (ADR §A3 is the fallback) — stop and report, do not improvise.
- **After Task 7:** if `FoldedHeadingFragment`/`NoteFolding` need edits, stop and report.
- **Before every commit** (CLAUDE.md, global): human approval. Feature branch only, never
  `main`, Conventional Commits.
- **Before the merge to `main`:** `scripts/uitests.sh` green plus the manual Obsidian round trip
  (Task 8 steps 2 and 4). Both are human-gated.
- **No schema change, no migration, no deletion, no deploy** in this chain — none of those gates
  apply.

---

TEST-CMD CANDIDATE: xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -derivedDataPath "/Users/stefer/Developer/Pergamenum/.build/DerivedData" -only-testing:PergamenumTests test
TEST-CMD MODE: brownfield

CODER-MODEL CANDIDATE: opus
