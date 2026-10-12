**Requirement set:** `docs/archive/specs/pg-387-n4-birth-of-note.SPEC.md` (root `SPEC.md` while this was built)

# Plan: N4, the birth of a note (PG-387, #889, R-01..R-18)

- **SPEC:** root `SPEC.md`, Approved 2026-10-06. It is the authority for scope. Requirement ids are
  the SPEC's local ones (R-01..R-18). The chain ids (R-29..R-34, R-44, R-45) appear only where an
  existing artefact cites them.
- **Base:** `c8f63e5d` (this branch, `origin/main` @ `2dfa4e4d` merged in; `origin/main` has since
  moved to `377b196e` with a `TODO.md` sync only). Every line number below was read there.
- **Precedent, not modified:** `docs/plans/note-workflow-n4.md` and
  `docs/plans/note-workflow-n4-mockup.md` were written against the chain SPEC. This plan supersedes
  them for `/build`; both stay as they are.
- **Delivery:** the mockup PR (Task 1), then one code PR (Tasks 2-8), as R-18 says.

## ADR outcome

**Existing ADRs cited, no new ADR.** `docs/adr/0085-a-da-classificare-pane-for-notes-and-one-composer.md`
and `docs/adr/0086-templates-where-notes-are-born.md` already record every decision this plan
implements: the pane as a query, the one classification rule, write-then-move, one composer with two
hosts, «Estrai» as a two-write door, the toast's scope, the two placeholders, the daily-template
setting at the one birth door, the one-shot caret, `--template`. Nothing in the SPEC decides a new
hard-to-reverse trade-off they do not already hold, so a third record would only restate them.

- **Status.** Both read `planned` on the base, not `proposed` as the SPEC's Destination says.
  `planned` is correct (`docs/adr/README.md` rule 2: no `proposed` record on the base). Both flip to
  `accepted` after the code PR merges (Task 8, ship record).
