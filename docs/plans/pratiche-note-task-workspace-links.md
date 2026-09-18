# Collegamenti Pratiche a note, attività e workspace — implementation plan

- **SPEC:** `SPEC.md` at the repository root, Status Approved (2026-09-18). Its `## Decisions`,
  `## Constraints` and `## Test seams` are settled input and are not reopened by any task below.
- **ADR:** `docs/adr/0049-pratiche-links-to-notes-tasks-and-boards.md` (new, this chain). Read
  **§D1, §D2, §D4, §D7 and §D8** before writing a line: each of them is a decision the "obvious"
  implementation violates silently rather than loudly.
- **Governing prior ADRs, registered and not reopened:** ADR-0036 §D5/§D6/§D12/§D21,
  ADR-0021 §D1–§D4, ADR-0022, ADR-0025 §D5, ADR-0039 §D3, ADR-0040 §D3, ADR-0042 §D8,
  ADR-0043 §D8, ADR-0046 §D1, ADR-0007 §D2/§D6, ADR-0001 §D1, ADR-0045 §D4.
- **UX-BLUEPRINT.md** (root, Pratiche scope) is a fixed input for identifier naming, column
  composition and the accessibility checklist. It predates this feature and names none of it;
  the new identifiers below extend its `pratiche-*` family rather than starting a second one.
- **Baseline:** worktree `Pergamenum.worktrees/feat-note-project`, branch `feat-note-project`,
  HEAD `a501823`, `SPEC.md` modified. The branch name does not match CLAUDE.md's Conventional
  Branch rule (`feature/pratiche-links` would); renaming is the orchestrator's call, not part of
  any task below.
- **Requirement ids** are the SPEC's own, R-01 … R-10. Every one is cited by at least one task;
  the coverage matrix at the foot is the check. No id in this SPEC carries a `(no-test:)` marker.
- **External dependencies:** none added. The only third-party packages in the project are the MCP
  Swift SDK (pinned 0.12.1, `Tuist/Package.resolved`) and Sparkle (2.9.6); Task 7 adds entries to
  the existing `ToolCatalogue` using the same `Tool(...)` construction already in the file and
  touches no SDK API. A documentation check found nothing Swift-SDK-specific that bears on this
  plan.

## Standing rules for every task

1. **Run the whole `PergamenumTests` target after every task**, never a per-file selection. This
   chain changes two command catalogues, a `MailFrontmatter` shape and a timeline row's layout;
   a contract change here reaches tests in files that have nothing to do with links.
2. **`tuist generate --no-open` before building in any task that adds a file** (Tasks 1, 2, 4, 5,
   6, 7 add files). The generated project lists files explicitly; skipping it produces an error
   naming the compiler rather than the cause.
3. **Both connector targets build in Tasks 1, 2 and 7**, not only the app:
   `xcodebuild -workspace Pergamenum.xcworkspace -scheme perg -destination 'platform=macOS' build`
   and the same for `pergamenum-mcp`. Files under `Sources/Core/**` and `Sources/Connector/**`
   are covered by the globs in `Project.swift:86-90`; anything added outside them must be named
   in `sharedSources` **by hand**. A new file under those two trees that imports SwiftUI or
   AppKit breaks both tool builds by design (ADR-0001 §D1) and is also caught by
   `Tests/SharedSourcesPurityTests.swift`.
4. **The tester owns every new signature.** Swift is compiled: a red test referencing a
   declaration that does not exist is a build failure, not a red test. In each task the items
   under **Declare first** are added with their final signature and a compiling body (the
   existing behaviour, or a stub returning the empty/`missing` case) *before* the assertions are
   written; the behaviour that turns them green is the task's second half.
