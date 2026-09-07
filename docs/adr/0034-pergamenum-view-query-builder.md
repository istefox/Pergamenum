# ADR-0034: A view is composed through controls, and the controls write the fence the parser already reads

- Status: proposed
- Date: 2026-09-07. Written after reading every file it names, at the line, on the working tree at
  `0bec334` (`feat/pergamenum-view-query-builder`, ADR-0033 merged through PR #178). Every claim
  about the grammar below was read out of `Sources/Core/Query/`, not out of the SPEC.
- **Relocation note:** this file is written at `docs/architecture/ADR-0034-…` because that is the
  architect's enforced write scope; the orchestrator relocates it to
  `docs/adr/0034-pergamenum-view-query-builder.md`, which is where this repo's ADRs live
  (`0001`…`0033`) and which is the path every reference below assumes. Same convention ADR-0029's
  and ADR-0033's own headers record.
- **Does not supersede ADR-0009.** The query grammar (§D3), the closed field list (§D2), the
  seven-key shape (§D1), the no-materialisation rule (§D6) and the cost rule (§D7) are carried
  forward unchanged. This ADR adds no term, no key, no field and no renderer: it decides *how a
  person writes the seven keys without typing them*, and everything it writes is text
  `ViewBlock.parse` already accepted the day before.
- **Does not supersede ADR-0033.** Its attachment mechanism (§D1/§D2), its ordinal host key (§D3),
  its range-keyed reveal (§D4/§D5), its closed-fence precondition (§D6), its fixed height (§D8) and
  its `nil`-default input rule (§D9) are used as they stand. This chain adds a **third** optional
  input to `RenderedViewBlock` on §D9's own terms, and a **second** door out of a drawn fence beside
  §D10's caret-placing one.
- Depends on: **ADR-0009 §D1/§D2/§D3/§D4/§D7**, **ADR-0033 §D3/§D6/§D7-follow-up/§D9/§D10/§D13**,
  **ADR-0019 §D7** (`replaceAtomically`, the one write mechanism), **ADR-0029 §D7/§D8** (the
  hosted-view commit and its reload guard — `commitTable` is the shape §D3 below copies),
  **ADR-0012 §D4** (per-column editor state, which is where the sheet is presented from),
  **ADR-0014** (`ViewDateBound`'s three forms and their real spellings).

## Context

A `pergamenum-view` fence is seven keys of YAML-shaped text over a small boolean grammar, and the
only way to write one is to know it. ADR-0033 made a closed fence render live in the editor and, in
its own §D7 follow-up, made a closed fence that *fails* to parse render `RenderedViewBlock`'s error
card there — so the editor now tells a person their query is wrong, on the line, and still offers
them nothing but the raw text to fix it with. This chain is the other half of that follow-up.

**Nothing in the query layer is built here.** `ViewBlock`, `ViewFilter`, `ViewField`,
`ViewDateBound`, `ViewEvaluator` and `ViewQuerySource` are used exactly as merged. The whole feature
is a sheet that produces a string and one atomic write that puts that string where the fence was.

**Ten findings, read from the source before this ADR was written, that the SPEC could not know.**
All ten are load-bearing; the first five would each produce a fence that does not parse if the SPEC
were implemented literally.

1. **The relative date keywords are not the ones the SPEC prints.** The SPEC's Filtro section asks
   for a bound control supporting `oggi`, `oggi-N` and `inizio-settimana`. `ViewDateBound.parse`
   accepts `today`, `today-N`, `week-start` and an ISO day, and nothing else
   (`ViewDateBound.swift:38-54`); `todayKeyword`/`weekStartKeyword` are the literals it compares
   against. A control writing the Italian words writes a fence that fails on that line. §D12.
2. **There is no folder-tree picker component in this app.** `NoteListPane`/`NoteTreeRow` and
   `WorkspaceBrowser+Tree`/`+Rows` are *panes*: they draw a tree bound to `VaultController`'s
   selection, its drag payloads, its context menus and (for the Workspace) `WorkspaceSelection`.
   The app's actual folder **picker** is a flat `Menu` over `vault.folders`, at two sites —
   `NewNoteComposer.folderPicker` (`:110-123`) and `NoteRowMenu`'s "Sposta in" (`:34-48`). §D11.
3. **`TagBrowserView` is not a picker either.** It is an `HSplitView` with a toolbar, a rename
   sheet, a rename-undo banner and pinned tags (`TagBrowserView.swift:50-66`). What is reusable is
   the data it reads: `IndexSnapshot.tagUsage()` and `TagNamespace.allCases`. §D11.
4. **`CompletingTextView`'s wikilink completion cannot be reused in a sheet row.** It is an
   `NSPanel` (`CompletionPanel`) positioned from `rangeForUserCompletion` inside an `NSTextView`,
   applied through `insertText(_:replacementRange:)` (`CompletingTextView.swift:266-296`). There is
   no note-title picker view in this app; `RelatedLinkSheet.swift:27-40` is the shape — a
   `TextField` over `vault.index.search(query, limit: 20)` and a `List` with `.tag(note.title)`.
   §D11.
5. **`from` is not a second filter and cannot hold one.** `ViewBlock.scope` is `[String]`, and
   `ViewBlock.parse` runs `from`'s value through `ViewFilter.parse` and then `collectPaths`, which
   throws for anything that is not `path()` or `or` (`ViewBlock.swift:175-193`). An Ambito row can
   only ever produce `path("…")`, and the rows can only ever be joined by `or`.
6. **`ViewBlock.parse` refuses a duplicate key and an empty value**, by line
   (`ViewBlock.swift:129-136`). A writer that emits `sort:` with nothing after it, or `where:`
   twice, produces a block that fails on a line the person never typed.
7. **The comparison term is restricted inside the parser, not by convention.**
   `ViewFilter.Parser.comparison` throws unless the field is `.date` or `.modified`
   (`ViewFilter.swift:186-193`), and `has()` takes a `ViewField` by raw value. Both pickers must
   restrict their contents rather than validate afterwards.
8. **The error card and the live render already share one header.** `RenderedViewBlock.body` calls
   `header(renderer:count:)` in both the `.failure` and `.success` branches
   (`RenderedViewBlock.swift:51-61`), and `onEditSource`'s button is drawn inside it. R-01's "both
   states" costs one `Button`, in one place, and cannot diverge. §D1.
9. **The insert-view command is a sixth surface, not a replacement.** `EditorCommand.viewEntries`
   already puts five `Vista …` entries in the slash menu, each writing a raw skeleton with a caret
   placement (`EditorCommand.swift:106-168`), added by M11 to a catalogue that declares itself
   closed. They are untouched by this chain.
10. **The caret-insert channel is a tuple in three declarations.** `Navigation.pendingInsertion` +
    `pendingCursorOffset`, bundled by `consumeInsertion()` into `(text:cursorBack:)`, held by
    `EditorColumnView.pendingInsertion` (`:30`) and consumed by `NoteTextView.insertion` (`:79`) at
    `NoteTextView.swift:332-338`. Ten `navigation.insert(` call sites exist. §D4.

**Two constraints inherited rather than re-derived.** `replaceAtomically(_:with:in:)`
(`NoteTextView+EmbedCaret.swift:101-113`) is the only mechanism a write to the note's characters may
use in this editor — ADR-0019 §D7's rule, restated by ADR-0029 §D7 and by ADR-0033 §D11's *"and
saying so is what stops someone building one by analogy"*. And `EditorDecorationDelegate` is on no
actor and owns no view, which is why every value that crosses into it is finished
(`ViewBlockHostStore` is ADR-0033 §D3's instance of that crossing).

## Decision

**D1. One affordance, declared once, in the header both fence states already share.**

`RenderedViewBlock` gains a **third** optional input on ADR-0033 §D9's terms:
`onEditQuery: (() -> Void)? = nil`, drawn as one more control in `header(renderer:count:)` beside
`onEditSource`'s `text.cursor` button and the refresh button, with accessibility identifier
`rendered-view-edit-query` and label «Modifica query».

Finding 8 is the whole of the design: `header(...)` is called by the `.failure` branch and by the
`.success` branch of the same `switch`, so a button placed there is present on a live board and on
an error card without either state knowing about the other. R-01 is satisfied by construction, not
by two implementations kept in step.

`nil` means the control is not drawn, which is exactly today's rendering. `MarkdownBlocksView.swift`
passes nothing and is not edited, so the transclusion path, `NoteExporter` and `ViewsPane` gain
nothing — ADR-0033 §D9's "true by construction rather than by care", extended by one input without
changing its shape. This is also the whole of R-16: a Workspace `.text` card never produces a
`.viewBlock` kind (ADR-0033 §D13 / ADR-0029 §D17), so no card ever reaches a host, so no card ever
sees this button. The card's own switch is not edited.

**D2. The click carries the fence's current text and the closure that writes it back. That is
`TableGridView.onCommit`'s shape, not a new one-shot channel.**

`ViewQueryEditRequest` (`Sources/Features/Editor/`, `Identifiable`) holds:

- `id: UUID` — two clicks on the same fence are two presentations;
- `source: String` — the fence's **body** as it is at the moment of the click, the same string
  `RenderedViewBlock` is rendering;
- `commit: (String) -> Bool` — body text in, `true` when the note was rewritten.

It is built inside `refreshViewBlockHosts` (`NoteTextView+ViewBlocks.swift:178-196`), in the loop
that already rebuilds each host's root view every styling pass, capturing the fence's `opening`
offset and `[weak textView]`. That loop already exists for exactly this reason and its own comment
says why the closure is rebuilt per pass rather than captured once: `parent` is a struct SwiftUI
replaces on each update. `TableGridView.onCommit` is re-set the same way, in the same shape, for the
same staleness reason (`NoteTextView+Tables.swift:95-98`).

Rejected: **a `Navigation`-style pending request, consumed by `EditorColumnView` and answered
downward.** `Navigation`'s channels exist because a *menu bar* holds no reference to a text view and
would go stale the moment the editor is rebuilt (`Navigation.swift:141-146`). A hosted view is not
in that position: it is rebuilt with the text view, per pass, and can therefore hold the closure
directly. Routing the anchor up through SwiftUI state and back down would add a second staleness
window for no gain, and would make the "which column?" question — already answered by ADR-0012
§D4's per-column state — something this feature has to answer again.

The request is presented from `EditorColumnView` as `.sheet(item:)`, beside the state that already
lives there (`find`, `pendingJump`, `pendingInsertion`, `closing`). Two columns therefore get two
independent builders, which is ADR-0012 §D4's rule applied without a special case. The sheet is
handed `viewQuerySource` from `EditorColumn+Text.swift:208-222` — **the same source the drawn fence
is rendering through**, so the count in the sheet and the count in the header cannot disagree.

**D3. The anchor is read at open time and re-read at commit time, and a fence that has moved on
refuses the write instead of taking it.**

`commitViewBlock(_ body: String, at offset: Int, in textView: NSTextView) -> Bool` on
`NoteTextView.Coordinator`, modelled on `commitTable` (`NoteTextView+Tables.swift:169-192`) and
carrying its reload guard verbatim, in this construct's own currency:

- `EditorDecorationDelegate.viewBlockRun(in: parent.text as NSString, atParagraphStart: offset)` —
  the note as the **model** still spells it;
- `EditorDecorationDelegate.viewBlockRun(in: textView.string as NSString, atParagraphStart: offset)`
  — the note as the **buffer** spells it;
- both non-nil, their `.range`s equal, and the buffer's substring over that range equal to the whole
  fence text recorded when the sheet opened.

Any of those failing returns `false`, the buffer untouched, and the sheet reports that the write
could not be applied. This is the SPEC's "fence deleted or its source range changes out from under
the sheet" edge case, resolved by the mechanism ADR-0029 §D8 already built for a grid that holds a
shape a later pass may have invalidated: **nothing parsed is carried across**; the fence is re-read
from the live characters at commit time.

`viewBlockRun` is already the right function for this and says so in its own header —
*"the static 'is a closed, still-valid fence really here' check that both the drawing pass and a
later commit-style read can share without re-implementing the rule twice"*
(`EditorDecorationDelegate+ViewBlockRendering.swift:9-11`). This is that later commit-style read.
It is `static`, takes an `NSString` and touches no delegate state, so a `@MainActor` caller is
exactly what it was written to allow.

The write itself is `replaceAtomically(live.range, with: fence, in: textView)` and nothing else —
one `shouldChangeText`/`beginEditing`/`replaceCharacters`/`endEditing`/`didChangeText`, therefore one
`Cmd+Z` for the whole edit however many controls moved in the sheet (R-13). Two consequences of the
range `viewBlockRun` returns, both of which the writer must respect: it starts at the opening fence
paragraph and **ends at the closing fence line's last character, its newline excluded**, so the
replacement is `"```pergamenum-view\n" + body + "\n```"` with no trailing newline; and it therefore
rewrites the opening line too, normalising it to exactly that spelling. A hand-written
` ```pergamenum-view   ` with trailing spaces loses them on commit, which is a normalisation and is
named rather than discovered.

**D4. The insert command writes the stub through the channel that already exists, and the stub is
written *first* so that "Fatto" has exactly one implementation.**

R-04's "insert then open" is not only a flow. Because the stub lands before the sheet does, the
sheet is always editing a fence that exists, so the commit path is *rewrite the fence at the anchor*
and there is no second, create-shaped write anywhere in the feature.

`Navigation`'s tuple becomes a struct, `Navigation.Insertion { text, cursorBack, opensQueryBuilder }`
— the nested-type crossing `Navigation.OutlineJump` already makes into `Sources/Features/Editor`.
`insert(_:cursorBack:opensQueryBuilder:)` takes the new flag with a default, so all ten existing
call sites are untouched; `consumeInsertion()` returns the struct; `EditorColumnView.pendingInsertion`
and `NoteTextView.insertion` change type. `NoteTextView.updateNSView`'s existing insertion branch
(`:332-338`) gains one more step: when the flag is set, it computes the inserted fence's opening
offset and calls `parent.onEditQuery?` with a request built exactly as D2 builds one.

**The opening offset is arithmetic, not a scan.** `viewBlockRun` requires the opening backticks to
start a paragraph, so the stub text carries a leading `\n` when the caret is not already at a
paragraph start — `EditorCommand.separator`'s own `"\n---\n\n"` convention, an existing entry in the
same catalogue. The opening offset is then `insertionStart + (prefixed ? 1 : 0)`, where
`insertionStart` is the selection's location read before `insertText`. Pure, testable, and no new
placement rule: the SPEC's "caret inside another construct" edge case is answered by the same
newline the separator command already writes.

Rejected: **a new `ShortcutCommand` case.** `ShortcutCommand` lives in `Sources/Core/Shortcuts/`,
which is a `sharedSources` glob (`Project.swift:73`) compiled into `perg` and `pergamenum-mcp`.
R-17 forbids a new capability there, and a rebindable key for a command that opens a sheet on the
caret is not worth reopening it.

Rejected: **a sixth slash-menu entry.** `EditorCommand.Action` has two cases and its own header says
*"Two kinds and no third"*; a command that writes markdown **and then** opens a sheet is neither, and
Swift does not permit a default value on an enum case payload, so widening `.insert` would rewrite
all twelve existing entries. The command therefore lives in the Inserisci menu only, beside
"Tabella", which is where every other structural insertion in this app is reachable. The five raw
`Vista …` slash entries (finding 9) stay exactly as they are: they are the fast path for somebody
who knows the grammar, and this chain is for everybody else.

**D5. Whether a `where` can be shown as rows is one pure function, and the raw-text fallback is what
it answers `nil` for.**

```
enum ViewQueryFlattening {
    /// The terms of a filter that is a flat conjunction of leaf terms, in source order.
    /// `nil` when the filter uses `or`, `not` or a nesting no row model can express.
    static func terms(of filter: ViewFilter) -> [ViewFilter]?
}
```

The rule, exhaustively: `.all` → `[]`; any leaf term (`.path`, `.tag`, `.linksTo`, `.linkedFrom`,
`.task`, `.has`, `.text`, `.comparison`) → `[that term]`; `.and(lhs, rhs)` → `terms(lhs) + terms(rhs)`
when both are non-nil; `.or`, `.not` → `nil`. Parentheses need no case of their own: the parser
consumes them and returns the inner expression (`ViewFilter.swift:114-122`), so `(a and b) and c`
flattens and `(a or b) and c` does not, which is the correct answer to "can this be shown as rows".
`ViewFilter.Parser.conjunction` associates `and` to the left, so the concatenation comes back in the
order the person wrote it.

`nil` is R-07: the Filtro section becomes a pre-filled text field validated live through
`ViewFilter.parse` on every change, and **every other section still loads structured**. The
distinction lives in the seed, never in the writer — a raw-text `where` is written back verbatim,
and the six other keys are written from their controls exactly as they would be otherwise, which is
R-07's "without dropping or altering any other key".

**D6. R-03's field-by-field recovery is seven single-key parses through the real parser. There is no
second, lenient grammar.**

`ViewBlock.parse` is all-or-nothing by design, and its per-key parsers are `private static`. The
seeder therefore splits the body on the first `:` of each non-empty line — the same rule
`ViewBlock.parse` uses (`:115-137`) — and, for each of the seven keys, parses a **synthetic
two-line block** through the public `ViewBlock.parse`: `"render: table\n<key>: <value>"`, reading
the corresponding field off the result. `render` itself is recovered as `"render: <value>"`.

A key that throws leaves its control at its default and the person fixes it in the control; a key
that parses seeds its section. A `render: board` value is recovered without tripping the
board-needs-group rule because the synthetic block for every *other* key says `render: table`.

Rejected: **making `ViewBlock`'s per-key parsers internal and calling them directly.** It is one
line of visibility per function and it is a `Sources/Core` edit inside a `sharedSources` glob,
against R-17, to save an allocation per key on a code path that runs once per sheet.

Rejected: **a lenient recovery parser.** A second grammar over the same text is the pair that
drifts — the argument `CodeFence`'s own header makes about "this line is a fence", and ADR-0018 §D1
and ADR-0029 §D10 both made about a second rendering. Two answers to "what does this `where` mean"
is worse than a control left at its default.

**D7. The draft is validated by round-tripping through `ViewBlock.parse`, and one computation feeds
"Fatto", its inline reason and the live count.**

The draft serialises to a fence body (D9), that body is parsed, and the resulting
`Result<ViewBlock, ViewBlockError>` is the only validity anything in the sheet consults. "Fatto" is
enabled exactly when it is `.success`; the inline reason beside it is the `ViewBlockError`'s own
`description`, which is `"riga N: motivo"` in the app's language already; the live count evaluates
the `.success` value and shows nothing at all otherwise.

The consequence is R-12's real content: the sheet cannot disagree with the note, because "would this
assemble" is not re-implemented — it is `ViewBlock.assemble` itself, reached through the one entry
point it has. The board-without-group case (the SPEC's first edge case) needs no rule here at all:
`assemble` already throws *"una board è fatta di colonne: aggiungi «group»…"* on line
`ViewBlock.swift:165-170`, and that sentence is what the sheet shows.

**An incomplete term row is omitted from the body and disables "Fatto" with its own reason.** A row
whose argument is still empty would otherwise serialise to `tag("")`, which parses cleanly and
matches nothing — a draft that looks valid and is not. Omitting it keeps the live count honest while
the person is still composing (R-11's "0 note corrispondono is a legitimate transient state"), and
disabling "Fatto" is what stops a half-filled row from being silently dropped into the note.

**D8. The live count is `.task(id: body)` plus a sleep. SwiftUI's own cancellation is the debounce;
no timer, no Combine, no new machinery.**

```
.task(id: draftBody) {
    try? await Task.sleep(for: .milliseconds(250))
    guard !Task.isCancelled else { return }
    count = queries.map { $0.evaluate(block).total }
}
```

`.task(id:)` cancels the in-flight task when the id changes, which is a debounce written as the
thing it is. The id is the **assembled body**, not a counter and not a timestamp: a change that does
not change the text — re-picking the folder already picked, toggling a column off and on again —
does not re-evaluate. This is `RenderedViewBlock`'s own `.task(id:)` keying (`:73`) applied to the
draft rather than to the fence, and it keeps ADR-0009 §D7's "never per keystroke" true for the sheet
as well as for the drawn block.

Named cost: `ViewQuerySource.evaluate` is `@MainActor` and synchronous, and a `text()` term reads
every candidate file (ADR-0033's own Consequence). The sheet does exactly what a drawn fence does,
once per settled draft rather than once per keystroke.

**D9. The writer is one pure function per key, and `columns` is written only when the selection
differs from `effectiveColumns` — compared as an ordered list.**

`ViewQueryText.body(of draft:) -> String` emits the keys in the order `ViewBlock` declares them
(`from`, `where`, `sort`, `group`, `render`, `columns`, `limit`), one line each, **omitting any key
whose value is its default**: no `from` with zero rows, no `where` with zero terms, no `sort` with
zero rows, no `group` outside a board, no `limit` when blank, and no `columns` when

```
selection == ViewBlock(render: draft.render).effectiveColumns
```

That comparison is exact and ordered, and it is why the columns selection is an **ordered `[ViewField]`
and not a `Set`**: `columns: [modified, title]` is a table whose first column is the date, so a
selection re-serialised in `allCases` order would silently reorder a hand-written block on a commit
that never touched that section. Seeding preserves the declared order; ticking a box appends;
unticking removes. Two facts make this cheap: every `effectiveColumns` default is already in
`ViewField.allCases` order (`[.title, .tags, .modified]`, `[.title, .tags]`, `[.title]`), so a
checklist ticked top-to-bottom produces the default exactly and writes nothing; and the rule is one
`==` a test can hold against all five renderers.

Findings 5 and 6 are the writer's other two obligations: `from` is written as
`path("a") or path("b")` and never anything else, and no key is ever emitted twice or with an empty
value. Term rendering quotes the string-argument terms (`path`, `tag`, `linksTo`, `linkedFrom`,
`text`) and leaves `task(open)`/`has(tasks.open)` bare, which is how ADR-0009's own examples are
written and what the lexer's word set accepts either way.

**D10. The sheet lives in `Sources/Features/Views/`; the anchor, the commit and the wiring live in
`Sources/Features/Editor/`.**

The split already in the tree is the justification: `Features/Views/` holds everything that knows the
*view construct* and nothing that knows an `NSTextView` — `RenderedViewBlock`, the four renderers,
`ViewsPane`, `ViewQuerySource`, `ViewCatalogue`. `Features/Editor/` holds the bridge and everything
that touches the buffer. The builder takes a `String` and gives back a `String`; it imports no
AppKit, holds no offset, and can be previewed and tested without an editor. So it belongs on the
Views side, and the six files it needs are:

| File | Holds |
|---|---|
| `ViewQueryFlattening.swift` | D5's pure function |
| `ViewQuerySeed.swift` | D6's recovery, and the `ViewQueryDraft` model (`@Observable`) |
| `ViewQueryText.swift` | D9's writer: body, term rendering, the columns rule, the stub text |
| `ViewQueryBuilderSheet.swift` | the shell: sections in key order, footer, reason, count |
| `ViewQuerySections.swift` | Ambito / Ordina / Raggruppa / Rendering / Colonne / Limite |
| `ViewQueryTermRow.swift` | the Filtro row, its 8 kinds and their controls, and the pickers |

plus, on the editor side, `NoteTextView+ViewBlockEditing.swift` (the request, the anchor,
`commitViewBlock`) beside `NoteTextView+ViewBlocks.swift`. One principal type per file, and no view
type over the 150 lines `~/.claude/rules/swift.md` sets — the sections are `private struct`s in their
own file rather than computed properties on the sheet, which is what `NoteRowMenu`/`RenameNoteSheet`
and `NoteListPane+FolderVerbs` already do when a view grows.

Nothing new goes under `Sources/Core/**`, `Sources/Connector/**`, `Sources/CLI/**` or
`Sources/MCPServer/**`. `Sources/Features/**` is in no `sharedSources` glob, so R-17 is structural
here rather than a rule anyone has to keep.

**D11. The pickers, and what is actually reusable.**

Findings 2, 3 and 4 are the answer, one control at a time. Every one of them reads through a
`VaultController` accessor that already exists, so no protected file is touched and no new index
question is asked.

- **Folder (Ambito, and the `path` term).** A `Menu` over `vault.folders` — the flat, sorted,
  ancestor-inclusive list `VaultSession.folders` already builds for "Sposta in…"
  (`VaultSession+Files.swift:92-105`) — beside a text field, because a `path()` argument is a glob
  (`Glob.matchesPath`: a prefix without a wildcard, a glob with one) and `path("01 *")` is in
  ADR-0009's own examples. Extracted once as `FolderPickerMenu` and used by both sections, so the
  two cannot drift.
  **Not a new tree.** Building a third one would mean a third thing to keep in step with two panes,
  and it would meet ADR-0024's `DisclosureGroup`/`List(selection:)` trap for no gain: a picker in a
  sheet row needs no `List(selection:)` at all.
- **Tag (the `tag` term).** A `Menu` grouped by `TagNamespace.allCases` over
  `vault.index.tagUsage()`, with a text field for a glob, since `tag("status-*")` is the common case
  and a picker with no wildcard row would make the sheet less capable than the text it replaces.
- **Tag namespace (Raggruppa).** The same eight namespaces, writing `group: tag("<namespace>-*")`,
  or a `ViewField` — the two shapes `ViewBlock.Grouping` has and no third.
- **Note title (`linksTo`/`linkedFrom`).** A new, small searchable list: a `TextField` over
  `vault.index.search(query, limit: 20)` and a `List` of titles. `RelatedLinkSheet.swift:27-40` is
  the shape it copies. It is copied and **not** extracted: `RelatedLinkSheet` carries two reason
  fields and a bidirectional write around the same list, and refactoring it is a change to a working
  sheet this chain has no requirement for. The near-duplication is recorded here rather than left to
  be found.
- **Field (`has`, Ordina, Colonne, the comparison's field).** `ViewField.allCases` with
  `ViewField.label`, restricted to `[.date, .modified]` for the comparison (finding 7).
- **Task state.** A two-way `Picker` over `open`/`done`, which is the closed pair `ViewFilter`
  accepts.

**D12. The date-bound control writes the parser's spellings, never the SPEC's.**

Three forms, one segmented control: a calendar day (a `DatePicker` writing `CalendarDate`'s own
`description`), `today` with an optional whole-day offset writing `today` / `today-N`, and
`week-start`. The labels the person reads are Italian — «oggi», «oggi meno N giorni», «inizio
settimana» — and the text written into the note is `ViewDateBound.todayKeyword` and
`ViewDateBound.weekStartKeyword` (finding 1). The round trip is asserted against
`ViewDateBound.text`, which exists for exactly this reason: *"how the bound is written, so a block
rendered back out is the block that was read"*.

**D13. Raggruppa is shown only for `render: board`, and its being required is not a second rule.**

R-08 is a visibility rule and is implemented as one: the section is present when
`draft.render == .board` and absent otherwise, and a `group` chosen for a board and then abandoned
by switching to `render: table` is not written (D9 omits it). Its *requiredness* is not restated
anywhere — D7's round trip through `ViewBlock.parse` produces the board-needs-group error itself,
with the sentence `assemble` already wrote for it.

**D14. Nothing is persisted, and nothing outside the app target is touched.**

No index field, no `schemaVersion` bump, no frontmatter key, no `.canvas` property, no
`.pergamenum/` file, no `~/Library/Application Support` state, no migration. The draft lives in the
sheet's own state for the duration of one edit, and the only durable artefact is the fence text in
the note — ADR-0009's "no view is ever saved or cached", unchanged. `IndexCache.schemaVersion`,
`VaultAPI.LintFinding`, `CompletingTextView+Pasteboard.swift` and `ImportNaming.recordingNoteTitle`
are all outside this diff, and `interface-check.sh` must stay silent for the whole chain.

## Alternatives considered

**A1. A visual editor for the full `where` tree — `or`, `not`, parentheses, arbitrary nesting.**
It is the complete feature, and it would make the raw-text fallback unnecessary. **Rejected:** the
SPEC puts it out of scope on its own merits and this ADR is not entitled to re-decide it, but the
argument is worth recording because it is what makes D5's fallback acceptable rather than a gap. A
tree editor is recursive rows plus a regrouping gesture — the largest UI in this chain by a wide
margin — for a shape ADR-0009's own examples use once (`not tag("status-chiuso")`, a single `not`
that a term row could carry as a flag if the need is ever measured). The flat model plus a validated
raw field means a nested `where` is still fully editable and is never dropped, which is R-07's
actual requirement.

**A2. A second, lenient parser to recover a broken fence field by field (R-03).** It is the obvious
reading of "seeded from whatever of the raw text is recoverable", and it would give better recovery
on a line the real parser rejects outright. **Rejected:** two grammars over one text is the pair
that drifts, and this project has refused that trade three times already for smaller things —
`CodeFence`'s own header ("two spellings of *this line is a fence* is exactly the kind of pair that
drifts silently"), ADR-0018 §D1, ADR-0029 §D10. D6's synthetic single-key parse gets the same
recovery out of the parser that will judge the result, which means a key the sheet recovers is a key
the note will accept, by construction.

**A3. Present the builder as an `NSPanel` anchored to the fence, like `FormatBarPanel`.** It would
leave the note visible behind it and match a repo pattern used four times. **Rejected on ADR-0033
A3's own two grounds, which apply unchanged:** panel placement here would depend on
`firstRect(forCharacterRange:)`, which this repo has documented returning a zero rectangle for a
range TextKit 2 has not laid out — reliably true at the end of a long note, and a zero rect clamps
the panel to a screen corner instead of failing loudly. A builder with eight sections is also taller
than a format bar, so the misplacement would be more visible, not less. A sheet needs no geometry at
all.

**A4. Commit through `VaultController.updateOpenNoteText` — build the new note text in the sheet and
write the model.** No AppKit at the commit site, no weak text view, no anchor closure.
**Rejected:** it bypasses `shouldChangeText`/`didChangeText` entirely, which is where
`NSTextView`'s undo registration lives, so R-13's single `Cmd+Z` would have to be built by hand;
`FormattingTextView.swift:288` records what assigning `string` directly costs in this codebase. It
would also reintroduce the divergence D3's guard exists to catch — the model and the buffer are the
two things `commitTable` compares, and writing the model while the buffer holds something else is
the exact state that comparison refuses.

**A5. Hold the columns selection as a `Set<ViewField>` and serialise in `allCases` order.** Simpler
model, simpler checklist, and the default comparison becomes a set comparison that cannot be fooled
by order. **Rejected:** column order is what a table draws. A block written `columns: [modified,
title]` by hand would come back reordered from a commit that only changed `limit`, silently, and the
person would find their table's first column had moved. The ordered list costs one index lookup per
row and preserves what was written.

**A6. Make `ViewBlock`'s seven per-key parsers internal and call them from the seeder.** The most
direct implementation of D6, one keyword per function. **Rejected:** `Sources/Core/Query/` is inside
a `sharedSources` glob compiled into both connectors, and R-17 draws the line at the directory
rather than at the semantics precisely so that this kind of judgement call does not have to be made
per edit. The synthetic-block parse costs one string interpolation per key, once per sheet opening.

**A7. A new `ShortcutCommand` case plus a sixth slash-menu entry for the insert command.** It would
give the command a rebindable key and put it where four of the five existing `Vista …` entries
already are. **Rejected:** `ShortcutCommand` is in `Sources/Core` (R-17, D4), and
`EditorCommand.Action` has two kinds by declaration and cannot gain a defaulted payload in Swift, so
the slash entry would rewrite all twelve existing entries to add a flag two of them would use. The
Inserisci menu already holds "Tabella" and "Nota correlata…" — a structural insertion that opens a
sheet is exactly the neighbourhood.

**A8. Open the builder on an empty draft and write the whole fence only at "Fatto".** Nothing is
left behind when the person cancels, which is tidier than a stub abandoned in the note.
**Rejected:** R-04 asks for the stub explicitly, and the stub buys something structural (D4): with
it, every commit in the feature is a rewrite of an existing fence at a known anchor, so there is one
write path with one staleness guard. Without it there would be two — a rewrite and an insert — and
the insert path would need its own answer to "where did the caret go while the sheet was open",
which is the question the anchor exists to avoid.

**A9. Build a real folder tree for Ambito, matching the SPEC's own words.** It is what the SPEC
describes and it would look like the sidebars. **Rejected:** finding 2 — there is no such component
to reuse, so this is *writing* a third tree, not reusing one, and it would be the third place in the
app that has to answer ADR-0024's `List(selection:)`/`DisclosureGroup` question. `vault.folders` is
already flat, already sorted, already ancestor-inclusive, and is what both existing folder pickers in
this app show.

**A10. Re-evaluate the count on every draft change with no debounce, or off the main actor.** The
count would be live in the strictest sense. **Rejected:** ADR-0009 §D7 forbids per-keystroke
evaluation and this ADR cannot amend it; `ViewQuerySource.evaluate` is `@MainActor` by declaration
and a `text()` term reads files, so an undebounced count would put a vault-wide file read on the
main actor between two keystrokes in a text field. Moving it off the main actor would mean a second
evaluation path with its own `Sendable` story, for a number that is only ever read by a human.

## Consequences

**Positive**

- **The grammar gains a second author and no second definition.** Every string the sheet writes goes
  through `ViewBlock.parse` before "Fatto" is enabled (D7), so the builder cannot produce a fence the
  app would reject, and cannot reject one the app would accept.
- **R-01 costs one `Button`.** The error card and the live render already share a header (finding 8),
  so "present on both states" is a structural fact rather than a pair to keep in step.
- **One write path, one undo step, one staleness guard** (D3/D4). The stub-first rule removes the
  create/rewrite fork before it exists, and `replaceAtomically` is reached exactly once per commit.
- **R-16 and R-17 are true by construction.** A Workspace card never reaches a host, so it never sees
  the affordance; `Sources/Features/**` is in no `sharedSources` glob, so neither connector can
  compile a line of this feature. Both are greps a reviewer can run.
- **The transclusion, export and Viste-pane surfaces are not in the diff at all**, for ADR-0033
  §D9's reason applied to a third input: `nil` is today's rendering and they pass nothing.
- **The pure half is most of the risk and all of it is testable offscreen** — flattening, recovery,
  the writer, the columns rule, the stub arithmetic and the commit guard are functions over strings
  and values, in a repo whose editor tests already reach `viewBlockRun` and `replaceAtomically`.

**Negative**

- **The sheet is the largest single SwiftUI surface this feature area has**: eight sections, eight
  term kinds, five pickers. D10's file split is a mitigation, not a cancellation, and
  `ViewQueryTermRow` is the file most likely to want a second split during implementation.
- **A commit normalises the opening fence line** (D3). Trailing spaces or an unusual info-string
  spelling are lost. Harmless for anything this app writes, and named because it is the kind of
  difference a person notices in a diff and cannot explain.
- **The `where` raw-text fallback is a text field in a builder that exists to remove text fields.**
  It is honest about the shape it cannot draw, and it is where a person meets the grammar anyway.
- **Near-duplicate note-title search** (D11): `RelatedLinkSheet` keeps its own copy. Deliberate,
  recorded, and the cheapest correct answer until a third caller appears.
- **The insert command has no keyboard shortcut and no slash entry** (D4/A7). Reachable from the
  Inserisci menu only. If that proves to be the thing people cannot find, the answer is a later
  decision with the `ShortcutCommand` question reopened deliberately, not a case added quietly.
- **`Navigation.Insertion` changes the type of a channel five sites read** (finding 10). Small,
  greppable, and it replaces two parallel one-shot values with one that cannot desynchronise — but
  it is a contract change in a file every menu entry touches.
- **The count evaluates on the main actor** (D8). The same cost a drawn fence already pays, paid
  once per settled draft, still unmeasured on a real vault — ADR-0033's own open Consequence,
  neither worsened nor closed here.
- **A fence edited from two columns at once resolves by refusal, not by merge.** Two builders on the
  same note in a split editor are possible; the second commit finds the fence's text changed and
  refuses (D3). Correct, and it will read as the button not working.

**Neutral**

- **`IndexCache.schemaVersion` stays 3.** No index, frontmatter, canvas or state-file change of any
  kind (D14).
- **No protected interface is touched**, checked one by one: `IndexCache.schemaVersion` (no index
  change), `VaultAPI.LintFinding` (no connector change), `CompletingTextView+Pasteboard.swift` (the
  builder is a SwiftUI sheet; no paste or drop path is involved), `ImportNaming.recordingNoteTitle`
  (unrelated).
- **`Sources/Core` and `Sources/Connector` are untouched**, so `perg view run` and the MCP `view`
  tools answer exactly as before, and neither knows a builder exists.
- **Obsidian compatibility is unchanged** (principle 4): what is written is the same fence in the
  same format, which Obsidian keeps rendering as an inert code block.
- **Principle 2 is untouched.** Nothing here opens a socket; the two named exceptions (ADR-0031,
  ADR-0032) are neither extended nor referenced.
- **The five raw `Vista …` slash entries survive** (finding 9). Two ways to start a view now exist,
  which is the same relationship "Tabella" in the Inserisci menu has with `/tabella`.
- **`ViewBoardRenderer`'s write path, its journal, its undo and its vocabulary guard are not
  reached by this chain at all** — the builder composes a block and never moves a card.
- **The unit suite can cover the pure half, the commit guard and the writer, and nothing
  interactive.** The sheet's controls, the sheet presentation and the atomic write on screen are
  `scripts/uitests.sh` and the hand-check, as ADR-0033's own Consequences record for the same reason.

## References

- `docs/adr/0009-views-are-queries-over-the-index.md` §D1, §D2, §D3, §D4, §D5, §D7
- `docs/adr/0012-tabs-split-view-and-the-tag-browser.md` §D4 (per-column editor state)
- `docs/adr/0014-a-view-can-say-today.md` (the three bound forms and their spellings)
- `docs/adr/0018-the-editor-hides-the-syntax-it-can-draw.md` §D1
- `docs/adr/0019-embed-drag-resize.md` §D7 (`replaceAtomically`, the one write mechanism)
- `docs/adr/0024-workspace-board-tree-single-selection.md` §D1 (the `DisclosureGroup` trap, and why
  no third tree is built)
- `docs/adr/0029-editor-wysiwyg-unification.md` §D7, §D8 (the hosted-view commit and its reload
  guard), §D17
- `docs/adr/0033-views-render-live-in-the-editor.md` §D3, §D6, §D7 + follow-up, §D9, §D10, §D13
- `SPEC.md` (pergamenum-view-query-builder) R-01 … R-17
- Source read for this ADR, at the line: `ViewBlock.swift`, `ViewFilter.swift`, `ViewField.swift`,
  `ViewDateBound.swift`, `ViewEvaluator.swift`, `Glob.swift`, `RenderedViewBlock.swift`,
  `ViewQuerySource.swift`, `ViewBlockAttachment.swift`, `ViewBlockHostStore.swift`,
  `NoteTextView+ViewBlocks.swift`, `EditorDecorationDelegate+ViewBlockRendering.swift`,
  `NoteTextView.swift`, `NoteTextView+Tables.swift`, `NoteTextView+EmbedCaret.swift`,
  `TableGridView+CellCommit.swift`, `EditorColumnView.swift`, `EditorColumn+Text.swift`,
  `EditorCommand.swift`, `CompletingTextView.swift`, `Navigation.swift`, `MenuCommands.swift`,
  `CommandActions.swift`, `NewNoteComposer.swift`, `NoteRowMenu.swift`, `RelatedLinkSheet.swift`,
  `TagBrowserView.swift`, `VaultSession+Files.swift`, `IndexSnapshot+Search.swift`,
  `Vocabulary.swift`, `Project.swift`, `.claude/protected-interfaces`, `.claude/test-cmd`
