**Requirement set:** `SPEC.md`

# Plan: N4, the birth of a note (R-29..R-34)

- **SPEC:** root `SPEC.md` (Approved 2026-10-04), milestone N4, issue #889, ledger `PG-387`. It
  is the authority for scope.
- **ADRs:** both `proposed`.
  - `docs/adr/0085-a-da-classificare-pane-for-notes-and-one-composer.md`: the pane, «Classifica»,
    one composer, «Estrai», the toast.
  - `docs/adr/0086-templates-where-notes-are-born.md`: the daily template, `{{time}}`/`{{cursor}}`,
    template choice, `--template`.
  - Recheck both numbers against `origin/main` right before merge (`docs/adr/README.md` rule 1).
- **Depends on N1**, planned in `docs/plans/note-workflow-n1.md`:
  - **the rule** (ADR-0080 §D1): every note born with no `topic-*` tag carries `status-inbox`,
    daily note excepted, decided in `TagRules.initialTags(for:topics:)` on the namespace. The «Da
    classificare» pane lists what this rule produces, and the composer's tag chips rely on its
    namespace test;
  - **the inbox-folder setting** (ADR-0080 §D6): `VaultSettings.inboxFolder`, default `00 Inbox`,
    resolved by `VaultSession.inboxFolder`;
  - `CaptureTitle.derive(fromTypedLine:now:calendar:)` (ADR-0080 §D3), which titles «Estrai» and a
    templated capture.
- **Depends on N3** (ADR-0083), because N4 ships after it:
  - unbound catalogue commands (`KeyBinding("")`, allow-listed in `ShortcutCommand.shipsUnbound`,
    §D3);
  - `VaultController.offerNoteCreation(title:besideNoteAt:)`, the composer's prefill entry (§D6);
  - the selection-change report path beside `recordLinkAtCaret` (§D3).
- **Before Task 1:**
  - `rg -n 'shipsUnbound|offerNoteCreation|CaptureTitle|inboxFolder|recordLinkAtCaret' Sources` on
    the base must find all five names.
  - A missing name is not invented here. Stop and report it: the plan rests on N1 and N3 being
    merged.
- **Mockup first:** `docs/plans/note-workflow-n4-mockup.md`, gate M, approved on the Debug build
  before Task 1 starts (SPEC Decisions, R-44). The variants chosen there are inputs to Task 5 and
  Task 6.
- **Base:** `48a2d912` for every line number below. Delivery is one PR (R-44).

## SPEC decisions registered, not reopened

- The pane is «Da classificare» in LAVORO, on Ctrl+Cmd+I, never «Inbox».
- «Classifica» works on any note, from four surfaces, and the connectors expose it.
- The composer is the one naming surface, with three entry points.
- «Estrai» writes twice, and the second write is guarded.
- Templates gain `{{time}}` and `{{cursor}}`, plus a daily-template setting and `--template`.
  `PG-121` closes as superseded.
- Creation undo is a 10-second toast, not the journal.
- At most two GUI tests: filing a capture, and the daily template.

## Gates carried by the ADRs (answer at plan approval)

- **G1** (ADR-0085): Contenitore schede carrying `status-inbox` are listed and classified through
  the scheda form. Recommended, as the literal R-29. Alternative: excluded, with a footer link.
- **G2** (ADR-0085): on a dirty note, «Salva e classifica» and «Salva ed estrai» save first as part
  of the confirmation. Recommended. Alternatives: refuse, or for «Estrai» only, a buffer edit plus a
  save.
- **G3** (ADR-0085): the toast follows the pane-host composer only, with six named exclusions.
  Recommended. Alternative: the Workspace too, removing the card.

## Contract changes and their call-sites

Each list below was found with `rg -n` on the base.