5. **`swiftlint --quiet` after every task**, no new violation on a touched file. `.swiftlint.yml`
   errors at 1000 lines per file and 350 per type body; a type that outgrows it splits into
   `Type+Aspect.swift` extensions (ADR-0045's shape), never into a type invented for size.
6. **One commit per task**, Conventional Commits in English: `feat(pratiche):`,
   `feat(connector):`, `docs(adr):`, `test(...)`.
7. **Never disable, skip or delete a test to make the suite pass** (CLAUDE.md).
8. **No hardcoded colour in any view.** The broken-reference treatment is
   `questionmark.square.dashed` plus the `textTertiary` token, which is what
   `BoardTray.noteRow` already draws for an unresolved reference — no new design token, no theme
   JSON change.
9. **UI strings Italian; code, comments and commits English.**
10. **`scripts/uitests.sh` by hand before the merge to `main`** (Task 8), not per task.

---

## Task 1 — The two codecs and the one resolver (R-07, R-08)

Pure `Sources/Core`, Foundation-only, no UI and no writing. This is where R-07 and R-08 are
actually decided, and where they are pinned.

**Files created**

- `Sources/Core/Pratiche/PraticaLinks.swift` — the three `pergamenum-dossier-links-*` keys
  (ADR §D1), rendered and parsed over `Frontmatter.ForeignKey` through the existing `DossierYAML`
  subset, plus `merging(_:into:)` with `Dossier.merging`'s in-place, byte-preserving rule, plus
  `parse(praticaFileAt:)` mirroring `Dossier.parse(praticaFileAt:)` **including its doc comment's
  warning about the index** (ADR §D4).
- `Sources/Core/Pratiche/PraticaLinkReference.swift` — the one renderer and the one parser for a
  reference's text: `[[Titolo]]`, `[[Nome.canvas]]`, `[[Nota]] ^id(3)` (ADR §D2, §D3). Written
  once so a future surface cannot spell a reference a second way.
- `Sources/Core/Pratiche/PraticaLinkResolver.swift` — `unique(String)` / `ambiguous` / `missing`
  for the four relations, with candidates **passed in** (ADR §D5). The board case delegates to
  `WorkspaceBoardResolver.resolve(_:in:)` literally; the note case folds
  `IndexSnapshot.resolve(title:)`'s `[String]`; the task case resolves the note half the same way
  then looks for the `^id`.
- `Tests/PraticaLinksTests.swift` — the SPEC's "parsing/scrittura delle nuove chiavi frontmatter"
  and "risoluzione by-title e rilevamento di link rotto" seams.

**Files modified**

- `Sources/Core/Pratiche/MessageDocument.swift` — `MailFrontmatter.linkedNote: String?`,
  defaulted `nil` and declared immediately after `pendingInlineImages`; rendered in
  `foreignKeys(of:)` between `inlinePendingKey` and `storeReferencesKey`; `noteKey` and
  `noteLine(for:)` beside `inlinePendingLine(for:)` so the key's text has one source (ADR §D6).
- `Sources/Core/Pratiche/MessageDocument+Reading.swift` — read the key back via the existing
  `scalar(_:_:)`.
- `Tests/MessageDocumentTests.swift` — round-trip of the new key, and a file written before it
  existed still parsing.

**Declare first (tester)**

`PraticaLinks` (parse → empty, render → `[]`), `PraticaLinkReference` (render → the input,
parse → `nil`), `PraticaLinkResolver` (every entry point → `.missing`),
`MailFrontmatter.linkedNote` with its default.

**Contract changes**

- `MessageDocument.MailFrontmatter`'s memberwise initialiser gains a defaulted parameter.
  Call sites, grepped: **8 occurrences of `MailFrontmatter(` across 7 files** —
  `Sources/Features/Pratiche/PraticaSyncEngine+Messages.swift`,
  `Sources/Core/Pratiche/MessageDocument+Reading.swift`, `Tests/PraticaLedgerTests.swift`,
  `Tests/MessageAttachmentPatchTests.swift`, `Tests/VaultBoundaryCallSiteTests.swift`,
  `Tests/PraticheControllerTests.swift`, `Tests/PraticaTimelineTests.swift`. All use keyword
  form, so the default keeps every one compiling; confirm rather than assume before moving on.
- `MessageDocument.render`'s output gains one line when a link exists. No protected interface is
  touched: `MessageDocument.isPendingAttachmentEntry` and `PraticaNaming.messageFileName` keep
  their signatures, and `Dossier.render` is not edited at all (ADR §D1).

**Assertions this task owns**

- R-07 at the level it is decided: `NoteRename.rewritingLinks` over a rendered `pratica.md` and
  over a rendered message file follows a **note** rename and a **board** rename, and
  `[[Nota]] ^id(3)` comes back as `[[Nuova]] ^id(3)` with the marker intact.
- R-08: resolution is `missing` for a target no longer in the candidate list, and the reference
  is still present in the parsed value — nothing is removed.
- Ambiguity is `ambiguous`, the same case `WorkspaceBoardResolver` already produces.
- A `pratica.md` carrying dossier keys and links keys round-trips through both merges, in either
  order, byte-for-byte on everything neither codec owns.

---

## Task 2 — The two write doors, and `^id` allocation (R-01, R-02, R-07)

The writing half, still with no UI: what the commands of Task 4 and the connector of Task 7 both
call.

**Files created**

- `Sources/Features/Pratiche/PraticaLinksWriter.swift` — `DossierWriter.update`'s shape exactly
  (`DossierWriter.swift:25-44`): read through `session.read`, mutate, `PraticaLinks.merging`,
  `try await session.write(..., expecting: record.contentHash)`, return the Italian refusal
  sentence on `VaultSession.WriteRefusal`, write nothing when nothing changed (ADR §D11).
- `Tests/PraticaLinksWriterTests.swift`.

**Files modified**

- `Sources/Core/Tasks/TaskParser+Writes.swift` — `line(for:assigningLocalID:)`, the counterpart
  of `line(for:assigningWorkspace:)` beside it; allocation through the existing
  `TaskParser.nextLocalID(in:)` with `insertingSubtask`'s staleness guard (ADR §D3).
- `Sources/Features/Pratiche/PraticaCommandActions.swift` — the message-side write: read the
  file, `MessageFrontmatterPatch.applying(line: MessageDocument.noteLine(for:),
  forKey: MessageDocument.noteKey, before: [storeReferencesKey, "pergamenum-mail-body"], to:)`,
  then `session.write(..., expecting:)`. Unlinking passes `line: nil`, which removes the key —
  the behaviour `MessageFrontmatterPatch` already has.
- `Tests/TaskMarkerTests.swift` (or a sibling) — `^id` allocation does not disturb the rest of
  the line.

**Declare first (tester)**

`PraticaLinksWriter.update(at:session:_:)`, `TaskParser.line(for:assigningLocalID:)` returning
the unchanged line, and the message-side link/unlink entry point on `PraticaCommandActions`.

**Assertions this task owns**

- A link written to `pratica.md` leaves every dossier key byte-identical, and vice versa.
- A link written to a message file leaves every other byte identical (the point of using the
  patch rather than a re-render, ADR §D6).
- A stale `expecting:` hash produces a refusal sentence and **no write** (ADR §D11).
- A task with no `^id` gets one; a task that already has one is not rewritten at all.
- Unlinking removes the key rather than writing an empty value.

---

## Task 3 — «Rigenera» carries the link, and a sync still writes nothing (R-02, R-07)

Three lines of code and the reason they are in this order.

**Files modified**

- `Sources/Features/Pratiche/PraticaSyncEngine+Messages.swift` — in `regenerationPreview`
  (`:670-730`), after `currentText` is read and **before** `UnifiedDiff.between` is called, parse
  the on-disk `pergamenum-mail-note` and patch it into `prepared.noteText`. `PreparedMessage` is
  `fileprivate` in this same file and `noteText` is a `var`, so nothing widens and ADR-0045 §D4's
  "keep the cluster whole" is untouched (ADR §D7).
- `Tests/PraticaRegenerationTests.swift` — a message carrying a link, regenerated, still carries
  it; and the plan's `diff`/`replacementText` contain the key, which is what proves the
  carry-over happened on the side §D21 guarantees.

**Assertions this task owns**

- R-07's regeneration half: the link survives «Rigenera».
- ADR-0036 §D6 is unchanged: an ordinary sync over an unchanged, complete message carrying a link
  writes nothing at all. Assert it, because this is the claim a future reader will doubt.

---

## Task 4 — The commands, the picker, and creating a target from context (R-01, R-02, R-03)

**Files created**

- `Sources/Features/Pratiche/PraticaLinkPicker.swift` — `WorkspacePicker`'s shape (filter, list,
  footer, 380×380), parameterised by target kind, with a «Crea nuova…» row (ADR §D10).
  Identifiers `pratiche-link-picker`, `pratiche-link-picker-filter`, `pratiche-link-picker-create`,
  `pratiche-link-picker-row-<reference>`.
