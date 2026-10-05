**Requirement set:** `docs/archive/specs/pg-384-n1-seams.SPEC.md` (root `SPEC.md` while this was built)

# PG-384 — N1 seams of the note workflow: implementation plan

- **SPEC:** `SPEC.md` at the repository root, "N1 Seams of the note workflow (PG-384)", Status
  Approved (2026-10-04), R-01 to R-22. Its `## Decisions` and `## Constraints` are settled input
  and no task below reopens them. Task 3 archives it as
  `docs/specs/note-workflow-n1-seams.spec.md`.
- **ADR:** new, `docs/adr/0080-a-topicless-note-is-a-capture.md` (proposed). It covers R-01 to
  R-06, R-16, R-17 and R-20: the topic-less rule, the derived capture title, the free-text
  truncator and the inbox folder setting. Read §D1, §D3 and §D5 before writing code. Those are
  the three a task can silently get wrong by writing the obvious version.
- **No ADR for the editor and navigation seams** (R-07 to R-15, R-18). Each one follows a pattern
  the code already has: `CardWikilinkCompletion`'s ranking, `.editorLink` plus
  `MarkdownAttributedText.clickTarget(for:)` (issue #188), `WindowPlace`'s `.day` destination,
  pane changes on `CommandActions` in the shape of `.newNote`/`open(link:)`, and tokens through
  `Theme` (ADR-0002, ADR-0030). Each is cheap to reverse, and the SPEC already records the
  decisions and their rejected alternatives. ADR-0080 §D7 names the one deliberate reversal: `[[`
  completion now writes the `]]`.
- **Governing ADRs, registered and not reopened:**
  - ADR-0001 §D1: `Sources/Core` imports no SwiftUI;
  - ADR-0007 §D2/§D6: connector parity and the shared sources;
  - ADR-0008 §D4/§D6, extended by ADR-0080;
  - ADR-0012 §D5: Cmd+T is a tab;
  - ADR-0023 §D1: one command catalogue;
  - ADR-0030: faces through `ProseTypography`, never a weight trait;
  - ADR-0041 §D1: a resolver, not a skippable assert;
  - ADR-0043 §D7/§D8 and ADR-0057 §D3: re-read after an `await`, one write door;
  - ADR-0045: the slug truncator's two protected callers;
  - ADR-0067: the landed-change door.
- **Baseline.** The branch is `kepler/task-00994c70` at `6c03f024`; `SPEC.md` is modified and
  ADR-0080 is untracked. `origin/main` is at `babdbb49`, 12 commits ahead. Those commits touch
  `TokenKeys.swift`, `Theme.swift`, both theme JSON files, `ShortcutCommand.swift`,
  `VaultCommands.swift`, `DesignSystemTests.swift` and SPEC §6.1/§10. Merge `origin/main` before
  Task 1, never rebase or force, then run `tuist install` and `tuist generate --no-open`. The
  branch name does not follow Conventional Branch (`feature/pg-384-n1-seams` would). Renaming is
  the orchestrator's call, not a task.
- **Delivery: two sessions, two PRs.**
  - Session 1 (Tasks 1 to 3) is the capture and inbox half, with ADR-0080 and the SPEC text.
  - Session 2 (Tasks 4 to 8) is the editor and navigation half.

  This departs from the dispatch in one point: the inbox folder setting (R-16, R-17) moves into
  session 1. ADR-0080 decides it (§D5/§D6), and `docs/adr/README.md` rule 2 wants an ADR
  `proposed` only while its implementation is off `main`. `scripts/check-adr-references.py` also
  reports a `proposed` ADR found on the base. Landing every ADR-0080 decision in PR 1 lets the
  record flip to `accepted` right after it, instead of sitting `proposed` on `main` between the
  two PRs.

## SPEC decisions registered (settled, not reopened)

- **Scope.** Roadmap N1 tasks 1 to 7 and 9 in one SPEC. `PG-219`, the cursor, stays its own
  ticket.
- **Topic-less notes.** A note born with no `topic-*` is a capture on every path. The daily note
  is the only exception.
- **The premise correction.** ADR-0008 §D6 never promised `status-inbox`. ADR-0080 extends
  ADR-0008 and amends SPEC §4.3 and §16, not §4.2.
- **The derived title.**
  - Strip, trim, and cut at about 60 characters at a word boundary.
  - The whole text goes to the body when the title differs.
  - With nothing left, the title is `YYYYMMDD HHmm Cattura`.
  - Only an empty capture is refused.
- **Navigation.**
  - The event note opens in the Note pane.
  - «Documento» opens no tab.
  - Links and dates open on Cmd+click only.
- **`spacing.paragraph`.** 8 pt in both themes, checked by eye on the Debug build. No mockup.
- **The inbox folder.** `inboxFolder` reaches the capture default, the task inbox file, import
  and the in-app strings.

## What reading the current tree added

1. **R-19 is half done on `origin/main`.**
   - PRs #880 and #884 (`e4ef12b5`, `f75bc682`) already rewrote SPEC §10. File now reads «Nuova
     board… (Cmd+Shift+B) · … · Nota di oggi (Cmd+Shift+D) · … · Nuova tab (Cmd+T)». Vista no
     longer says «Oggi (Cmd+T)»; the pane row is «Ctrl+Cmd+1, 2, 3, …», and `paneToday` is
     Ctrl+Cmd+3.
   - What is left is SPEC §8.1 line 379: «`Cmd+T` apre oggi».
   - The menu label is «Nota di oggi», not «Nota del giorno».
2. **The protected truncator's tests.**
   - `ImportNaming.recordingNoteTitle`'s tests live in `ConventionsNamingTests.swift`, not in
     `ConventionsTests.swift`.
   - `PraticaNaming.messageFileName`'s tests live in `PraticaNamingTests.swift`.
   - R-06 means both files stay unmodified and green.
3. **`NoteName.versionSuffix(in:)` is `private`.** Task 2 widens it to `internal`, with one
   comment naming `CaptureTitle.swift` as its reader (ADR-0045's convention). It is not copied.
4. **Pratiche create-and-link always passes `topic-pratica`.** Both connector paths
   (`VaultPraticheLinks.swift:263`, `:322`) and the app path (`PraticaCommandActions+Links.swift:144`,
   fed by `praticaContextTags`) do so. Their output does not change. The shared rule covers R-01's
   "without topics" wording, because no Pratiche path passes none today. The tests pin the topic
   case.
5. **The test seam for Cmd+N.** The SPEC's "note-list editing tests" are `NewNoteDraftTests.swift`
   plus a new `NewNoteSeedTests.swift`. `NoteListEditingTests` is about markdown list items, not
   the note list.
6. **Where the inbox literal lives.**
   - The capture default: `VaultCapture.swift:31`, read at `:161`, `CapturePanelView.swift:102`,
     `:110`, `:281`, and `VaultController+Import.swift:26`, `:60`, `:72`.
   - `TaskDestination.relativePath`: `VaultSession+Tasks.swift:36-41`, `:226`, and
     `TaskComposer.swift:177`.
   - The default path shown or opened as a literal: `TaskComposer.swift:212` and
     `PergamenumApp.swift:290`.
   - No test references `CaptureDestination.defaultFolder` or `relativePath`. Seven test sites read
     `TaskDestination.inboxPath`, which stays, as the default.
7. **The `#` completion stack-overflow guard** is
   `EditorCompletionCrashTests.typingAHashAtTheStartOfALineDoesNotTakeTheProcessDown`.
8. **The heading colour has two arms:** `MarkdownAttributedText.swift:142` (editor) and
   `CardTextAttributes.swift:121`/`:206` (card). `ProseTypography.heading(level:)` serves both,
   from `font.proseTitle` (weight 700).

## Interpretations to confirm at GATE 1 (G0)

Each is this plan's reading of a SPEC sentence. A correction here changes a test, not the design.

1. **R-01's "no `topic-*`" is a namespace test.** A `client-acme` alone still gives
   `status-inbox` (ADR-0080 §D1).
2. **"The typed first line" is the first line trimmed of outer whitespace**, as today. Outer
   whitespace alone produces no caption and no derived title.
3. **Forbidden characters become spaces**, not nothing, and the derivation repeats to a fixed
   point (ADR-0080 §D3).
4. **The Cmd+N seed** (R-11):
   - one selected known folder gives itself;
   - one selected note or file gives its parent;
   - anything else (none, several, an unknown id) gives the root.
5. **Cmd+Shift+D** reads the pane at the keypress and switches to Note only after the note is
   open, and only if the pane is still the one it read (ADR-0043 §D7). From Oggi it switches
   nothing and still opens the note, as today.
6. **`spacing.paragraph` is per source line.**
   - It goes after each prose or heading source line.
   - It does not go after blank lines, frontmatter, code, tables, view blocks, list items, task
     lines, quotes, rules, message anchors or embed and transclusion lines.
   - Editor only: neither the card nor the transclusion picture
     (`MarkdownAttributedText.attributed`) gains it.
7. **H6 is regular weight in `textSecondary`, in the editor and in Workspace cards alike.** The
   regular face is `font.prose`'s face at H6's current size, not a weight trait (ADR-0030).
8. **Aliases are offered in the note editor only.** The card's candidate list stays titles and
   boards. Section completion (`[[Nota#…`) is unchanged and inserts no `]]`.
9. **Tag and date Cmd+clicks are wired in four surfaces:** the Note editor, the Today pane's daily
   note, the Diario pane and Workspace text cards.
10. **The CLI and MCP help wording** (R-16): «la cartella inbox (00 Inbox se non impostata)».
11. **A fallback caption** under the inbox field, saying a refused value fell back, is a named
    follow-up and not in scope.

## Standing rules for every task

1. **Run TEST-CMD before Task 1 to set the baseline, and after every task.** Run the whole
   `PergamenumTests` target, never a per-file selection. This chain changes `createNote`'s output,
   the capture contract and three exhaustive enums, and a contract change reaches tests in modules
   that have nothing to do with it.
2. **Run `tuist generate --no-open` after any task that adds a file** (Tasks 1, 4, 6 and 7). New
   files under `Sources/Core/**` are in `sharedSources` by glob. Every other new file here is
   app-only, so `Project.swift` is not edited.
3. **A stale test is changed only after saying why in chat** (global rule). The ones this plan
   expects are listed under "Observable contracts changed". A test outside that list going red is
   a finding to report, not a test to edit.
4. **Label each new or rewritten test with this SPEC's pin**, in a comment such as
   `// (n1-seams R-03)`. For example, `CaptureTitleTests.swift` carries `(n1-seams R-03, R-04)`.
   The coverage check then counts only this SPEC's ids in shared test files.
5. **Shared sources stay Foundation-only:** `Sources/Core/**`, `Sources/Connector/**` and the
   `Sources/Vault` files named in `sharedSources`. After a session-1 task, build `perg` and
   `pergamenum-mcp`.
6. **Every write goes through `VaultSession.write`/`createNote`.** No new disk path.
7. **UI strings are Italian; code, comments and commits are English.** Colours and fonts go
   through tokens only.
8. **SwiftLint.** Introduce no new violation in a touched file. Read the per-file output; the
   whole-repo run is red by design (see `CHECK-CMD`).

## Session 1 — capture, inbox folder, ADR-0080 (PR 1)

### Task 1 — Tester: the topic-less rule, the derived capture title and the inbox folder (R-01, R-02, R-03, R-04, R-05, R-06, R-16, R-17)
Owner: tester
Files: Sources/Core/Conventions/CaptureTitle.swift, Sources/Core/Conventions/ImportNaming.swift, Sources/Features/Capture/CaptureController.swift, Sources/Vault/VaultSettings.swift, Sources/Vault/VaultSession+Tasks.swift, Tests/TopiclessNoteRuleTests.swift, Tests/TopiclessCreationPathTests.swift, Tests/CaptureTitleTests.swift, Tests/CaptureTests.swift, Tests/CapturePanelTests.swift, Tests/NoteTemplateTests.swift, Tests/InboxFolderSettingsTests.swift, Tests/InboxFolderReachTests.swift
Tests: TopiclessNoteRuleTests.swift, TopiclessCreationPathTests.swift, CaptureTitleTests.swift, CaptureTests.swift, CapturePanelTests.swift, NoteTemplateTests.swift, InboxFolderSettingsTests.swift, InboxFolderReachTests.swift, ConventionsNamingTests.swift, PraticaNamingTests.swift, ConventionsImportTests.swift
Red: yes
Signatures:
- TagRules.initialTags — `static func initialTags(for category: NoteCategory, topics: [Tag] = []) -> [Tag]` (existing, unchanged)
- CaptureTitle — `struct CaptureTitle: Equatable, Sendable { let title: String; let differsFromTyped: Bool }`
- CaptureTitle.typedLine — `static func typedLine(of text: String) -> String`
- CaptureTitle.derive — `static func derive(fromTypedLine typed: String, now: Date, calendar: Calendar) -> CaptureTitle`
- ImportNaming.truncatedAtSpace — `static func truncatedAtSpace(_ text: String, toFit limit: Int) -> String`
- CaptureController.titleCaption — `func titleCaption(now: Date = Date(), calendar: Calendar = .current) -> String?`
- VaultSettings.defaultInboxFolder — `static let defaultInboxFolder = "00 Inbox"`
- VaultSettings.inboxFolder — `var inboxFolder: String`, plus the memberwise `init` gaining `inboxFolder: String = VaultSettings.defaultInboxFolder` as its last parameter
- VaultSettings.resolveInboxFolder — `static func resolveInboxFolder(_ stored: String, root: URL) -> String`
- VaultSession.inboxFolder — `var inboxFolder: String { get }`
- VaultSession.inboxNotePath — `var inboxNotePath: String { get }`
- VaultSession.relativePath(of:) — `func relativePath(of destination: TaskDestination) -> String`

The tester declares every symbol above with a body that compiles and keeps today's behaviour,
so the target builds and the new tests fail on their assertions, never on a trap:

- `typedLine` returns the text unchanged;
- `derive` returns `CaptureTitle(title: typed, differsFromTyped: false)`;
- `truncatedAtSpace` returns the text;
- `titleCaption` returns `nil`;
- `resolveInboxFolder` returns `stored`;
- `inboxFolder` returns the default;
- `inboxNotePath` returns `TaskDestination.inboxPath`;
- `relativePath(of:)` returns `destination.relativePath`;
- `VaultSettings.init(from:)` sets `inboxFolder = fallback.inboxFolder`, ignoring the key for now.

`CaptureTitle.swift` imports Foundation only. `inboxFolder`, `inboxNotePath` and
`relativePath(of:)` go in `VaultSession+Tasks.swift`, which is already in `sharedSources`.

**`TopiclessNoteRuleTests.swift`** (pure, R-01). One test per row of ADR-0080 §D1's table:

- `.daily` → `["type-note"]`;
- `.capture` → `type-note`, `status-inbox`;
- `.note` with `topic-acustica` → no `status-inbox`;
- `.note` with no tags → `type-note`, `status-inbox`;
- `.note` with only `client-acme` → `status-inbox` present;
- `.note` with `topic-pratica` plus `client-acme` → no `status-inbox`.

**`TopiclessCreationPathTests.swift`** (R-01, R-02):

- **Creation paths.** A topic-less note created through each of these carries `type-note` and
  `status-inbox`, and lints clean:
  - `VaultSession.createNote`;
  - `VaultController.createNote`, the door the composer, Quick Open and «Documento» share;
  - `VaultAPI.createNote` with `topic: nil` (`perg note create` and MCP `create_note` both call
    it);
  - `VaultAPI.capture(.newNote(folder: nil))`.

  "Lints clean" means `session.violations(forRecordAt:)` is empty and `VaultAPI.lint` reports
  nothing for the path, with a vocabulary fixture written the way `CategoryLintTests` writes one.
- **The topic case.** `VaultAPI.createAndLinkPraticaNote` gives `topic-pratica` and no
  `status-inbox`.
- **The MCP diff.** With `VaultAPI.arm(session, command: "create_note", dryRun: true)`, a
  topic-less `createNote` summary's `diff` contains `+  - status-inbox`.
- **Byte pins, green before and after.**
  - The daily note: `dailyNote(for:)` gives `---\ndate: …\ntags:\n  - type-note\n---\n\n`.
  - The event note.
  - The Contenitore scheda: `ContenitoreScheda.render`.
  - The inbox task note, through `captureTask` into an empty vault.

**`CaptureTitleTests.swift`** (pure, R-03, R-04, R-06). `derive` with a fixed `now` and an
injected UTC `Calendar`:

| Input | Title | Differs |
|---|---|---|
| a legal line | unchanged | false |
| `Idea: usare i token anche per i font?` | `Idea usare i token anche per i font` | true |
| `questo/non va` | `questo non va` | true |
| `3/10 prove` | `3 10 prove` | true |
| `Relazione v2` | `Relazione` | true |
| `Bozza v2 v3` | `Bozza` | true |
| `.nascosta` | `nascosta` | true |

More cases:

- A 90-character sentence is cut at the last space at or before 60.
- A single 70-character word is cut at 60.
- A cut that exposes a version token, or leaves a trailing space, is repaired on the next pass.
- `???` gives `20261004 1430 Cattura`.
- `v2` gives the fallback.
- Every non-fallback output passes `NoteName.validate`.
- `truncatedAtSpace` has its own cases: shorter than the limit, an exact fit, a cut at a space,
  and a hard cut.
- `typedLine` splits at `LineBreak.isTerminator` or a lone `\r` (ADR-0080 §D3), so `"A\r\nB"`
  gives `A`, and trims spaces.

**`CaptureTests.swift`** (R-03, R-04). One stale test is rewritten, after the chat note:
`aTitleTheConventionsRefuseStopsTheCaptureInsteadOfBeingCorrected` (`:94-110`). It becomes two
tests:

- `questo/non va\ncorpo` creates `00 Inbox/questo non va.md`, whose body holds both lines.
- `Relazione v2` creates `00 Inbox/Relazione.md` with body `Relazione v2`.

New tests:

- A legal first line behaves as today: the title is not repeated in the body.
- A derived title already taken is refused with a `ConnectorError` and writes nothing.
- An empty or whitespace-only capture is refused.
- `???` creates the fallback title. Assert the `Cattura` suffix and the `^\d{8} \d{4} ` shape,
  since `VaultAPI.capture` reads the clock.

**`CapturePanelTests.swift`** (R-05). Set `CaptureController.destination` and `text`, then read
`titleCaption`:

- `nil` for a legal first line;
- `nil` for an empty text;
- `nil` when the destination is `.task`, `.today` or `.existing`;
- `"Titolo: Idea usare i token anche per i font"` for the R-22 line.

**`NoteTemplateTests.swift`** (R-01). Two stale byte pins gain `  - status-inbox` after
`  - type-note`, after the chat note: `:106` and the expected block at `:125-131`. The second
pin's body content is unchanged.

**`InboxFolderSettingsTests.swift`** (R-16). Modelled on `PraticheSettingsTests.swift`:

- A `settings.json` without the key decodes to `00 Inbox`, and one with `"inboxFolder": "Triage"`
  decodes to `Triage`.
- `resolveInboxFolder` against a temporary root:
  - `"Triage"` is kept;
  - `" Triage/ "` gives `Triage`;
  - `""`, `"/abs"`, `".."`, `"../x"` and `"a/../b"` each give `00 Inbox`.

**`InboxFolderReachTests.swift`** (R-16, R-17). With `updateSettings { $0.inboxFolder = "Triage" }`
on an open session, and no reopen:

- `VaultAPI.capture(.newNote(folder: nil))` lands in `Triage/`;
- `captureTask` into `.inbox` creates `Triage/Capture.md`, while an existing
  `00 Inbox/Capture.md` is left byte-identical;
- `relativePath(of: .inbox) == "Triage/Capture.md"`;
- `VaultController`'s import destination proposal starts with `Triage/`;
- a refused stored value falls back to `00 Inbox` on all four.

These stay unmodified and green:

- `ConventionsNamingTests.swift` and `PraticaNamingTests.swift`, which pin R-06;
- `ConventionsImportTests.swift:53-55`, the current rule rows;
- `CRLFCaptureTests.swift`;
- `VaultSessionTests.aSessionCapturesATaskIntoAnInboxItCreates`.

### Task 2 — Coder: implement the rule, the derived title and the inbox folder (R-01, R-02, R-03, R-04, R-05, R-06, R-16, R-17)
Owner: coder
Files: Sources/Core/Conventions/Tag.swift, Sources/Core/Conventions/CaptureTitle.swift, Sources/Core/Conventions/NoteName.swift, Sources/Core/Conventions/ImportNaming.swift, Sources/Connector/VaultCapture.swift, Sources/Connector/VaultWrites.swift, Sources/Vault/VaultSession+Notes.swift, Sources/Vault/VaultSession+Tasks.swift, Sources/Vault/VaultSettings.swift, Sources/Features/Capture/CaptureController.swift, Sources/Features/Capture/CapturePanelView.swift, Sources/Features/Settings/SettingsView.swift, Sources/Features/Tasks/TaskComposer.swift, Sources/App/PergamenumApp.swift, Sources/App/VaultController+Import.swift, Sources/App/VaultCommands.swift, Sources/App/FileImportSheet.swift, Sources/Features/Help/HelpSheets.swift, Sources/CLI/Help.swift, Sources/MCPServer/ToolCatalogue+Writing.swift
Tests: TopiclessNoteRuleTests.swift, TopiclessCreationPathTests.swift, CaptureTitleTests.swift, CaptureTests.swift, CapturePanelTests.swift, NoteTemplateTests.swift, InboxFolderSettingsTests.swift, InboxFolderReachTests.swift
Red: no
Signatures:
- TagRules.initialTags — `static func initialTags(for category: NoteCategory, topics: [Tag] = []) -> [Tag]`
- CaptureTitle.derive — `static func derive(fromTypedLine typed: String, now: Date, calendar: Calendar) -> CaptureTitle`
- NoteName.versionSuffix — `static func versionSuffix(in title: String) -> String?` (widened from `private` to `internal`)
- VaultSession.inboxFolder — `var inboxFolder: String { get }`

**The rule.** In `initialTags`, `.note` adds `status-inbox` when no tag in `topics` has namespace
`.topic`. `.daily` and `.capture` keep their exact output. `missingRequired` is not touched.

**Capture.** `captureAsNote` takes `CaptureTitle.typedLine(of:)`, then
`derive(fromTypedLine:now: Date(), calendar: .current)`.

- **When the title differs:** create with the derived title, then append the whole text, trimmed
  of outer whitespace and newlines, as the body.
- **Otherwise:** the body is today's `rest`.
- The dry-run branch keeps today's shape.
- Rewrite the doc comment above `captureAsNote` (`:140-143`): it currently says a refused title
  comes back with its reason.
- `derive` implements ADR-0080 §D3 literally, through `NoteName.forbiddenCharacters`,
  `versionSuffix(in:)`, `maximumLength` and `ImportNaming.truncatedAtSpace`. The final
  `NoteName.validate` check is an `assert`-free guard: if it still fails, take the fallback.
- `CaptureController.titleCaption` returns «Titolo: \(title)» only for `.note` with a non-empty
  text whose `differsFromTyped` is true.
- `CapturePanelView` shows the caption under the field with `.themedText(.caption, color:
  .textSecondary)`, Italian, no new token.

**The inbox folder.**

- `VaultSettings.init(from:)` reads `inboxFolder` with `decodeIfPresent` and falls back to the
  default.
- `resolveInboxFolder` follows ADR-0080 §D5, in this order:
  - trim, and refuse a leading `/`;
  - split on `/`, trim each component, and refuse any `..` component;
  - drop every empty and `.` component and rejoin with `/`;
  - refuse when nothing is left, or when `VaultBoundary(root:).url(for:)` throws;
  - on any refusal, return the default.
- `VaultSession.inboxFolder` resolves `settings.inboxFolder` against `root` on every read, with
  no cache, so R-17 needs no relaunch. `inboxNotePath` is `"\(inboxFolder)/Capture.md"`.
  `relativePath(of:)` maps `.inbox` to `inboxNotePath` and `.note(path)` to `path`.
- **Deletions.** `TaskDestination.relativePath` and `VaultAPI.CaptureDestination.defaultFolder`
  are deleted.
- **Call sites switched**, every one listed under "Observable contracts changed":
  - `captureTask` (`:226`);
  - `captureAsNote` (`:161`);
  - `CapturePanelView` (`:102`, `:110`, `:281`, which read `session?.inboxFolder ??
    VaultSettings.defaultInboxFolder`);
  - `VaultController+Import` (`:26`, `:60`, `:72`);
  - `TaskComposer` (`:177`, `:212`);
  - `PergamenumApp.swift:290` (the menu bar's Inbox opens `session.inboxNotePath`).
- **`TaskDestination.inboxPath` stays.** Fix the doc comments that name it as "the" inbox
  (`VaultCapture.swift:19`, `:29`).
- **Strings that name the folder:**
  - read the setting: `HelpSheets.swift:98`, the import alert in `VaultCommands.swift` (`:83` on
    `origin/main`) and `FileImportSheet.swift:17`;
  - say «la cartella inbox (00 Inbox se non impostata)»: `perg` help (`Help.swift:36`) and the MCP
    `capture` folder description (`ToolCatalogue+Writing.swift:137`), since they cannot read a
    vault before one is open;
  - the topic-less wording: the `perg note create` and MCP `create_note` topic descriptions gain
    «senza topic la nota nasce come cattura (status-inbox)».
- **Settings.** `SettingsView`'s Convenzioni gains `TextField("Cartella inbox", …)` beside the
  daily and diary fields, in the same binding shape (`:132-148`).
- `DesignGallery` mockups keep their literal: they are static fixtures.

**Doc comments.** `VaultWrites.createNote` and `VaultSession.createNote` (`:24-34`) state the new
rule and that `createNote` still refuses an invalid title.

**After the task:**

- build `perg` and `pergamenum-mcp`;
- run `scripts/mcp-smoke.py`, since `Sources/MCPServer` changed;
- run the full TEST-CMD.

The Settings field, the panel caption and R-17's no-relaunch behaviour in the UI are checked by
hand in Task 8.

### Task 3 — Coder: ADR-0080 in the index, SPEC amendments and the stale daily-note comments (R-19, R-20, R-21)
Owner: coder
Files: docs/specs/note-workflow-n1-seams.spec.md, docs/20260811_Pergamenum_SpecApp.md, CLAUDE.md, docs/adr/0080-a-topicless-note-is-a-capture.md, Sources/Connector/VaultCapture.swift, Sources/Vault/VaultSession+Notes.swift, Sources/Vault/VaultSession+TimeBlocks.swift, Sources/Features/Today/DayController.swift
Tests: PergamenumTests
Red: no
Signatures:
- ShortcutCommand.defaultBinding — read-only source of truth for every shortcut the SPEC text names (`dailyNote` Cmd+Shift+D, `newBoard` Cmd+Shift+B, `newTab` Cmd+T, `paneToday` Ctrl+Cmd+3)

**Archive the SPEC.** Copy the repo-root `SPEC.md` verbatim to
`docs/specs/note-workflow-n1-seams.spec.md`. ADR-0080 already cites that path. Leave the root
file as it is; clearing it is the orchestrator's step at ship time.

**App SPEC amendments.** In Italian, each tagged *Emendato 2026-10-04 (ADR-0080)*, the house
style:

- **§4.3, line 136.** «Capture inbox senza argomento» becomes: «Ogni nota che nasce senza un
  `topic-*`, da qualunque superficie (Cmd+N, Apri rapido, «Documento», cattura, `perg`, MCP), è
  una cattura: `- type-note` + `- status-inbox`. La daily note resta col solo `- type-note`.»
- **§4.1, line 93.** The `00 Inbox/` tree note says the folder is configurable (Impostazioni ›
  Convenzioni › Cartella inbox, default `00 Inbox`).
- **§8.1, line 379.** «`Cmd+T` apre oggi» becomes «`Cmd+Shift+D` apre la nota di oggi; `Cmd+T`
  apre una nuova tab (ADR-0012 §D5)». This is R-19's remaining half; see "What reading the
  current tree added" §1. The same line's «Template configurabile» is untrue too, but it belongs
  to N4 (template choice at birth). Report it, don't fix it here.
- **§10.** Re-read it after the `origin/main` merge, against `ShortcutCommand.defaultBinding`. It
  should already say Cmd+Shift+B, Cmd+Shift+D and Cmd+T as a new tab, with no «Oggi (Cmd+T)».
  Change nothing if it does; record the check in the PR body.
- **§12.** The Impostazioni › Convenzioni list gains «cartella inbox».
- **§16.**
  - The Inbox sentence reads `<cartella inbox>/Capture.md` (default `00 Inbox/Capture.md`).
  - A new bullet: «Una prima riga che non è un nome di nota valido produce un titolo proposto
    (caratteri vietati tolti, spazi compattati, suffisso di versione tolto, taglio a 60 caratteri
    a una parola); se diverso dalla riga, tutto il testo va nel corpo; se non resta nulla, il
    titolo è `YYYYMMDD HHmm Cattura`. Il pannello mostra «Titolo: …» prima dell'invio. Solo una
    cattura vuota è rifiutata.»

**`CLAUDE.md`.** Add one line to the Chain decision index after ADR-0079, in the index's style.
Proposed text:

> **ADR-0080** — `PG-384` (N1, session 1): a note born without a `topic-*` is a capture on every
> creation path — `TagRules.initialTags` adds `status-inbox` to a `.note` carrying no tag of
> namespace `topic`, the daily note, the event note, the scheda and the inbox note stay
> byte-identical, and `perg lint` stops flagging what the app writes (#30's lesson, one function
> decides). Capture «Nota nuova» derives a title from a first line `NoteName.validate` refuses
> (`CaptureTitle.derive`, shared sources: forbidden characters to spaces, whitespace collapsed,
> leading dots and a trailing version token removed, cut at a space within 60, repeated to a fixed
> point, `YYYYMMDD HHmm Cattura` when nothing is left), puts the whole text in the body when the
> title differs, shows «Titolo: …» in the panel and refuses only an empty capture;
> `VaultSession.createNote` still refuses. `ImportNaming.truncatedAtSpace` sits beside the slug
> truncator, so `recordingNoteTitle` and `messageFileName` are untouched. The inbox folder is
> `VaultSettings.inboxFolder` (default `00 Inbox`, resolved at read through `VaultBoundary` with
> `..` refused), read through `VaultSession.inboxFolder`/`inboxNotePath`/`relativePath(of:)`;
> `CaptureDestination.defaultFolder` and `TaskDestination.relativePath` are deleted. Corrects the
> roadmap: ADR-0008 §D6 never promised `status-inbox`. No format, schema or protected interface
> touched. Extends ADR-0008 §D4/§D6, amends SPEC §4.3 and §16 →
> `docs/adr/0080-a-topicless-note-is-a-capture.md`

**R-21's four doc comments.** Each says what the code does. There is no daily template: the
daily note is created with the daily frontmatter (`type-note` alone) and an empty body.

- `VaultCapture.swift:105` («created from the template when the day has none»);
- `VaultSession+Notes.swift:119` («created from the template when it is not there yet»);
- `VaultSession+TimeBlocks.swift:96-98` («written from the template first … indistinguishable
  from one opened with Cmd+T», which becomes Cmd+Shift+D);
- `DayController.swift:158` («creating it from the template»).

`VaultSession+Tasks.swift:258` is about the inbox template, which does exist. Leave it.

**ADR-0080.** Change it only if G0 corrected an interpretation that §D1 or §D3 records. Keep it
`proposed`.

**Checks:**

- `rg -n -i "from the template" Sources/Connector Sources/Vault Sources/Features/Today` finds only
  `VaultSession+Tasks.swift:258`;
- `scripts/check-adr-references.py` is clean, after `git fetch`;
- the number 0080 is still free on `origin/main` right before the merge (README rule 1).

**After PR 1 merges.** The first docs change flips ADR-0080 to `accepted`, naming PR 1, its merge
hash from `git log --first-parent main` and the date (README rule 2). It is a small docs-only
commit at the head of the session-2 branch, or its own PR. It is a HITL commit like any other.

## Session 2 — editor and navigation seams (PR 2)

### Task 4 — Tester: `[[` completion, tag and date click targets, `spacing.paragraph`, H6 (R-07, R-08, R-12, R-13, R-14, R-15)
Owner: tester
Files: Sources/Features/Workspace/CardWikilinkCompletion.swift, Sources/Features/Editor/CompletionPanel.swift, Sources/Features/Editor/CompletingTextView.swift, Sources/Features/Editor/NoteTextView.swift, Sources/Features/Editor/NoteTextView+Inputs.swift, Sources/Features/Editor/NoteTextView+Coordinator.swift, Sources/Features/Editor/MarkdownAttributedText.swift, Sources/Features/Workspace/CardTextView.swift, Sources/Features/Editor/ProseParagraphSpacing.swift, Sources/DesignSystem/TokenKeys.swift, Sources/DesignSystem/Theme.swift, Sources/DesignSystem/ProseTypography.swift, Tests/WikilinkClosingTests.swift, Tests/CardWikilinkCompletionTests.swift, Tests/CompletionPanelTests.swift, Tests/TagDateClickTargetTests.swift, Tests/ProseParagraphSpacingTests.swift, Tests/DesignSystemTests.swift, Tests/ProseTypographyTests.swift
Tests: WikilinkClosingTests.swift, CardWikilinkCompletionTests.swift, CompletionPanelTests.swift, TagDateClickTargetTests.swift, ProseParagraphSpacingTests.swift, DesignSystemTests.swift, ProseTypographyTests.swift, EditorCompletionTests.swift, EditorCompletionCrashTests.swift, ListIndentFontInvariantTests.swift, WikilinkClickNavigationTests.swift, MarkdownAttributedTextTests.swift, TransclusionLayoutTests.swift, TranscludedLineTests.swift
Red: yes
Signatures:
- WikilinkTrigger.closingInsertion — `static func closingInsertion(of title: String, ahead: Substring) -> (text: String, caretOffset: Int)`
- WikilinkNote — `struct WikilinkNote: Equatable, Sendable { let title: String; let aliases: [String] }`
- CardWikilinkCompletion.candidates — `static func candidates(matching typed: String, notes: [WikilinkNote], boards: [String], limit: Int = 8) -> [WikilinkCandidate]` (the existing `[String]` overload stays)
- WikilinkCandidate.matchedAlias — `var matchedAlias: String? = nil`
- WikilinkCandidate.label — `var label: String { get }`
- CompletionItem.wikilink — `case wikilink(WikilinkCandidate)`
- CompletingTextView.noteAliases — `var noteAliases: [String: [String]] = [:]`
- NoteTextView.init — gains `noteAliases: [String: [String]] = [:]`
- MarkdownAttributedText.tagURL — `static func tagURL(for tag: Tag) -> URL`
- MarkdownAttributedText.dayURL — `static func dayURL(for day: CalendarDate) -> URL`
- MarkdownAttributedText.clickURL — `static func clickURL(for span: MarkdownStyler.Span, source: Substring) -> URL?`
- MarkdownAttributedText.LinkClickTarget — gains `case tag(Tag)` and `case day(CalendarDate)`
- NoteTextView.VaultInputs.onOpenTag — `var onOpenTag: ((Tag) -> Void)?`
- NoteTextView.VaultInputs.onOpenDay — `var onOpenDay: ((CalendarDate) -> Void)?`
- CardTextView.onOpenTag — `var onOpenTag: (Tag) -> Void = { _ in }`
- CardTextView.onOpenDay — `var onOpenDay: (CalendarDate) -> Void = { _ in }`
- SpacingToken.paragraph — `case paragraph = "spacing.paragraph"`, with `Theme.emergency`'s spacings gaining `.paragraph: 8` in the same edit
- ProseTypography.paragraphSpacing — `static func paragraphSpacing(_ theme: Theme) -> CGFloat`
- ProseTypography.headingColor — `static func headingColor(level: Int) -> ColorToken`
- ProseParagraphSpacing.paragraphRanges — `static func paragraphRanges(in text: String, spans: [MarkdownStyler.StyledRange]) -> [NSRange]` (new file, `enum ProseParagraphSpacing`)

**Stubs that keep the target building:**

- `closingInsertion` returns `(title, title.count)`;
- the new `candidates` overload maps to the `[String]` one by title;
- `label` returns `displayTitle`;
- `tagURL` and `dayURL` return a fixed placeholder URL, and `clickURL` returns `nil`;
- `paragraphSpacing` returns `0`, `headingColor` returns `.textPrimary`, and `paragraphRanges`
  returns `[]`.

**Two traps that kill the process instead of failing a test:**

1. `SpacingToken.paragraph` goes into `Theme.emergency` in the same edit. PG-225: a token missing
   from the emergency dictionary traps at `theme.spacing(_:)`.
2. Every exhaustive switch over the two enlarged enums gets a stub arm. These stub arms are
   placeholders for the coder, not behaviour:
   - for `CompletionItem`: the `id`, `title`, `symbol` and `shortcutCaption` switches in
     `CompletionPanel.swift:20-47`, and `CompletingTextView.apply` (`:319-325`);
   - for `LinkClickTarget`: the two `performLinkNavigation` switches
     (`NoteTextView+Coordinator.swift:248-262`, `CardTextView.swift:338`), whose stub arms return
     `false`.

The JSON values stay out. That keeps `DesignSystemTests.bundledThemesDefineEveryToken` red until
Task 5, the pattern that test's own comments describe.

**`WikilinkClosingTests.swift`** (R-07):

- `closingInsertion` with nothing ahead gives `Titolo]]`, caret after the `]]`;
- with `]]` ahead it gives `Titolo`, caret moved past the existing `]]`;
- with `]` or ` ]]` ahead it is treated as nothing ahead.
- In a real `CompletingTextView`, `Vedi [[Tras` + Return gives `Vedi [[Trasmissibilità e
  rapporto di frequenza]]`, caret at the end.
- `Vedi [[Tras]] e` with the caret before `]]` does not double it.
- The card: `FormattingTextView.applyWikilinkCompletion` with `]]` already ahead does not double
  it either.

**`CardWikilinkCompletionTests.swift`** (R-08):

- a note matched only through an alias is offered, with `matchedAlias` set, and `insertText`
  stays the title;
- a note matched by title has `matchedAlias == nil`, even when an alias also matches;
- `label` reads «Titolo · alias: X» for an alias match and the bare title otherwise;
- the existing tests stay green unmodified.

**`CompletionPanelTests.swift`** (R-07, R-08). Three stale expectations change after the chat
note:

- `aWikilinkOffersNoteTitlesAsCandidates` (`:36-39`): `.text(…)` becomes `.wikilink(…)`;
- `returnWritesTheCandidateOverExactlyWhatWasTyped` (`:183-192`): the result gains `]]`;
- `clickingARowLandsWhereReturnLands` (`:259-268`): it chooses the `.wikilink` item, and the
  result gains `]]`.

New tests:

- an alias row shows «Titolo · alias: X» and inserts the title plus `]]`;
- `[[Prove#Cam` + Return stays `[[Prove#Campioni` with no `]]` (section completion unchanged).

The `#` guard (`EditorCompletionCrashTests`) and `EditorCompletionTests` stay green unmodified.

**`TagDateClickTargetTests.swift`** (R-12, R-13):

- **Which spans become click URLs.** `clickURL(for:source:)` gives a tag URL for
  `.tag("client-acme")`. It gives a day URL for `.scheduled` over `>2026-10-12` and for `.due`
  over `!2026-10-12`. It gives `nil` for `>2026-02-31`, for `.annotation` over `@done(2026-10-01)`,
  `@remind(…)` and `@repeat(…)`, and for any other span.
- **The round trip.** `clickTarget(for:)` decodes `tagURL` and `dayURL` back to `.tag` and `.day`.
- **The styled text.**
  - In the note editor's styled storage, the `#client-acme` and `>2026-10-12` runs carry the
    clickable attribute and keep their token colour.
  - With `StyleContext(links: false)` they carry none.
  - A Workspace card's styled text does the same.
- **Click behaviour.** In the shape of `WikilinkClickNavigationTests`:
  - Cmd+click on a tag in a hosted `NoteTextView` calls `onOpenTag` with that tag;
  - a plain click calls nothing and places the caret;
  - a date calls `onOpenDay`;
  - the same holds for `CardTextView`.

**`ProseParagraphSpacingTests.swift`** (R-14):

- `paragraphRanges` returns the ranges of prose and heading source lines.
- It excludes blank lines and every line covered by these spans: `.frontmatter`, `.codeBlock`,
  `.tableRun`, `.viewBlockRun`, `.listMarker`, `.taskMarker`, `.blockquoteMarker`,
  `.horizontalRule`, `.messageAnchor` and `.embedRun`.
- In a hosted `NoteTextView`, the paragraph style of a prose line has `paragraphSpacing == 8`, a
  list line's has 0, and a transclusion line keeps its `reservedHeight`.

**`DesignSystemTests.swift`** (R-14). `bundledThemesDefineEveryToken` gains
`spacing.paragraph`, by name, in its explicit list. It asserts `theme.spacing(.paragraph) == 8`
for light and dark. `Theme.emergency.spacing(.paragraph) == 8`.

**`ProseTypographyTests.swift`** (R-15):

- H6's font has no bold symbolic trait, and H5's has one;
- H1 to H6 sizes are unchanged from today's formula;
- `headingColor(level: 6) == .textSecondary`, and levels 1 to 5 are `.textPrimary`;
- a `###### Nota` line in the editor's styled storage and in a card's styled text is drawn in
  `textSecondary`.

These stay unmodified and green:

- `ListIndentFontInvariantTests`;
- `MarkdownAttributedTextTests`'s click-target cases;
- `TransclusionLayoutTests` and `TranscludedLineTests`;
- `ProseTypographyTests`' `paragraphStyle` pins, because `paragraphStyle` itself does not change.

### Task 5 — Coder: implement the editor seams (R-07, R-08, R-12, R-13, R-14, R-15)
Owner: coder
Files: Sources/Features/Workspace/CardWikilinkCompletion.swift, Sources/Features/Workspace/FormattingTextView.swift, Sources/Features/Editor/CompletionPanel.swift, Sources/Features/Editor/CompletionPanelView.swift, Sources/Features/Editor/CompletingTextView.swift, Sources/Features/Editor/NoteTextView.swift, Sources/Features/Editor/NoteTextView+Update.swift, Sources/Features/Editor/NoteTextView+Coordinator.swift, Sources/Features/Editor/EditorColumnView.swift, Sources/Features/Editor/EditorColumn+Text.swift, Sources/Features/Today/TodayView.swift, Sources/Features/Diary/DiaryView.swift, Sources/Features/Editor/MarkdownAttributedText.swift, Sources/Features/Workspace/CardTextView.swift, Sources/Features/Workspace/CardTextAttributes.swift, Sources/Features/Workspace/CardTextView+Styling.swift, Sources/Features/Editor/ProseParagraphSpacing.swift, Sources/DesignSystem/ProseTypography.swift, Resources/Themes/pergamenum-light.json, Resources/Themes/pergamenum-dark.json
Tests: WikilinkClosingTests.swift, CardWikilinkCompletionTests.swift, CompletionPanelTests.swift, TagDateClickTargetTests.swift, ProseParagraphSpacingTests.swift, DesignSystemTests.swift, ProseTypographyTests.swift
Red: no
Signatures:
- WikilinkTrigger.closingInsertion — `static func closingInsertion(of title: String, ahead: Substring) -> (text: String, caretOffset: Int)`
- MarkdownAttributedText.clickURL — `static func clickURL(for span: MarkdownStyler.Span, source: Substring) -> URL?`
- ProseParagraphSpacing.paragraphRanges — `static func paragraphRanges(in text: String, spans: [MarkdownStyler.StyledRange]) -> [NSRange]`

**Completion.**

- `CompletingTextView.refreshCompletion` (`:224`) builds `.wikilink` items from
  `CardWikilinkCompletion.candidates(matching:notes:boards:limit: 12)`. `notes` is
  `noteTitles.map { WikilinkNote(title: $0, aliases: noteAliases[$0] ?? []) }`.
- `apply` (`:312`) inserts through `closingInsertion` for `.wikilink` and leaves `.text` as it is,
  so sections and tags are unchanged.
- `CompletionPanelView` draws `label`.
- `noteTitles` stays: `CompletingTextView+Pasteboard.swift:323`, a protected file, reads it.
- `noteAliases` is fed where `noteTitles` already is: `EditorColumnView.swift:67`/`:93` and
  `TodayView.swift:27`/`:64`/`:217` from `vault.index.allNotes` (`frontmatter.aliases`), and
  `DiaryView.swift:108`.
- The card's `applyWikilinkCompletion` (`:267`) uses `closingInsertion` too.

**Click targets.**

- `clickURL` covers three spans:
  - `.tag(name)` becomes `tagURL` when `Tag(name)` parses;
  - `.scheduled`/`.due` become `dayURL` when the source after `>`/`!` is a valid `CalendarDate`;
  - everything else is `nil`.
- `NoteTextView+Coordinator.applyStyling` (`:268`) adds the link through the same `clickable`
  mechanism wikilinks use (`MarkdownAttributedText.swift:216`). The token colour stays and only
  the click gate is added. With `links: false`, nothing is added.
- `performLinkNavigation` gets real arms: `.tag` calls `parent.vault.onOpenTag`, and `.day` calls
  `onOpenDay`. The same goes for the card.
- The Cmd gate is the existing one; a plain click places the caret.
- Wiring the closures to `CommandActions` is Task 7. Here they are inputs.
- Known side effect: «Apri collegamento» and the accessibility link elements now also appear on
  tags and dates. Accept it, and note it in the PR.

**Paragraph spacing.**

- After the spans loop in `applyStyling`, and before `applyTransclusions`, merge
  `paragraphSpacing = ProseTypography.paragraphSpacing(theme)` into the existing paragraph style
  of every range `paragraphRanges` returns. Merge: never replace, because list rendering sets its
  own styles.
- `ProseTypography.paragraphStyle`, the card and `MarkdownAttributedText.attributed` (the
  transclusion picture) are not changed.
- Add `"paragraph": { "$value": { "value": 8, "unit": "px" } }` to both theme files' `spacing`
  group.

**H6.**

- `ProseTypography.heading(level:)`: level 6 returns `font.prose`'s face, which is weight 400, at
  H6's unchanged size. No weight trait (ADR-0030); levels 1 to 5 are unchanged.
- `headingColor(level:)` returns `.textSecondary` for 6 and `.textPrimary` otherwise. Both heading
  arms use it: `MarkdownAttributedText.swift:142` and `CardTextAttributes.swift:121`.
- The exhaustive `colorToken(for:)` tables are left alone.

**After the task.** Run the full TEST-CMD. If the Debug build crashes at launch in
`initializeWithCopy`, read the CLAUDE.md rule on stale incremental builds before suspecting the
change.

### Task 6 — Tester: Cmd+Shift+D, the event note, «Documento», Cmd+N, tag and day opens, inline creation errors (R-09, R-10, R-11, R-12, R-13, R-18)
Owner: tester
Files: Sources/App/Navigation.swift, Sources/App/CommandActions+Open.swift, Sources/App/NewNoteSeed.swift, Sources/App/VaultController.swift, Sources/App/VaultController+Notes.swift, Sources/Features/Workspace/WorkspaceController+Documents.swift, Tests/CommandActionNavigationTests.swift, Tests/NewNoteSeedTests.swift, Tests/NewNoteDraftTests.swift, Tests/QuickOpenCreationTests.swift, Tests/WorkspaceDocumentCreationTests.swift
Tests: CommandActionNavigationTests.swift, NewNoteSeedTests.swift, NewNoteDraftTests.swift, QuickOpenCreationTests.swift, WorkspaceDocumentCreationTests.swift, CommandActionTests.swift, OpenLinkUnresolvedTests.swift, WindowPlaceTests.swift, TagBrowserTests.swift
Red: yes
Signatures:
- Navigation.TagFilterRequest — `struct TagFilterRequest: Equatable { let id: Int; let tag: Tag }`
- Navigation.tagFilter — `private(set) var tagFilter: TagFilterRequest?`
- Navigation.showTag — `func showTag(_ tag: Tag)`
- Navigation.takeTagFilter — `func takeTagFilter() -> Tag?`
- Navigation.noteTreeSelection — `var noteTreeSelection: Set<String> = []`
- CommandActions.open(tag:) — `func open(tag: Tag)`
- CommandActions.open(day:) — `func open(day: CalendarDate)`
- CommandActions.openTodayNote — `func openTodayNote() async`
- CommandActions.openEventNote — `@discardableResult func openEventNote(for eventTitle: String, on day: CalendarDate, start: TaskTime?, end: TaskTime?, attendees: [String]) async -> String?`
- NewNoteSeed.folder — `static func folder(forSelection selection: Set<String>, knownFolders: Set<String>) -> String` (`enum NewNoteSeed`)
- VaultController.beginNewNote — `func beginNewNote(in folder: String? = nil, seed: String? = nil)`
- VaultController.createNote — gains `opening: Bool = true` as its last parameter
- VaultController.quickSwitcherProblem — `var quickSwitcherProblem: String?`
- VaultController.createNoteFromQuickOpen — `@discardableResult func createNoteFromQuickOpen(title: String) async -> Bool`
- WorkspaceController.DocumentCreation — `enum DocumentCreation: Equatable { case created(path: String); case failed(String) }`
- WorkspaceController.createDocument — `func createDocument(titled title: String, at point: CGPoint, through vault: VaultController) async -> DocumentCreation`

**Stored properties** go in the declaring files, since an extension cannot hold one: `tagFilter`
and `noteTreeSelection` in `Navigation.swift`, `quickSwitcherProblem` in `VaultController.swift`.

**Stubs:**

- `showTag` sets nothing, and `takeTagFilter` returns `nil`;
- `open(tag:)` and `open(day:)` do nothing;
- `openTodayNote` calls today's `.dailyNote` body, with no pane change;
- `openEventNote` forwards to `vault.openEventNote`;
- `NewNoteSeed.folder` returns `""`;
- `beginNewNote` ignores `seed`;
- `createNote` ignores `opening`;
- `createNoteFromQuickOpen` calls `createNote` and returns `true`, recording nothing;
- `createDocument` returns `.failed("")`.

**`CommandActionNavigationTests.swift`.** Hosted `CommandActions`, built as
`OpenLinkUnresolvedTests` builds them:

- **R-09.**
  - From the `.tasks` pane, `openTodayNote()` leaves `navigation.pane == .notes` and today's note
    as the focused tab.
  - From `.today` the pane stays `.today`.
  - A missing daily note is created.
  - A failure records a problem and switches nothing.
- **R-10.**
  - `openEventNote(…)` from `.today` leaves `.notes` and the event note focused.
  - Its bytes match Task 1's pin.
- **R-12.**
  - `open(tag:)` sets `.tags`, and `takeTagFilter()` returns that tag once, then `nil`.
  - A second `open(tag:)` with another tag replaces the first. The pane consumes exactly one, so
    nothing accumulates.
- **R-13.** `open(day: 2026-10-12)` sets `.today`, and the `DayController` shows that day
  (`day.day == 2026-10-12`), through `WindowPlace.apply(.day(date, day.scale))`.

**`NewNoteSeedTests.swift`** (R-11):

- `{"Progetti/Alfa"}` with that folder known gives `Progetti/Alfa`;
- `{"Progetti/Alfa/Nota.md"}` gives `Progetti/Alfa`;
- `{"Nota.md"}` gives `""`;
- `{}`, two items, or an unknown id give `""`.

**`NewNoteDraftTests.swift`** (R-11):

- `beginNewNote(seed: "Progetti")` with no parked draft composes in `Progetti`;
- with a parked titled draft, it keeps that draft's folder;
- `beginNewNote(in: "X")` («Nuova nota qui») still overrides, as today;
- `.newNote` through `CommandActions` reads `navigation.noteTreeSelection` from any pane and
  leaves `.notes`.

**`QuickOpenCreationTests.swift`** (R-18):

- `createNoteFromQuickOpen` on a taken title returns `false`, sets `quickSwitcherProblem` to the
  creation failure's sentence (`ConformanceText.creationFailure`) and opens no tab;
- on success it returns `true`, clears the problem and opens the note in a new tab.

**`WorkspaceDocumentCreationTests.swift`** (R-10, R-18):

- `createDocument` on an open board returns `.created`;
- the card is placed and opens no tab: the focused tab and column are unchanged and the pane stays
  `.workspace`;
- the note carries `status-inbox`;
- a taken title returns `.failed` with the sentence and places no card;
- a board switched during the `await` gets no card (ADR-0043 §D7, `placeCreatedNote`'s guard).

These stay unmodified and green: `CommandActionTests`, `OpenLinkUnresolvedTests`,
`WindowPlaceTests` and `TagBrowserTests`.

### Task 7 — Coder: implement the navigation seams and wire the clicks (R-09, R-10, R-11, R-12, R-13, R-18)
Owner: coder
Files: Sources/App/Navigation.swift, Sources/App/CommandActions.swift, Sources/App/CommandActions+Open.swift, Sources/App/NewNoteSeed.swift, Sources/App/VaultController+Notes.swift, Sources/Features/Editor/NoteListPane.swift, Sources/Features/Tags/TagBrowserView.swift, Sources/Features/Today/DayTimeline.swift, Sources/Features/Editor/VaultBrowser.swift, Sources/Features/Editor/QuickSwitcher.swift, Sources/Features/Workspace/WorkspaceView+Creation.swift, Sources/Features/Workspace/BoardSheets.swift, Sources/Features/Workspace/WorkspaceController+Documents.swift, Sources/Features/Editor/EditorColumn+Text.swift, Sources/Features/Today/TodayView.swift, Sources/Features/Diary/DiaryView.swift, Sources/Features/Workspace/StickyTextCard.swift
Tests: CommandActionNavigationTests.swift, NewNoteSeedTests.swift, NewNoteDraftTests.swift, QuickOpenCreationTests.swift, WorkspaceDocumentCreationTests.swift, TagDateClickTargetTests.swift
Red: no
Signatures:
- CommandActions.openTodayNote — `func openTodayNote() async`
- VaultController.createNote — `func createNote(title: String, in folder: String = "", date: CalendarDate, category: NoteCategory = .note, topics: [Tag] = [], body: String = "", opening: Bool = true) async throws -> String`
- WorkspaceController.createDocument — `func createDocument(titled title: String, at point: CGPoint, through vault: VaultController) async -> DocumentCreation`

**R-09.** `runFile(.dailyNote)` calls `openTodayNote()`. That function:

1. reads `navigation.pane`;
2. awaits `vault.openDailyNote(for: .today)`;
3. after the await, sets `.notes` only if the pane read is not `.today` and the pane is still
   that value.

A failure keeps today's `recordProblem` sentence.

**R-10.**

- **The event note.** `DayTimeline.openEventNote` (`:133-148`) goes through
  `commandActions.openEventNote`, from `@Environment(CommandActions.self)`, which sets `.notes`
  after a successful open.
- **«Documento».**
  - `createDocument` calls `vault.createNote(…, opening: false)`, still followed by the rescan,
    then `placeCreatedNote` with the board read before the `await`.
  - `WorkspaceView+Creation.create(.note…)` awaits it.
  - `NewCanvasItemSheet` (`BoardSheets.swift:3-46`) stays open, with the draft kept, until
    `.created`, and shows `.failed`'s sentence inside the sheet as the Cmd+N composer does.
  - The sheet must not close before the write ends. This changes today's close-then-create order.

**R-11.**

- `NoteListPane` mirrors `selectedRows` (`:53`, updated in `syncSelectedRows` `:445`) into
  `navigation.noteTreeSelection` on every change.
- `runFile(.newNote)` passes the seed: `NewNoteSeed.folder(forSelection:knownFolders:)` with the
  session's folder list.
- `beginNewNote` applies `seed` only when it builds a fresh draft.

**R-12, R-13.**

- **Navigation.** `Navigation.showTag` sets `.tags` and a request with a fresh `id`.
  `TagBrowserView` consumes it with `.onChange(of: navigation.tagFilter?.id)` plus `.task` on
  appear, replacing `chosen` (`:26`) with exactly that tag.
- **The opens.** `CommandActions.open(tag:)` calls `navigation.showTag`, and `open(day:)` applies
  `WindowPlace`'s `.day`.
- **The closures.** `onOpenTag`/`onOpenDay` are wired to those two in four places:
  `EditorColumn+Text.swift` (`:72`, `:107`), `TodayView.swift:224`, `DiaryView.swift:115` and
  `StickyTextCard.swift:109`.

**R-18.**

- `VaultBrowser.open(choice)` (`:71`) calls `createNoteFromQuickOpen` for `.createNote` and
  dismisses only on `true`.
- `QuickSwitcher` shows `quickSwitcherProblem` under its field, in `.caption`/`.textSecondary`
  tokens, and clears it on the next keystroke.
- No other `recordProblem` site changes (SPEC Out of scope).

**After the task:**

- run the full TEST-CMD;
- run `scripts/uitests.sh --status`;
- `--affected` at merge belongs to Task 8.

### Task 8 — Tester: full verification, the R-22 hand check and the ledger (R-22)
Owner: tester
Files: TODO.md
Tests: PergamenumTests, mcp-smoke.py, uitests.sh
Red: no
Signatures:
- scripts/uitests.sh — `--status`, then `--affected` at merge (CLAUDE.md merge-gate rule)
- scripts/mcp-smoke.py — `scripts/mcp-smoke.py [binary]`

**Automated checks:**

- the full TEST-CMD;
- builds of `perg` and `pergamenum-mcp`;
- `scripts/mcp-smoke.py`;
- `scripts/uitests.sh --status`, then `--affected`. Read a red from its `.xcresult` before
  rerunning anything; it does not block the merge.
- `scripts/check-adr-references.py`;
- `scripts/check-merge-integrity.py --landing` through the pre-push hook.

Then give Stefano the R-22 script, one step at a time, on this checkout's Debug build. Find the
build by `WorkspacePath` as CLAUDE.md shows, and launch it with `open -n "$APP" --args
-recentVaults '("<vault>")'` on a throwaway copy of a vault.

1. From Safari, Ctrl+Opt+Space, type `Idea: usare i token anche per i font?`. The caption reads
   «Titolo: Idea usare i token anche per i font». Press Return. `00 Inbox/Idea usare i token anche
   per i font.md` exists, with `type-note` and `status-inbox`, and the whole line in the body.
   `perg lint` reports nothing for it.
2. In a note, `[[Tras` + Return gives `[[Trasmissibilità e rapporto di frequenza]]`, caret after
   `]]`. A note with an alias shows «Titolo · alias: X».
3. From Attività, Cmd+Shift+D shows today's note in the Note pane. From Oggi the pane stays.
4. Cmd+click `#client-acme` opens Tag narrowed to it. Cmd+click `>2026-10-12` opens Oggi on that
   day. A plain click only places the caret.
5. Further checks:
   - Impostazioni › Convenzioni › Cartella inbox set to `Triage`: the next capture lands in
     `Triage/` with no relaunch (R-17);
   - an event note opens in Note;
   - «Documento» stays on the board with its card;
   - Cmd+N from a selected folder composes there;
   - a taken title in Quick Open and in «Documento» is reported in place;
   - `spacing.paragraph` (8 pt) and H6 look right in light and dark (R-14, R-15).

**The ledger.** Correct the `PG-384` entry's wording, which cites ADR-0008 §D6 for the
`status-inbox` promise; ADR-0080's Context gives the right sources. Record tasks 1 to 7 and 9 as
done and task 8 (`PG-219`) as open. Go through the project's usual `chore(tasks)` ledger sync, not
a hand edit inside the feature PR, so the parallel TODO.md sync PRs do not conflict.

## Requirement coverage

| Id | Tasks | Test or check |
|---|---|---|
| R-01 | 1, 2 | `TopiclessNoteRuleTests`, `TopiclessCreationPathTests`, `NoteTemplateTests` |
| R-02 | 1, 2 | `TopiclessCreationPathTests` (byte pins, lint, MCP diff) |
| R-03 | 1, 2 | `CaptureTitleTests`, `CaptureTests` |
| R-04 | 1, 2 | `CaptureTitleTests`, `CaptureTests` |
| R-05 | 1, 2 | `CapturePanelTests` |
| R-06 | 1, 2 | `ConventionsNamingTests`, `PraticaNamingTests` unmodified, `CaptureTitleTests` |
| R-07 | 4, 5 | `WikilinkClosingTests`, `CompletionPanelTests` |
| R-08 | 4, 5 | `CardWikilinkCompletionTests`, `CompletionPanelTests` |
| R-09 | 6, 7 | `CommandActionNavigationTests` |
| R-10 | 6, 7 | `CommandActionNavigationTests`, `WorkspaceDocumentCreationTests` |
| R-11 | 6, 7 | `NewNoteSeedTests`, `NewNoteDraftTests` |
| R-12 | 4, 5, 6, 7 | `TagDateClickTargetTests`, `CommandActionNavigationTests` |
| R-13 | 4, 5, 6, 7 | `TagDateClickTargetTests`, `CommandActionNavigationTests` |
| R-14 | 4, 5 | `ProseParagraphSpacingTests`, `DesignSystemTests`, `ListIndentFontInvariantTests` |
| R-15 | 4, 5 | `ProseTypographyTests` |
| R-16 | 1, 2 | `InboxFolderSettingsTests`, `InboxFolderReachTests` |
| R-17 | 1, 2 | `InboxFolderReachTests`; the field by hand (Task 8) |
| R-18 | 6, 7 | `QuickOpenCreationTests`, `WorkspaceDocumentCreationTests` |
| R-19 | 3 | no-test: SPEC §8.1 and §10 read against `ShortcutCommand.defaultBinding` |
| R-20 | 3 | no-test: SPEC §4.3/§16, ADR-0080, the `CLAUDE.md` index line |
| R-21 | 3 | no-test: the four comments, plus the `rg` check in Task 3 |
| R-22 | 8 | no-test: Stefano's hand check |

## Order and dependencies

- **The merge comes first.** Merge `origin/main`, then `tuist install` and `tuist generate`.
- **Session 1 runs 1 → 2 → 3.** Task 1 is red before Task 2 runs (`/build` runs the tester
  first). Task 3 depends on nothing in code and goes last, so the SPEC text describes merged
  behaviour. Then come the HITL commit gate, the push and PR 1.
- **Between the sessions.** After PR 1 merges, the ADR-0080 flip to `accepted` is the first docs
  change (Task 3's last paragraph). Session 2 starts from the updated `main`.
- **Session 2 runs 4 → 5 → 6 → 7 → 8.**
  - Tasks 4/5 and 6/7 are independent of each other.
  - Task 7 wires the closures Task 4 declared, so 4 and 5 go first.
  - Task 8 closes PR 2.

## Observable contracts changed: call sites found

These greps ran on 2026-10-04 against `6c03f024`. Re-run them after the `origin/main` merge, then
update every listed site and every test asserting the old behaviour.

1. **`createNote` output for a topic-less note** (`initialTags`).
   - Producers: `VaultSession+Notes.swift:56`, plus `VaultSession+Tasks.swift:318` and
     `ContenitoreScheda.swift:49`, which stay `.capture`.
   - Callers inheriting the rule:
     - `VaultBrowser.swift:83`;
     - `NewNoteComposer.swift:212`;
     - `WorkspaceView+Creation.swift:84`;
     - `PraticaCommandActions+Links.swift:144`;
     - `VaultPraticheLinks.swift:263`, `:322`;
     - `VaultWrites.swift:73`;
     - `VaultCapture.swift:158`;
     - `VaultSession+EventNotes.swift:48`;
     - `VaultSession+Notes.swift:125`;
     - `CLI/Commands/WriteCommands.swift:12`;
     - `MCPServer/VaultHost.swift:186`.
   - **Stale:** `NoteTemplateTests.swift:106` and `:125-131`.
   - **Checked and green:**
     - `GuardrailTests.swift:84` (a `contains`);
     - `ConventionsImportTests.swift:53-55`;
     - `VaultSessionTests.swift:108-128`;
     - `VaultTests.swift:506-508`;
     - `CategoryLintTests.swift:186`;
     - `FrontmatterRoundTripTests.swift:60`;
     - `BoardDropTests.swift:65`. These last three are hand-written fixtures, not `createNote`
       output.
2. **The capture first line: a refusal becomes a derivation.** **Stale:** `CaptureTests.swift:94-110`.
   `CRLFCaptureTests.swift` uses legal lines and stays green.
3. **`VaultAPI.CaptureDestination.defaultFolder`, deleted.**
   - `VaultCapture.swift:31`, `:161`;
   - `CaptureController.swift:77` (doc);
   - `CapturePanelView.swift:102`, `:110`, `:281`;
   - `VaultController+Import.swift:26`, `:60`, `:72`.

   No test references it.
4. **`VaultSession.TaskDestination.relativePath`, deleted.** `VaultSession+Tasks.swift:36-41`,
   `:226`; `TaskComposer.swift:177`. No test references it.
5. **The default inbox path shown or opened as a literal.**
   - Sites: `TaskComposer.swift:212`, `PergamenumApp.swift:290`, and the docs at
     `VaultCapture.swift:19`, `:29`.
   - Tests read `TaskDestination.inboxPath` as the default, and that stays valid:
     - `WorkspaceIntegrationWalkTests.swift:73`;
     - `VaultSessionTests.swift:116`;
     - `CRLFAppendTests.swift:59`, `:168`;
     - `VaultUnguardedWriteGuardTests.swift:146`, `:169`;
     - `CapturePanelTests.swift:286`.
6. **Strings naming `00 Inbox`.**
   - `HelpSheets.swift:98`;
   - `VaultCommands.swift` (the import alert, `:83` on `origin/main`);
   - `FileImportSheet.swift:17`;
   - `CLI/Help.swift:36`;
   - `ToolCatalogue+Writing.swift:137`.

   `DesignGallery` mockups are left as fixtures. `scripts/mcp-smoke.py` asserts the tool list; run
   it.
7. **`[[` insertion now writes `]]`, and the `CompletionItem.wikilink` case.**
   - Switches: `CompletionPanel.swift:20-47`, `CompletingTextView.swift:319-325`.
   - `CompletionPanelView.swift:109`, `:208` use `if case`, unaffected.
   - **Stale:** `CompletionPanelTests.swift:36-39`, `:183-192`, `:259-268`.
8. **`LinkClickTarget` gains `.tag`/`.day`.** Switches: `NoteTextView+Coordinator.swift:248-262`,
   `CardTextView.swift:338`. The `MarkdownAttributedTextTests` and `CardTextViewTests:195` click
   cases stay green.
9. **`WikilinkCandidate` gains a defaulted field.** `CardWikilinkCompletion.swift:76`, `:81` keep
   compiling.
10. **`VaultController.createNote` gains `opening:`, defaulted.** All callers keep opening, except
    `createDocument`.

Run the **full** `PergamenumTests` suite after each of these changes, not only the new files.

## Risks and HITL gates

**Risks:**

- **The merge.** `origin/main` moved under `TokenKeys.swift`, `Theme.swift`, the theme JSON files
  and `DesignSystemTests.swift` (PG-263's icon tokens). Merge before Task 1, or Task 4's token
  edit conflicts. Merging `main` in is the repo's rule (memory: parallel chains), never a force.
  The pre-push merge-integrity check guards the result.
- **The PG-225 token trap.** A `SpacingToken` case without its `Theme.emergency` entry kills the
  test process, not one test. Task 4 adds both in one edit.
- **Exhaustive switches.** Task 4's new enum cases fail the build unless every switch gets an arm.
  A build that does not compile produces no red at all.
- **Transclusion layout.** `paragraphSpacing` is the mechanism transclusion uses to reserve height
  (`NoteTextView+Transclusion.swift:171`). Task 5 merges into, and never overwrites, a line's
  style, and transclusion lines are excluded. The transclusion suites guard it.
- **The protected file.** `CompletingTextView+Pasteboard.swift` stays byte-identical, and
  `noteTitles` stays.
- **Wider link affordances.** Tags and dates gain the link context-menu item and accessibility link
  elements. This is accepted and noted in PR 2. Report it if Stefano dislikes it at the hand check.
- **Stale DerivedData crash.** See the CLAUDE.md rule; it is not a defect of this change.
- **SwiftLint.** Introduce no new violations in touched files. `CaptureTitle.swift` and the
  `CommandActions` extension stay small.
- **Contract change for connector users.** A model calling `create_note` without a topic now gets
  `status-inbox` in its diff and file. The tool descriptions say so.
- **No externally provisioned resource is needed:** no network, no new dependency, no new
  permission, no port.

**HITL gates:**

- G0/GATE 1, plan approval, including the eleven interpretations above and the session split
  departure;
- the commit gate at the end of each session;
- the push of each branch;
- the merge of PR 1, then the ADR-0080 flip commit;
- the merge of PR 2;
- Stefano's hand check (R-22) before PR 2 merges;
- the ledger sync;
- no schema change, deletion of user data or deploy is involved.

Two code deletions happen in Task 2, `CaptureDestination.defaultFolder` and
`TaskDestination.relativePath`. They are symbol deletions inside a reviewed diff, not file
deletions.

## Candidates

TEST-CMD CANDIDATE: xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -only-testing:PergamenumTests test
TEST-CMD MODE: brownfield

This keeps `.claude/test-cmd` unchanged. The `-only-testing:PergamenumTests` restriction is
load-bearing (CLAUDE.md, the Stop hook), and this chain adds no GUI test.

CHECK-CMD CANDIDATE: NONE

The project declares no static check that is green on the tree. `ci.yml` does not run SwiftLint,
and a whole-repo `swiftlint lint` exits non-zero on the existing debt, so as a stop-gate it would
fail every turn for reasons this chain did not introduce. Per-file SwiftLint on the touched files
stays a review step (Standing rule 8), not the gate.

## Build result (2026-10-05)

BUILD · DONE WITH WARNINGS

Files: 54 changed files (editor and navigation seams in App/Features/DesignSystem, theme tokens, 7 new test files plus edits to existing ones)
Tests: 5374 passed in 312 suites, 5 known issues, 0 (coverage)
Review: sonnet, safe; opus, safe
Coverage: STALE-WAIVER	R-22
Dropped: 1 (nit 1)
Dispatch: Round 0 (red): tester — Task 4, tester — Task 6
Dispatch: Round 1: debugger — CommandActions.swift:168, debugger — BoardSheets.swift:47, coder — Navigation.swift:407, coder — ProseParagraphSpacing.swift:33
Dispatch: Round 2: debugger — NewNoteSeed.swift:15, coder — CommandActions.swift:171
Dispatch: Round 1 (sweep): coder — 5 NITs and 4 follow-ups
Dispatch: Round 2 (sweep): coder — CardTextAttributes.swift:12, DesignSystemTests.swift:188, Navigation.swift:289
WARN: STALE-WAIVER R-22, the (no-test: …) exemption is mentioned in a test file the plan names; delete the clause from the SPEC (not auto-repaired)
INFO: scope is session 2 of the plan (Tasks 4 to 8); Tasks 1 to 3 merged with #897
INFO: review escalated, size: 50 changed files, threshold 20
INFO: opus BLOCKER TODO.md:4 discarded as a verified false positive: local main advanced to 05fa8bb2 (#902) after the branch, TODO.md is unchanged against HEAD
INFO: the second sweep round (RootView.swift noteTreeSelection clear, CardTextAttributes header, one test line wrap) was not re-reviewed; suite green after it
INFO: Task 8 hand check R-22 done by Stefano on 2026-10-05, Debug build, dark theme for the spacing and H5/H6 checks, light theme pending: capture, [[ completion, Cmd+Shift+D, Cmd+click on a tag and a date, inbox folder change, event note, Documento, Cmd+N seed, taken title in Documento all as specified. The check found one defect, fixed in CompletionPanelView.swift: the alias caption was cut off by a long title in the 340 pt panel, and now the title gives way. A taken title cannot be reached by hand from Quick Open (the index matches case-insensitively); the unit test covers it
INFO: the TODO.md ledger sync (chore(tasks)) is not done; uitests.sh --status has no verdict for this tree, --affected runs at merge

```text
DROP	nit	**NIT** Sources/Features/Editor/CompletingTextView+Context.swift:166 — substring(from:) copies the whole remainder of the note to inspect two characters (same shape in FormattingTextView.swift:272); use substring(with:) of length min(2, remaining). (reviewer: opus)
FIX	swept	Tests/DesignSystemTests.swift:110 and Tests/CommandActionNavigationTests.swift:77 long lines wrapped
FIX	swept	Tests/WorkspaceDocumentCreationTests.swift stale red-phase assertion now asserts .created
FIX	swept	clickURL switch made exhaustive (MarkdownAttributedText+Clicks.swift)
FIX	swept	NoteTextView.swift aliasesByTitle moved below the stored properties
FIX	swept	CardTextAttributes.swift doc comment and header corrected (#188)
FIX	swept	NoteTextView+Coordinator.swift applyStyling spacing block moved to ProseParagraphSpacing.apply
FIX	swept	NewNoteSeed.swift header comment corrected
FIX	swept	CommandActions.swift runFile complexity 11 to 10
FIX	swept	DesignSystemTests.swift:188 long line wrapped
FIX	swept	RootView.swift noteTreeSelection cleared when the vault root changes
```
