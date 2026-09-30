# PG-147 — Core and app shell: one markdown grammar for the exporter, and a verdict on every open sub-item

- Issue: `TODO.md` `PG-147` (P2, chain "core and app shell"), GitHub #247. The brief is the ledger
  entry and its three indented lines. There is no SPEC: the repo-root `SPEC.md` belongs to the
  Contenitore chain and is not this chain's input. There are no R-ids. Each task cites the PG-147
  sub-item it closes, by the entry's own name.
- ADR: **`docs/adr/0077-html-exporter-renders-from-the-shared-parsers.md`** (new, proposed). It
  governs Tasks 1 to 3. Read §D2 (escape once, at emission) and §D4 (the closed element set) before
  Task 3: they carry the PG-124 security properties, and a green suite alone does not prove them.
- Governing prior ADRs, registered and not reopened:
  - ADR-0001 §D1 with ADR-0007: `Sources/Core` is Foundation-only and compiles into `perg` and
    `pergamenum-mcp`;
  - ADR-0018 §D1 and ADR-0029 §D10: one grammar, read by every surface;
  - ADR-0045: a `Type+Aspect.swift` split, and `private` widened only with a comment that names the
    reader;
  - ADR-0065 §D9.2 and §D13.1.
- Read at `096d36a5`, which is both `origin/main` and this branch's HEAD (clean tree, 2026-09-30).
  Lint findings come from `swiftlint 0.65.1` and the repo's `.swiftlint.yml`. The old/new exporter
  outputs quoted below were measured with a throwaway harness that compiled `MarkdownHTML` beside the
  two parsers, outside the repository. None of these numbers is recalled from the ledger entry
  (2026-09-12) or its progress note (2026-09-20).
- Branch: `refactor/pg-147-core-app-shell-structure` (already cut from `origin/main`).

## Verdict on every open sub-item

The progress note of 2026-09-20 closed `structure-Theme.swift-d64`, `structure-HTMLTextReducer.swift-abe`
and `-6ef`, `structure-VaultBrowser.swift-8ae`, the selection half of `structure-NoteListPane.swift-b4a`,
and the value types of `structure-CalendarService.swift-d72`. They are not reopened. What was still
open, measured today:

| Sub-item | Measured on `096d36a5` | Verdict |
|---|---|---|
| `structure-NoteExport.swift-c0f` | `MarkdownHTML` (`NoteExport.swift:82-303`) is a second grammar. Against the shared parsers, on 45 inputs, it is wrong on 24, right on 4 where the parser is wrong, and mixed on 1 (ADR-0077 §Context). SwiftLint: `cyclomatic_complexity` 11 and `function_body_length` 68 on `render` (`:136`), one 121-column line (`:150`). PG-124, which the entry wanted it inside, closed on 2026-09-24 (PR #486) without it. | **Do**, Tasks 1 to 3, under ADR-0077. |
| NoteListPane's move machinery (`structure-NoteListPane.swift-b4a`, move half) | `NoteListPane.swift` is 573 lines (`file_length` warning, limit 400) and its type body 328 (`type_body_length` warning at 250; the error is at 350). The move block (`:452-543`) is 92 lines, 41 of them code; the move itself already lives in `vault.moveItems`, and `NoteMoveContext` is already a value type. Moving the block to `NoteListPane+Move.swift` would widen five members: `@State dragging` (`:60`), `@Environment undoManager` (`:21`), `moveContext` (read at `:335`), `beginDrag` (`:373`) and `dropOnRoot` (`:342`, `:388`). The ledger counted seven; `selectedRows` and `moveRefused` have since been widened for other extensions. It would **still** leave the file at about 481 lines and the type body at about 287. No duplication. | **Close.** The split widens a `@State` and an `@Environment` and clears neither warning. The type is 22 lines under the error; the feature that crosses it should split with its own reason. |
| `structure-PergamenumURL.swift-ab3` | `PergamenumRoute.init?(_:)` (`PergamenumURL.swift:33-84`) is a 50-line switch, one short case per SPEC §9 route. `cyclomatic_complexity` is 17, a warning; SwiftLint's default error is 20. There is nothing duplicated between cases. `Tests/URLSchemeTests.swift`, `NoteIDRouteTests.swift` and `PendingRouteTests.swift` cover it. `PG-122`, which the entry paired it with, is closed. | **Close.** A parser per host moves each case into a function the same switch calls: the branches stay, and the one table SPEC §9 describes stops reading as one table. |
| `structure-RootView.swift-c0b` | The ledger calls it "line-count only". It is not. Nine pane properties (`RootView.swift:273-353`) repeat one shape: `if vault.root == nil { needsVault(…) } else { X() }`. `notesPane` (`:371-389`) carries a hand copy of `needsVault` (`:355-369`), and the copy has already drifted: only it has the «Apri cartella note…» shortcut and its own sentence. The type body is 268 (a warning, limit 250). All of it is in one file, so collapsing it widens nothing. | **Do**, Task 4. The fix is a same-file dedup, not the extension split the entry rejected. It clears the warning because it removes duplication. |
| `structure-EditorSettings.swift-11d` | `EditorSettings.swift` is 214 lines with **no SwiftLint finding**. The "typography math" is `applyProse` (`:199-213`), which does one multiplication and a rounding, with fixed weights and line heights (ADR-0030 §D9), and `selectedFamily` (`:180-190`), which reads `NSFontManager` and the theme. `ThemeCustomizationTests` already pins the persistence path (ten font-override tests, `:228-441`); no test names `EditorSettings`. | **Close.** There is no structure debt to pay. Extracting a type to test one multiplication is test work, not structure work. It is worth doing only if the picker's «Sistema» fallback regresses, and then as that regression's fix. |
| Follow-up named by the progress note: `ConformanceText` vs the connector's `"\($0)"` (`Sources/Connector/VaultPayloads.swift:142-152`) | The two renderings serve two audiences. `ConformanceText` writes Italian sentences for the app. `VaultAPI.LintFinding` writes each violation's Swift reflection string (`duplicateKey("tags")`) for external callers of `perg lint --json` and the MCP `lint` tool. `LintFinding` is in `.claude/protected-interfaces`, and `Tests/FrontmatterDamageLintTests.swift:97-114` already treats one of those strings as part of the shape. | **Close, do not unify.** Unifying would put Italian prose into a protected JSON shape and break the scripts and models that match on the identifiers, and no reader gains anything. The real hazard is different: a rename of any violation case or label silently changes that protected JSON, and only one string is pinned. Task 5 pins the rest. |

## ADR outcome: new ADR

**`docs/adr/0077-html-exporter-renders-from-the-shared-parsers.md`**, proposed. The refactor itself
would not pass the significance gate: it is easy to revert and is the obvious approach. It is
written under the override:

- the escaping mechanism behind a PG-124 security property moves, from "escape, then substitute" to
  "parse, then escape once at emission", and PG-124 itself landed without an ADR;
- two constraints are invisible in the code. The PDF path reads the HTML, so the renderer emits no
  element that names a resource. Embeds export as text, and that is an explicit "no" to `<img>`.

It also records that a defect the exporter inherits from the parser is fixed in the parser (§D5).

Tasks 4 and 5 need no ADR:

- Task 4 is a same-file dedup of a view that follows ADR-0045's conventions: no member widens and
  nothing crosses a boundary;
- Task 5 adds a test to an already-protected interface and changes no contract.

The five closed verdicts are recorded in `TODO.md` (Task 6), not in an ADR. None of them is a
decision a future reader needs to find there; each is a "not worth it" with a measured reason.

## Standing rules for every task

1. **The tester owns the signature and the coder owns the body.** No task declares a new API that
   a test calls. `MarkdownHTML.render(_:)` and `MarkdownHTML.inline(_:)` keep their signatures, so
   every red test compiles against the code as it is.
2. **`tuist generate --no-open` after a file is added** (Tasks 1, 3 and 5), before building.
   `Project.swift` is not edited. `sharedSources` globs `Sources/Core/**` (`Project.swift:88`), so
   `Sources/Core/Markdown/MarkdownHTML.swift` reaches `perg` and `pergamenum-mcp` with no edit, and it
   must import `Foundation` only.
3. **Lint before and after** each touched file with `swiftlint lint --quiet <files>`, and record the
   table in the commit body. No new `file_length` or `type_body_length` finding. No
   `swiftlint:disable`. No change to `.swiftlint.yml`.
4. **Counts never drop.** Run `rg -c '@Test' Tests | awk -F: '{s+=$2} END {print s}'` and the same
   count for `#expect\(|#require\(`. The baseline on `096d36a5` is **4455** and **11574** grep
   occurrences.
5. **No existing assertion is edited.** `Tests/NoteExportTests.swift` and
   `Tests/ViewBlockOutOfScopeTests.swift` stay unmodified in every assertion. ADR-0077 claims both
   stay green byte for byte, and they are the evidence for that claim. If one goes red, stop and
   report: it means an ADR claim is wrong, not that the test needs updating. The one permitted
   edit is the doc comment at `ViewBlockOutOfScopeTests.swift:141-144` (Task 3).
6. **Tests to run:**
   - the full `PergamenumTests` after every task (TEST-CMD below), not only the suites named;
   - the `perg` and `pergamenum-mcp` builds after Tasks 2 and 3, which touch `Sources/Core`;
   - `scripts/uitests.sh` is not run per task.
7. **One commit per task**, Conventional Commits. Each commit is a HITL gate (CLAUDE.md), with the
   diff shown.

## Before Task 1: the baseline (orchestrator)

1. `git fetch origin`. If `origin/main` has moved past `096d36a5`, merge it into the branch; never
   rebase, never force. The pre-push merge-integrity hook (ADR-0061/0062) checks the merge.
2. `tuist install` once for the worktree, then `tuist generate --no-open`.
3. Record: TEST-CMD green; the two counts; the lint table for `NoteExport.swift`,
   `MarkdownInline.swift`, `MarkdownBlocks.swift`, `TaskParser.swift` and `RootView.swift`.
4. Confirm `docs/adr/0077*` is still free on `origin/main` and on every remote branch. ADR-0075
   (PR #722) and ADR-0076 (PR #724, `0076-pratiche-message-anchored-entries.md`) are on `main`, and
   this chain's ADR already moved from 0076 to 0077 before its first commit (register row in
   `docs/adr/README.md`); if another branch takes 0077 first, rename this chain's still-uncommitted
   ADR to the next free number and update every reference in this plan.

---

### Task 1 — Pin today's export for a fixed corpus (tester) (`structure-NoteExport.swift-c0f`)

**File:** `Tests/NoteExportGoldenTests.swift` (new).

- One `Sendable` case type (name, markdown, expected HTML) and one parameterised
  `@Test(arguments:)` asserting `MarkdownHTML.render(case.markdown) == case.expected`.
- Two whole-page cases through `NoteExport.html(from:title:)`:
  - **W01** is the `note` fixture of `Tests/NoteExportTests.swift:5-25` (frontmatter plus a
    `## Note correlate` section);
  - **W02** is a kitchen-sink note with one of each block kind: heading, paragraph, bullet, numbered,
    task, quote, fence, `pergamenum-view` fence, rule, table, embed line, transclusion line.
- The corpus is **E01 to E45** from the decision table in Task 3 (inputs verbatim), plus an escape
  corpus. X01 to X08 put `&`, `<`, `>`, `"` and `'` in the places a note can hold text:
  - X01 heading, X02 code span, X03 link label and URL;
  - X04 wikilink, X05 embed name, X06 table cell;
  - X07 fence body, X08 task text.
- **Every expected string is captured by running today's `MarkdownHTML`, never written by hand.**
  A temporary test that prints each output's `debugDescription` is fine; delete it before the
  commit. Paste the values as raw string literals.
- **Done when:** green against `096d36a5`'s code, and the counts are up.
- **Commit:** `test(export): pin today's HTML export for a fixed corpus`.

This commit is the record of the old output. Task 3's diff of this file becomes the old/new
comparison that gate G2 reviews.

### Task 2 — Three parser corrections the exporter would otherwise inherit (tester, then coder) (`structure-NoteExport.swift-c0f`, ADR-0077 §D5)

**Tester (red), file `Tests/MarkdownParserCorrectionTests.swift` (new):**

- **P1, intraword underscore:**
  - `MarkdownInlineParser.spans(in: "file_name_here")` is one plain span;
  - `"__forte__"` is strong and `"_lieve_"` is emphasis;
  - `"x _y_ z"` has `y` emphasised;
  - `"a*b*c"` still emphasises `b`. `*` is untouched: CommonMark allows it intraword.
- **P2, link labels:**
  - `spans(in: "[**forte**](https://x.it)")` is one span, text `forte`, styles `[.strong]`, link
    `.url("https://x.it")`;
  - `"[a **b**](https://x.it)"` is two spans, both carrying the link;
  - `"![alt](https://x.it/a.png)"` keeps its one link span, text `alt`.
- **P3, task markers:**
  - `MarkdownBlockParser.blocks(in: "- [1] Rossi, 2020")` is `[.bulletList(["[1] Rossi, 2020"])]`,
    and `"- [a] voce"` is likewise a bullet;
  - `"- [ ] a\n- [x] b\n- [X] c\n- [-] d\n- [>] e"` is one `.tasks` block of five;
  - `"- [ ]attaccato"` stays a task, as `TaskParser` counts it.
- **Knock-ons, in the existing files:**
  - `Tests/NoteOutlineTests.swift`: `NoteOutline.entries(in: "## file_name_here")` gives the title
    `file_name_here`;
  - `Tests/TransclusionTests.swift`: `Transclusion.excerpt(of: "## a_b_c\n\ntesto", section: "a_b_c")`
    is not nil.

**Coder:**

- `Sources/Core/Markdown/MarkdownInline.swift`:
  - `spans(in:)` (`:39-62`) hands `match(at:)` the character before `index`;
  - for `_` and `__` only, `opensEmphasis` (`:148-151`) refuses a marker whose previous character
    is a letter or digit;
  - `closingRange` (`:158-176`) skips a closing `_`/`__` run whose next character is a letter or
    digit;
  - `link(at:)` (`:106-115`) returns `spans(in: parsed.label)` with `.link` set on each span.
- `Sources/Core/Markdown/MarkdownBlocks.swift`: `taskLine(in:)` (`:272-279`) returns nil unless
  `TaskParser.state(for: marker)` is non-nil.
- `Sources/Core/Tasks/TaskParser.swift`: `state(for:)` (`:100`) goes from `private` to internal. Add
  the ADR-0045 comment: "Not `private`: `MarkdownBlockParser.taskLine(in:)` (`MarkdownBlocks.swift`)
  asks it which markers make a task line, so the reading view and the task index share one
  vocabulary (ADR-0077 §D5)."
- `Sources/Features/Editor/MarkdownStyler.swift` is **not** touched (ADR-0077 §D5).

**Done when:**

- the new tests are green and everything else stays green. Task 1's goldens do too: the old
  exporter never calls the parsers;
- `perg` and `pergamenum-mcp` build.

**Commit:** `fix(markdown): parse intraword underscores, styled link labels and task markers as the
dialect says`. This is a `fix`, because it changes what the reading surfaces show (ADR-0077 §D5).

### Task 3 — The exporter renders from the parsers (tester, then coder) (closes `structure-NoteExport.swift-c0f`)

**Tester (red), file `Tests/NoteExportGoldenTests.swift`:**

- Each case gains a class and a one-line reason from the table below. Only the expectations of
  class **A** change. B, C and unchanged cases keep their Task 1 string byte for byte.
- W01, W02 and X01 to X08 get their new expectation from ADR-0077 §D2, §D4 and §D6, and are tagged
  the same way.
- Add three tests:
  - **escape once**: over every output of the corpus, `&amp;amp;`, `&amp;lt;`, `&amp;quot;` and
    `&amp;apos;` never appear, and no `<` is left that does not open an allowed tag;
  - **closed element set**: over every body in the corpus, each tag is one of ADR-0077 §D4's
    elements, each attribute is `href` on `a` or `style="text-align: center|right"` on `th`/`td`,
    and `<img`, `src=`, `<script`, `<link` and `<iframe` never appear, nor does an event-handler
    attribute (a space, `on`, letters, `=`);
  - **the four task glyphs**, with the characters gate G0 fixes.

**Coder:**

- **New file `Sources/Core/Markdown/MarkdownHTML.swift`**, Foundation-only: `enum MarkdownHTML` with
  the same two signatures. `render` maps `MarkdownBlockParser.blocks(in:)` through one emitter per
  case, joined by `"\n"`. `inline` maps `MarkdownInlineParser.spans(in:)`:
  - span text is escaped;
  - styles wrap inside to outside as `code`, `del`, `em`, `strong`;
  - consecutive spans with the same `.url` share one `<a>`, written only when
    `LinkPolicy.isOpenable(target)` accepts the raw target (§D3);
  - `.note(title:)`: the parser puts the alias in the span's text, the title itself when there is
    no alias, and `""` for `[[Nota|]]`. So the text is shown as is when it is non-empty and differs
    from `title`; otherwise the title up to its first `#` is shown (§D3). E24, E30 and E31 pin the
    three cases;
  - `.embed` shows its target as text.
- **Block emitters**, keeping today's serialisation:
  - lists as `<ul>\n<li>…</li>\n…\n</ul>`;
  - tables as `<table>\n<thead><tr>…</tr></thead>\n<tbody>…</tbody>\n</table>`;
  - a quote as `<blockquote><p>…</p></blockquote>`;
  - a paragraph's and a quote's lines trimmed and joined by one space before `inline`;
  - a fence as `<pre><code>` plus the escaped lines joined by `"\n"`, with no class;
  - `.rule` as `<hr>`;
  - `.embed` as `<p>` plus the escaped alt, or the escaped target when there is no alt;
  - `.transclusion` as `<p>` plus the escaped reference.
- `Sources/Core/Conventions/NoteExport.swift`:
  - delete `:81-303`, the old `MarkdownHTML`;
  - rewrite the doc comment of `html(from:title:)` (`:28-34`) to "the dialect the reading surfaces
    read, through the same parsers (ADR-0077)";
  - rewrite the doc comment of `escape` (`:63-70`) to the §D2 rule, keeping `&apos;` and giving the
    new reason.
- `Sources/Core/Email/LinkPolicy.swift:34-39`: the string overload's comment now says it reads the
  raw target, before escaping. Keep the argument that escaping cannot change a scheme's
  openability.
- `Sources/Features/Editor/MarkdownReadingView.swift:15-18`: "a separate generator" becomes "a
  separate generator over the same two parsers (ADR-0077)".
- `Tests/ViewBlockOutOfScopeTests.swift:141-144`, comment only: "renders every fence as plain code,
  whatever its language". Its assertion and expected string are not touched.
- Run `tuist generate --no-open`.

**Done when:**

- the whole suite is green, `NoteExportTests` and the R-11 test included and unmodified;
- `perg` and `pergamenum-mcp` build;
- `swiftlint` shows none of `NoteExport.swift`'s three findings, and nothing new on
  `MarkdownHTML.swift`;
- `rg -n "replacePairs|replaceMarkdownLinks|listItem\(|struct Blocks" Sources` is empty.

**Commit:** `refactor(export): render HTML from the shared markdown parsers (ADR-0077)`.
**Then gate G2** (below).

#### The decision table (the measured old outputs, and the new ones ADR-0077 prescribes)

Inputs are Swift string contents: `\n` is a newline. A `\|` in this table is a literal `|`. The glyph
column of E08 is pending gate G0.

| Id | Input | Old (measured) | New | Class |
|---|---|---|---|---|
| E01 | `#project-av45 in corso\n\nTesto.` | `<h1>project-av45 in corso</h1>\n<p>Testo.</p>` | `<p>#project-av45 in corso</p>\n<p>Testo.</p>` | A |
| E02 | `#Titolo` | `<h1>Titolo</h1>` | `<p>#Titolo</p>` | A |
| E03 | `####### troppo` | `<h6># troppo</h6>` | `<p>####### troppo</p>` | A |
| E04 | `\| solo \| riga \|\n\nTesto.` | `<table>\n<thead><tr><th>solo</th><th>riga</th></tr></thead>\n<tbody></tbody>\n</table>\n<p>Testo.</p>` | `<p>\| solo \| riga \|</p>\n<p>Testo.</p>` | A |
| E05 | `\| a \| b \| c \|\n\|:--\|:-:\|--:\|\n\| 1 \| 2 \|\n\| x \| y \| z \| w \|` | `…<tbody><tr><td>1</td><td>2</td></tr><tr><td>x</td><td>y</td><td>z</td><td>w</td></tr></tbody>…`, no alignment | rows padded/truncated to 3; `b` cells `style="text-align: center"`, `c` cells `style="text-align: right"`, `a` cells none | A |
| E06 | `>citato\n> ancora` | `<p>&gt;citato</p>\n<blockquote><p>ancora</p></blockquote>` | `<blockquote><p>citato ancora</p></blockquote>` | A |
| E07 | `1) primo\n2) secondo` | `<p>1) primo 2) secondo</p>` | `<ol>\n<li>primo</li>\n<li>secondo</li>\n</ol>` | A |
| E08 | `- [ ] da fare\n- [x] fatto\n- [-] annullato\n- [>] rinviato\n- normale` | one `<ul>`; `<li>[-] annullato</li>`, `<li>[&gt;] rinviato</li>` | `<ul>\n<li>☐ da fare</li>\n<li>☑ fatto</li>\n<li>⊟ annullato</li>\n<li>▷ rinviato</li>\n</ul>\n<ul>\n<li>normale</li>\n</ul>` | A |
| E09 | `- [ ]attaccato` | `<ul>\n<li>[ ]attaccato</li>\n</ul>` | `<ul>\n<li>☐ attaccato</li>\n</ul>` | A |
| E10 | `sopra\n\n---\n\nsotto` | `<p>sopra</p>\n<p>---</p>\n<p>sotto</p>` | `<p>sopra</p>\n<hr>\n<p>sotto</p>` | A |
| E11 | `* * *` | `<ul>\n<li><em> </em></li>\n</ul>` | `<hr>` | A |
| E12 | `![[foto.png]]` | `<p>!foto.png</p>` | `<p>foto.png</p>` | A |
| E13 | `![[foto.png\|300]]` | `<p>!300</p>` | `<p>foto.png</p>` | A |
| E14 | `![didascalia](foto.png)` | `<p>!didascalia</p>` | `<p>didascalia</p>` | A |
| E15 | `![[Altra nota#Sezione]]` | `<p>!Altra nota</p>` | `<p>Altra nota</p>` | A |
| E16 | `Vedi ![[foto.png\|300]] qui.` | `<p>Vedi !300 qui.</p>` | `<p>Vedi foto.png qui.</p>` | A |
| E17 | `![[https://x.it/a.png]]` | `<p>!https://x.it/a.png</p>` | `<p>https://x.it/a.png</p>` | A |
| E18 | `![alt](https://x.it/a.png)` | `<p>!<a href="https://x.it/a.png">alt</a></p>` | `<p><a href="https://x.it/a.png">alt</a></p>` | A |
| E19 | ```` ``` ```` (alone) | empty string | `<pre><code></code></pre>` | A |
| E20 | ``Usa `[[x]]` e `a*b*c`.`` | `<p>Usa <code>x</code> e <code>a<em>b</em>c</code>.</p>` | `<p>Usa <code>[[x]]</code> e <code>a*b*c</code>.</p>` | A |
| E21 | `2 * 3 * 4` | `<p>2 <em> 3 </em> 4</p>` | `<p>2 * 3 * 4</p>` | A |
| E22 | `~~via~~` | `<p>~~via~~</p>` | `<p><del>via</del></p>` | A |
| E23 | `**forte con *corsivo***` | `<p><strong>forte con <em>corsivo</strong></em></p>` | `<p><strong>forte con </strong><strong><em>corsivo</em></strong></p>` | A |
| E24 | `[[Nota\|a#b]]` | `<p>a</p>` | `<p>a#b</p>` | A |
| E25 | `file_name_here e __forte__ e _lieve_` | `<p>file_name_here e __forte__ e _lieve_</p>` | `<p>file_name_here e <strong>forte</strong> e <em>lieve</em></p>` | A (needs Task 2's P1) |
| E26 | `[**forte**](https://x.it)` | `<p><a href="https://x.it"><strong>forte</strong></a></p>` | same | B (P2) |
| E27 | `[a **b**](https://x.it)` | `<p><a href="https://x.it">a <strong>b</strong></a></p>` | same | B (P2) |
| E28 | `- [1] Rossi, 2020` | `<ul>\n<li>[1] Rossi, 2020</li>\n</ul>` | same | B (P3) |
| E29 | `- [a] voce` | `<ul>\n<li>[a] voce</li>\n</ul>` | same | B (P3) |
| E30 | `[[Nota#Sezione]] e [[Nota#Sezione\|come qui]]` | `<p>Nota e come qui</p>` | same | C (§D3) |
| E31 | `[[Nota\|]]` | `<p>Nota</p>` | same | C (§D3) |
| E32 | `riga uno\n  riga due\nriga tre` | `<p>riga uno riga due riga tre</p>` | same | C (§D6) |
| E33 | `[t](javascript:alert(1))` | `<p>t)</p>` | same | unchanged |
| E34 | `[x](https://x"><img src=y)` | `<p><a href="https://x&quot;&gt;&lt;img src=y">x</a></p>` | same | unchanged |
| E35 | `[[Nota d'Arco]] l'articolo` | `<p>Nota d&apos;Arco l&apos;articolo</p>` | same | unchanged |
| E36 | `~~~\ncodice\n~~~` | `<p>~~~ codice ~~~</p>` | same | unchanged |
| E37 | `- uno\ncontinua` | `<ul>\n<li>uno</li>\n</ul>\n<p>continua</p>` | same | unchanged |
| E38 | `Frequenza < 5 Hz & carico > 400 daN` | `<p>Frequenza &lt; 5 Hz &amp; carico &gt; 400 daN</p>` | same | unchanged |
| E39 | `## Titolo con **forte** e [[Nota]]` | `<h2>Titolo con <strong>forte</strong> e Nota</h2>` | same | unchanged |
| E40 | `https://vibrofer.it e <https://x.it>` | `<p>https://vibrofer.it e &lt;https://x.it&gt;</p>` | same | unchanged |
| E41 | `<script>alert(1)</script>` | `<p>&lt;script&gt;alert(1)&lt;/script&gt;</p>` | same | unchanged |
| E42 | `* **grassetto** voce` | `<ul>\n<li><strong>grassetto</strong> voce</li>\n</ul>` | same | unchanged |
| E43 | `# T\r\n\r\npara\r\n` | `<h1>T</h1>\n<p>para</p>` | same | unchanged |
| E44 | `- [ ] rientrato`, indented two spaces | `<ul>\n<li>☐ rientrato</li>\n</ul>` | same | unchanged |
| E45 | `1. [x] numerato` | `<ol>\n<li>[x] numerato</li>\n</ol>` | same | unchanged |

E05's full new string:

```html
<table>
<thead><tr><th>a</th><th style="text-align: center">b</th><th style="text-align: right">c</th></tr></thead>
<tbody><tr><td>1</td><td style="text-align: center">2</td><td style="text-align: right"></td></tr><tr><td>x</td><td style="text-align: center">y</td><td style="text-align: right">z</td></tr></tbody>
</table>
```

The "Old" column is what the harness measured. Task 1 re-captures it from the real target, and on
any disagreement the capture wins: report it, do not re-derive. The "New" column is the rules of
ADR-0077 applied by hand. If the renderer and the table disagree, the table is checked against the
ADR first; only then does either one change.

### Task 4 — RootView: one door for "no vault is open" (coder) (closes `structure-RootView.swift-c0b`)

**File:** `Sources/App/RootView.swift` only. `RootView+Sheets.swift` is not touched.

- Replace `needsVault(_:)` (`:355-369`) and `notesPane`'s inline copy (`:371-389`) with one
  `private func requiringVault(_ explanation: String, shortcut: KeyboardShortcut? = nil,
  @ViewBuilder content: () -> some View) -> some View`.
- `detail`'s switch (`:258-271`) calls it once per pane, and the ten `…Pane` properties
  (`:273-353`, `:371-389`) are deleted.
- The Notes case passes its own sentence ("Scegli la cartella che contiene le note. Pergamenum non
  la modifica finché non salvi una nota.") and `shortcuts.shortcut(for: .openVault)`
  (`ShortcutStore.shortcut(for:) -> KeyboardShortcut?`, `ShortcutStore.swift:55`). The other nine
  carry no shortcut, as today. Every explanation string moves byte for byte.
- No `private` is widened.

**Done when:**

- `type_body_length` no longer appears for `RootView.swift`. Measured after the edit; the estimate
  is about 210 against a limit of 250;
- the 123-column line at `:276` and the double blank line at `:327` go with the deleted properties;
- the build and the unit suite are green;
- hand check H2 is done (gate G2).

**Commit:** `refactor(app): one "no vault open" door for the ten panes`.

### Task 5 — Pin the connector's violation strings (tester) (closes the `ConformanceText`/`"\($0)"` follow-up as "do not unify")

**File:** `Tests/LintFindingStringsTests.swift` (new).

- For every case of `NoteName.Violation`, `FrontmatterViolation`, `TagViolation`,
  `TaskMarkerViolation` and `CategoryViolation`, which `VaultAPI.LintFinding.init` renders with
  `"\($0)"` (`VaultPayloads.swift:142-152`), take one representative value and pin its string.
  Each string is captured by running today's code, never written by hand.
- The suite's doc comment says why: the strings are values inside the protected `LintFinding` shape
  (`.claude/protected-interfaces`), they come from Swift reflection, and a case or label rename
  would change external callers' JSON silently. It cites `FrontmatterDamageLintTests.swift:97-114`
  as the one string pinned so far.
- No production change. Green against the current code. Run `tuist generate --no-open`.

**Commit:** `test(connector): pin every lint violation string LintFinding emits`.

### Task 6 — Close-out (orchestrator, with the coder for any stale comment) (closes `PG-147`)

- **`TODO.md`:** `PG-147` becomes `[x]`, with the verdict table's outcome per sub-item (two done,
  four closed with their reason) and the PR number.
- **`CLAUDE.md`:** add the ADR-0077 line to the chain decision index, in the style of its
  neighbours.
- **Stale-reference greps.** Each must be empty, or name only the new home:
  - `rg -n "escaping pass runs before|splits a wikilink at|never reads a fence's language" Sources Tests`;
  - `rg -n "MarkdownHTML" Sources`, which should list only `MarkdownHTML.swift` and the call in
    `NoteExport.swift`;
  - `rg -n "needsVault|notesPane|todayPane|tasksPane" Sources`.
- **Final verification:**
  - TEST-CMD green;
  - `perg` and `pergamenum-mcp` build;
  - the lint table before and after;
  - both counts at or above the baseline, plus the new tests;
  - `scripts/check-adr-references.py` (after `git fetch`).
- **At merge:** `scripts/uitests.sh --status`, then `--affected` (advisory, CLAUDE.md).
- **After merge:** ADR-0077's status flips to accepted (PR, merge hash, date), as the first docs
  change. GitHub #247 is closed.

**Commit:** `docs: close PG-147, record ADR-0077 in the chain index`.

## Observable-contract staleness

Every contract this chain changes, and the call sites grep found on `096d36a5`. **Run the full
`PergamenumTests` after each change**, not only the suites named: a parser change reaches suites
that never mention the parser.

| Contract | Task | Production call sites | Test call sites |
|---|---|---|---|
| `MarkdownInlineParser.spans(in:)` output (P1, P2) | 2 | `MarkdownBlocksView.swift:230`, which draws the reading surfaces: `TranscludedNoteView.swift:106`, `PraticaEntryRow.swift:77`, `PraticaMessageRow.swift:175`, `PratichePane+Inspector.swift:68`, and `MarkdownReadingView.swift:59` (retained, unreferenced). `NoteOutline.swift:92-94` (`plainText(of:)`) feeds heading titles to `Transclusion.excerpt` (`Transclusion.swift:108-111`), `NoteJump`, `QuickSwitcher`, `OutlinePane`, `NoteListPane+Footer`, `OutlineMove`, `NoteFolding`, `CommandActions`, `CardCommand`, `CardTextView`, `FormattingTextView`, `WorkspaceController`, `BoardCardMenu`, `NoteTab`, `NoteTextView`, `EditorColumn+Text`, `PraticaEntry` and `PraticaEntryComposer`. Most of these read ranges; title readers change only for headings with two underscores or a styled link label. | 14 direct: `MarkdownReadingTests.swift` (9), `TextFormatEdgeTests.swift` (4), `NoteOutlineTests.swift` (1). 49 more read through `NoteOutline.entries`/`Transclusion.excerpt`: `NoteOutlineTests` (11), `FoldStateOrdinalIndexStalenessTests` (8), `TransclusionTests` (7), `CRLFLineWalkTests` (5), `OutlinePaneFoldableOffsetTests` (4), `EditorCompletionTests` (3), `NoteFoldingTests`, `TextFormatEdgeTests`, `CardFoldTests`, `EditorControllerReadTimingRemainingTests` (2 each), `FoldBadgeClickTests`, `CardCommandTests`, `NoteSectionsProviderTests` (1 each) |
| `MarkdownBlockParser.blocks(in:)` output (P3) | 2 | the same `MarkdownBlocksView` surfaces; `ViewBlock.blocks(in:)` (`ViewBlock.swift:266-272`) keeps `.code` blocks only, so it is unaffected | 35: `MarkdownReadingTests.swift` (29), `CRLFAppendTests.swift` (2), and 1 each in `MarkdownStylerTests`, `EditorCommandTests`, `TransclusionTests` and `NoteOutlineTests` |
| `TaskParser.state(for:)`: `private` becomes internal, signature unchanged | 2 | `TaskParser.swift:49` (unchanged), `MarkdownBlocks.swift` (new) | none |
| `MarkdownHTML.render(_:)` / `inline(_:)` output, and the type's file | 3 | `NoteExport.swift:36`, then `NoteExporter.swift:44` (HTML) and `:47` (PDF). The Markdown export, `:42`, does not change | `NoteExportTests.swift` (19 calls, **must stay green unedited**), `ViewBlockOutOfScopeTests.swift:176` (R-11, **byte-identical, unedited**), the new golden file |
| `LinkPolicy.isOpenable(_: String)`: input becomes the raw target, and only the doc comment changes | 3 | `NoteExport` (old) becomes `MarkdownHTML` (new); `HTMLTextReducer.swift:290` is unchanged | through `NoteExportTests.swift:80-94` |
| `RootView` empty states: structure only, strings and shortcut unchanged | 4 | `RootView.swift` only | none (hand check H2) |

## Risks and HITL gates

**Risks**

- **A PG-124 property regresses under a green suite.** The `href` escaping and the scheme gate now
  hold by §D2's rule rather than by substitution order.
  - Mitigations: the three existing PG-124 tests stay unedited; Task 3 adds the escape-once and
    closed-element-set scans over the whole corpus; the reviewer reads `MarkdownHTML.swift` for any
    interpolation of a note-derived string that skips `NoteExport.escape`.
- **The parser fixes change surfaces outside the export** (Task 2): the reading view, Pratiche rows,
  transclusions and outline titles. They are corrections, but they are visible. A heading with two
  underscores gets a different outline title, which is what makes `![[Nota#a_b_c]]` resolve.
  The index caches no parser output, so `IndexCache.schemaVersion` stays 7, and fold state is keyed
  by ordinal. **One thing is persisted from these titles** (found in review, this bullet was wrong
  before): the `[[Nota#` completion writes `entry.title` into the note, and `Transclusion.excerpt`
  matches it later. A section link completed earlier against `## file_name_here` (old title
  `filenamehere`) or `## Vedi [**x**](u)` (old title `Vedi **x**`) stops resolving. Accepted: the old
  titles were wrong, a fallback would be a second grammar, and re-completing the link fixes it.
  Recorded in ADR-0077 §D5 and pinned by `aSectionNamedByAnOldOutlineTitleNoLongerMatches`.
- **P1's flanking rule is new code on a hot path.** `spans(in:)` runs per paragraph when a reading
  surface draws. The added work is one character comparison per `_` marker, with no new allocation.
  The reviewer checks that.
- **The editor keeps its own emphasis rules** (ADR-0077 §D5). After Task 2, `file_name_here` shows
  plain in the reading surfaces and still italicises `name` in the editor, where the `_` stay
  visible. That disagreement already existed for `*` and `2 * 3 * 4`. It is recorded, not fixed
  here.
- **The PDF path is not unit-tested for layout.** `<hr>`, `<del>` and the inline `text-align` style
  reach `NSAttributedString(html:)` for the first time. Hand check H1 covers them.
- **The GUI suite at merge.** `RootView` is the app shell, so `scripts/uitests.sh --affected` may
  select most classes, about 25 minutes of the machine. Ask `--status` first. The result is
  advisory (CLAUDE.md merge gate).
- **Merge conflicts with parallel chains.** They are expected only in `TODO.md` (merge `origin/main`
  in, never force) and in the ADR number (`docs/adr/README.md` §1).

**Dependencies.** Nothing external: no third-party API, no consent flow, no cloud console, no new
environment variable or port. No new SPM dependency (ADR-0077 rejects one). Tuist 4, the Xcode 27
toolchain and `swiftlint 0.65.1` are already required.

**HITL gates. None of them is the implementing agent's to pass:**

- **G0: approve this plan and ADR-0077.** Includes:
  - the task glyphs for `[-]` and `[>]` (recommended `⊟` and `▷`; E08's expectation depends on
    them);
  - the five closed verdicts;
  - Task 4's inclusion.
- **The baseline merge of `origin/main`**, if it has moved; it is a merge commit.
- **Each task's commit**, with its diff.
- **G2, after Tasks 3 and 4:**
  - Stefano reads Task 3's diff of `Tests/NoteExportGoldenTests.swift` (the old → new comparison,
    case by case, each with its class);
  - **H1:** in a Debug build, File ▸ Esporta nota, as HTML and as PDF, on a note built from W02.
    Open both. Check the rule, the struck text, the aligned column, and that each embed line reads
    as its file name;
  - **H2:** launch a Debug build with no vault (`-recentVaults '()'`) and visit the ten panes. Each
    shows its own sentence. Only Notes' button shows and answers its shortcut. Use `open -n`, not
    `nohup`, and `ls -dt` to find the newest build (CLAUDE.md).
- **The ADR number re-check** against `origin/main` immediately before the merge.
- **Push, pull request and merge to `main`**, then the ADR status flip and the closing of #247.
- **Nothing here authorises** editing an assertion in `NoteExportTests.swift` or
  `ViewBlockOutOfScopeTests.swift`, a `swiftlint:disable`, a threshold change, touching
  `MarkdownStyler.swift`, or an edit to `.claude/protected-interfaces`. If a task cannot meet its bar
  without one, stop and report.

## Open for Stefano

- **Glyphs for cancelled and rescheduled tasks in an export** (G0). The recommendation is `⊟`
  (U+229F) and `▷` (U+25B7): both fall back to system fonts, and neither reads as done. `☐` and `☑`
  stay as today.
- **Embeds export as their file name** (ADR-0077 §D4). Pictures in the PDF would be a feature of
  their own, not part of this refactor. Say so if you want it filed.
- **The editor's emphasis rules.** Aligning `MarkdownStyler` with the reading parser's flanking
  rules (`_` intraword, whitespace-flanked `*`) is a separate, editor-side change. The
  recommendation is to file it as its own entry rather than widen this chain.

---

TEST-CMD CANDIDATE: `xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -only-testing:PergamenumTests test`

TEST-CMD MODE: brownfield

This is `.claude/test-cmd` verbatim, and it deliberately stays as it is. It runs through the `Stop`
hook at the end of every turn, and CLAUDE.md records why `-only-testing:PergamenumTests` is
load-bearing. It covers every new test in this plan, which are all unit tests. What it does not
cover runs at the gates above and is never wired into the hook:

```bash
xcodebuild -workspace Pergamenum.xcworkspace -scheme perg           -destination 'platform=macOS' build
xcodebuild -workspace Pergamenum.xcworkspace -scheme pergamenum-mcp -destination 'platform=macOS' build
scripts/uitests.sh --status && scripts/uitests.sh --affected   # at merge, advisory
```