- `Tests/PraticaLinkCommandTests.swift` — the catalogues' new cases and their applicability.

**Files modified**

- `Sources/Features/Pratiche/PraticaCommand.swift` — `.linkNote`, `.linkTask`, `.linkBoard`,
  declared **before `.delete`** (the divider in `PraticaMenuItems.menu` is keyed on `.delete`).
- `Sources/Features/Pratiche/MessageCommand.swift` — `.linkNote`, `.unlinkNote`;
  `available(hasAttachments:)` becomes `available(hasAttachments:hasLinkedNote:)`, with
  `.unlinkNote` offered only when a link exists.
- `Sources/Features/Pratiche/PraticaCommandActions.swift` — the new `run` branches for both
  catalogues; `commands(for detail:)` passes the second argument.
- `Sources/App/Navigation.swift` — one field for the picker's target, held here and not in a view
  for ADR-0039 §D3's reason (the command is offered from the list column, the timeline and the
  inspector).
- `Sources/App/RootView+Sheets.swift` — hosts the picker's `.sheet(item:)`.
- `Sources/Features/Pratiche/PraticaMenuItems.swift` — nothing, if the catalogues are read as
  they already are. Confirm rather than assume: the new cases must appear without a hand-written
  entry, which is ADR-0023 §D1 holding.