| Contract | Call-sites found | Handled in |
| --- | --- | --- |
| `NewNoteComposer(draft:onCreated:onCancel:)` | `Sources/Features/Editor/VaultBrowser.swift:184` | Task 3 |
| `ClassificaSheet(schedaPath:actions:)` | `Sources/Features/Contenitore/ContenitoreView.swift:51` | Task 3 |
| `Navigation.Pane` (exhaustive switches) | `Navigation.swift:59`, `:79`, `:112`, `RootView.swift:307` | Task 3 |
| `ShortcutCommand` (exhaustive switches) | `ShortcutCommand.swift` `section`, `title`, `defaultBinding`, `CommandActions+CanRun.swift:29` | Task 3 |
| `ShortcutCommand` (`assertionFailure` defaults) | `CommandActions.swift:199`, `:236`, `:284` | Task 3 |
| `NoteTemplate.substituting` | `NewNoteComposer.swift:162`, `TemplateSheet.swift:69`, `Tests/NoteTemplateTests.swift:63`, `:71`, `:72`, `:79`, `:89`, `:116` | sources in Task 6; tests unchanged (forward keeps bytes) |
| `VaultSession.dailyNote(for:)` (signature kept) | `VaultController+Notes.swift:94`, `VaultCapture.swift:117`, `VaultSession+EventNotes.swift:78`, `PraticaEntryComposer.swift:152`, `Tests/PraticaEntryCommandTests.swift:279`, `:376`, `Tests/VaultControllerLandedChangeTests.swift:443` | the first in Task 6; the rest inherit the template by design (ADR-0086 §D3) |
| `openDailyNote(for:)` (signature kept) | `VaultBrowser.swift:77`, `VaultController+Routes.swift:146`, `CommandActions.swift:178`, `DayController.swift:163`, `Tests/VaultTests.swift:551`, `:560` | unchanged; with no setting the bytes are today's |
| `VaultAPI.createNote` (+ `template:` default nil) | `WriteCommands.swift:12`, `VaultHost.swift:186`, `Tests/ConnectorTests.swift:270`, `:432`, `:437` | Task 2 front ends; tests unchanged |
| `VaultAPI.capture` (+ `template:` default nil) | `WriteCommands.swift:76`, `VaultHost.swift:211`, `CaptureController.swift:139`, `VaultController+Routes.swift:186`, `Tests/CaptureTests.swift` (14 calls), `Tests/CRLFCaptureTests.swift:153` | Task 2 front ends, Task 6 panel; tests unchanged |
| `CommandActions.rowCommands` | `CommandActions.swift:134`, `CommandActions+CanRun.swift:104` | Task 5 |
| Quick Open `.createNote` | `VaultBrowser.swift:81-86` | Task 6 |
| `NewCanvasItemSheet(kind: .note)` | `WorkspaceView+Creation.swift:50` | Task 6 |
| `VaultController.NoteDraft` (+ `tags`, default `[]`) | `Tests/NewNoteDraftTests.swift` (13 calls), `Tests/TaskComposerTests.swift:209`, `:213` | unchanged |
| `SidebarItem.Group.work.items` | `Tests/SidebarTests.swift:9-16`, `:57-69` | Task 3 test, Task 5 row |
| `ShortcutCommand.shipsUnbound` (N3 pin: two) | `Tests/ShortcutTests.swift` (N3's pin) | Task 3 (two becomes four) |
| Unchanged on purpose | `Tests/ContenitoreCoreTests.swift:166-189`, `Tests/EditorCommandTests.swift:152`, `UITests/ComposerUITests.swift:31` | stay green unmodified, which is the acceptance |

After the change, run the **whole** `PergamenumTests` suite, not the new files alone. These
contracts are shared by the Contenitore, the capture, the connectors and the command catalogue.

## Tasks

### Task 1 — Core rules and the session and connector doors, declared and red (R-30, R-31, R-33)
Owner: tester
Files:
- Sources/Core/Conventions/NoteTemplate.swift
- Sources/Core/Conventions/NoteClassification.swift
- Sources/Core/Conventions/TagEntry.swift
- Sources/Core/Conventions/NoteExtraction.swift
- Sources/Vault/VaultSettings.swift
- Sources/Vault/VaultSession+NoteBirth.swift
- Sources/Connector/VaultNoteBirth.swift
- Sources/Connector/VaultWrites.swift
- Sources/Connector/VaultCapture.swift
- Project.swift
- Tests/NoteTemplateTests.swift
- Tests/NoteClassificationTests.swift
- Tests/TagEntryTests.swift
- Tests/NoteExtractionTests.swift
- Tests/NoteBirthSessionTests.swift
- Tests/NoteBirthConnectorTests.swift
Tests: NoteTemplateTests.swift, NoteClassificationTests.swift, TagEntryTests.swift, NoteExtractionTests.swift, NoteBirthSessionTests.swift, NoteBirthConnectorTests.swift
Signatures:
- NoteTemplate.Resolved — struct Resolved: Equatable, Sendable { var body: String; var caretOffset: Int?; func caret(inWritten text: String) -> Int?; var cursorBack: Int? }
- NoteTemplate.resolve — static func resolve(_ template: String, title: String, date: CalendarDate, time: TaskTime) -> NoteTemplate.Resolved
- NoteTemplate.composing — static func composing(captured: String, into resolved: NoteTemplate.Resolved) -> String
- NoteTemplate.reference — static func reference(_ reference: String, among templatePaths: [String]) -> Result<String, TemplateReferenceError>
- TemplateReferenceError — enum TemplateReferenceError: Error, Equatable, Sendable { case unknown(String, available: [String]); case ambiguous(String, candidates: [String]) }
- NoteClassification.classify — static func classify(tags: [Tag], topics: [Tag], vocabulary: Vocabulary) -> Result<[Tag], ClassificationRefusal>
- TagEntry.Refusal — enum Refusal: Error, Equatable, Sendable { case malformed(String); case notInVocabulary(Tag); case vocabularyUnavailable(TagNamespace); case dateTag(Tag); case notAllowedHere(Tag) }
- TagEntry.check — `static func check(_ typed: String, allowing namespaces: Set<TagNamespace>, vocabulary: Vocabulary) -> Result<Tag, TagEntry.Refusal>`
- TagEntry.completions — `static func completions(for typed: String, allowing namespaces: Set<TagNamespace>, usage: [(tag: Tag, count: Int)], vocabulary: Vocabulary, excluding chosen: [Tag], limit: Int) -> [Tag]`
- NoteExtraction.Refusal — enum Refusal: Error, Equatable, Sendable { case empty; case outOfBounds; case textChanged; case touchesFrontmatter }
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
- VaultSession.templatePaths — var templatePaths: [String] { get }
- VaultAPI.ClassifySummary — struct ClassifySummary: Codable, Equatable, Sendable { let path: String; let applied: Bool; let diff: String?; let movedTo: String?; let note: String? }
- VaultAPI.ExtractSummary — struct ExtractSummary: Codable, Equatable, Sendable { let created: String; let applied: Bool; let createdDiff: String?; let sourceDiff: String?; let sourceRefused: String?; let note: String? }
- VaultAPI.classifyNote — static func classifyNote(_ session: VaultSession, at path: String, topics: String, folder: String?) async throws -> ClassifySummary
- VaultAPI.extractToNote — static func extractToNote(_ session: VaultSession, at path: String, fromLine: Int, toLine: Int, title: String, folder: String?, topics: String?) async throws -> ExtractSummary
- VaultAPI.createNote — static func createNote(_ session: VaultSession, title: String, folder: String?, topic: String?, date: String?, template: String? = nil) async throws -> WriteSummary
- VaultAPI.capture — static func capture(_ session: VaultSession, to destination: CaptureDestination, text: String, scheduled: String? = nil, due: String? = nil, template: String? = nil) async throws -> WriteSummary
Red: yes

**Declarations.**

- Stub bodies return a neutral value (`.failure(.noTopic)`, `Resolved(body: template, caretOffset:
  nil)`, `[]`) or throw. Never `fatalError`, which kills the Debug test host and turns a red file
  into a crashed run.
- `Sources/Vault/VaultSession+NoteBirth.swift` is new and is named in `Project.swift`'s
  `sharedSources` beside `VaultSession+Notes.swift`, with a one-line ADR-0085 §D4 comment. Run
  `tuist generate --no-open` after the edit.
- The new `VaultAPI` payloads live in `VaultNoteBirth.swift`, not in `VaultPayloads.swift`, whose
  `LintFinding` and `PraticaSummary` are protected.
- `perg` and `pergamenum-mcp` must still build with the stubs (R-45).

**Tests.**

- **`NoteTemplateTests` (extended): `resolve` and `caret(inWritten:)`.**
  - `{{time}}` with `TaskTime(hour: 9, minute: 5)` is `09:05`.
  - `# {{title}}\n\n{{cursor}}` with the title «Ciao» gives body `# Ciao\n\n` and offset 8.
  - Two `{{cursor}}` markers: the first wins and both are gone.
  - The offset counts UTF-16, with an emoji before the marker.
  - No marker gives a nil offset.
  - A title containing the literal `{{cursor}}` is written as typed.
  - `{{autore}}` is kept.
  - `caret(inWritten:)` over a rendered frontmatter plus a line break plus the body is the absolute
    offset, and `cursorBack` is `body.utf16.count - caretOffset`.
  - The six existing `substituting` assertions are left untouched and must stay green.
- **`NoteTemplateTests` (extended): `composing` and `reference`.**
  - `composing` puts the captured text at the marker. Without a marker it is the body, one blank
    line, then the text.
  - `reference` resolves an exact path, a title and `Titolo.md`. It returns `.unknown` listing the
    available templates, and `.ambiguous` for two `Riunione.md` in two subfolders of `Templates/`.
- **`NoteClassificationTests`.**
  - `status-inbox` is removed, `type-note` kept or added, topics added, and the result ordered.
  - Refusals: `.noTopic`, `.notATopic`, `.tooManyTags`.
  - Parity: for the same tags and topics, `ContenitoreClassification.classify(…, type: nil, …)`
    equals `NoteClassification.classify`, and with a type it equals the note result plus that type.
- **`TagEntryTests`.**
  - Bare `materiali` is `topic-materiali`, and `#client-acme` is `client-acme`.
  - `area-xyz` outside a vocabulary is `.notInVocabulary`. With the empty vocabulary it is
    `.vocabularyUnavailable(.area)`.
  - A date-shaped value is `.dateTag`, `type-note` outside `allowing` is `.notAllowedHere`, and
    `Topic Bad` is `.malformed`.
  - Completions offer vocabulary values for closed families and used values, most used first, for
    open ones. They exclude the chosen tags and honour `limit`.
- **`NoteExtractionTests`.**
  - `range(ofLines:)` is 1-based and inclusive over the whole file. It covers out of bounds, CRLF
    and a last line with no terminator.
  - `plan` refuses a range inside the frontmatter (`.touchesFrontmatter`), a text mismatch and an
    empty range.
  - The replaced source keeps the frontmatter bytes identical and puts `[[Titolo]]` exactly where
    the range was.
  - For a line range, the extracted text drops the final line break, which stays in the source.
- **`NoteBirthSessionTests`**, on a temporary vault with a temporary `stateBase`.
  - **`classifyNote`.**
    - It lands one `.written` change (counted through `landedChangeSubscriber`).
    - The frontmatter changes as the rule says.
    - With a folder, the file moves.
    - A destination that already holds the name leaves the classification written,
      `movedTo == nil` and `moveProblem` set.
  - **`extractToNote`.**
    - The new note holds the selection, the source holds `[[Titolo]]` and its frontmatter is
      byte-identical.
    - A taken title throws `CreationError.alreadyExists` and nothing is written.
    - A changed `expectedText` throws and nothing is written.
    - **The half-done case.** Remove write permission on the source file after the session read
      it, so step 3 fails: the outcome is `.refused` and the new note exists. Restore the
      permission in a `defer`. This is deterministic, with no timing (ADR-0046 §D11).
  - **`dailyNoteBirth`.**
    - With no setting, the bytes are today's.
    - With a setting, the body is resolved at the injected `at`, `created` is true and `caret` is
      the absolute offset.
    - An existing day gives `created == false`, `caret == nil` and untouched bytes.
    - A missing template creates the bare day and records a problem.
    - A setting outside `Templates/` is ignored, with a problem.
  - `VaultSettings` decodes an absent `dailyTemplate` as nil and round-trips a present one.
- **`NoteBirthConnectorTests`**, armed through `VaultAPI.arm`, `dryRun` first.
  - **Classify.** `classifyNote` returns `applied == false` and a diff with `-  - status-inbox`
    and `+  - topic-x`. A real run applies it. `"a,b"` reads as two topics, and a malformed topic
    is a usage error.
  - **Extract.** `extractToNote` returns two diffs. A range touching the frontmatter is refused.
  - **`createNote` with a template.** The resolved body is written with no `{{cursor}}`. An unknown
    template is a `ConnectorError` that lists the available ones.
  - **`capture` with a template.** With `.newNote`, one note, with the text at the marker. With
    `.today` or `.task`, a usage error.

### Task 2 — Core, session and connector bodies; both front ends; the smoke script (R-30, R-31, R-33, R-45)
Owner: coder
Files:
- Sources/Core/Conventions/NoteTemplate.swift
- Sources/Core/Conventions/NoteClassification.swift
- Sources/Core/Conventions/TagEntry.swift
- Sources/Core/Conventions/NoteExtraction.swift
- Sources/Core/Contenitore/ContenitoreClassification.swift
- Sources/Vault/VaultSettings.swift
- Sources/Vault/VaultSession+Notes.swift
- Sources/Vault/VaultSession+NoteBirth.swift
- Sources/Connector/VaultNoteBirth.swift
- Sources/Connector/VaultWrites.swift
- Sources/Connector/VaultCapture.swift
- Sources/CLI/main.swift
- Sources/CLI/Commands/WriteCommands.swift
- Sources/CLI/Help.swift
- Sources/MCPServer/ToolCatalogue+Writing.swift
- Sources/MCPServer/VaultHost.swift
- scripts/mcp-smoke.py
Tests: NoteTemplateTests.swift, NoteClassificationTests.swift, TagEntryTests.swift, NoteExtractionTests.swift, NoteBirthSessionTests.swift, NoteBirthConnectorTests.swift, ContenitoreCoreTests.swift, ConnectorTests.swift, CaptureTests.swift, CRLFCaptureTests.swift
Signatures: relies on Task 1's declarations; no new public shape.
Red: no

Make Task 1 green without editing its tests.

- **`NoteTemplate`.**
  - `resolve` splits the template at `{{cursor}}` first, substitutes each segment, then joins with
    the first marker's offset recorded. This is ADR-0086 §D1's ordering.
  - `substituting` becomes `resolve(…, time: TaskTime(hour: 0, minute: 0)).body`.
  - `{{time}}` is spelled by `TimeOfDay.formatted`.
- **The classification rules.** `NoteClassification` holds the rule body.
  `ContenitoreClassification.classify` keeps its signature and calls it, then adds the type, the
  second-type check and the count check.
- **`VaultSession+NoteBirth.swift`.**
  - `classifyNote` reads, applies the rule and runs `write(_:to:expecting:)` inside
    `transaction("note classify")`. Then, outside that gesture, it calls `moveNote(at:toFolder:)`,
    which opens its own; a nested transaction asserts (ADR-0050). A thrown move becomes
    `moveProblem`.
  - `extractToNote` runs inside `transaction("note extract")`: `createNote` (`expectingAbsent:`),
    then `write(_:to:expecting:)` with the hash read first. A refusal or failure of the second
    becomes `.refused(sentence)`, and the sentence is `VaultWriteRefusal.movedOn` or the recorded
    problem.
  - `dailyNoteBirth` follows ADR-0086 §D3. `dailyNote(for:)` in `VaultSession+Notes.swift` becomes
    a forward that keeps its signature, and its doc comment is now true.
  - `templatePaths` reads the index for `NoteTemplate.isTemplate`.
- **`VaultCapture`.**
  - `capture(… template:)` refuses `template` on every destination but `.newNote`.
  - For `.newNote` with a template, it resolves the template and composes the body through
    `NoteTemplate.composing`. It titles the note through `CaptureTitle.derive`, keeping N1's
    first-line rule, and writes once through `createNote(… body:)`.
  - Without a template, the path is N1's, unchanged.
- **The front ends translate and nothing else** (ADR-0007 §D2).
  - `perg note classify <percorso> --topic a,b [--folder F]`.
  - `perg note extract <percorso> --lines A-B --title T [--folder F] [--topic t]`, where `--lines`
    is parsed into `fromLine` and `toLine` in the CLI and a malformed range is a usage error.
  - `--template` on `note new` and `capture`.
  - `noteGroup` in `main.swift` gains `classify` and `extract`, and `Help.swift` gains the three
    lines.
  - MCP: `classify_note` and `extract_to_note` are write tools, absent from `tools/list` without
    `--allow-write`, with `dryRun` defaulting to true. `create_note` and `capture` gain a `template`
    string property.
- **`scripts/mcp-smoke.py`.**
  - Read-only: assert that `classify_note` and `extract_to_note` are not listed.
  - Writing:
    - a `classify_note` rehearsal with no `dryRun` has `applied` false and a diff naming
      `status-inbox`;
    - a real classify on the smoke vault's note applies;
    - an `extract_to_note` rehearsal has `applied` false.
- **Verify.** Run all three builds from `CLAUDE.md` ## Commands (app, `perg`, `pergamenum-mcp`),
  then `scripts/mcp-smoke.py`. Report its output (R-45).

### Task 3 — Update tests and call-sites asserting the old behaviour (R-29, R-30, R-32, R-33, R-34)
Owner: tester
Files:
- Sources/App/Navigation.swift
- Sources/Core/Shortcuts/ShortcutCommand.swift
- Sources/App/RootView.swift
- Sources/App/CommandActions.swift
- Sources/App/CommandActions+CanRun.swift
- Sources/Features/Contenitore/ClassificaSheet.swift (moved to Sources/Features/Editor/ClassificaSheet.swift)
- Sources/Features/Contenitore/ContenitoreView.swift
- Sources/Features/Editor/NewNoteComposer.swift
- Sources/Features/Editor/NoteComposition.swift
- Sources/Features/Editor/VaultBrowser.swift
- Sources/Features/Unfiled/UnfiledPane.swift
- Sources/Features/Unfiled/UnfiledListModel.swift
- Sources/App/VaultController+Notes.swift
- Sources/App/VaultController+NoteBirth.swift
- Sources/App/VaultController+Tabs.swift
- Sources/App/CreationUndo.swift
- Sources/Vault/NoteTab.swift
- Sources/Features/Capture/CaptureController.swift
- Tests/ShortcutTests.swift
- Tests/SidebarTests.swift
Tests: ShortcutTests.swift, SidebarTests.swift, CommandActionTests.swift, EditorCommandTests.swift, NewNoteDraftTests.swift, ContenitoreCoreTests.swift
Signatures:
- Navigation.Pane.unfiled — case unfiled // title «Da classificare», symbol from the mockup, shortcut .paneUnfiled
- Navigation.ClassifyRequest — struct ClassifyRequest: Identifiable, Equatable { let id: String } // id is the note path
- Navigation.classifying — var classifying: ClassifyRequest?
- Navigation.unfiledSelection — var unfiledSelection: String?
- ShortcutCommand.paneUnfiled — case paneUnfiled // .view, «Vai a Da classificare», KeyBinding("i", [.command, .control])
- ShortcutCommand.classifyNote — case classifyNote // .file, «Classifica…», KeyBinding("") (unbound)
- ShortcutCommand.extractToNote — case extractToNote // .edit, «Estrai in una nota», KeyBinding("") (unbound)
- ShortcutCommand.takesSelection — var takesSelection: Bool { get } // true for .extractToNote only
- ClassificaSheet.Subject — enum Subject: Identifiable, Equatable { case note(String); case scheda(String) }
- ClassificaSheet.init — init(subject: ClassificaSheet.Subject)
- NewNoteComposer.Host — enum Host: Equatable { case pane; case sheet(folder: String); case extract(VaultController.ExtractionDraft) }
- NewNoteComposer.init — init(draft: VaultController.NoteDraft, host: Host = .pane, perform: @escaping @MainActor (NoteComposition) async throws -> String, onCreated: @escaping (String) -> Void, onCancel: @escaping () -> Void)
- NoteComposition — struct NoteComposition: Equatable, Sendable { var title: String; var folder: String; var tags: [Tag]; var body: String; var bodyCaret: Int? }
- VaultController.NoteDraft.tags — var tags: [Tag] = []
- VaultController.ExtractionDraft — struct ExtractionDraft: Identifiable, Equatable { let id: UUID; let tabID: UUID; let sourcePath: String; let range: NSRange; let text: String; var title: String; var folder: String }
- VaultController.extraction — var extraction: ExtractionDraft?
- VaultController.createComposedNote — func createComposedNote(_ composition: NoteComposition) async throws -> String
- VaultController.classifyNote — func classifyNote(at path: String, topics: [Tag], toFolder folder: String?, savingFirst: Bool) async throws -> VaultSession.NoteClassifyOutcome
- VaultController.beginExtraction — func beginExtraction() -> Bool
- VaultController.extract — func extract(_ draft: ExtractionDraft, as composition: NoteComposition, savingFirst: Bool) async throws -> VaultSession.ExtractOutcome
- VaultController.creationUndo — var creationUndo: CreationUndo.Offer?
- VaultController.undoCreation — func undoCreation(now: Date) async -> CreationUndo.Decision
- VaultController.openNote — func openNote(at relativePath: String, caret: Int? = nil)
- VaultController.openNoteInNewTab — func openNoteInNewTab(at relativePath: String, caret: Int? = nil)
- CreationUndo — struct CreationUndo { static let window: TimeInterval = 10; struct Offer: Equatable, Sendable { let path: String; let createdHash: String; let expiresAt: Date }; enum Decision: Equatable, Sendable { case trashed; case expired; case unsaved; case changed; case failed(String) }; static func offer(for result: VaultSession.WriteResult, at now: Date) -> Offer; static func decide(_ offer: Offer, now: Date, currentHash: String?, tabIsDirty: Bool) -> Decision }
- NoteTab.pendingCaret — var pendingCaret: Int? = nil
- NoteTab.selection — var selection: NSRange? = nil
- UnfiledListModel — enum UnfiledListModel { struct Row: Identifiable, Equatable { let id: String; let title: String; let folder: String; let date: CalendarDate?; let isScheda: Bool }; static func rows(from records: [NoteRecord], folder: String?) -> [Row]; static func folders(from records: [NoteRecord]) -> [(folder: String, count: Int)]; static func selection(after removed: String, in rows: [Row]) -> String? }
- UnfiledPane — struct UnfiledPane: View
- CaptureController.template — var template: String?
- CaptureController.Destination.takesTemplate — var takesTemplate: Bool { get }
Red: yes

This task changes every app-layer contract N4 needs. It updates every call-site the build forces,
and every existing test whose expectation the change makes stale, so the target builds and the old
expectations are replaced before any coder task runs.

- **Moves and generation.** `git mv` `ClassificaSheet.swift` into `Sources/Features/Editor/`, then
  run `tuist generate --no-open` (CLAUDE.md: a file move leaves the generated project stale). Also
  regenerate after adding `Sources/Features/Unfiled/`.
- **Stubs that keep today's behaviour where one exists, so nothing regresses while red:**
  - `createComposedNote` forwards to today's `createNote(title:in:date:topics:body:)` and
    `ComposerUITests`' path stays unchanged;
  - `ClassificaSheet(subject: .scheda)` is today's sheet body;
  - `.note` shows a placeholder;
  - `UnfiledPane` is an empty pane;
  - every new `VaultController` door throws or returns `.failed("stub")`;
  - `undoCreation` returns `.expired`;
  - `UnfiledListModel` returns `[]`.
- **Call-sites updated for the build.**
  - `VaultBrowser.swift:184`: `NewNoteComposer(draft:, host: .pane, perform: { try await
    vault.createComposedNote($0) }, onCreated:, onCancel:)`.
  - `ContenitoreView.swift:51`: `ClassificaSheet(subject: .scheda(item.id))`.
  - `RootView.swift:307`: a `.unfiled` arm hosting `UnfiledPane()` through `requiringVault`.
  - `Navigation.swift:59`, `:79`, `:112`: the new pane's title, symbol and shortcut.
  - Every exhaustive switch in `ShortcutCommand.swift`.
  - `CommandActions+CanRun.swift:29`: the three commands answer `false`.
- **No new command may reach an `assertionFailure` default.** `runFile`, `runEdit` and `runView` get
  no-op arms for the three commands. An `assertionFailure` traps the Debug test host, and
  `CommandActionTests.switchingPaneIsTheOneActionSafeToRunWithNothingOpen` runs every pane's
  command. With a no-op it fails red for `.unfiled` instead.
- **Stale tests rewritten to the new expectation.**
  - `ShortcutTests`: N3's `shipsUnbound` pin goes from exactly two to exactly four
    (`followLinkInNewTab`, `followLinkInOtherColumn`, `classifyNote`, `extractToNote`). The
    collision walk now also sees Ctrl+Cmd+I and must still find no duplicate.
  - `SidebarTests`: a new `unfiledSitsInLavoroRightAfterTasks`, in the shape of
    `praticheSitsInLavoroImmediatelyBeforeRecordings`, with the position the mockup approved. It is
    red until Task 5.
- **Expected reds after this task:**
  - `SidebarTests.everyPaneHasExactlyOneRow`-style checks (`:9-16`);
  - the new placement test;
  - the pane-switch loop for `.unfiled`.

  Nothing else may go red. Run the whole `PergamenumTests` suite and report anything beyond these
  three.

### Task 4 — App-layer behaviour tests: pane, sheet, composer hosts, caret, extract, toast (R-29, R-30, R-31, R-32, R-33, R-34)
Owner: tester
Files:
- Tests/UnfiledListModelTests.swift
- Tests/UnfiledPaneHostedTests.swift
- Tests/ClassifyNoteControllerTests.swift
- Tests/NoteBirthCommandTests.swift
- Tests/NoteComposerHostTests.swift
- Tests/DailyNoteCaretTests.swift
- Tests/CaptureTemplateTests.swift
- Tests/ExtractSelectionTests.swift
- Tests/SlashSelectionStashTests.swift
- Tests/CreationUndoTests.swift
- Sources/Features/Editor/CompletingTextView+SlashSelection.swift
Tests: UnfiledListModelTests.swift, UnfiledPaneHostedTests.swift, ClassifyNoteControllerTests.swift, NoteBirthCommandTests.swift, NoteComposerHostTests.swift, DailyNoteCaretTests.swift, CaptureTemplateTests.swift, ExtractSelectionTests.swift, SlashSelectionStashTests.swift, CreationUndoTests.swift
Signatures:
- CompletingTextView.slashSelectionStash — var slashSelectionStash: (location: Int, text: String)? // declared, stub never set
- CompletingTextView.restoreSlashSelection — func restoreSlashSelection(replacing range: NSRange) -> Bool // stub returns false
- relies on every declaration of Task 3
Red: yes

Hosted-view tests use `Tests/HostedViewSupport.swift` and never make a window key or send it an
event (R-15 there). A controller test passes a temporary `stateBase`. A test that trashes a file
uses the real Finder Trash on a temporary vault, the way `VaultSessionFileOperationsTests` already
does.

- **`UnfiledListModelTests`.**
  - Rows come from records carrying `status-inbox`, a scheda included with `isScheda`.
  - Order: date, newest first, then `modifiedAt`, then title (or the direction the mockup chose).
  - The folder filter and the folders with their counts.
  - `selection(after:in:)` returns the following row, else the previous one, else nil.
- **`UnfiledPaneHostedTests`.**
  - Three captures, one capture scheda and one classified note give four table rows. Count them by
    the `NSTableView` under the pane, the `ContenitoreHostedViewTests` technique, because
    identifiers are unreachable in-process.
  - An empty vault gives no rows.
  - After `session.classifyNote` on one row and a settle, three rows.
- **`ClassifyNoteControllerTests`.**
  - `classifyNote(…, savingFirst: false)` on a dirty tab is refused with
    `unsavedNoteRefusal`-shaped wording and writes nothing.
  - With `savingFirst: true`, it saves and then classifies.
  - With a folder, every tab showing the note follows the move (ADR-0067).
  - A scheda through `.scheda` is untouched by this path. The existing Contenitore tests cover it.
- **`NoteBirthCommandTests`.**
  - `canRun(.classifyNote)` is false with nothing open and true with a note open.
  - `rowCommands` contains `.classifyNote`.
  - File «Classifica…» acts on `navigation.unfiledSelection` when «Da classificare» is in front, and
    sets `contenitore.classifying` when the Contenitore is in front (ADR-0071 §D12's redirect).
    Otherwise it acts on the open note. Each case is observed through `navigation.classifying`.
  - `run(.paneUnfiled)` shows the pane.
  - `canRun(.extractToNote)` follows the focused tab's `selection`.
- **`NoteComposerHostTests`.**
  - The composition from a draft carries the tags and the resolved template body and caret.
  - `.sheet(folder:)` fixes the folder.
  - `.extract` hides the template and proposes `CaptureTitle.derive` of the first line.
  - A closed-family violation blocks «Crea» through `TagEntry`.
  - `createComposedNote` opens a new tab whose `pendingCaret` is the absolute caret, and sets
    `creationUndo`.
  - Hosted: the composer builds in all three hosts and its fitting width is at most the sheet's
    520 pt in `.sheet`.
- **`DailyNoteCaretTests`.**
  - With a `dailyTemplate`, `openDailyNote` sets the new tab's `pendingCaret` to the birth's caret.
  - Reopening the day sets none.
  - The column consumes the caret once and clears it.
  - `TemplateSheet`'s insertion carries `Resolved.cursorBack`.
- **`CaptureTemplateTests`.**
  - `Destination.takesTemplate` is true for `.note` only.
  - `CaptureController` with a template passes it to `VaultAPI.capture`, and the note holds the
    text at the marker.
- **`ExtractSelectionTests`.**
  - `beginExtraction` with a tab `selection` builds a draft: the source's folder, and the title
    from `CaptureTitle`. With no selection, false.
  - `extract(…, savingFirst: true)` on a dirty tab saves, re-reads the tab after the `await`, and
    refuses when the buffer's text at the range changed in between.
  - A clean run leaves the source tab showing `[[Titolo]]` with no conflict prompt.
  - The half-done outcome reaches the caller.
- **`SlashSelectionStashTests`.** A hosted `CompletingTextView`, driven by `insertText` and
  `setSelectedRange` calls, not events.
  - `/` typed over a selection at a line start stashes it.
  - `restoreSlashSelection` puts the text back over `/prefix` and reselects it.
  - Accepting another command, or dismissing, drops the stash.
  - `/` with no selection stashes nothing.
  - The slash candidates include «Estrai in una nota» only while a stash exists. That filter is in
    the text view, not in `EditorCommand.all`, so `EditorCommandTests:152` keeps its count.
- **`CreationUndoTests`.**
  - Pure: an offer is live at 9.9 s and expired at 10 s.
  - `decide` gives `.unsaved` for a dirty tab, `.changed` for a moved hash, and otherwise
    `.trashed`.
  - Controller: `undoCreation` within the window moves the file to the Trash, forgets its note id
    (`lookUpNote(id:)` is `unknown`) and closes the clean tab. After the window it is `.expired` and
    the file stays.

### Task 5 — The «Da classificare» pane and «Classifica» on notes (R-29, R-30)
Owner: coder
Files:
- Sources/Features/Unfiled/UnfiledPane.swift
- Sources/Features/Unfiled/UnfiledListModel.swift
- Sources/App/SidebarItem.swift
- Sources/App/Navigation.swift
- Sources/App/RootView+Sheets.swift
- Sources/App/CommandActions.swift
- Sources/App/CommandActions+CanRun.swift
- Sources/App/CommandActions+NoteBirth.swift
- Sources/App/MenuCommands.swift
- Sources/App/VaultController+NoteBirth.swift
- Sources/Features/Editor/ClassificaSheet.swift
- Sources/Features/Editor/NoteRowMenu.swift
- docs/20260811_Pergamenum_SpecApp.md
Tests: UnfiledListModelTests.swift, UnfiledPaneHostedTests.swift, ClassifyNoteControllerTests.swift, NoteBirthCommandTests.swift, SidebarTests.swift, CommandActionTests.swift, ShortcutTests.swift, ContenitoreCoreTests.swift, ContenitoreEditorTests.swift
Signatures: relies on Tasks 1 and 3.
Red: no

- **The pane** follows ADR-0085 §D1 and §D2.
  - **List.** `List(selection: $navigation.unfiledSelection)` with flat rows. Use the layout,
    position, badge and order the mockup approved. A `.badge`, if adopted, goes before `.tag`.
  - **Focus.** A `@FocusState` is set on selection change and used as a setter, never as a guard
    (ADR-0070).
  - **Keys.** Return opens the sheet through `navigation.classifying`, and a double click opens the
    note.
  - **Row menu.** The row-level `.contextMenu` holds «Classifica…», «Apri», «Apri in una nuova
    tab», «Mostra nel Finder», plus «Mostra nel Contenitore» on a scheda row. No nested menu
    (ADR-0069).
  - **After a filing,** the selection becomes `UnfiledListModel.selection(after:in:)`.
  - **Identifiers** for the GUI test: `unfiled-pane`, `unfiled-row`, `unfiled-folder-filter`.
- **The sheet.**
  - `ClassificaSheet(subject: .note)`: topics through `TagEntry`, an optional folder picker over
    `vault.folders`, and a frontmatter preview.
  - On a dirty note the confirm reads «Salva e classifica» (G2).
  - It calls `VaultController.classifyNote`, which saves the dirty tabs showing the path through
    `saveTab(_:)`, re-reads them after the `await`, then asks `canOperate(on:)` and calls the
    session door.
  - A half-done move is shown in the sheet before it closes.
  - The `.scheda` branch keeps its identifiers and behaviour, minus the unused `actions`.
- **The commands.**
  - `.classifyNote` joins `rowCommands`.
  - `CommandActions+NoteBirth.swift` holds the routing: the pane in front, then the Contenitore,
    then the open note. It is its own file because `CommandActions.swift` sits at the edge of
    `file_length`, the `CommandActions+Contenitore.swift` precedent.
  - File «Classifica…» goes beside «Applica un template…» (`MenuCommands.swift:114`), and
    `NoteRowMenu` gets the row command.
  - `SidebarItem` LAVORO gains `.pane(.unfiled)` at the approved position.
- **SPEC (app).** Add dated notes to §7.4 and to §10's File and Vista, as ADR-0085 §D12 says.
- **Verify.** Measure Ctrl+Cmd+I against `com.apple.symbolichotkeys` before shipping, the way every
  default since ADR-0021 was.

### Task 6 — Templates in the app, one composer in three places, and the creation toast (R-31, R-32, R-34)
Owner: coder
Files:
- Sources/Features/Editor/NewNoteComposer.swift
- Sources/Features/Editor/NewNoteComposer+Tags.swift
- Sources/Features/Editor/NoteComposition.swift
- Sources/Features/Editor/VaultBrowser.swift
- Sources/Features/Editor/CreationUndoStrip.swift
- Sources/Features/Editor/EditorColumnView.swift
- Sources/Features/Editor/TemplateSheet.swift
- Sources/App/CreationUndo.swift
- Sources/App/VaultController+Notes.swift
- Sources/App/VaultController+NoteBirth.swift
- Sources/App/VaultController+Tabs.swift
- Sources/App/VaultController+Settings.swift
- Sources/Vault/NoteTab.swift
- Sources/Features/Workspace/WorkspaceView+Creation.swift
- Sources/Features/Workspace/BoardSheets.swift
- Sources/Features/Capture/CaptureController.swift
- Sources/Features/Capture/CapturePanelView.swift
- Sources/Features/Settings/SettingsView.swift
- docs/20260811_Pergamenum_SpecApp.md
Tests: NoteComposerHostTests.swift, DailyNoteCaretTests.swift, CaptureTemplateTests.swift, CreationUndoTests.swift, NewNoteDraftTests.swift, VaultTests.swift, NoteTemplateTests.swift
Signatures: relies on Tasks 1 and 3.
Red: no

- **The composer** follows ADR-0085 §D7.
  - **Composing.** It composes `NoteComposition` and calls `perform`.
  - **The tag field** moves into `NewNoteComposer+Tags.swift`, because the view is already 225
    lines. It holds chips, `TagEntry` completion and refusal, and `client-`/`project-` chips from
    `index.tagUsage()`. «Crea» stays disabled while `TagRules.validate` of the tags the rule would
    write reports anything.
  - **The pane host** keeps `new-note-title`, `new-note-folder` and `new-note-template` and parks
    drafts.
  - **The sheet host** shows the folder as a fixed label and parks nothing.
  - The template preview and the body go through `NoteTemplate.resolve`.
- **The three entries.**
  - Cmd+N and «Nuova nota qui», unchanged.
  - Quick Open's `.createNote(title)` (`VaultBrowser.swift:81-86`) now calls
    `offerNoteCreation(title:besideNoteAt: nil)`, ADR-0083 §D6's entry. A parked draft wins, as it
    does there.
  - Workspace «Documento» (`WorkspaceView+Creation.swift:50`) hosts
    `NewNoteComposer(host: .sheet(folder: boardFolder))`. Its `perform` keeps N1's behaviour:
    create, place the card, no tab, and «Apri» in the confirmation.
  - `NewCanvasItemSheet` loses its `.note` kind.
- **Templates in the app** follow ADR-0086.
  - `createComposedNote` writes, then `openNoteInNewTab(at:caret:)` with
    `Resolved.caret(inWritten:)`, then rescans.
  - `openDailyNote` calls `session.dailyNoteBirth(for:at:)` and passes the caret only when
    `created`.
  - `EditorColumnView` consumes `pendingCaret` once, on the first update showing the tab, and
    clears it through the controller.
  - `TemplateSheet` passes `cursorBack`.
  - Impostazioni › Convenzioni gains «Modello della nota del giorno» (`vault.templates` plus
    «Nessuno»), written through `VaultController+Settings.swift`.
  - The capture panel gains the template menu under «Nota nuova» (`capture-template`, the
    `capture-folder` popover shape), shown only when `takesTemplate`.
- **The toast** follows ADR-0085 §D9.
  - `createComposedNote` from the pane host sets `creationUndo`.
  - `CreationUndoStrip` is an `.overlay(alignment: .bottom)` on `VaultBrowser.editor`, of constant
    height and token-only.
  - A `.task(id: offer)` clears the offer at `expiresAt`.
  - «Annulla» calls `undoCreation(now:)`. A refusal shows its sentence in the strip.
  - No other creation path sets the offer.
- **SPEC (app).** Add dated notes to §8.1, to §12 (Convenzioni, and the quick switcher's «crea nota
  chiamata X») and to §16, as ADR-0085 §D12 and ADR-0086 §D9 say.

### Task 7 — «Estrai in una nota» (R-33)
Owner: coder
Files:
- Sources/Features/Editor/CompletingTextView+SlashSelection.swift
- Sources/Features/Editor/CompletingTextView.swift
- Sources/Features/Editor/NoteTextView.swift
- Sources/Features/Editor/EditorColumn+Text.swift
- Sources/Features/Editor/NewNoteComposer.swift
- Sources/Features/Editor/VaultBrowser.swift
- Sources/App/VaultController+NoteBirth.swift
- Sources/App/CommandActions+NoteBirth.swift
- Sources/App/CommandActions+CanRun.swift
- Sources/App/MenuCommands.swift
- docs/20260811_Pergamenum_SpecApp.md
Tests: ExtractSelectionTests.swift, SlashSelectionStashTests.swift, NoteBirthCommandTests.swift, EditorCommandTests.swift, NoteExtractionTests.swift, NoteBirthSessionTests.swift
Signatures: relies on Tasks 1, 3 and 4.
Red: no

- **The selection report.** The editor reports the selection beside N3's `recordLinkAtCaret`:
  `NoteTab.selection` is nil for an empty selection and is written only when it changes, so typing
  with a bare caret writes nothing. This keeps N2's restyle budget untouched; the budget test must
  stay green.
- **The slash stash.** It lives in `CompletingTextView+SlashSelection.swift`, as an `override func
  insertText(_:replacementRange:)` that stashes only when the string is `/` and the selection is
  non-empty. That is an O(1) check per insertion.
  - The `.app` branch in `CompletingTextView.swift:334` calls `restoreSlashSelection(replacing:)`
    before `onRunCommand` when `takesSelection` is true. It drops the stash otherwise, and on
    dismissal.
  - The slash candidate filter drops `takesSelection` entries without a stash.
  - `CompletingTextView+Pasteboard.swift` is protected and is not touched.
- **The command.** `.extractToNote` runs `beginExtraction()`, which fills `vault.extraction`.
  `VaultBrowser` presents it as a sheet with `NewNoteComposer(host: .extract(draft))`, whose
  `perform` calls `vault.extract(_:as:savingFirst:)`.
- **The sheet.** On a dirty source the confirm reads «Salva ed estrai» (G2). The half-done outcome
  keeps the sheet open with ADR-0085 §D8's sentence and «Chiudi». No toast.
- **Afterwards.** The source stays in front and the new note is not opened.
- **Menu and SPEC (app).** Modifica gains «Estrai in una nota» beside the find group
  (`MenuCommands.swift:315`). Add a dated note to SPEC (app) §10's Modifica.

### Task 8 — Two GUI tests, the UI-suite mapping, and the full verification (R-29, R-30, R-31, R-44)
Owner: tester
Files: UITests/NoteBirthUITests.swift, scripts/uitests.sh
Tests: NoteBirthUITests.swift
Signatures: relies on the identifiers of Task 5 (`unfiled-pane`, `unfiled-row`, `note-classifica-topic`, `note-classifica-folder`, `note-classifica-confirm`)
Red: no

`UITests/NoteBirthUITests.swift` subclasses `PergamenumUITestCase`. It makes its vault with
`makeTemporaryVault(prefix:)`, launches with `launchApp(extraArguments:)`, sets no launch arguments
of its own, and finds every control by identifier, never by its words.
`UITestLaunchHarnessGuardTests` enforces the harness rule.

- **`testFilingACaptureFromDaClassificare`** (ADR-0085 §D11).
  - **Seed.** `00 Inbox/Idea.md` with `type-note` and `status-inbox`, and an empty `03 Risorse/`.
  - **Steps.** Ctrl+Cmd+I, Down, Return. Type `materiali` into `note-classifica-topic`, choose
    `03 Risorse` and press `note-classifica-confirm`.
  - **Assertions, on the file.** `03 Risorse/Idea.md` exists. Its frontmatter holds
    `topic-materiali` and no `status-inbox`. `00 Inbox/Idea.md` is gone. The pane shows no
    `unfiled-row`.
- **`testTheDailyTemplatePlacesTheCaret`** (ADR-0086 §D8).
  - **Seed.** `Templates/Giornata.md`, and `dailyTemplate` merged into `.pergamenum/settings.json`.
  - **Steps.** Cmd+Shift+D, type `Primo appunto`, then Cmd+S.
  - **Assertions, on the file.** The text sits on the `{{cursor}}` line between the two headings, a
    `## \d{2}:\d{2}` heading exists, and no placeholder remains.
- **`scripts/uitests.sh`.**
  - In `classes_for_path`, before the `*` arm,
    `Sources/Features/Unfiled/*|Sources/Core/Conventions/NoteClassification.swift|Sources/Core/Conventions/NoteTemplate.swift`
    maps to `NoteBirthUITests`.
  - Add two `expect_eq` lines to its self-test, in the shape of `:978-989`.
  - Run `scripts/uitests.sh --self-test`.
- **Verification, in order.**
  1. The three builds (app, `perg`, `pergamenum-mcp`) and `scripts/mcp-smoke.py` (R-45).
  2. The whole `PergamenumTests` suite through `.claude/test-cmd`.
  3. `scripts/uitests.sh --status`, then the two new tests by name:
     `scripts/uitests.sh NoteBirthUITests`.
  4. At merge, `--affected`. This branch touches `Sources/App` and `Sources/Features/Editor`, which
     map to `ALL`, so expect the whole GUI suite, about 25 minutes. It is advisory, not blocking
     (CLAUDE.md merge gate).

  A red is diagnosed from its `.xcresult` before any rerun.
- **R-44 (process), for the orchestrator and Stefano at `/ship`.**
  - The PR closes #889 and `PG-387`.
  - `PG-121` is closed as superseded with a pointer to ADR-0086 §D7, and the `PG-387` ledger line's
    "PG-121's engine stays deferred" is corrected.
  - ADR numbers are rechecked.
  - The two ADRs gain their implementation notes, including the mockup choices.
  - Their status flips at landing, and the CLAUDE.md chain index gains both entries.

## Risks & HITL gates

- **N1 and N3 names.** The plan cites ADR-0080's and ADR-0083's names as written in their proposed
  records. If the merged code names them differently, adopt the merged names. A missing capability
  is reported, never re-implemented here.
- **The `assertionFailure` trap.** A new command reaching a section's default kills the Debug test
  host. Task 3 adds no-op arms first.
- **Protected surfaces.** `CompletingTextView+Pasteboard.swift`, `VaultPayloads.swift`'s
  `LintFinding`/`PraticaSummary`, `IndexCache.schemaVersion` and `ImportNaming.recordingNoteTitle`
  stay untouched. ADR-0080 already widened the truncator through a defaulted parameter, and N4 adds
  nothing to it.
- **Project generation.** The new shared session file needs `Project.swift`'s `sharedSources`,
  and both tool builds must pass (R-45). The `ClassificaSheet` move and the new `Unfiled` folder
  need `tuist generate --no-open`.
- **File length.** `CommandActions.swift` and `NewNoteComposer.swift` are near SwiftLint's limits.
  New code goes into `CommandActions+NoteBirth.swift` and `NewNoteComposer+Tags.swift`.
- **The keystroke budget (N2).** The slash stash is one comparison per insertion, and the selection
  report writes only on change. If N2's budget test moves, treat it as a regression, not noise.
- **Behaviour widened on purpose.**
  - The event note's day and the Pratiche diary mirror now get the daily template when they create
    the day (ADR-0086 §D3).
  - Templates and event notes carrying `status-inbox` appear in the pane.
  - Both are named in the ADRs.
- **Toast race.** A write between the hash check and the trash is trashed with the note
  (ADR-0085 §D9). It is the Finder Trash, so it is recoverable.
- **Tests and the Trash.** Controller tests that trash use the real Finder Trash on temporary
  vaults, as the existing ones do.
- **The GUI run at merge is the whole suite** (`--affected` maps `Sources/App` to `ALL`). It is
  advisory, about 25 minutes, and the pointer is shared with the person at the keyboard.
- **External resources: none.** Fully offline, with no new dependency, port, consent flow or
  environment variable.
- **HITL:**
  - G1, G2 and G3 at plan approval;
  - gate M (the mockup) before Task 1;
  - commit, push and merge are Stefano's;
  - no schema change and no deletion beyond the person's own «Annulla», which goes to the Trash;
  - flipping ADR-0085 and ADR-0086 from `proposed` at landing.

TEST-CMD CANDIDATE: xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -only-testing:PergamenumTests test
TEST-CMD MODE: brownfield

CHECK-CMD CANDIDATE: NONE