- **Numbers.** 0085 and 0086 are already held on `main` (PR #904). Re-check both against
  `origin/main` right before the merge anyway (`docs/adr/README.md` rule 1), because PR #978 and N3
  Session C both write to `docs/adr/`.
- **Sections per task.**

  | Task | ADR-0085 | ADR-0086 |
  | --- | --- | --- |
  | 1 (mockup) | §D1, §D2, §D5, §D7, §D8, §D9 (visual only) | §D5 (composer and capture menus, visual only) |
  | 2, 3 (Core, session, connectors) | §D3, §D4, §D8 (door and `NoteExtraction`), §D10 | §D1, §D2 (decode), §D3, §D5 (`composing`, connector capture), §D6, §D7 |
  | 4 (app contracts, red) | §D1, §D2, §D5, §D6, §D7, §D8, §D9 (declarations) | §D4, §D5 (declarations) |
  | 5 (pane, «Classifica») | §D1, §D2, §D5, §D6, §D12 (§7.4, §10) | none |
  | 6 (templates, composer, toast) | §D7, §D9, §D12 (§12) | §D2 (picker), §D3 (app side), §D4, §D5, §D9 |
  | 7 («Estrai») | §D8, §D12 (§10 Modifica) | none |
  | 8 (GUI, verification, ship) | §D11 | §D8 |

### SPEC wins: points to correct in the ADRs at ship

Each is recorded in the ADR's implementation notes when Task 8's ship record runs. None changes a
decision; each corrects a fact or fills a gap the SPEC closes.

1. **«Source» lines.** Both cite `SPEC.md` approved 2026-10-04 and R-29..R-34 (0086 also R-32).
   Repoint to the SPEC approved 2026-10-06, R-01..R-18 (the SPEC's own Decision "Existing artefacts
   are kept").
2. **ADR-0085 §D3, "`ClassificationRefusal` keeps its cases."** R-02 requires the one rule to refuse
   a date-shaped topic, and no existing case says that. The plan adds `case dateTopic(Tag)` and
   moves the refusal's `sentence` from the app (`ContenitoreInspectorModel.swift:131`) into Core, so
   the connectors can word it. A malformed topic is unrepresentable in `[Tag]` (`Tag.init?`), so it
   is refused where text becomes a tag (`TagEntry.check`, the connector's topic parser).
3. **ADR-0085 §D7, "`NewCanvasItemSheet` keeps its folder, link and sticky kinds."** There is no
   sticky kind: `NewCanvasItemSheet.Kind` is `folder, link, note` (`BoardSheets.swift:4`). It keeps
   folder and link.
4. **ADR-0085 Context and §D7 on Quick Open.** The ADR describes a direct write at
   `VaultBrowser.swift:81-86`. On the base the create row calls
   `VaultController.createNoteFromQuickOpen(title:)` (n1-seams R-18, `VaultController+Notes.swift:49`),
   which leaves a failure on `quickSwitcherProblem` and is pinned by five tests in
   `Tests/QuickOpenCreationTests.swift`. R-11 makes that door and its sentence dead. The plan deletes
   both and re-points the five tests (HITL: a test change, explained in chat first).
5. **ADR-0085 §D4 and §D5 disagree on a scheda's folder.** §D4 says "a scheda moves as a pair";
   §D5 says the scheda form has no folder field because a scheda's place is the Contenitore's
   (ADR-0071 §D7). The SPEC's edge case sides with §D5 for the app. For the session door and the
   connectors this plan refuses `toFolder` on a scheda path (gate G-S below). The ADR note records
   whichever the person picks.
6. **ADR-0086 References, "Data model (two new settings)."** The SPEC's data model adds one key,
   `dailyTemplate` (N1 already shipped `inboxFolder`).
7. **Line numbers.** Both ADRs read their numbers at `48a2d912`. They are stale throughout (for
   example `dailyNote(for:)` is now `VaultSession+Notes.swift:131`, capture «Oggi» calls it at
   `VaultCapture.swift:115`). The implementation notes name `c8f63e5d`.
8. **ADR-0086 §D4 does not say the caret takes the keyboard.** The plan places the pending caret
   through the coordinator's existing `scroll(_:to:takingFocus:)` (`NoteTextView+Coordinator.swift:175`,
   `takingFocus` defaults to true), which also makes the text view first responder. Without that,
   R-08 and the daily-template GUI test have nowhere for the first key to land. It is an
   elaboration, recorded as one.
9. **The SPEC's own Decision "N4 is built after N3"** says the three prerequisites "do not exist".
   They now do (below). Its rationale is satisfied; what remains is file overlap with N3 Session C
   (gate G-N3C).

## Prerequisites (verified on the base)

- `ShortcutCommand.shipsUnbound` (`Sources/Core/Shortcuts/ShortcutCommand.swift:155`, two members).
- `VaultController.offerNoteCreation(title:besideNoteAt:)` (`Sources/App/VaultController+Notes.swift:194`).
- `VaultController.recordLinkAtCaret(_:inColumn:)` (`Sources/App/VaultController+LinkOpening.swift:41`).
- N1: `CaptureTitle.derive`, `VaultSettings.inboxFolder`, `VaultSession.inboxFolder` (ADR-0080).
- N3 Sessions A and B are merged; ADR-0083 and ADR-0084 still read `planned` because Session C
  (`docs/plans/note-workflow-n3.md` Tasks 5-8) is unbuilt and has no open PR.
- `/workplan` does not stop: no prerequisite is missing.

## Sequencing, N3 Session C and PR #978

**Overlap with N3 Session C** (its Files lines, Tasks 5-8):

| File | Session C | N4 | Handling |
| --- | --- | --- | --- |
| `Sources/Features/Editor/VaultBrowser.swift` | inspector sections move out, `InspectorSection.unresolved(shown:)` becomes `unresolved(count:)` | Quick Open's `.createNote` arm (`:72-78`), one modifier line | Tasks 6 and 7 only, after Session C's PR merges; N4's bulk goes into the new `VaultBrowser+NoteBirth.swift` |
| `Sources/App/CommandActions+LinkNavigation.swift` | `goToLink`, `linkInputs` | none | N4 wires its selection report through `EditorColumn+Text.swift` instead |
| `docs/adr/INDEX.md` | ADR-0083/0084 flip (its Task 8) | ADR-0085/0086 entries (ship) | line-adjacent, keep both sides |
| `Sources/Features/DesignGallery/*` | `InspectorLinksMockup.swift`, `UnlinkedMentionsMockup.swift` | new `NoteBirthMockup*.swift`, one case and one page arm in `MockupGalleryView.swift` | no shared file in Session C's list; if it relabels its pages at `MockupGalleryView.swift:91` and `:101`, keep both sides |

- **`NoteTextView+Coordinator.swift`.** Session C does not touch it. N4 adds exactly one line in
  `textViewDidChangeSelection` (`:190`), calling `reportSelection(in:)`, whose body lives in a new
  `NoteTextView+SelectionReport.swift` with its claim in `RequestLedger` (`NoteTextView+Requests.swift`).
  The caret one-shot is consumed in `NoteTextView+Update.swift`'s `consumeOneShots`, not in the
  Coordinator.
- **PR #978** (`feature/pg-401-ceilings`, open) touches `Tests/EditorRestyleBudgetTests.swift`,
  `Tests/PG401GateTests.swift`, `Tests/RestyleBudgetSupport.swift`, `scripts/pg-401-gates.sh`, its
  ADR-0091 file and `docs/adr/INDEX.md`. It touches no N4 source. Its ceilings bind N4: the two
  per-keystroke additions (the selection report and the slash stash) are O(1) and write nothing on a
  bare caret, and `scripts/pg-401-gates.sh` runs in Task 8. Whichever of #978 and the N4 code PR
  lands second resolves the `INDEX.md` adjacency.

**Gate G-N3C (decision for the person, at plan approval).**

- **Option A (recommended):** Task 1 (mockup PR) and Tasks 2-3 start now. They share no file with
  Session C or #978, and the mockup decides nothing they declare (the SPEC fixes the name, position,
  order, shortcut, labels and the 10 s window; the mockup chooses only visual variants). Tasks 4-8
  start after gate M is approved and Session C's PR is merged into `main` and then into this branch.
  The code PR lands after N3.
- **Option B (the Decision's literal reading):** nothing starts before Session C merges.
- The task order is the same under both; only the start of Tasks 1-3 differs.

**Sessions** (the Stop hook runs `PergamenumTests` at the end of every turn, so each session ends
green):

| Session | Tasks | Starts when |
| --- | --- | --- |
| M | 1 (mockup PR) | now (Option A) |
| S1 | 2, 3 | now (Option A), or after Session C (Option B) |
| S2 | 4, 5, 6, 7 | gate M approved and Session C merged; Task 4's reds are made green by Tasks 5-7 in the same session |
| S3 | 8, then `/ship` | S2 green |

Within a session, `/build` runs a `Red: yes` tester before the coders that turn it green. A session
that stops between Task 4 and Task 7 ends with Task 4's declared reds still red; do not close S2 in
between.

## SPEC decisions registered, not reopened

- «Da classificare» in LAVORO after «Attività», Ctrl+Cmd+I, a query on the index, schede included
  and classified through their own form (G1).
- One classification rule, the scheda rule as its special case; write first, move second.
- A dirty note is saved as part of the confirmation: «Salva e classifica», «Salva ed estrai» (G2).
- The composer composes, the host creates: the Note pane host (ADR-0003 §D1, `ComposerUITests`
  unmodified) and a sheet host for Workspace «Documento» and «Estrai»; Quick Open opens the pane host
  prefilled.
- `TagEntry` is the one door from typed text to a tag.
- «Estrai» is a two-write session door; a range touching the frontmatter is refused.
- The toast covers the pane-host composer only (G3).
- `{{time}}` and `{{cursor}}`; the daily template is a vault setting applied at the one birth door;
  the caret is a one-shot tab property.
- Two GUI tests at most. `PG-121` closes as superseded.

## Gates for the person (at plan approval)

- **G-N3C:** above.
- **G-S (recommended: refuse).** A connector `classify --folder` or a session `classifyNote(…,
  toFolder:)` on a scheda path is refused with «Un documento del Contenitore resta nel Contenitore:
  classificalo senza cartella.», matching ADR-0085 §D5 and ADR-0071 §D7. Alternative: allow it, and
  `moveNote` carries the pair (ADR-0071 §D6). Under the alternative, Task 3 drops one guard and one
  test in Task 2 flips its expectation.
- **Test changes to explain in chat before Task 4 runs** (global rule: a test that must change is
  explained first):
  - `Tests/ShortcutTests.swift:83-88` `onlyTheTwoLinkVariantsShipUnbound` pins exactly two
    unbound commands; N4 ships two more (`classifyNote`, `extractToNote`), so the pin becomes four.
  - `Tests/QuickOpenCreationTests.swift` (five tests) pins the Quick Open door R-11 retires. Its
    assertions are re-pointed at the new door (prefilled composer, no file written, parked draft
    wins) and at `createComposedNote` (a taken title's sentence and problem-list entry).

## Contract changes and their call-sites

Found with `rg -n` on the base. After the change run the **whole** `PergamenumTests` suite, not the
new files alone: these contracts are shared by the Contenitore, the capture, the connectors and the
command catalogue.

| Contract | Call-sites found | Handled in |
| --- | --- | --- |
| `NewNoteComposer(draft:onCreated:onCancel:)` gains `host:` and `perform:`, both defaulted | `Sources/Features/Editor/VaultBrowser.swift:190` | compiles unchanged after Task 4; Task 6 passes the pane host explicitly |
| `ClassificaSheet(schedaPath:actions:)` becomes `ClassificaSheet(subject:)`, file moves to `Sources/Features/Editor/` | `Sources/Features/Contenitore/ContenitoreView.swift:51` | Task 4 |
| `Navigation.Pane` gains `.unfiled` (exhaustive switches) | `Sources/App/Navigation.swift:48`, `:64`, `:90`; `Sources/App/RootView.swift:273`; automatic: `MenuCommands.swift:32`, `CommandActions.swift:302` | Task 4 |
| `ShortcutCommand` gains three cases (exhaustive switches) | `ShortcutCommand.swift` `section` (`:179`), `title` (`:206`), `defaultBinding` (`:275`, the unbound arm at `:397`); `CommandActions+CanRun.swift` `canRun` switch (`:30`) | Task 4 |
| `ShortcutCommand` sections' `assertionFailure` defaults | `CommandActions.swift:199` (File), `:235` (Modifica), `:283` (Vista) | Task 4 adds arms first |
| `ShortcutCommand.shipsUnbound` pin | `Tests/ShortcutTests.swift:83-88` | Task 4 (two becomes four, HITL) |
| `createNoteFromQuickOpen(title:)`, `quickSwitcherProblem` | `VaultController+Notes.swift:49`, `VaultController.swift:95-96`, `QuickSwitcher.swift:62`, `:68`, `:77`, `VaultBrowser.swift:75`, `Tests/QuickOpenCreationTests.swift` (5 tests) | tests in Task 4 (HITL), sources deleted in Task 6 |
| `ClassificationRefusal` gains `.dateTopic`; `sentence` moves to Core | `Sources/Features/Contenitore/ContenitoreInspectorModel.swift:131` | Task 2 |
| `TagRules.isDateLike` `private` to `internal` | `Sources/Core/Conventions/Tag.swift:194` | Task 2 |
| `NoteTemplate.substituting` (signature kept, becomes a forward) | `NewNoteComposer.swift:162`, `TemplateSheet.swift:69`; `Tests/NoteTemplateTests.swift:63`, `:71`, `:72`, `:79`, `:89`, `:120` | sources move to `resolve` in Tasks 4 (`TemplateSheet.insertion`) and 6; tests unchanged |
| `VaultSession.dailyNote(for:)` (signature kept, forwards to `dailyNoteBirth`) | `VaultController+Notes.swift:137`, `PraticaEntryComposer.swift:152`, `VaultCapture.swift:115`, `VaultSession+EventNotes.swift:78`; `Tests/TopiclessCreationPathTests.swift:232`, `Tests/VaultControllerLandedChangeTests.swift:443`, `Tests/PraticaEntryCommandTests.swift:279`, `:376` | the first switches to `dailyNoteBirth` in Task 6; the rest inherit the template by design (ADR-0086 §D3) |
| `openDailyNote(for:)` (signature kept) | `CommandActions+Open.swift:16`, `VaultController+Routes.swift:146`, `DayController.swift:163`, `VaultBrowser.swift:85` | unchanged; with no setting the bytes are today's |
| `openNote(at:)`, `openNoteInNewTab(at:)` gain `caret: Int? = nil` in place (no overload, so no ambiguity with `openNote(at:how:)`) | every call site keeps compiling | Task 4 |
| `VaultAPI.createNote` gains `template: String? = nil` | `WriteCommands.swift:12`, `VaultHost.swift:186`, `Tests/ConnectorTests.swift:273`, `:337`, `:342`, `Tests/TopiclessCreationPathTests.swift:92`, `:194`, `:213` | Task 3; tests unchanged |
| `VaultAPI.capture` gains `template: String? = nil` | `WriteCommands.swift:101`, `VaultHost.swift:211`, `CaptureController.swift:173`, `VaultController+Routes.swift:186`, `Tests/CaptureTests.swift` (24 calls), `Tests/CRLFCaptureTests.swift:156`, `Tests/InboxFolderReachTests.swift:41`, `:56`, `:186`, `Tests/TopiclessCreationPathTests.swift:109` | Task 3 front ends, Task 6 panel; tests unchanged |
| `CommandActions.rowCommands` gains `.classifyNote` | `CommandActions.swift:134`, `CommandActions+CanRun.swift:108` | Task 5 |
| `SidebarItem` LAVORO gains `.pane(.unfiled)` | `Sources/App/SidebarItem.swift:93`; `Tests/SidebarTests.swift` | test in Task 4, row in Task 5 |
| `NewCanvasItemSheet.Kind` loses `.note`; `WorkspaceController.TapBehaviour` gains `.composeDocument` | `BoardSheets.swift:4`, `:45`, `:53`; `WorkspaceController+Tools.swift:83`, `:99`; `WorkspaceView+Creation.swift` | Task 6 |
| Unchanged on purpose | `Tests/ContenitoreCoreTests.swift:161-189` and the rest of the scheda suite, `Tests/EditorCommandTests.swift:152`, `UITests/ComposerUITests.swift`, `Tests/NewNoteDraftTests.swift`, `Tests/WorkspaceDocumentCreationTests.swift` (`NewCanvasItemSheet.confirmation` stays), the six existing `NoteTemplateTests` assertions | staying green unmodified is the acceptance |

New files compiled into `perg` and `pergamenum-mcp`: **`Sources/Vault/VaultSession+NoteBirth.swift`**
must be named by hand in `Project.swift`'s `sharedSources` (beside `VaultSession+Notes.swift` at
`Project.swift:155`, with an ADR-0085 §D4 comment). The new `Sources/Core/Conventions/*.swift` and
`Sources/Connector/VaultNoteBirth.swift` are covered by the `Sources/Core/**` and
`Sources/Connector/**` globs. The new `Sources/CLI/Commands/NoteBirthCommands.swift` and the two
`Sources/MCPServer/*+NoteBirth.swift` files belong to their tool target only, by its own glob. Run
`tuist generate --no-open` after each of these and after the `ClassificaSheet` move and the new
`Sources/Features/Unfiled/` folder.

## Tasks

### Task 1 — Mockup PR: «Da classificare», the generalised «Classifica…» sheet, the composer sheet, «Estrai» and the toast (R-01, R-04, R-11, R-12, R-13, R-14, R-16, R-18)
Owner: coder
Files: Sources/Features/DesignGallery/NoteBirthMockup.swift, Sources/Features/DesignGallery/NoteBirthMockupPieces.swift, Sources/Features/DesignGallery/MockupGalleryView.swift, Tests/MockupGalleryLayoutTests.swift
Tests: MockupGalleryLayoutTests.swift
Signatures:
- NoteBirthMockup — struct NoteBirthMockup: View
- MockupGalleryView.Screen.noteBirth — case noteBirth // Page("Nascita di una nota", "N4, da approvare", NoteBirthMockup())
Red: no

Its own branch and PR (`feature/pg-387-n4-mockup`), merged before Task 4 starts (SPEC Constraint
"Mockups first", R-18's "after its mockup PR"). No production type is referenced except the theme
and the design tokens; static data only; tokens only, no hardcoded colour or font.

- **Scenes** (the `note-workflow-n4-mockup.md` precedent, reworded for this SPEC):
  - **4a sidebar:** LAVORO with «Da classificare» right after «Attività», light and dark; variants
    for the count badge (none, or `.badge` before `.tag`) and the SF Symbol.
  - **4b pane:** rows (title, folder, date; a document glyph on a scheda row), the folder filter
    with counts, its hidden state when empty, the empty pane; two layout variants (list only, list
    plus a frontmatter preview). Order is not a variant: newest first is settled.
  - **4c «Classifica…»:** the note subject (topic chips with a vocabulary refusal shown, the folder
    picker, the frontmatter preview with `status-inbox` struck through, «N di 7 tag»), the scheda
    subject (no folder field, the content type), and the dirty-note confirm «Salva e classifica».
  - **4d composer sheet:** Workspace «Documento» (folder shown as a fixed label, template menu),
    «Estrai» (selection preview, title prefilled from the first line, no template menu, «Salva ed
    estrai»), and the half-done state (note created, source refused, both named, «Chiudi»). The tag
    field with `client-`/`project-` chips and a blocked closed-family value.
  - **4e toast:** «Nota creata · Annulla» at the bottom of the Note pane's editor, constant height,
    with its refusal sentence in the same height.
- **Tests (coder-written, the gutter and N3 precedent):** `theNoteBirthPageIsListedWithItsMilestone`
  and `theNoteBirthScenesFitInTheRow` in `MockupGalleryLayoutTests`.
- **Gate M (HITL).** Stefano opens Impostazioni › Design system › «Mockup delle schermate», page
  «Nascita di una nota», on this checkout's Debug build, found by `WorkspacePath` (CLAUDE.md, never
  by newest mtime). The chosen variants are written into the PR description; Tasks 5-7 read them
  there. The label becomes «N4, approvato» in the code PR (Task 5).
- **Observation for the gate, not a reopening:** the Contenitore's own column already labels its
  inbox scope «Da classificare» (`ContenitoreSidebar.swift:43`). The new pane lists those schede too
  (G1), so the label means the same set; the mockup should show both so the person sees them side by
  side.

### Task 2 — Core rules, the session doors and the connector doors, declared and red (R-02, R-03, R-05, R-06, R-07, R-08, R-09, R-10, R-13, R-14, R-15)
Owner: tester
Files: Sources/Core/Conventions/NoteTemplate.swift, Sources/Core/Conventions/NoteClassification.swift, Sources/Core/Conventions/TagEntry.swift, Sources/Core/Conventions/NoteExtraction.swift, Sources/Core/Conventions/Tag.swift, Sources/Core/Contenitore/ContenitoreClassification.swift, Sources/Features/Contenitore/ContenitoreInspectorModel.swift, Sources/Vault/VaultSettings.swift, Sources/Vault/VaultSession+NoteBirth.swift, Sources/Connector/VaultNoteBirth.swift, Sources/Connector/VaultWrites.swift, Sources/Connector/VaultCapture.swift, Project.swift, Tests/NoteTemplateTests.swift, Tests/NoteClassificationTests.swift, Tests/TagEntryTests.swift, Tests/NoteExtractionTests.swift, Tests/NoteBirthSessionTests.swift, Tests/NoteBirthConnectorTests.swift
Tests: NoteTemplateTests.swift, NoteClassificationTests.swift, TagEntryTests.swift, NoteExtractionTests.swift, NoteBirthSessionTests.swift, NoteBirthConnectorTests.swift
Signatures:
- NoteTemplate.Resolved — struct Resolved: Equatable, Sendable { var body: String; var caretOffset: Int?; func caret(inWritten text: String) -> Int?; var cursorBack: Int? { get } }
- NoteTemplate.resolve — static func resolve(_ template: String, title: String, date: CalendarDate, time: TaskTime) -> NoteTemplate.Resolved
- NoteTemplate.composing — static func composing(captured: String, into resolved: NoteTemplate.Resolved) -> String
- NoteTemplate.reference — static func reference(_ reference: String, among templatePaths: [String]) -> Result<String, TemplateReferenceError>
- TemplateReferenceError — enum TemplateReferenceError: Error, Equatable, Sendable { case unknown(String, available: [String]); case ambiguous(String, candidates: [String]); var sentence: String { get } }
- ClassificationRefusal.dateTopic — case dateTopic(Tag)
- ClassificationRefusal.sentence — var sentence: String { get } // moved to Sources/Core/Conventions/NoteClassification.swift, existing wording byte-identical
- TagRules.isDateLike — static func isDateLike(_ value: String) -> Bool // was private
- NoteClassification.classify — static func classify(tags: [Tag], topics: [Tag], vocabulary: Vocabulary) -> Result<[Tag], ClassificationRefusal>
- TagEntry.Refusal — enum Refusal: Error, Equatable, Sendable { case malformed(String); case notInVocabulary(Tag); case vocabularyUnavailable(TagNamespace); case dateTag(Tag); case notAllowedHere(Tag); var sentence: String { get } }
- TagEntry.check — `static func check(_ typed: String, allowing namespaces: Set<TagNamespace>, vocabulary: Vocabulary) -> Result<Tag, TagEntry.Refusal>`
- TagEntry.completions — `static func completions(for typed: String, allowing namespaces: Set<TagNamespace>, usage: [(tag: Tag, count: Int)], vocabulary: Vocabulary, excluding chosen: [Tag], limit: Int) -> [Tag]`
- TagEntry.topics — static func topics(fromList list: String, vocabulary: Vocabulary) -> Result<[Tag], TagEntry.Refusal> // the connectors' comma-separated string
- NoteExtraction.Refusal — enum Refusal: Error, Equatable, Sendable { case empty; case outOfBounds; case textChanged; case touchesFrontmatter; var sentence: String { get } }
- NoteExtraction.Plan — struct Plan: Equatable, Sendable { let extracted: String; let replacedSource: String; let link: String }
- NoteExtraction.range — `static func range(ofLines lines: ClosedRange<Int>, in text: String) -> Result<NSRange, NoteExtraction.Refusal>`
- NoteExtraction.plan — static func plan(source: String, range: NSRange, expectedText: String?, title: String) -> Result<NoteExtraction.Plan, NoteExtraction.Refusal>
- VaultSettings.dailyTemplate — var dailyTemplate: String?
- VaultSession.NoteClassifyOutcome — struct NoteClassifyOutcome: Equatable, Sendable { let written: WriteResult; let movedTo: String?; let moveProblem: String? }
- VaultSession.classifyNote — func classifyNote(at path: String, topics: [Tag], toFolder folder: String?) async throws -> NoteClassifyOutcome
- VaultSession.ExtractOutcome — struct ExtractOutcome: Equatable, Sendable { let created: WriteResult; let source: SourceWrite; enum SourceWrite: Equatable, Sendable { case replaced(WriteResult); case refused(String) } }
- VaultSession.extractToNote — func extractToNote(from sourcePath: String, range: NSRange, expectedText: String, title: String, in folder: String, topics: [Tag], date: CalendarDate) async throws -> ExtractOutcome
- VaultSession.DailyNoteBirth — struct DailyNoteBirth: Equatable, Sendable { let path: String; let created: Bool; let caret: Int? }
- VaultSession.dailyNoteBirth — func dailyNoteBirth(for date: CalendarDate, at now: Date) async throws -> DailyNoteBirth
- VaultAPI.ClassifySummary — struct ClassifySummary: Encodable { let path: String; let applied: Bool; let diff: String?; let movedTo: String?; let note: String? }
- VaultAPI.ExtractSummary — struct ExtractSummary: Encodable { let created: String; let applied: Bool; let createdDiff: String?; let sourceDiff: String?; let sourceRefused: String?; let note: String? }
- VaultAPI.classifyNote — static func classifyNote(_ session: VaultSession, at path: String, topics: String, folder: String?) async throws -> ClassifySummary
- VaultAPI.extractToNote — static func extractToNote(_ session: VaultSession, at path: String, fromLine: Int, toLine: Int, title: String, folder: String?, topics: String?) async throws -> ExtractSummary
- VaultAPI.createNote — static func createNote(_ session: VaultSession, title: String, folder: String?, topic: String?, date: String?, template: String? = nil) async throws -> WriteSummary
- VaultAPI.capture — static func capture(_ session: VaultSession, to destination: CaptureDestination, text: String, scheduled: String? = nil, due: String? = nil, template: String? = nil) async throws -> WriteSummary
Red: yes

**Declarations.**

- Stub bodies return a neutral value (`.failure(.noTopic)`, `Resolved(body: template, caretOffset:
  nil)`, `[]`) or throw. Never `fatalError`: it kills the Debug test host and turns a red file into
  a crashed run.
- `VaultSession+NoteBirth.swift` is new and is named in `Project.swift`'s `sharedSources`, then
  `tuist generate --no-open`. `VaultSession.templates` (`VaultSession+Files.swift:133`) already lists
  the templates: no `templatePaths` symbol is added (ADR-0086's draft named one).
- The new `VaultAPI` payloads live in `VaultNoteBirth.swift`, never in `VaultPayloads.swift`, whose
  `LintFinding` and `PraticaSummary` are protected.
- Moving `ClassificationRefusal.sentence` deletes the extension at
  `ContenitoreInspectorModel.swift:131` in the same change, with the five existing sentences
  byte-identical, so the Contenitore keeps its words.
- `perg` and `pergamenum-mcp` must still build with the stubs.

**Tests (Swift Testing, `#expect`).**

- **`NoteTemplateTests` (extended): `resolve` and `caret(inWritten:)`** (R-07, R-08).
  - `{{time}}` with `TaskTime(hour: 9, minute: 5)` is `09:05`.
  - `# {{title}}\n\n{{cursor}}` with «Ciao» gives body `# Ciao\n\n` and offset 8.
  - Two markers: the first wins and both are gone. A title containing the literal `{{cursor}}` is
    written as typed. `{{autore}}` stays. No marker gives a nil offset.
  - The offset counts UTF-16, with an emoji before the marker.
  - `caret(inWritten:)` over frontmatter plus a line break plus the body is the absolute offset;
    `cursorBack` is `body.utf16.count - caretOffset`.
  - The six existing `substituting` assertions are untouched and must stay green.
- **`NoteTemplateTests` (extended): `composing` and `reference`** (R-09, R-10).
  - `composing` puts the captured text at the marker; without one, the body, one blank line, then
    the text.
  - `reference` resolves an exact path, a title and `Titolo.md`; `.unknown` lists the available
    templates; `.ambiguous` for two `Riunione.md` in two subfolders of `Templates/`.
- **`NoteClassificationTests`** (R-02).
  - `status-inbox` removed, `type-note` kept or added, topics added, result ordered.
  - Refusals: `.noTopic`, `.notATopic`, `.dateTopic` (`topic-2026`, `topic-20261011`),
    `.tooManyTags`.
  - Parity: for the same tags and topics, `ContenitoreClassification.classify(…, type: nil, …)`
    equals `NoteClassification.classify`; with a type it equals the note result plus that type.
  - Refusal order on the scheda rule is unchanged: a second content type is reported before the
    count (`ContenitoreCoreTests:161-183` already pins the cases; this test pins the order with a
    case that violates both).
- **`TagEntryTests`** (R-12, and the topic parse of R-05/R-15).
  - Bare `materiali` is `topic-materiali`; `#client-acme` is `client-acme`.
  - `area-xyz` outside the vocabulary is `.notInVocabulary`; with an empty vocabulary,
    `.vocabularyUnavailable(.area)`.
  - A date-shaped value is `.dateTag`; `type-note` and `status-done` outside `allowing` are
    `.notAllowedHere`; `Topic Bad` is `.malformed`.
  - Completions: vocabulary values for closed families, used values most used first for open ones,
    chosen tags excluded, `limit` honoured.
  - `topics(fromList: "a, b")` is two topics; `"a,,b"` ignores the empty item; a malformed item is
    the refusal.
- **`NoteExtractionTests`** (R-13, R-15).
  - `range(ofLines:)` is 1-based and inclusive over the whole file: out of bounds, CRLF, a last line
    with no terminator.
  - `plan` refuses a range intersecting the frontmatter, a text mismatch and an empty range.
  - The replaced source keeps the frontmatter bytes identical and puts `[[Titolo]]` exactly where
    the range was. For a line range the extracted text drops the final line break, which stays in
    the source.
- **`NoteBirthSessionTests`**, temporary vault and temporary `stateBase` (R-03, R-06, R-13, R-14).
  - **`classifyNote`:** one `.written` landed change (counted through `landedChangeSubscriber`), the
    frontmatter as the rule says; with a folder, then one `.moved`; a destination holding the name
    leaves the classification written, `movedTo == nil` and `moveProblem` set; a write refused by
    `expecting:` (the file changed after the read, driven through the existing `writeGuarded` seam,
    ADR-0046 §D2) moves nothing; on a scheda path with a folder, refused before any write (G-S).
  - **`extractToNote`:** the new note holds the selection, the source holds `[[Titolo]]`, its
    frontmatter byte-identical; a taken title throws and writes nothing; a changed `expectedText`
    throws and writes nothing; a frontmatter range is refused. **The half-done case:** remove write
    permission on the source after the session read it, so the second write fails; the outcome is
    `.refused` and the new note exists; restore the permission in a `defer`. Deterministic, no
    timing (ADR-0046 §D11).
  - **`dailyNoteBirth`:** with no setting the bytes are today's; with a setting the body is resolved
    at the injected `at`, `created` true and `caret` the absolute offset; an existing day gives
    `created == false`, `caret == nil`, untouched bytes; a missing template, and a setting outside
    `Templates/`, each create the bare day and record a problem; `dailyNote(for:)` returns the same
    path.
  - `VaultSettings` decodes an absent `dailyTemplate` as nil and round-trips a present one.
- **`NoteBirthConnectorTests`**, armed through `VaultAPI.arm`, rehearsal first (R-05, R-10, R-15).
  - **Classify:** `applied == false` and a diff with `-  - status-inbox` and `+  - topic-x`; a real
    run applies; `"a,b"` is two topics; a malformed topic is a usage error; a refused `expecting:`
    reports its sentence.
  - **Extract:** two diffs; a range touching the frontmatter is refused; `undo` reverses the source
    and declines the creation.
  - **`createNote` with a template:** the resolved body is written with no `{{cursor}}`; an unknown
    template is a `ConnectorError` listing the available ones; an ambiguous one lists candidates.
  - **`capture` with a template:** `.newNote` writes one note with the text at the marker; `.today`,
    `.task` and `.note` with a template are usage errors.

### Task 3 — Core, session and connector bodies; both front ends; the smoke script; three builds (R-02, R-03, R-05, R-06, R-07, R-08, R-09, R-10, R-13, R-14, R-15, R-18)
Owner: coder
Files: Sources/Core/Conventions/NoteTemplate.swift, Sources/Core/Conventions/NoteClassification.swift, Sources/Core/Conventions/TagEntry.swift, Sources/Core/Conventions/NoteExtraction.swift, Sources/Core/Contenitore/ContenitoreClassification.swift, Sources/Vault/VaultSettings.swift, Sources/Vault/VaultSession+Notes.swift, Sources/Vault/VaultSession+NoteBirth.swift, Sources/Connector/VaultNoteBirth.swift, Sources/Connector/VaultWrites.swift, Sources/Connector/VaultCapture.swift, Sources/CLI/main.swift, Sources/CLI/Help.swift, Sources/CLI/Commands/WriteCommands.swift, Sources/CLI/Commands/NoteBirthCommands.swift, Sources/MCPServer/ToolCatalogue+NoteBirth.swift, Sources/MCPServer/VaultHost+NoteBirth.swift, Sources/MCPServer/ToolCatalogue+Writing.swift, Sources/MCPServer/VaultHost.swift, scripts/mcp-smoke.py
Tests: NoteTemplateTests.swift, NoteClassificationTests.swift, TagEntryTests.swift, NoteExtractionTests.swift, NoteBirthSessionTests.swift, NoteBirthConnectorTests.swift, ContenitoreCoreTests.swift, ConnectorTests.swift, CaptureTests.swift, CRLFCaptureTests.swift, InboxFolderReachTests.swift, TopiclessCreationPathTests.swift
Signatures:
- ToolCatalogue.noteBirth — static let noteBirth: [Tool] // classify_note, extract_to_note
- ToolCatalogue.templateProperty — static let templateProperty: Value // the `template` string property shared by create_note and capture, the `dryRunProperty` shape (`ToolCatalogue+Writing.swift:324`)
Red: no

Make Task 2 green without editing its tests. May run in parallel with Task 1 (Option A): no view,
no file the mockup decides.

- **`NoteTemplate`.** `resolve` locates the first `{{cursor}}` in the template before any other
  substitution, substitutes each segment, then joins, recording the offset (ADR-0086 §D1).
  `substituting` becomes `resolve(…, time: TaskTime(hour: 0, minute: 0)).body`. `{{time}}` is
  spelled by `TimeOfDay.formatted(hour:minute:)` (`Sources/Core/TimeOfDay.swift:15`).
- **The classification rules.** One internal merge core in `NoteClassification` (remove
  `status-inbox`, add `type-note` and the topics) is shared by both rules. Each rule keeps its own
  refusal order: the note rule checks no topic, not a topic, a date-shaped topic, then the count;
  `ContenitoreClassification.classify` keeps its signature and its order (no topic, not a topic, a
  date-shaped topic, unknown type, merge, second type, count). A date-shaped topic on a scheda is
  now refused too, which is R-02's "one rule"; `ContenitoreCoreTests` has no date-shaped topic, so it
  stays green unmodified.
- **`VaultSession+NoteBirth.swift`** (`@MainActor`, shared).
  - `classifyNote`: refuse a folder on a scheda path (G-S); read text and hash; apply the rule; write
    with `expecting:` inside `transaction("note classify")`. Then, outside that gesture, call
    `moveNote(at:toFolder:)` (`VaultSession+Files.swift:69`), which opens its own; a nested
    transaction asserts (ADR-0050). A thrown or failed move becomes `moveProblem`.
  - `extractToNote`: inside `transaction("note extract")`: read source and hash, `NoteExtraction.plan`,
    `createNote(…, body:)` (`expectingAbsent: true`, `VaultSession+Notes.swift:40`), then
    `write(_:to:expecting:)` with the hash read first. A refusal or failure of the second write is
    `.refused(sentence)`, the sentence being `VaultWriteRefusal`'s or the recorded problem.
  - `dailyNoteBirth` follows ADR-0086 §D3: existing day returned unchanged; otherwise read the
    setting, `NoteTemplate.body(of:)`, `resolve` with the day's compact title, the day and the time
    of `at`, `createNote(… category: .daily, body:)`. A missing, unreadable or out-of-`Templates/`
    setting records a problem through `recordProblem` and creates the bare day.
  - `dailyNote(for:)` in `VaultSession+Notes.swift:131` becomes `dailyNoteBirth(for:at: Date()).path`,
    signature kept; its doc comment ("there is no daily template") is corrected. So is
    `VaultCapture.captureIntoDay`'s (`:105-108`).
- **`VaultNoteBirth.swift`.** `classifyNote` and `extractToNote` parse `topics` through
  `TagEntry.topics(fromList:vocabulary:)`, lines through `NoteExtraction.range`, map refusals to
  `ConnectorError(…, usage: true)` with their `sentence`, and report the diff(s) from the armed
  session. `createNote`/`capture` resolve `template` through `NoteTemplate.reference(_:among:
  session.templates.map(\.relativePath))`, remove `{{cursor}}` (resolved body only), and for
  `capture` refuse `template` on every destination but `.newNote`. With a template, `.newNote`
  titles through `CaptureTitle.derive` and writes once through `createNote(… body:
  NoteTemplate.composing(…))`. Without one, N1's path is unchanged.
- **The front ends translate and nothing else** (ADR-0007 §D2).
  - `perg note classify <percorso> --topic a,b [--folder F]` and
    `perg note extract <percorso> --lines A-B --title T [--folder F] [--topic t]` in the new
    `NoteBirthCommands.swift` (`WriteCommands.swift` is 292 lines); `--lines` is parsed into
    `fromLine`/`toLine` in the CLI, a malformed range is a usage error. `noteGroup` in `main.swift`
    gains `classify` and `extract`; `Help.swift` gains the lines; `--template` on `note new` and
    `capture` in `WriteCommands.swift`.
  - MCP: `classify_note {path, topics, folder?, dryRun}` and
    `extract_to_note {path, fromLine, toLine, title, folder?, topics?, dryRun}` in
    `ToolCatalogue+NoteBirth.swift` and `VaultHost+NoteBirth.swift` (the `+NoteLinks` precedent);
    `VaultHost.swift:36` and `:173` add `ToolCatalogue.noteBirth` to the writing lists, so both are
    absent without `--allow-write` and `dryRun` defaults to true. `create_note` and `capture` gain
    `template` through one shared `templateProperty` (`ToolCatalogue+Writing.swift` is at 400 lines).
- **`scripts/mcp-smoke.py`.** Read-only: neither new tool is listed. Writing: a `classify_note`
  call without `dryRun` has `applied` false and a diff naming `status-inbox`; a real classify on the
  smoke vault's capture applies; an `extract_to_note` rehearsal has `applied` false; `create_note`
  with an unknown `template` is refused with the list.
- **Verify (R-18's build half).** The three builds from CLAUDE.md ## Commands (app, `perg`,
  `pergamenum-mcp`), `scripts/mcp-smoke.py`, then the whole `PergamenumTests` suite. Report the
  smoke output.

### Task 4 — App-layer contracts, stale tests rewritten, and the app behaviour tests, red (R-01, R-03, R-04, R-06, R-08, R-09, R-11, R-12, R-13, R-14, R-16)
Owner: tester
Files: Sources/App/Navigation.swift, Sources/Core/Shortcuts/ShortcutCommand.swift, Sources/App/RootView.swift, Sources/App/CommandActions.swift, Sources/App/CommandActions+CanRun.swift, Sources/App/CommandActions+NoteBirth.swift, Sources/App/VaultController+NoteBirth.swift, Sources/App/VaultController+Notes.swift, Sources/App/VaultController+Tabs.swift, Sources/App/CreationUndo.swift, Sources/Vault/NoteTab.swift, Sources/Features/Contenitore/ClassificaSheet.swift, Sources/Features/Editor/ClassificaSheet.swift, Sources/Features/Contenitore/ContenitoreView.swift, Sources/Features/Editor/ClassificaPreview.swift, Sources/Features/Editor/NewNoteComposer.swift, Sources/Features/Editor/NoteComposition.swift, Sources/Features/Editor/TemplateSheet.swift, Sources/Features/Editor/NoteTextView.swift, Sources/Features/Editor/NoteTextView+Inputs.swift, Sources/Features/Editor/CompletingTextView+SlashSelection.swift, Sources/Features/Unfiled/UnfiledPane.swift, Sources/Features/Unfiled/UnfiledListModel.swift, Sources/Features/Capture/CaptureController.swift, Tests/ShortcutTests.swift, Tests/SidebarTests.swift, Tests/QuickOpenCreationTests.swift, Tests/UnfiledListModelTests.swift, Tests/UnfiledPaneHostedTests.swift, Tests/ClassifyNoteControllerTests.swift, Tests/NoteBirthCommandTests.swift, Tests/NoteComposerHostTests.swift, Tests/DailyNoteCaretTests.swift, Tests/CaptureTemplateTests.swift, Tests/ExtractSelectionTests.swift, Tests/SlashSelectionStashTests.swift, Tests/SelectionReportHostedTests.swift, Tests/CreationUndoTests.swift
Tests: ShortcutTests.swift, SidebarTests.swift, QuickOpenCreationTests.swift, UnfiledListModelTests.swift, UnfiledPaneHostedTests.swift, ClassifyNoteControllerTests.swift, NoteBirthCommandTests.swift, NoteComposerHostTests.swift, DailyNoteCaretTests.swift, CaptureTemplateTests.swift, ExtractSelectionTests.swift, SlashSelectionStashTests.swift, SelectionReportHostedTests.swift, CreationUndoTests.swift, CommandActionTests.swift, EditorCommandTests.swift, NewNoteDraftTests.swift, ContenitoreCoreTests.swift
Signatures:
- Navigation.Pane.unfiled — case unfiled // title «Da classificare», symbol per gate M, shortcut .paneUnfiled; appended last
- Navigation.classifying — var classifying: ClassificaSheet.Subject?
- Navigation.unfiledSelection — var unfiledSelection: String?
- ShortcutCommand.paneUnfiled — case paneUnfiled // .view, «Vai a Da classificare», KeyBinding("i", [.command, .control])
- ShortcutCommand.classifyNote — case classifyNote // .file, «Classifica…», KeyBinding(""), in shipsUnbound
- ShortcutCommand.extractToNote — case extractToNote // .edit, «Estrai in una nota», KeyBinding(""), in shipsUnbound
- ShortcutCommand.takesSelection — var takesSelection: Bool { get } // true for .extractToNote only
- ClassificaSheet.Subject — enum Subject: Identifiable, Equatable { case note(String); case scheda(String); var id: String { get } }
- ClassificaSheet.init — init(subject: ClassificaSheet.Subject)
- ClassificaPreview — enum ClassificaPreview { struct Line: Equatable { let tag: Tag; let struck: Bool; let added: Bool }; static func lines(current: [Tag], result: [Tag]) -> [Line]; static func countLabel(_ count: Int) -> String }
- NoteComposition — struct NoteComposition: Equatable, Sendable { var title: String; var folder: String; var tags: [Tag]; var body: String; var bodyCaret: Int?; func blockingProblems(vocabulary: Vocabulary) -> [String] }
- NewNoteComposer.Host — enum Host: Equatable { case pane; case sheet(folder: String); case extract(VaultController.ExtractionDraft) }
- NewNoteComposer.init — init(draft: VaultController.NoteDraft, host: Host = .pane, perform: (@MainActor (NoteComposition) async throws -> String)? = nil, onCreated: @escaping (String) -> Void, onCancel: @escaping () -> Void) // nil perform = the pane host's vault.createComposedNote
- TemplateSheet.insertion — static func insertion(templateText: String, title: String, date: CalendarDate, time: TaskTime) -> (text: String, cursorBack: Int)
- VaultController.NoteDraft.tags — var tags: [Tag] = []
- VaultController.ExtractionDraft — struct ExtractionDraft: Identifiable, Equatable { let id: UUID; let tabID: NoteTab.ID; let sourcePath: String; let range: NSRange; let text: String; var title: String; var folder: String; let sourceIsDirty: Bool }
- VaultController.extraction — var extraction: ExtractionDraft?
- VaultController.createComposedNote — func createComposedNote(_ composition: NoteComposition) async throws -> String
- VaultController.offerNoteFromQuickOpen — func offerNoteFromQuickOpen(title: String)
- VaultController.classifyNote — func classifyNote(at path: String, topics: [Tag], toFolder folder: String?, savingFirst: Bool) async throws -> VaultSession.NoteClassifyOutcome
- VaultController.beginExtraction — func beginExtraction() -> Bool
- VaultController.extract — func extract(_ draft: ExtractionDraft, as composition: NoteComposition, savingFirst: Bool) async throws -> VaultSession.ExtractOutcome
- VaultController.recordSelection — func recordSelection(_ range: NSRange?, inColumn columnIndex: Int)
- VaultController.takePendingCaret — func takePendingCaret(forColumn columnIndex: Int) -> Int?
- VaultController.creationUndo — var creationUndo: CreationUndo.Offer?
- VaultController.undoCreation — func undoCreation(now: Date) async -> CreationUndo.Decision
- VaultController.openNote — func openNote(at relativePath: String, caret: Int? = nil) // existing function, parameter added in place
- VaultController.openNoteInNewTab — func openNoteInNewTab(at relativePath: String, caret: Int? = nil) // existing function, parameter added in place
- CreationUndo — enum CreationUndo { static let window: TimeInterval = 10; struct Offer: Equatable, Sendable { let path: String; let createdHash: String; let expiresAt: Date }; enum Decision: Equatable, Sendable { case trashed; case expired; case unsaved; case changed; case failed(String); var sentence: String? { get } }; static func offer(for result: VaultSession.WriteResult, at now: Date) -> Offer; static func decide(_ offer: Offer, now: Date, currentHash: String?, tabIsDirty: Bool) -> Decision }
- NoteTab.pendingCaret — var pendingCaret: Int? = nil
- NoteTab.selection — var selection: NSRange? = nil
- NoteTextView.SelectionInputs — struct SelectionInputs { var caretRequest: CaretRequest?; var onCaretApplied: () -> Void = {}; var onSelectionChanged: ((NSRange?) -> Void)?; struct CaretRequest: Equatable { let id: Int; let offset: Int } }
- NoteTextView.selection — var selection = NoteTextView.SelectionInputs()
- CompletingTextView.slashSelectionStash — var slashSelectionStash: (location: Int, text: String)? // declared, stub never set
- CompletingTextView.restoreSlashSelection — func restoreSlashSelection(replacing range: NSRange) -> Bool // stub returns false
- UnfiledListModel — enum UnfiledListModel { struct Row: Identifiable, Equatable { let id: String; let title: String; let folder: String; let date: CalendarDate?; let modifiedAt: Date?; let isScheda: Bool }; static func rows(from records: [NoteRecord], folder: String?) -> [Row]; static func folders(from records: [NoteRecord]) -> [(folder: String, count: Int)]; static func selection(after removed: String, in rows: [Row]) -> String? }
- UnfiledPane — struct UnfiledPane: View
- CaptureController.template — var template: String?
- CaptureController.Destination.takesTemplate — var takesTemplate: Bool { get }
Red: yes

This task changes every app-layer contract N4 needs, updates every call-site the build forces, and
rewrites every existing test the change makes stale, so the target builds and the old expectations
are replaced before any coder task runs. It touches no file N3 Session C touches, and not
`VaultBrowser.swift`: the composer's new parameters are defaulted, so `VaultBrowser.swift:190`
compiles unchanged.

- **Moves and generation.** `git mv Sources/Features/Contenitore/ClassificaSheet.swift
  Sources/Features/Editor/ClassificaSheet.swift`, add `Sources/Features/Unfiled/`, then
  `tuist generate --no-open` (CLAUDE.md: a move leaves the generated project stale).
- **Stubs that keep today's behaviour, so nothing regresses while red:**
  - `createComposedNote` forwards to today's `createNote(title:in:date:topics:body:)`, so the pane
    host behaves as now and `ComposerUITests`' path is unchanged;
  - `ClassificaSheet(subject: .scheda)` is today's sheet body minus the unused `actions`; `.note`
    shows a placeholder;
  - `TemplateSheet.insertion` returns today's `substituting` body with `cursorBack` 0, and `apply`
    calls it, so the sheet inserts exactly what it does now;
  - `UnfiledPane` is an empty pane; `UnfiledListModel` returns `[]`;
  - every new `VaultController` door throws, returns `false`/`nil` or `.failed("stub")`;
    `undoCreation` returns `.expired`; `recordSelection` and `takePendingCaret` do nothing;
  - `openNote(at:caret:)`/`openNoteInNewTab(at:caret:)` ignore `caret`;
  - `NoteTextView.selection` is accepted and never read.
- **Call-sites updated for the build.**
  - `ContenitoreView.swift:51`: `ClassificaSheet(subject: .scheda(item.id))`.
  - `RootView.swift:273`: an `.unfiled` arm hosting `UnfiledPane()` through `requiringVault`.
  - `Navigation.swift:48`, `:64`, `:90`: the pane's title, symbol and shortcut.
  - Every exhaustive switch in `ShortcutCommand.swift`; `CommandActions+CanRun.swift`'s `canRun`
    switch (`:30`): the two verbs answer `false`.
  - **No new command may reach an `assertionFailure` default.** `runFile` (`:199`), `runEdit`
    (`:235`) and `runView` (`:283`) get arms that forward to `runNoteBirth(_:)` in the new
    `CommandActions+NoteBirth.swift` (a no-op stub here). An assertion traps the Debug test host,
    and `CommandActionTests.switchingPaneIsTheOneActionSafeToRunWithNothingOpen` runs every pane's
    command. `.paneUnfiled` reaches the pane lookup at `CommandActions.swift:302` before the
    default, so that loop is green at once.
- **Stale tests rewritten (explained in chat first, see Gates):**
  - `ShortcutTests`: the pin becomes exactly four (`followLinkInNewTab`, `followLinkInOtherColumn`,
    `classifyNote`, `extractToNote`) under a name that says so; the collision walk now also sees
    Ctrl+Cmd+I and must still find no duplicate.
  - `QuickOpenCreationTests`: the five tests are replaced by tests of `offerNoteFromQuickOpen`
    (composer open, draft title prefilled, folder `""`, no file written, switcher closed; a parked
    draft wins and the problem is recorded, ADR-0083 §D6) and of `createComposedNote` (a taken title
    throws, its sentence lands in `problems`, no tab opens).
  - `SidebarTests`: new `unfiledSitsInLavoroRightAfterTasks`, in the shape of
    `praticheSitsInLavoroImmediatelyBeforeRecordings` (`:57`).
- **Behaviour tests.** Hosted-view tests use `Tests/HostedViewSupport.swift` and never make a window
  key or send an event. A controller test passes a temporary `stateBase`. A test that trashes uses
  the real Finder Trash on a temporary vault, as `VaultSessionFileOperationsTests` does.
  - **`UnfiledListModelTests`** (R-01): rows from records carrying `status-inbox`, a scheda with
    `isScheda`, templates and event notes included; order date newest first, then `modifiedAt`, then
    title; the folder filter and folders with counts (empty when none); `selection(after:in:)`
    returns the next row, else the previous, else nil.
  - **`UnfiledPaneHostedTests`** (R-01): three captures, one capture scheda and one classified note
    give four table rows, counted on the `NSTableView` under the pane (the
    `ContenitoreHostedViewTests` technique; identifiers are unreachable in-process); an empty vault
    gives the empty state and no rows; after `session.classifyNote` on one row and a settle, three.
  - **`ClassifyNoteControllerTests`** (R-03, R-04): `savingFirst: false` on a dirty tab is refused
    and writes nothing; `savingFirst: true` saves through `saveTab(_:)`, re-reads the tab after the
    `await`, then classifies; with a folder every tab showing the note follows the move (ADR-0067);
    `ClassificaPreview.lines` strikes `status-inbox` and marks the added topics;
    `countLabel(5)` is «5 di 7 tag».
  - **`NoteBirthCommandTests`** (R-01, R-04, R-13): `canRun(.classifyNote)` false with nothing open,
    true with a note open or a row selected in «Da classificare»; `rowCommands` contains
    `.classifyNote`; File «Classifica…» sets `navigation.classifying` to the selected row's subject
    when «Da classificare» is in front (`.scheda` for a scheda row), sets `contenitore.classifying`
    when the Contenitore is in front (ADR-0071 §D12's redirect), and otherwise `.note(open note)`;
    `run(.paneUnfiled)` shows the pane; `canRun(.extractToNote)` follows the focused tab's
    `selection`.
  - **`NoteComposerHostTests`** (R-11, R-12): the composition from a draft carries the tags and the
    resolved template body and caret; `.sheet(folder:)` fixes the folder; `.extract` hides the
    template and proposes `CaptureTitle.derive` of the first line; a closed-family violation or a
    `type-*` makes `blockingProblems` non-empty; `createComposedNote` opens a new tab whose
    `pendingCaret` is the absolute caret and sets `creationUndo`; hosted: the composer builds in all
    three hosts, and in `.sheet` its fitting width is at most the sheet's 520 pt.
  - **`DailyNoteCaretTests`** (R-06, R-08): with a `dailyTemplate`, `openDailyNote` sets the new
    tab's `pendingCaret` to the birth's caret; reopening the day sets none; `takePendingCaret`
    returns it once, for its own column only, and clears it; `TemplateSheet.insertion` carries
    `Resolved.cursorBack`, and 0 for a template without a marker.
  - **`CaptureTemplateTests`** (R-09): `Destination.takesTemplate` is true for `.note` only; the
    controller passes its template to `VaultAPI.capture` and the note holds the text at the marker;
    switching to «Task» drops the template from the call.
  - **`ExtractSelectionTests`** (R-13, R-14): `beginExtraction` with a tab `selection` builds a
    draft (source folder, title from `CaptureTitle`, `sourceIsDirty`); no selection, `false`;
    `extract(…, savingFirst: true)` on a dirty tab saves, re-reads the tab after the `await`, and
    refuses when the text at the range changed in between; a clean run leaves the source tab showing
    `[[Titolo]]` with no conflict prompt and the new note not opened; the half-done outcome reaches
    the caller unthrown.
  - **`SlashSelectionStashTests`** (R-13): a hosted `CompletingTextView` driven by `insertText` and
    `setSelectedRange`, not events: `/` typed over a selection stashes it; `restoreSlashSelection`
    puts the text back over `/prefix` and reselects it; accepting another command or dismissing
    drops the stash; `/` with no selection stashes nothing; the slash candidates include «Estrai in
    una nota» only while a stash exists (filtered in the text view, so
    `EditorCommandTests:152`'s count holds).
  - **`SelectionReportHostedTests`** (R-13): a hosted `NoteTextView` reports a non-empty selection
    once per change and nil once when it collapses; moving a bare caret, and typing with one, report
    nothing; a `caretRequest` places the caret at its offset once and calls `onCaretApplied`.
  - **`CreationUndoTests`** (R-16): pure, an offer is live at 9.9 s and expired at 10 s; `decide`
    gives `.unsaved` for a dirty tab, `.changed` for a moved hash, else `.trashed`; controller,
    `undoCreation` within the window trashes the file, forgets its note id (`lookUpNote(id:)` is
    `unknown`) and closes the clean tab; after the window `.expired` and the file stays; a second
    creation replaces the offer; hosted, the strip's fitting height is the same with and without a
    refusal sentence.
- **Expected reds after this task:** `SidebarTests.everyPaneHasExactlyOneRow` and the new placement
  test, and the new behaviour tests above. Nothing else may go red: run the whole `PergamenumTests`
  suite and report anything beyond these.

### Task 5 — The «Da classificare» pane and «Classifica…» on notes (R-01, R-02, R-03, R-04)
Owner: coder
Files: Sources/Features/Unfiled/UnfiledPane.swift, Sources/Features/Unfiled/UnfiledListModel.swift, Sources/Features/Unfiled/UnfiledRow.swift, Sources/App/SidebarItem.swift, Sources/App/Navigation.swift, Sources/App/RootView+Sheets.swift, Sources/App/CommandActions.swift, Sources/App/CommandActions+CanRun.swift, Sources/App/CommandActions+NoteBirth.swift, Sources/App/MenuCommands.swift, Sources/App/VaultController+NoteBirth.swift, Sources/Features/Editor/ClassificaSheet.swift, Sources/Features/Editor/ClassificaPreview.swift, Sources/Features/Editor/NoteRowMenu.swift, Sources/Features/DesignGallery/MockupGalleryView.swift, docs/20260811_Pergamenum_SpecApp.md
Tests: UnfiledListModelTests.swift, UnfiledPaneHostedTests.swift, ClassifyNoteControllerTests.swift, NoteBirthCommandTests.swift, SidebarTests.swift, CommandActionTests.swift, ShortcutTests.swift, ContenitoreCoreTests.swift, ContenitoreEditorTests.swift, ContenitoreHostedViewTests.swift
Signatures:
- UnfiledRow — struct UnfiledRow: View
Red: no

- **The pane** (ADR-0085 §D1, §D2), with the layout, badge and symbol gate M approved.
  - `List(selection: $navigation.unfiledSelection)` with flat rows (ADR-0024); a `.badge`, if
    adopted, goes before `.tag`.
  - A `@FocusState` bound with `.focused(_:)`, set on appear and on selection change, used as a
    setter and never as a guard (ADR-0070), so Ctrl+Cmd+I then Down moves in the list.
  - Return opens the sheet through `navigation.classifying`. Do not assume the route: ADR-0070
    measured that a focused table sends Backspace down an AppKit command rather than as a key press,
    and Return may likewise arrive as `insertNewline:`. Use whichever route a real key window
    delivers, and let the GUI test prove it. A double click opens the note; no delete key and no
    delete verb (SPEC Out of scope).
  - One row-level `.contextMenu`: «Classifica…», «Apri», «Apri in una nuova tab», «Mostra nel
    Finder», plus «Mostra nel Contenitore» on a scheda row. No nested menu (ADR-0069).
  - The folder filter hides when there are no folders; rows read `vault.index` per generation, never
    cached (principle 3).
  - After a filing, the selection becomes `UnfiledListModel.selection(after:in:)`.
  - Identifiers for the GUI test: `unfiled-pane`, `unfiled-row`, `unfiled-folder-filter`.
- **The sheet** (ADR-0085 §D5).
  - `.note(path)`: topics through `TagEntry` with vocabulary completion and the refusal sentence, an
    optional folder picker over `vault.folders`, the preview through `ClassificaPreview`, «N di 7
    tag». Identifiers `note-classifica-topic`, `note-classifica-folder`, `note-classifica-confirm`.
  - On a dirty note the confirm reads «Salva e classifica» (G2). It calls
    `VaultController.classifyNote(…, savingFirst:)`, which saves the dirty tabs showing the path
    through `saveTab(_:)`, re-reads them after the `await` (ADR-0043 §D7), asks `canOperate(on:)`,
    then calls the session door. A `moveProblem` is shown in the sheet before it closes.
  - `.scheda(path)`: today's behaviour and `contenitore-classifica-*` identifiers, through the
    unchanged `ContenitoreInspectorModel.classify`.
  - `RootView+Sheets.swift` presents `navigation.classifying` for both subjects; the Contenitore
    keeps presenting its own from `contenitore.classifying`.
- **The commands** (ADR-0085 §D6). `.classifyNote` joins `rowCommands`; `CommandActions+NoteBirth.swift`
  routes: «Da classificare» in front (selected row), then the Contenitore (its selection), then the
  open note. File «Classifica…» beside «Applica un template…» (`MenuCommands.swift:122`);
  `NoteRowMenu` gets the row command beside `rowCommand(.applyTemplate)` (`:55`). The slash entry
  needs no code.
- **Sidebar.** LAVORO gains `.pane(.unfiled)` right after `.pane(.tasks)` (`SidebarItem.swift:93`).
- **Mockup label.** `MockupGalleryView.swift`'s `noteBirth` page becomes «N4, approvato».
- **SPEC (app).** Dated notes in §7.4 and §10 (File «Classifica…», Vista «Vai a Da classificare»)
  per ADR-0085 §D12, bodies untouched.
- **Verify.** Measure Ctrl+Cmd+I against `com.apple.symbolichotkeys`, as every default since
  ADR-0021 was, and report the result.

### Task 6 — Templates in the app, one composer in its hosts, the tag field, the capture menu, the setting and the creation toast (R-06, R-07, R-08, R-09, R-11, R-12, R-16)
Owner: coder
Files: Sources/Features/Editor/NewNoteComposer.swift, Sources/Features/Editor/NewNoteComposer+Tags.swift, Sources/Features/Editor/NoteComposition.swift, Sources/Features/Editor/VaultBrowser.swift, Sources/Features/Editor/VaultBrowser+NoteBirth.swift, Sources/Features/Editor/CreationUndoStrip.swift, Sources/Features/Editor/QuickSwitcher.swift, Sources/Features/Editor/EditorColumnView.swift, Sources/Features/Editor/EditorColumn+Text.swift, Sources/Features/Editor/NoteTextView+Update.swift, Sources/Features/Editor/NoteTextView+Requests.swift, Sources/Features/Editor/TemplateSheet.swift, Sources/App/CreationUndo.swift, Sources/App/VaultController.swift, Sources/App/VaultController+Notes.swift, Sources/App/VaultController+NoteBirth.swift, Sources/App/VaultController+Tabs.swift, Sources/App/VaultController+Settings.swift, Sources/Vault/NoteTab.swift, Sources/Features/Workspace/WorkspaceView+Creation.swift, Sources/Features/Workspace/BoardSheets.swift, Sources/Features/Workspace/WorkspaceController+Tools.swift, Sources/Features/Capture/CaptureController.swift, Sources/Features/Capture/CapturePanelView.swift, Sources/Features/Capture/CaptureTemplateMenu.swift, Sources/Features/Settings/SettingsView.swift, Sources/Features/Settings/DailyTemplateField.swift, docs/20260811_Pergamenum_SpecApp.md
Tests: NoteComposerHostTests.swift, DailyNoteCaretTests.swift, CaptureTemplateTests.swift, CreationUndoTests.swift, QuickOpenCreationTests.swift, SelectionReportHostedTests.swift, NewNoteDraftTests.swift, NoteTemplateTests.swift, WorkspaceDocumentCreationTests.swift, WorkspaceControllerTests.swift, CapturePanelTests.swift, VaultTests.swift
Signatures:
- CreationUndoStrip — struct CreationUndoStrip: View
- NoteBirthPresentation — struct NoteBirthPresentation: ViewModifier // VaultBrowser+NoteBirth.swift: the toast overlay now, the extract sheet in Task 7
- WorkspaceController.TapBehaviour.composeDocument — case composeDocument
- DailyTemplateField — struct DailyTemplateField: View
- CaptureTemplateMenu — struct CaptureTemplateMenu: View
Red: no

Starts after Session C's PR is merged into this branch (`VaultBrowser.swift`).

- **The composer** (ADR-0085 §D7). It composes a `NoteComposition` and calls `perform`, or
  `vault.createComposedNote` when the host passes none. The tag field moves into
  `NewNoteComposer+Tags.swift` (the view is 225 lines): chips, `TagEntry` completion and refusal,
  `client-`/`project-` chips from `index.tagUsage()` via `TagEntry.completions`. «Crea» is disabled
  while `blockingProblems` is non-empty. The pane host keeps `new-note-title`, `new-note-folder`,
  `new-note-template` and parks drafts; the sheet host shows the folder as a fixed label and parks
  nothing. Preview and body go through `NoteTemplate.resolve`. `NoteDraft.topic` stays as the text
  being typed (`NewNoteDraftTests` unchanged).
- **Its entries.**
  - Cmd+N and «Nuova nota qui»: unchanged, now through `createComposedNote`.
  - Quick Open's `.createNote(title)` (`VaultBrowser.swift:72-78`) calls
    `vault.offerNoteFromQuickOpen(title:)`, which calls `offerNoteCreation(title:besideNoteAt: nil)`
    and closes the switcher. `createNoteFromQuickOpen`, `quickSwitcherProblem`
    (`VaultController.swift:95-96`) and `QuickSwitcher.swift:62`, `:68`, `:77` are deleted, now
    that nothing sets the sentence.
  - Workspace «Documento»: the `.document` tool maps to `.composeDocument`
    (`WorkspaceController+Tools.swift:99`); `WorkspaceView+Creation.swift` hosts
    `NewNoteComposer(host: .sheet(folder: boardFolder), perform: …)` whose `perform` keeps N1's
    behaviour (`workspace.createDocument(titled:at:through:)`, the card placed, no tab) and whose
    confirmation reuses `NewCanvasItemSheet.Phase`/`confirmation(after:title:)`, so
    `WorkspaceDocumentCreationTests` stays unmodified. `NewCanvasItemSheet.Kind` loses `.note`.
- **Templates in the app** (ADR-0086).
  - `createComposedNote` writes, then `openNoteInNewTab(at:caret:)` with
    `Resolved.caret(inWritten:)`, then rescans, then sets `creationUndo` (pane host only).
  - `openDailyNote` calls `session.dailyNoteBirth(for:at:)` and passes the caret only when
    `created`.
  - **Caret consumption.** `EditorColumnView` watches the tab's `pendingCaret` with
    `.onChange(…, initial: true)` (the `editorFocusRequest` shape at `:170`) and, when
    `takePendingCaret(forColumn:)` answers, hands `NoteTextView.selection.caretRequest` an offset;
    `NoteTextView+Update.swift`'s `consumeOneShots` claims it once (`RequestLedger.claimCaret`) and
    calls `coordinator.scroll(textView, to: NSRange(location: offset, length: 0))`, which places the
    caret and takes the keyboard. The Oggi pane's embedded editor passes no request (ADR-0086 §D4).
  - `TemplateSheet.insertion` resolves through `NoteTemplate.resolve` and returns
    `Resolved.cursorBack` (0 without a marker); `apply` passes it to
    `Navigation.insert(_:cursorBack:)`.
  - Impostazioni › Convenzioni gains «Modello della nota del giorno» (`DailyTemplateField`,
    `vault.templates` plus «Nessuno»), written through `VaultController+Settings.swift`.
  - The capture panel shows `CaptureTemplateMenu` under «Nota nuova» only (`capture-template`, the
    `capture-folder` popover shape at `CapturePanelView.swift:120`), remembered with the last
    destination; `CaptureController` passes it to `VaultAPI.capture(…, template:)`.
- **The toast** (ADR-0085 §D9). `CreationUndoStrip` is an `.overlay(alignment: .bottom)` on
  `VaultBrowser.editor` (`:187-199`), applied through `NoteBirthPresentation`: constant height, its
  refusal sentence inside the same height, tokens only, never a layout row above the `HSplitView`
  (ADR-0075). A `.task(id: offer)` clears it at `expiresAt`. «Annulla» calls `undoCreation(now:)`,
  which re-reads the tab and the hash after any `await`, then `VaultController.trashNote(at:)`. No
  other creation path sets the offer.
- **SPEC (app).** Dated notes in §8.1, §12 (Convenzioni; the quick switcher's «crea nota chiamata
  X» now opens the composer) and §16, per ADR-0085 §D12 and ADR-0086 §D9.

### Task 7 — «Estrai in una nota» (R-13, R-14)
Owner: coder
Files: Sources/Features/Editor/CompletingTextView+SlashSelection.swift, Sources/Features/Editor/CompletingTextView.swift, Sources/Features/Editor/NoteTextView+SelectionReport.swift, Sources/Features/Editor/NoteTextView+Coordinator.swift, Sources/Features/Editor/NoteTextView+Requests.swift, Sources/Features/Editor/EditorColumn+Text.swift, Sources/Features/Editor/NewNoteComposer.swift, Sources/Features/Editor/VaultBrowser+NoteBirth.swift, Sources/App/VaultController+NoteBirth.swift, Sources/App/CommandActions+NoteBirth.swift, Sources/App/CommandActions+CanRun.swift, Sources/App/MenuCommands.swift, docs/20260811_Pergamenum_SpecApp.md
Tests: ExtractSelectionTests.swift, SlashSelectionStashTests.swift, SelectionReportHostedTests.swift, NoteBirthCommandTests.swift, EditorCommandTests.swift, NoteExtractionTests.swift, NoteBirthSessionTests.swift, EditorRestyleBudgetTests.swift
Signatures:
- NoteTextView.Coordinator.reportSelection — func reportSelection(in textView: NSTextView)
- RequestLedger.claimSelection — func claimSelection(_ range: NSRange?) -> Bool
Red: no

Starts after Session C's PR is merged into this branch (the extract sheet rides on
`VaultBrowser+NoteBirth.swift`, applied to `VaultBrowser` in Task 6).

- **The selection report** (ADR-0085 §D8). One line in `textViewDidChangeSelection`
  (`NoteTextView+Coordinator.swift:190`) calls `reportSelection(in:)`, whose body is in the new
  `NoteTextView+SelectionReport.swift`: nil for an empty selection, reported only when
  `requests.claimSelection` says it changed, so typing with a bare caret writes nothing (O(1), the
  PG-401 budget). `EditorColumn+Text.swift`'s `editing(_:)` wires
  `selection.onSelectionChanged` to `vault.recordSelection(_:inColumn:)`, never through
  `CommandActions+LinkNavigation.swift` (Session C's file).
- **The slash stash.** In `CompletingTextView+SlashSelection.swift`, an
  `override func insertText(_:replacementRange:)` that stashes only when the string is `/` and the
  selection is non-empty (one comparison per insertion). The `.app` branch of the slash `apply(_:)`
  (`CompletingTextView.swift:335`) calls `restoreSlashSelection(replacing:)` before `onRunCommand`
  when `takesSelection` is true, and drops the stash otherwise and on dismissal; the candidate
  filter in `refreshCompletion` (`:235-237`) drops `takesSelection` entries without a stash.
  `CompletingTextView+Pasteboard.swift` is protected and is not touched.
- **The command.** `.extractToNote` runs `beginExtraction()`, which fills `vault.extraction` from
  the focused tab's `selection` and buffer. `NoteBirthPresentation` presents it as a sheet with
  `NewNoteComposer(host: .extract(draft), perform: …)`, whose `perform` calls
  `vault.extract(_:as:savingFirst:)`.
- **The sheet.** On a dirty source the confirm reads «Salva ed estrai» and says the note is saved
  first (G2); the door saves through `saveTab(_:)`, re-reads the tab after the `await`, and checks
  the text is still at the range. The half-done outcome keeps the sheet open naming both results
  with «Chiudi». No toast. Afterwards the source stays in front, its tab adopts the landed text
  through ADR-0067's door, and the new note is not opened.
- **Menu and SPEC (app).** Modifica gains «Estrai in una nota» beside the find group
  (`MenuCommands.swift:323-330`), disabled by `canRun`. Dated note in SPEC (app) §10 Modifica.

### Task 8 — Two GUI tests, the UI-suite mapping, the full verification and the ship record (R-01, R-03, R-06, R-08, R-17, R-18)
Owner: tester
Files: UITests/NoteBirthUITests.swift, scripts/uitests.sh
Tests: NoteBirthUITests.swift
Signatures:
- NoteBirthUITests — final class NoteBirthUITests: PergamenumUITestCase
Red: no

`UITests/NoteBirthUITests.swift` subclasses `PergamenumUITestCase`, makes its vault with
`makeTemporaryVault(prefix:)`, launches with `launchApp(extraArguments:)`, sets no isolation flag
of its own and finds every control by identifier, never by its words
(`UITestLaunchHarnessGuardTests` enforces the harness). These are the only two GUI tests N4 adds
(R-17, counted at review): each covers a link only a real key window shows (a menu shortcut reaching
a pane, a list's keyboard focus, a sheet over a key window, the first key landing at the caret).

- **`testFilingACaptureFromDaClassificare`** (ADR-0085 §D11; R-01, R-03).
  - Seed `00 Inbox/Idea.md` with `type-note` and `status-inbox`, and an empty `03 Risorse/`.
  - Ctrl+Cmd+I, Down, Return; type `materiali` into `note-classifica-topic`, choose `03 Risorse` in
    `note-classifica-folder`, press `note-classifica-confirm`.
  - On the file: `03 Risorse/Idea.md` exists, its frontmatter holds `topic-materiali` and no
    `status-inbox`, `00 Inbox/Idea.md` is gone; the pane shows no `unfiled-row`.
- **`testTheDailyTemplatePlacesTheCaret`** (ADR-0086 §D8; R-06, R-08).
  - Seed `Templates/Giornata.md` (`## {{time}}`, blank, `{{cursor}}`, blank, `## Note`) and merge
    `dailyTemplate` into `.pergamenum/settings.json`.
  - Cmd+Shift+D, type `Primo appunto`, Cmd+S.
  - On the file: the text sits on the `{{cursor}}` line between the two headings, a
    `## \d{2}:\d{2}` heading exists, no placeholder remains.
- **`scripts/uitests.sh`.** In `classes_for_path` (`:163-183`), before the `*` arm,
  `Sources/Features/Unfiled/*|Sources/Core/Conventions/NoteClassification.swift` maps to
  `NoteBirthUITests`. `NoteTemplate.swift`, `TagEntry.swift` and `NoteExtraction.swift` stay on
  `ALL`: the composer and the template sheet reach other classes. Two `expect_eq` lines in the
  self-test, in the shape of `:978-989`; run `scripts/uitests.sh --self-test`.
- **Verification, in order.**
  1. The three builds (app, `perg`, `pergamenum-mcp`) and `scripts/mcp-smoke.py` (R-18).
  2. The whole `PergamenumTests` suite through `.claude/test-cmd`.
  3. `scripts/pg-401-gates.sh` (Release, its own DerivedData): the editor gained the selection
     report and the slash stash; a moved row is a regression, not noise. Use #978's ceilings if it
     has merged, the script's defaults otherwise.
  4. `scripts/uitests.sh --status`, then the two new tests by name:
     `scripts/uitests.sh NoteBirthUITests`. A red is diagnosed from its `.xcresult` before any rerun.
  5. At merge, `--affected`: this branch touches `Sources/App` and `Sources/Features/Editor`, which
     map to `ALL`, so expect the whole GUI suite (about 25 minutes, advisory, the CLAUDE.md merge
     gate).
- **Ship record (R-18), for the orchestrator and Stefano at `/ship`.**
  - The code PR follows the merged mockup PR and closes #889 and `PG-387`.
  - `PG-121` closes as superseded with a pointer to ADR-0086 §D7; the `PG-387` ledger line's
    "PG-121's engine stays deferred" (`TODO.md:11`) is corrected.
  - ADR numbers re-checked against `origin/main`. ADR-0085 and ADR-0086 gain implementation notes
    (the gate M variants, the nine corrections listed under "SPEC wins" above, gate G-S's answer),
    their «Source» lines are repointed, and their status flips to `accepted` once the code PR is
    merged (`docs/adr/README.md`).
  - `docs/adr/INDEX.md` and the CLAUDE.md chain index gain both entries; neither lists them today.

## Risks & HITL gates

- **N3 Session C.** Tasks 6-7 edit `VaultBrowser.swift`, which Session C restructures. They wait for
  its PR; N4's bulk lives in `VaultBrowser+NoteBirth.swift` so the edit there is two or three lines.
  If Session C names its inspector types differently than its plan, nothing here changes: N4 reads
  none of them.
- **The `assertionFailure` trap.** A new command reaching a section's default kills the Debug test
  host. Task 4 adds the arms before any test runs them.
- **Protected surfaces untouched.** `CompletingTextView+Pasteboard.swift`, `IndexCache.schemaVersion`
  (no change), `VaultPayloads.swift`'s `LintFinding`/`PraticaSummary`, `ContenitoreScheda.render`,
  `ImportNaming.recordingNoteTitle`, `VaultBoundary.url(for:)`.
- **Behaviour widened on purpose, named in the ADRs.** The event note's day and the Pratiche diary
  mirror get the daily template when they create the day (ADR-0086 §D3); templates and event notes
  carrying `status-inbox` appear in the pane; a date-shaped topic is now refused on a scheda too
  (R-02's one rule).
- **The slash path's ordering.** `restoreSlashSelection` must reach the tab's buffer and `selection`
  before `onRunCommand` reads them. If the binding or the report is deferred, `beginExtraction`
  reads stale state. `SlashSelectionStashTests` and `ExtractSelectionTests` pin it; if it fails,
  pass the restored range and text through the command rather than re-reading the tab.
- **Return in the pane.** A focused macOS table may deliver Return as a command, not a key press
  (the ADR-0070 lesson for Backspace). Task 5 does not assume the route; the GUI test is the proof.
- **Keystroke budget (PG-401, PR #978).** Both editor additions are O(1) and write nothing on a bare
  caret. `scripts/pg-401-gates.sh` runs in Task 8.
- **File length.** `ShortcutCommand.swift` (400 lines) passes SwiftLint's 400-line warning with the
  three cases (warning only, the cases cannot leave the enum); `CommandActions.swift` (399),
  `VaultController+Tabs.swift` (412), `ToolCatalogue+Writing.swift` (400), `WriteCommands.swift`,
  `NewNoteComposer.swift`, `SettingsView.swift` and `CapturePanelView.swift` get their new code in
  the new `+NoteBirth`/`+Tags` files and the new views named above.
- **Project generation.** `VaultSession+NoteBirth.swift` in `sharedSources`, the `ClassificaSheet`
  move and `Sources/Features/Unfiled/` each need `tuist generate --no-open`; both tool builds must
  pass (R-18).
- **Toast race.** A write between the hash check and the trash is trashed with the note (ADR-0085
  §D9 residual); it goes to the Finder Trash, so it is recoverable.
- **Tests and the Trash.** Controller tests that trash use the real Finder Trash on temporary vaults.
- **External resources: none.** Fully offline; no dependency, port, consent flow, cloud console or
  environment variable is needed before `/build`.
- **HITL:**
  - at plan approval: G-N3C, G-S, and the two test changes explained in chat (ShortcutTests pin,
    QuickOpenCreationTests);
  - gate M on the Debug build before Task 4, the mockup PR's commit, push and merge;
  - the code PR's commit, push and merge are Stefano's;
  - no schema change; no deletion beyond the person's own «Annulla», which goes to the Trash;
  - flipping ADR-0085 and ADR-0086 to `accepted` after the code PR merges.

TEST-CMD CANDIDATE: xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -only-testing:PergamenumTests test
TEST-CMD MODE: brownfield

CHECK-CMD CANDIDATE: NONE

## Build result (2026-10-12)

BUILD · DONE WITH WARNINGS
Files: 113 (65 modified, 48 new)
Tests: 6561 passed in 381 suites, 5 known issues (PergamenumTests)
Review: sonnet, safe; opus, safe
Coverage: no UNCOVERED R-id; STALE-WAIVER R-17, R-18 (the (no-test:) clauses protect nothing, delete them from SPEC.md)
Dropped: 8 (fix-hunk 3, post-sweep 5)
Dispatch: Round 0 (red): tester — Task 2, tester — Task 4; Round 1: debugger — selection ledger, debugger — capture template menu, coder — composer length; Round 2: debugger — same-path two-tab selection, debugger — capture template resolver, coder — bare-caret test; Round 3 (sweep): debugger — outline entry and caret request, coder — five NITs and three follow-ups; Round 4 (sweep): coder — caret-request coverage, ADR citations, wrapped signature, CompletingTextView move; Round 5 (sweep, beyond the cap by the human's answer): coder — creationUndo and extraction reset, ADR citations, two NITs
INFO: review escalated, size: 110 changed files, threshold 20
WARN: round 5 (the creationUndo and extraction reset with its test, plus comment edits) was not re-reviewed: the review cap was reached and the human asked for the fix without a further round
WARN: the «N4, approvato» label (NoteBirthMockup.swift:9, pinned by MockupGalleryLayoutTests.swift:94) was left as is; gate M was skipped by the person's choice, so confirm the label at the merge gate or set it back to «da approvare»
WARN: unverified follow-up, low confidence: Sources/App/Navigation.swift:132, navigation.classifying (the «Classifica…» sheet's note path) is not reset on a vault switch; check whether a switch can run while that sheet is open
WARN: NoteBirthUITests.testTheDailyTemplatePlacesTheCaret red in a GUI run contaminated by focus-taken (external monitor, Mail, Kepler, ChatGPT); the same test passed in an earlier contaminated run; no verdict recorded
WARN: scripts/pg-401-gates.sh exit 1 on its default ceilings (1024KB-fences 68.82 ms, 1024KB-prose 67.34 ms CPU, default 20 ms); within PR #978's ceilings; no main baseline measured in this worktree
WARN: STALE-WAIVER R-17, R-18

```text
DROP	fix-hunk	**MINOR** [other] Tests/SelectionReportHostedTests.swift:212 — test could assert on reports (follow-up: coder)
DROP	fix-hunk	**MINOR** [other] Sources/Vault/NoteTab.swift:36 — explicit = nil on pendingCaret and selection (follow-up: coder)
DROP	fix-hunk	**MINOR** [other] Tests/SelectionReportHostedTests.swift:439 — aClearedCaretRequestDoesNotReplayOnARebuiltView gets a nil request only from the harness flag and asserts a selection any fresh view also has; the column's caretRequestCount rule stays untested through hand-numbered ids. Fix: reword the comments to claim only the ledger and view contract, or test the column. (reviewer: sonnet)
DROP	post-sweep	**MINOR** [other] scripts/uitests.sh:1 — GUI test cap message already exceeded before N4 (follow-up: tester)
DROP	post-sweep	**MINOR** [other] Sources/Core/Shortcuts/ShortcutCommand.swift:425 — file_length 425 over 400 (follow-up: coder)
DROP	post-sweep	**MINOR** [other] Sources/App/VaultController.swift:458 — file_length 458 over 400, 455 on main (follow-up: coder)
DROP	post-sweep	**MINOR** [other] scripts/uitests.sh:394 — 35 GUI tests against a cap of 17, 33 on main (follow-up: coder)
DROP	post-sweep	**MINOR** [plan-deviation] Sources/Features/DesignGallery/NoteBirthMockup.swift:9 — Gate M (separate mockup PR, variants approved before Task 4) was skipped by the person's choice, yet the gallery label and MockupGalleryLayoutTests.swift:94 assert N4, approvato. Fix: confirm the claim at the merge gate or revert the label to da approvare. (reviewer: opus)
FIX	swept	**NIT** Sources/Core/Conventions/NoteClassification.swift:12-21 — classify takes a vocabulary parameter it never reads (reviewer: opus)
FIX	swept	**NIT** Sources/Core/Conventions/NoteTemplate.swift:54-58 — substituting doc comment says kept for callers, only tests remain (reviewer: opus)
FIX	swept	**NIT** UITests/NoteBirthUITests.swift:145-147 — three consecutive blank lines (reviewer: opus)
FIX	swept	**MINOR** [other] Sources/Core/Conventions/NoteTemplate.swift:121 — signature of 121 characters (follow-up: coder)
FIX	swept	**NIT** Sources/App/VaultController+NoteBirth.swift:73 — line of 121 characters (reviewer: opus)
FIX	swept	**NIT** Sources/Vault/NoteTab.swift:38 — selection report cited as ADR-0085 §D4, is §D8 (reviewer: opus)
FIX	swept	**MINOR** [wrong-behaviour] Sources/Features/Editor/EditorColumn+Text.swift:80-83 — SelectionInputs omits onCaretApplied, stale caretRequest replayed (reviewer: opus)
FIX	swept	**MINOR** [wrong-behaviour] Sources/Features/Editor/NoteTextView+Requests.swift:101-105 — lastOutlineEntry not reset on a same-note tab switch (reviewer: opus)
FIX	swept	**MINOR** [other] Sources/Features/Unfiled/UnfiledPane.swift:36 — line of 121 characters (follow-up: debugger)
FIX	swept	**MINOR** [other] UITests/NoteBirthUITests.swift:136 — two stray blank lines before // MARK: Support (follow-up: debugger)
FIX	swept	**NIT** Sources/Core/Shortcuts/ShortcutCommand.swift:419-420 — comments cite §D3/§D4 for extractToNote and dailyNoteBirth (reviewer: sonnet, opus)
FIX	swept	**MINOR** [other] Sources/Features/Editor/CompletingTextView.swift:412 — file_length 412 over 400 (follow-up: coder)
FIX	swept	**MINOR** [style] Sources/App/CreationUndo.swift:3 — The creation toast is cited as ADR-0086 §D7 in eight files, but that section is PG-121's engine superseded; the toast is ADR-0085 §D9. Fix: repoint all eight citations to ADR-0085 §D9. (reviewer: sonnet, opus)
FIX	swept	**MINOR** [style] Sources/Features/Editor/ClassificaSheet.swift:14 — ADR-0085 section mismatches left by the sweep: sheet and preview are §D5 not §D3 (ClassificaSheet.swift:14, Navigation.swift:129, RootView+Sheets.swift:41, ClassificaPreview.swift:3); Quick Open create row is §D7 not §D5 (VaultBrowser.swift:67, QuickOpenCreationTests.swift:5); the unbound verbs are §D6/§D8 not §D3/§D4 (ShortcutTests.swift:84 and 375, NoteBirthCommandTests.swift:5). (reviewer: sonnet, opus)
FIX	swept	**MINOR** [style] Tests/NoteTemplateTests.swift:272 — ADR-0086 §D2 cited for template references and connectors, which are §D6 (also scripts/mcp-smoke.py:530, NoteBirthConnectorTests.swift:5, NewNoteComposer.swift:210 where the preview resolve is §D5 not §D4, CaptureTemplateTests.swift:5 where the capture menu is §D5 not §D6). (reviewer: sonnet, opus)
FIX	swept	**NIT** Sources/App/CommandActions.swift:131 — Doc comment still says three commands a note row may run but rowCommands now holds four. (reviewer: sonnet)
FIX	swept	**NIT** Sources/Features/DesignGallery/NoteBirthMockup.swift:28 — The mockup's toastHeight is 28 while the built CreationUndoStrip.height is 32. (reviewer: opus)
FIX	swept	**MAJOR** [wrong-behaviour] Sources/App/VaultController+VaultSwitch.swift:91-95 — A vault switch and close() clear every other path-naming transient but not creationUndo and extraction, so an offer or extract draft from the old folder resolves against the new session. Fix: set both to nil in switchVault's reset block and in close(). (reviewer: opus)
```