- Creation from context (R-03): a new note through `VaultSession.createNote` pre-filled with the
  title from context (the email subject for a message link, the pratica title for a general one)
  and the pratica's own `topic-pratica` / `client-<slug>` tags; a new task through the existing
  capture path with the `^id` allocated by Task 2; a new board through **ADR-0022's existing
  creation flow unchanged** (`WorkspaceFolderActions`), linked immediately after it returns.

**Declare first (tester)**

The three + two enum cases, `MessageCommand.available(hasAttachments:hasLinkedNote:)`, and
`PraticaLinkPicker`'s initialiser.

**Contract changes — grepped call sites, update them in this task**

- `Tests/PraticaCommandTests.swift:18` — `PraticaCommand.allCases.count == 7` → **10**.
- `Tests/PraticaCommandTests.swift:70` — `MessageCommand.allCases.count == 6` → **8**.
- `Tests/PraticaCommandTests.swift` — three calls to `MessageCommand.available(hasAttachments:)`
  take the new argument.
- `Sources/Features/Pratiche/PraticaCommandActions.swift:50` — the one production call site of
  the same function.
- `Sources/Features/Pratiche/PraticaTopBar.swift:58,86` — reads `available(isActive:)` and
  filters it to the two status verbs. Verify the filter is by case and not by position, or the
  status pill will grow three link commands.
- `Sources/Features/Pratiche/PraticaMenuItems.swift:17` — the `.delete` divider, which is why the
  declaration order above is load-bearing.
- No `UITests/` file references either catalogue's count (grepped, none found).

**Assertions this task owns**

- R-01: three commands offered on a pratica row, each producing a link on the right key.
- R-02: `.linkNote` on a message replaces rather than appends — the relation is 0/1.
- R-03: the picker's «Crea nuova…» path produces a target pre-filled with title and tags, then
  links it, in that order (create first, link second: a link to a note that failed to be created
  is worse than no link).

---

## Task 5 — The inspector's link sections and the aggregate list (R-04, R-06, R-09)

**Files created**

- `Sources/Features/Pratiche/PratichePane+Links.swift` — the three new sections under
  `pratica.md`'s body in the existing inspector column, built with `BoardTray.traySection`'s
  shape (a caption header with a count badge, then rows or one line of empty text). A separate
  extension file because `PratichePane+Inspector.swift` is already a split for length
  (ADR-0045 §D3). Identifiers `pratiche-links`, `pratiche-links-notes`, `pratiche-links-tasks`,
  `pratiche-links-boards`, `pratiche-link-row-<reference>`.
- `Tests/PraticaLinkAggregationTests.swift` — the aggregate list's own rule.

**Files modified**

- `Sources/Features/Pratiche/PraticheController.swift` (+ `PraticheController+TimelineRead.swift`)
  — hold the parsed `PraticaLinks` for the selected pratica and the per-message link map, loaded
  on the **same beat** the inspector already uses (`.task(id: pratiche.selection)`,
  `PratichePane.swift:88`) and refreshed after every link write. Reading them per draw would
  reopen every message file on every observable change the pane sees, which is the cost
  `BoardTray` documents for itself.
- `Sources/Features/Pratiche/PraticaRowModels.swift` — `PraticaRowDetail.linkedNote: String?`,
  defaulted and **declared last**, which is the convention that file's own comment states for
  `pendingAttachments`. Call sites: **2, both in
  `Sources/Features/Pratiche/PraticheController+TimelineRead.swift`** (grepped).
- `Sources/Features/Pratiche/PratichePane.swift` — the inspector column renders the new sections
  under the body. **Nothing else about the inspector changes** (R-09, ADR §D9).

**Assertions this task owns**

- R-04: the three sections list what the keys hold, with a broken entry marked and present.
- R-06: the aggregated "note collegate" list is the union of the general note links and the
  per-message ones, de-duplicated, with a per-message one attributable to its message.
- R-09: no code path in this task writes `navigation`'s inspector state or swaps its content —
  a structural check, asserted by the absence being deliberate and recorded, plus the manual
  verification in Task 8.

---

## Task 6 — The aligned column and the row indicator (R-05, R-08)

**Files created**

- `Sources/Features/Pratiche/PraticaMessageNoteSlot.swift` — the per-row slot: the linked note's
  title and opening lines, read-only, opening it with `vault.openChosenNote(at:)` plus
  `navigation.pane = .notes` (ADR §D9); the broken state when resolution is `missing`; an empty
  slot when there is no link. Identifier `pratiche-message-note-<hash>`.

**Files modified**

- `Sources/Features/Pratiche/PraticaTimelineView.swift` — `row(_:)` becomes an `HStack` of the
  message lane plus the fixed-width slot, and the existing `containerRelativeFrame` closure
  (`:140-142`) computes the lane's 70 % on `width - gutter` (ADR §D8). **The trap:**
  `containerRelativeFrame` resolves against the scroll container however deeply it is nested, so
  the gutter must be subtracted explicitly or the lanes will draw underneath the column.
- `Sources/Features/Pratiche/PraticaMessageRow.swift` — the indicator glyph in `header`, drawn
  only when `detail?.linkedNote != nil`, with `accessibilityLabel` and identifier
  `pratiche-message-note-indicator-<hash>`; the row's composed accessibility label gains the
  fact, per UX-BLUEPRINT's checklist.

**Assertions this task owns**

- R-05 is the SPEC's manually-verified half (Task 8). What is assertable here and is asserted:
  the slot's *model* — which reference a row resolves to, and to which of the three states —
  through the resolver of Task 1, without a window.
- R-08's visual half: a `missing` resolution produces the broken state rather than an empty slot,
  and the row keeps its indicator.

---

## Task 7 — The connector: one capability file, two front ends (R-10)

**Files created**

- `Sources/Connector/VaultPraticheLinks.swift` — every read and write of this feature
  (ADR §D12). `VaultPratiche.swift`'s header rule applies verbatim and is repeated in this file's
  own header: **no `MailStore`, `EMLXReader` or `SQLite3` name may appear here** (ADR-0036 R-36).
- `Tests/PraticheLinksConnectorTests.swift` — the SPEC's connector seam, dry-run behaviour
  included.

**Files modified**

- `Sources/Connector/VaultPayloads.swift` — a **new** payload for the links read.
  `VaultAPI.PraticaSummary` is a protected interface and is **not** touched;
  `PraticaTimelinePayload.Entry` (not protected) gains `linkedNote` additively.
- `Sources/Connector/VaultPratiche.swift` — `messageRows` fills the new entry field.
- `Sources/CLI/Commands/PraticheCommands.swift` (+ `Sources/CLI/main.swift` dispatch and
  `Help.swift`) — the read as a printed section and `--json`; the writes through
  `Writing.session(_:command:)`, which arms the session, so `--dry-run` is opt-in on this side.
  That asymmetry with MCP is ADR-0007 §D6's existing contract and is deliberate: do not "fix" it.
- `Sources/MCPServer/ToolCatalogue.swift` — the read tool beside `pratiche`.
- `Sources/MCPServer/ToolCatalogue+Writing.swift` — the write tools, each with the shared
  `dryRunProperty` defaulting to **true**, so they are absent from `tools/list` without
  `--allow-write` and return a diff when `dryRun` is omitted.
- `Sources/MCPServer/VaultHost.swift` — the handlers.

**Assertions this task owns**

- R-10: every read and write of this feature is reachable from both front ends, and a write with
  `dryRun` true changes no byte while still returning the diff.
- The write goes through `VaultSession.write` after `VaultAPI.arm`, so the journal records it and
  `undo` can reverse it.

**Also run:** `scripts/mcp-smoke.py` after this task — the protocol layer has no unit tests and
cannot have them (CLAUDE.md), so the smoke script is the check that the new tools are actually
listed and callable.

---

## Task 8 — Documentation, the protected-interface proposal, and the manual pass (R-04, R-05, R-06, R-09)

**Files modified**

- `CLAUDE.md` — one line in the "Chain decision index" for ADR-0049, in the established shape,
  and one compacted paragraph in the later-chains section.
- `PROJECT_BRIEF.md` — the Status section, per CLAUDE.md's working agreement.
- `docs/adr/0049-…md` — any deviation the chain actually measured, recorded as a follow-up
  section rather than by editing the decisions (the convention ADR-0036 and ADR-0043 follow).

**Proposed, not applied by the coder:** an entry in `.claude/protected-interfaces` for
`Sources/Core/Pratiche/PraticaLinks.swift:PraticaLinks.render`, with the same reasoning
`Dossier.render`'s entry carries — it emits the lines every existing link on disk is recognised
by, so a silent shape change orphans them all. That file is outside this plan's write scope and
the addition is a human decision at a gate.

**Manual verification, per the SPEC's Test seams** (no new automated UI test in this iteration):
`scripts/uitests.sh` with no arguments, then by hand on a Debug build —
the three inspector sections (R-04), the aligned column and the row indicator (R-05), a
per-message note appearing in the aggregate list (R-06), and the inspector never changing content
when a timeline row is selected (R-09). Launch the newest build with `ls -dt`, not `ls -d`
(CLAUDE.md), and kill stale UI-test instances before trusting a red run.

---

## Requirement coverage

| Id | Tasks |
|---|---|
| R-01 | 2, 4 |
| R-02 | 2, 3, 4 |
| R-03 | 4 |
| R-04 | 5, 8 |
| R-05 | 6, 8 |
| R-06 | 5, 8 |
| R-07 | 1, 2, 3 |
| R-08 | 1, 6 |
| R-09 | 5, 8 |
| R-10 | 7 |

## Order and dependencies

1 → 2 → (3, 4, 7 in any order) → (5, 6) → 8. Tasks 5 and 6 both consume Task 1's resolver and
Task 2's writer; Task 3 is independent of the UI and can land as soon as Task 1's key exists;
Task 7 needs 1 and 2 and nothing else.

## Risks, dependencies and HITL gates

- **HITL before every commit, and before the merge to `main`** (CLAUDE.md). No task below commits
  on its own authority.
- **HITL for the `.claude/protected-interfaces` addition** proposed in Task 8: it changes what
  `interface-check.sh` blocks for everyone afterwards.
- **`tuist generate --no-open` after any task that adds or removes a file**, and after any git
  operation that does (`git checkout`, a stash) — the generated project still lists what is no
  longer there and the build fails naming the compiler rather than the cause.
- **A vault-wide note rename now rewrites `email/*.md` files.** This is how R-07 is satisfied for
  free (ADR §D2) and it is new behaviour for those files. It is not an ADR-0036 §D6 trigger (§D6
  governs the sync), but a person watching modification times will see message files touched by
  an operation unrelated to Mail. Verify on a real pratica before the merge.
- **`interface-check.sh` blocks a change to `Dossier.render` and to `VaultAPI.PraticaSummary`.**
  The design deliberately avoids both. A coder who "simplifies" by folding the three keys into
  `Dossier` will trip the gate — and, worse, would make the links erasable by
  `DossierWriter.update` (ADR §D1).
- **Do not read a link off `NoteRecord.frontmatter.foreignKeys`.** On a cache-reused record that
  array is empty, so the feature would work on a freshly scanned vault and silently stop working
  from the second launch (ADR §D4). Read the file, as `Dossier.parse(praticaFileAt:)` does.
- **`regenerationPreview` must patch `prepared.noteText`, not `replacementText`** — the commit
  writes `prepared` (ADR §D7). Getting this wrong produces a sheet that shows the right bytes and
  writes the wrong ones, which is the exact failure ADR-0036 §D21 exists to prevent.
- **The timeline's gutter arithmetic** (ADR §D8): `containerRelativeFrame` measures the scroll
  container regardless of nesting, so the lane factor must subtract the gutter explicitly.
- **Stale link data in the pane**: the links and the per-message map must be refreshed on the
  selection beat *and* after every write, or a section will show what was there before the
  gesture.
- **UI-test hygiene** for Task 8: a new UI-test file would need `-disableCalendar YES
  -disableUpdater YES -mailStoreRoot <fixture>`; this iteration adds none, but a stale instance
  from a previous run still poisons a full run wholesale — kill instances first and read the
  per-test seconds before believing a red.
- **No externally provisioned resource is required.** No network call, no third-party service, no
  OAuth or consent flow, no new environment variable or port, no cloud console. The feature reads
  and writes files this app already owns inside the open vault; the Mail store is not touched by
  any code path in this plan.

---

TEST-CMD CANDIDATE: `xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -only-testing:PergamenumTests test`
TEST-CMD MODE: brownfield
