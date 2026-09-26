# ADR-0063: The connectors refuse malformed input, board creation goes through the session's guarded door, and five more sites resolve through the vault boundary

- Status: **accepted**, 2026-09-26, at gate G1 of `docs/plans/connector-input-hardening.md`.
  Stefano approved all four decisions that go past the SPEC's letter, so §D4.5 is implemented in
  full and R-13 is met by the in-actor guard, not by the filter alone. The four were:
  - §D4.5, `expectingAbsent:` on the `.canvas` write door;
  - §D4.7, the choice to create a missing parent folder;
  - §D1.5, the non-trapping conversion reaching `ToolArguments.int`;
  - §D1.6, the one-line fix to `VaultSession.search`.
- Date: 2026-09-26. Written **before** the implementation, against `a6ce602` (`HEAD` =
  `origin/main`). The tree was clean apart from `SPEC.md` (`shasum` `38a9f1a`). Every file:line
  below was read from that tree today.
- **Numbering note.**
  - `0062` is the highest number under `docs/adr/`, `0061` is used twice, and
    `git log --all -- 'docs/adr/0063*'` is empty.
  - `ROADMAP.md:947` (Chain 14, item 2) proposes renumbering one of the two `0061` files *to*
    `0063`. This ADR takes the number first, so Chain 14 renumbers to the next free one when it
    runs.
- **Path note:** the architect's write scope names `docs/architecture/**`, which does not exist in
  this repo. ADRs live at `docs/adr/NNNN-<slug>.md`, as ADR-0054/0055/0058/0061 already recorded.
- **Why an ADR at all.** `ROADMAP.md:410` sized this chain «S, no ADR». It is written anyway, for
  five reasons:
  - it moves a security boundary: the dry-run lock and the vault boundary each reach a site they
    missed;
  - it writes the protected-interface line ADR-0041 proposed and deferred;
  - it records deliberate deviations a later reader would "fix" (§D4.7, §D5);
  - it widens a shared write door the SPEC assumed was already sufficient (§D4.5);
  - it records explicit no's (§D4.6, §D9).
- Source:
  - `SPEC.md` (Approved 2026-09-26);
  - issue **#570** (`TODO.md:9`, **`PG-256`**, Audit Fable chain 3);
  - **`PG-151`** → #280 (`TODO.md:38`), the protected-interface line ADR-0041 proposed.
- **Extends:**
  - ADR-0007 §D6: the dry-run lock and the journal now reach the one connector write that bypassed
    them;
  - ADR-0041 §D1/§D2: five more call sites resolve through `VaultBoundary`, and ADR-0041's own
    «Protected-interface proposal» is finally written;
  - ADR-0057 §D3: `expectingAbsent` widens from the note door to the `.canvas` door;
  - ADR-0043 §D7/§D8: the board door's precondition sits on the far side of the suspension.
- **Amends none.** ADR-0025 §D1's «`createBoard` creates no directory» stays true of
  `CanvasStore.createBoard`, which the app keeps calling (§D5). The new session door is a different
  door with a different precedent (§D4).
- **Reopens nothing.**
  - No on-disk format or frontmatter key changes. `IndexCache.schemaVersion` stays 4.
  - The write-summary JSON keys are unchanged.
  - The two protected payload shapes (`VaultAPI.LintFinding`, `VaultAPI.PraticaSummary`) are
    untouched.
  - One protected-interface line is **added** (§D8). No protected signature changes.
- **Principle 2 untouched.** Nothing here gains a network path.
- **GUI-test budget: zero.** Nothing in this chain is visible in the app's interface. The MCP
  protocol layer is verified by `scripts/mcp-smoke.py`; everything else is tested in-process.

---

## Context

Audit Fable chain 3 found four defects with one root: `perg` and `pergamenum-mcp` trust the shape
of what they receive. Each was re-read on `a6ce602`.

### A negative number traps the process

- **The journal.** `VaultAPI.journalLog` ends in `.entries().suffix(limit ?? 20)`
  (`Sources/Connector/VaultWrites.swift:340`). `suffix(-1)` is a precondition failure, so
  `perg journal log --limit -1` dies.
- **The resource cursor.** `VaultHost.resources(after:)` (`Sources/MCPServer/VaultHost.swift:276-295`)
  computes `start = cursor.flatMap(Int.init) ?? 0` (`:278`) and slices `notes[start..<end]`.
  - A cursor of `"-1"` traps.
  - `"9223372036854775807"` traps too: `start + Self.pageSize` (`:279`) overflows before the
    `guard start < end` (`:280`) can answer an empty page.
  - A non-numeric cursor silently restarts at page zero. A client that mis-echoes a cursor once
    then loops on page one forever.
- **Search** does not trap on `-1`, but answers empty: the same mistake with a quieter symptom.
- **Both front ends read the number leniently.** `arguments["limit"].flatMap(Int.init)`
  (`Sources/CLI/Commands/JournalCommands.swift:19`, `SearchCommands.swift:13`) and
  `ToolArguments.int` (`Sources/MCPServer/ToolArguments.swift:41-49`) turn `"abc"` into «no limit
  given».
- **`ToolArguments.int` has a trap of its own.** Its `.double` case is `Int(number)` (`:45`), which
  traps on a JSON number outside `Int`'s range. The same function also serves `minutes` and
  `ordinal`.

**Measured while planning:** `VaultSession.search` appends a hit and only then tests
`results.count >= limit` (`Sources/Vault/VaultSession+Search.swift:30-35`). So `limit: 0` answers
**one** hit, and the SPEC's «`0` stays legal and answers empty» is not true of search today.

### A value-taking option eats the next flag

`Arguments.init` (`Sources/Connector/Arguments.swift:56-68`) assigns `options[body] = raw[index]`
to whatever token follows.

- `perg note new Titolo --folder --dry-run` writes for real, into a folder named `--dry-run`.
- `--dry-run=true` takes the `=` branch (`:57-60`) and lands among the options. The flag test
  `has("dry-run")` then fails, so the write is real.
- A bare `--` becomes an option named `""` that swallows the next token.

### Board creation bypasses the lock and the journal

`VaultAPI.createAndLinkPraticaBoard` (`Sources/Connector/VaultPraticheLinks.swift:283-296`) calls
`CanvasStore(root:).createBoard` directly (`:290`).

- `isDryRun` never sees that call, so the MCP default `dryRun: true` still creates the `.canvas`.
- The journal never hears of it.
- The verb's summary is the link's diff alone. So is the summary of the other two «create and
  link» verbs (`:252-262`, `:298-309`). A rehearsal of a two-write verb therefore shows only one of
  the two writes.

**Measured while planning:** the session's `.canvas` write door is `VaultSession.writeFile`
(`Sources/Vault/VaultSession+Journal.swift:199-239`), which calls
`VaultDisk.writeFile(_:to:expecting:journalDescriptor:journal:)` (`Sources/Vault/VaultDisk.swift:349`).

- As the SPEC says, the door honours `isDryRun`, journals, and keeps the index out.
- It has **no** absent precondition, and `expecting:` cannot express «must not exist». A nil
  `hashBefore` never equals a non-nil expectation, so `expecting:` would refuse every creation.
- The SPEC's constraint says: «the taken-name check runs on the same side of the suspension as
  the write, or the write door's own refusal decides». The door as it stands cannot meet it.

### Five disk-touching sites build a path from the root by hand

| Site | Location |
|---|---|
| `VaultSession.importFile` | `Sources/Vault/VaultSession+Notes.swift:96-113` (`:98-100`) |
| `CanvasStore.createFolder` | `Sources/Vault/CanvasStore.swift:293-301` (`:295`) |
| `FolderFileOperations.renameFolder`/`trashFolder` | `Sources/Vault/FolderFileOperations.swift:387`, `:392`, `:440` |
| The connector's pratica timeline | `Sources/Connector/VaultPratiche.swift:187` |
| `Attachment`'s existence probe | `Sources/Core/Conventions/Attachment.swift:99` |

Three of them are reachable with an escaping path today:

- `importFile` beside `../../fuori/n.md` copies outside the vault.
- `createFolder(named: "../../fuori", in: "")` creates a directory outside it.
- `Attachment.resolve("x.png", nearNoteAt: "../../fuori/n.md", …)` probes outside and can answer
  `"../../fuori/x.png"`. Only the *target* is screened for `..` (`:85-87`), never the note's
  folder.

**Measured while planning:** folder rename and trash are **already refused upstream** for an
escaping source.

- `renamePlan` and `trashFolder` both call `isDirectory(_:)` first (`:190`, `:432`). It resolves
  through `store.url(for:)` and answers `false` for a path outside the vault. Both then throw
  `FileOperationError.missing` before `:387/392/440` are reached.
- The destination of a rename is a validated name under the source's own parent.

So those three lines are defence in depth, and the SPEC's «today the path reaches the move» does
not hold.

## Decision

### §D1 — A malformed `limit` is refused in the shared layer, and no reader traps (SPEC Decision 1, registered)

`Sources/Connector` gains one rule and one sentence. Every read and both front-end readers go
through them.

1. **The reads refuse a negative number.**
   - `VaultAPI.search` and `VaultAPI.journalLog` refuse a `limit < 0` with a
     `ConnectorError(…, usage: true)`, **before any disk work**. The usage error therefore wins
     over «vault mai aperto» and similar errors.
   - `0` is legal and answers empty on both.
2. **The text rule lives beside it.** A pure `VaultAPI` function reads an argument's text into an
   `Int?`.
   - `nil` in, `nil` out.
   - Text that `Int.init` does not read, `""` included, is refused with the **same sentence** as a
     negative number. Proposed wording, with the argument's own name and raw value:
     `«limit» vuole un numero intero da 0 in su: «abc» non lo è`.
   - `"-1"` reads as `-1` and is refused by rule 1, never by the parser (§D3).
3. **`perg`** reads `--limit` through rule 2 in `JournalCommands.log` and `SearchCommands.run`.
   This is R-04 and is checked by review only, since `perg` has no harness.
4. **`pergamenum-mcp`** gains a throwing integer reader on `ToolArguments` that keeps «absent»
   apart from «unreadable». `search_vault` and `journal_log` read `limit` through it.

   | JSON value | Result |
   |---|---|
   | absent, or `null` | `nil` |
   | `.int` | the value |
   | `.double` | truncated toward zero; **refused rather than trapping** when outside `Int`'s range |
   | `.string` | rule 2, so `""` is refused rather than treated as absent (unlike `ToolArguments.string`, which does that for a folder) |
   | anything else | refused |
5. **`ToolArguments.int` shares the non-trapping truncation** (`:45`). It keeps its lenient
   «unreadable means absent» contract for `minutes` and `ordinal`, but stops killing the server on
   `1e300`. This is outside the SPEC's R-ids and is put to gate G1, for three reasons:
   - the SPEC's stated objective is «never a dead process»;
   - the conversion is the same one line rule 4 needs;
   - leaving a known trap in a function the task already edits costs more than the line.
6. **`VaultSession.search` answers empty for `limit <= 0`.** The guard sits beside its existing
   `guard !query.isEmpty` (`VaultSession+Search.swift:20`).
   - It is fixed in the session, not short-circuited in `VaultAPI.search`, because the off-by-one
     belongs to the session and the app's own search shares the loop.
   - Every existing caller passes a positive limit, so nothing they see changes.

Rejected, registered from the SPEC:

- clamping to `0`, because it hides the caller's bug;
- the issue's journal-only scope, because search's silent empty answer is the same defect.

### §D2 — The MCP cursor is parsed, not trusted, and lives with the only front end that pages (SPEC Decision 2, registered)

`VaultHost.resources(after:)` becomes `throws`.

- A cursor that `Int.init` does not read, or that reads negative, throws
  `MCPError.invalidParams(…)`. The SDK sends it as JSON-RPC `-32602`, and the session survives.
- `start >= notes.count` answers an empty page with no `nextCursor`, **before** any arithmetic.
- `end` is `start + min(pageSize, notes.count - start)`, so `Int.max` gives an empty page instead
  of an overflow trap.
- `register(_:on:)` (`Sources/MCPServer/main.swift:50-52`) awaits it with `try`.

The rule stays in `Sources/MCPServer`, not `Sources/Connector`.

- Pagination exists in one front end only.
- The error it must produce is an `MCP` type the shared sources cannot name: `perg` does not link
  the SDK.
- Its acceptance is the smoke script, which already fails the run when the server stops answering
  (CLAUDE.md «AI connector»).

Verified against the installed SDK, not recalled:

- `swift-sdk` is 0.12.1 (`Tuist/Package.resolved`).
- `MCPError.invalidParams(String?)` has code `-32602`
  (`Tuist/.build/checkouts/swift-sdk/Sources/MCP/Base/Error.swift:34,53`).
- The server forwards a thrown `MCPError` as-is and wraps anything else as `internalError`
  (`Server.swift:710`).
- The MCP specification revision 2025-11-25 («Pagination › Error Handling») asks for `-32602` on an
  invalid cursor.

### §D3 — The flag parser refuses three shapes (SPEC Decision 3, registered)

In `Arguments.init`, a token beginning `--` is handled in this order:

1. `--` alone throws `ParseError.unknownFlagSyntax("--")`.
2. `--name=value`, where `name` is in `flagNames`, throws a new `ParseError.flagTakesNoValue(name)`.
   Proposed wording: `l'opzione --dry-run non vuole un valore`.
   Any other `--name=value` is an option with `value` taken verbatim. So `--title=--strange` is
   the escape hatch for a value that starts with `--`.
3. `--name`, where `name` is in `flagNames`, is a flag.
4. Otherwise the next token is the value. If there is none, **or it begins with `--`**, the parser
   throws `ParseError.missingValue(name)`. A value beginning with a single `-` (`-1`) is still a
   value.

The parser runs before any dispatch in both entry points, so a refused command line cannot write:

- `Sources/CLI/main.swift:123-127` returns `.usage`;
- `Sources/MCPServer/main.swift:59-65` exits 1.

One consequence is worth knowing: `pergamenum-mcp --vault --allow-write` used to open a vault named
`--allow-write` read-only. It now refuses to start.

### §D4 — Board creation gets a session door modelled on note creation, guarded in the actor

`VaultSession` gains `createBoard(named:in:) async throws -> String` in
`Sources/Vault/VaultSession+Notes.swift`. That file already holds «the writes that add something»
and is already in `sharedSources`, so the manifest needs no edit. The door runs in this order:

1. **Validate the name** with the rule the Workspace creation sheet already applies
   (`WorkspaceFolderSheets.swift:28`).
   - That rule is `FolderFileOperations.validate(_:)`, which is `NoteName.validate` plus the
     `.`/`..` clause (`FolderFileOperations.swift:42-46`).
   - `FolderFileOperations` is not in `sharedSources`, so the rule's body moves to `FolderName` in
     `Sources/Core/Vault/FolderIdentity.swift`. `FolderFileOperations.validate` forwards to it.
     There is one spelling, and every existing caller is untouched.
   - A violation throws `CreationError.invalidTitle`.
2. **One path spelling.** `CanvasStore.boardFilePath(named:in:)` (`CanvasStore.swift:211`, today
   `private`) becomes `internal`, and is the only way the door spells the path. So the SPEC's
   «never a second spelling» holds for the path. Because the door writes
   `CanvasDocument.empty.encoded()`, it holds for the bytes too.
3. **Resolve through the boundary.** `store.url(for:)` on that path. An escaping `parent` throws
   `VaultBoundary.Violation` before anything else, on a rehearsal too.
4. **Check for a taken name, as a filter.** `exists(path)` throws `CreationError.alreadyExists(path)`.
   - This runs before the `await`, so by ADR-0043 §D7 it is a filter, not a guard.
   - It exists so that a **rehearsal** refuses what the real run would refuse. This is the SPEC's
     edge case: a rehearsal that says it would create a board that already exists would be false.
   - It also makes the common case read «esiste già».
5. **The guard is the write door's own refusal.** The door calls
   `writeFile(emptyCanvas, to: path, expectingAbsent: true)`.
   - `VaultSession.writeFile` and `VaultDisk.writeFile(…journalDescriptor:journal:)` gain
     `expectingAbsent: Bool = false`.
   - It is checked inside the actor, immediately before the byte write, on **existence**
     (`fileExists`, `VaultDisk.swift:288`) and not on readability. This is ADR-0057 §D3's rule,
     applied to the non-note door.
   - A refusal is `VaultWriteRefusal.movedOn(path)`: nothing is written and there is no journal
     entry.
   - The default is `false`, so the three existing callers and every existing test keep their
     behaviour.
6. **Dry run and journal are inherited, not re-implemented.**
   - `writeFile` returns before the hop when `isDryRun` is set.
   - On a real run, `VaultDisk` journals the entry under the armed `journalCommand` with
     `textBefore: nil`.
   - `VaultAPI.undo` already declines such an entry with «quella scrittura ha creato… questo
     comando non cancella» (`VaultWrites.swift:301-307`).
   - The journal never deletes. The note-creation precedent and
     `undoingACreationIsDeclinedRatherThanDeletingTheFile` say so.
7. **A missing parent folder is created**, as `createNote` creates one: its write goes through
   `NoteStore.write`, which creates intermediate folders by default. Put to gate G1.
   - This departs from `CanvasStore.createBoard`, which creates no directory (ADR-0025 §D1). That
     store's `parent` is a folder picked from the Workspace tree, and a vanished one must fail
     loudly.
   - A connector's `folder` is typed text, with no tree behind it.
   - The SPEC models this door on note creation, and `create_note` into a new folder already works.

The connector's `createAndLinkPraticaBoard` adopts the door.

- Its rescan after a real creation stays. A rehearsal rescans nothing (SPEC).
- `CreationError` and `Violation` become a `ConnectorError` with their own sentence.
- A `VaultWriteRefusal` becomes the same «non è stato creato: …» shape `updateLinks` already uses
  for its own refusals.

Rejected, registered from the SPEC:

- teaching undo to delete a created board;
- teaching the canvas store about the session. That inverts the dependency; the store stays a pure
  file layer.

### §D5 — The app's two board creations stay on the store (SPEC Decision 6, registered)

`PraticaCommandActions+Links.swift:170` and `WorkspaceView+FolderVerbs.swift:77` keep calling
`CanvasStore.createBoard`.

- The app arms no journal and no dry-run switch, so the door buys it no guarantee.
- Routing two synchronous UI closures through an `async` door is the cascade whose cost ADR-0043's
  implementation notes measured.

A future reader who finds two board-creation paths should read this before unifying them. The
split is deliberate.

### §D6 — A «create and link» summary names the file it creates (SPEC Decision 5, registered)

The three verbs are `createAndLinkPraticaNote`, `createAndLinkPraticaBoard` and
`createAndLinkMessageNote`. Each returns the link's `WriteSummary`, with its existing `note` field
set to a sentence naming the created file. Proposed wording:

- on a rehearsal, `creerebbe «<path>»`;
- on a real run, `creato «<path>»`.

When the link write carried a note of its own (`nessuna modifica`, a link already present), that
note follows after `; `. `path`, `applied` and `diff` stay the link's.

There is no new JSON key. `perg` already prints `note` as a line (`Sources/CLI/Writing.swift:23`).
`createAndLinkPraticaTask` is not one of the three, since it creates no file of its own.

### §D7 — Five sites resolve through the boundary, none of them hands it the root

The resolver refuses the vault root (ADR-0041 §D1), so each site must avoid asking for it:

| Site | Change | Why the root never reaches `url(for:)` |
|---|---|---|
| `VaultSession.importFile` (`VaultSession+Notes.swift:98-100`) | A non-empty note folder resolves through `store.url(for:)`, before `ImportNaming.uniqueFileName` probes it. A violation records a problem and returns `nil`, with nothing copied. | An empty folder is `store.root`, which is derived from no caller input. |
| `CanvasStore.createFolder` (`CanvasStore.swift:295`) | `boundary.url(for: relativePath)` | `relativePath` is `name` or `parent/name`. An empty `name` at the root is `""`, which the resolver correctly refuses. |
| `FolderFileOperations.renameFolder`/`trashFolder` (`:387`, `:392`, `:440`) | Source and destination go through `store.url(for:)`. | Both guards above them already refuse an empty folder (`:183-185`, `:429-431`). |
| `VaultAPI.timeline(ofPraticaFolder:)` (`VaultPratiche.swift:187`) | `session.store.url(for: folder)`, returning `[]` on a violation | A pratica folder is never empty: `praticaNotes` admits only paths ending in `/pratica.md` (`:109`). |
| `Attachment` existence probe (`Attachment.swift:97-103`) | See below. | Candidates are never empty, since `target` is non-empty (`:72`). |

**`Attachment` sits on the editor's path.** The SPEC requires that the boundary reach it without a
symlink resolution per keystroke. `VaultBoundary.init` is where the resolution happens: it resolves
the root once (`VaultBoundary.swift:20-22`). So:

- **The work moves into `resolve(_:nearNoteAt:within boundary: VaultBoundary)`.**
  - When the note's folder is non-empty, it must resolve through the boundary. Otherwise the answer
    is `nil` with **no probe at all**, so «returns no result» holds even when a file of the same
    name sits inside the vault.
  - Every candidate is probed only through `boundary.url(for:)`.
  - `byName` walks from `boundary.root`, which is already resolved, and drops its own second
    resolution.
- **`resolve(_:nearNoteAt:inVaultAt:)` keeps its signature** and builds one boundary per call. It
  serves the existing tests and the three call sites that are off the keystroke path:
  `EmbeddedFileView.swift:33`, `ViewThumbnail` (`ViewGridRenderers.swift:80`), and
  `EditorColumn+Text.swift:32`, which runs on a click.
- **`EmbedTable` is the one call site on the keystroke path** (`NoteTextView+Embeds.swift:181`).
  - It builds its boundary **once per root** and calls the `within:` form.
  - `resolutionCache` already limits resolves to one per (note, target). But a keystroke that edits
    a target inside an existing `![[…]]` is a new key each time. With the memo, even that miss adds
    no resolution.
  - `apply(runs:…)` keeps its parameter list, because it is at SwiftLint's cap (its own comment says
    so).

The folder-rename and folder-trash changes are defence in depth only (see Context). Their tests pin
a refusal that already happens, and the sentence stays `FileOperationError.missing`.

### §D8 — The resolver becomes a protected interface (`PG-151`, operator decision taken in the SPEC)

ADR-0041's «Protected-interface proposal» recommended adding the line after that chain merged. It
merged on 2026-09-13, and the line was never written. This chain writes it: the text is verbatim
from ADR-0041, with the provenance the registry's other lines carry:

```text
Sources/Core/Vault/VaultBoundary.swift:VaultBoundary.url(for:) — added 2026-09-26 per ADR-0041 (proposal) and ADR-0063 §D8 (PG-151, operator decision taken in the connector-input-hardening SPEC); the vault's only path-resolution door; a signature change that removes `throws`, or a behaviour change that resolves symlinks per call instead of once at construction, silently reopens the path-traversal gap ADR-0041 §D1 closed and reintroduces the symlinked-vault regression recorded at NoteStore.swift:48-55
```

Nothing in this chain changes `url(for:)`'s signature or body. `Attachment`'s new form (§D7) takes a
`VaultBoundary` and calls `url(for:)`, which is exactly the use the line protects.

### §D9 — Named here and not fixed

- **The residual path-building sites.**
  - The SPEC counts «thirty-eight other sites across twenty-five files». On `a6ce602`,
    `rg -n "root\.appending\(path:" Sources` returns exactly 38 lines in 25 files. That count
    **includes** the seven lines of the five sites above.
  - After this chain, the same command should return 31 lines in 21 files.
  - The follow-up ledger entry (R-21) carries the count re-measured at ship with that command. It
    names the three heaviest `FileManager.default` concentrations: `PraticaFileOperations.swift`
    (11), `VaultDisk.swift` (10) and `CanvasStore.swift` (7).
  - Among them are the connector's own `praticaLinks`/`praticaNotes` root appends
    (`VaultPraticheLinks.swift:43`, `VaultPratiche.swift:110`).
- **`createNote` has the same filter-before-`await` shape without an in-actor guard**
  (`VaultSession+Notes.swift:52`, `:62`). If two creations of one title run concurrently, the
  second overwrites the first. §D4's `expectingAbsent: true` would close it. It changes a door that
  the app, the daily note and capture all share, so it is its own follow-up.
- **`perg --ordinal abc` and `--minutes abc` still fall back silently**
  (`Sources/CLI/Commands/ViewCommands.swift:40`, `WriteCommands.swift:137`). `ordinal` is
  range-checked downstream; `minutes` is not. Same class as `limit`, outside the SPEC's scope.
- **`--=value`** still parses as an option named `""` (`Arguments.swift:57-60`). It is harmless,
  and the same shape as the bare `--` that §D3 refuses.
- **`VaultSession.unlinkedMentions(limit: 0)`** has search's append-then-test shape
  (`VaultSession+Search.swift:88`). Nothing passes `0`.
- **A board or folder name beginning with `.`** passes `FolderFileOperations.validate` and produces
  a file the walk skips as hidden. This happens in the app, and now through the door as well.

## Alternatives considered

### §D4: where the taken-name refusal is decided

- (a) *The pre-check alone*, as `createNote` does. Rejected for two reasons:
  - it does not meet the SPEC's constraint;
  - the window is real. The MCP server's handlers are `async` on one main actor, so two tool calls
    can interleave at the `await` between the check and the byte write.
- (b) *The door calls `CanvasStore.createBoard`* and journals around it. Rejected:
  - the store writes outside `VaultDisk`'s serialization and outside `isDryRun`, which is the defect
    this ADR fixes;
  - wrapping it adds a second journal writer beside the one the actor owns (ADR-0043 §D1).
- (c) **Chosen:** the pre-check as a filter, so the rehearsal tells the truth, plus
  `expectingAbsent` in the actor as the guard. It costs one defaulted parameter on two functions.

### §D4.7: a missing parent folder

- (a) *Require it*, for parity with `CanvasStore.createBoard`. Rejected: the store's rule exists for
  a folder picked from a tree that can vanish mid-gesture. A connector's folder is typed text, and
  the SPEC models the door on note creation, which creates it. The option also costs more than it
  looks:
  - the `.canvas` door would need `requiringExistingFolder:` as well; that is PG-168's parameter,
    which the note door has and this one lacks;
  - it would also need a second rehearsal pre-check.
- (b) **Chosen:** create it, as `createNote` does.

### §D4.1: which name rule

- (a) *`NoteName.validate` alone*, already in `Sources/Core`. Rejected: it differs from the
  Workspace sheet's rule by the `.`/`..` clause. Through the connector, `.` would produce a hidden
  `..canvas`, while the app refuses it. That is two rules for one kind of name.
- (b) **Chosen:** move `FolderFileOperations.validate`'s body to `Sources/Core`, and leave the old
  name as a forwarder.

### §D7: how the boundary reaches `Attachment`

- (a) *Build a `VaultBoundary` inside every `resolve` call.* Rejected by the SPEC's constraint. The
  editor resolves once per new (note, target) key, and editing a target inside an existing embed
  makes a new key on every keystroke.
- (b) *Thread a `VaultBoundary` from the session through every view, instead of `root`.* Rejected:
  it rewrites the inputs of `NoteTextView`, `EmbeddedFileView` (built at
  `MarkdownBlocksView.swift:89`) and `ViewThumbnail`, all for three call sites that are not on the
  keystroke path.
- (c) *A lexical containment check inside `Attachment`, with no `VaultBoundary`.* Rejected: a second
  spelling of the boundary rule is precisely what ADR-0041 §D1 deleted, and what §D8's registry
  line exists to prevent.
- (d) **Chosen:** a `within:` form that does the work, a wrapper for the callers off the keystroke
  path, and one memoised boundary in `EmbedTable`.

### §D2: where the cursor rule lives

- (a) *`Sources/Connector`*, as a pure function a unit test could reach. Rejected:
  - it has one consumer;
  - the error it must raise is an `MCP` type the shared sources cannot import. A shared function
    returning a neutral error for the server to translate is a layer with nothing to share.
- (b) **Chosen:** `VaultHost`, with the smoke script as the seam the SPEC names.

## Consequences

### Positive

- A malformed number reaches a script or a model as one sentence. `limit` and `cursor` can no
  longer kill either process, and neither can a huge `minutes` or `ordinal` (§D1.5).
- `--dry-run` can no longer be eaten by the option before it, or spelled into a real write.
- Every connector write now passes the dry-run lock and the journal. For all three «create and
  link» verbs, the MCP default `dryRun: true` means what it says, and a rehearsal names every file it
  would write.
- The `.canvas` door gains the creation precondition the note door already had. Any future creator
  of a non-note file can use it.
- `VaultBoundary.url(for:)` can no longer drift silently.

### Negative

- There are two board-creation paths with different folder semantics: §D4.7 against ADR-0025 §D1.
  The split is deliberate and recorded here and in the door's doc comment, but a reader must know
  to look.
- `perg` and MCP callers that relied on the lenient forms now get an error. Examples are
  `--dry-run=true` «working», or a bad `limit` falling back to the default. That reliance was the
  bug.
- The R-17 tests are green before and after the change. They pin a refusal that already happens,
  not the site change; review verifies the site change.

### Neutral

- No format, schema, frontmatter or JSON-key change. `IndexCache.schemaVersion` stays 4.
- `FolderFileOperations.validate` keeps its name, as a forwarder.
- The CLI help text is unchanged (out of scope in the SPEC).

## Acceptance

**Unit suite (`PergamenumTests`), all in-process:**

| File | Covers |
|---|---|
| `Tests/ArgumentsTests.swift` (new) | R-08, R-09, R-10 |
| `Tests/ConnectorTests.swift` | R-01 (shared layer), R-02, R-05, and the text rule R-03 and R-04 rely on |
| `Tests/VaultWriteAbsentPreconditionTests.swift`, `Tests/VaultSessionJournalTests.swift` | the door and `writeFile(expectingAbsent:)` (§D4) |
| `Tests/PraticheLinksConnectorTests.swift` | R-11, R-12, R-13, R-14 |
| `Tests/VaultBoundaryCallSiteTests.swift` | R-15, R-16, R-17, R-18, and the door's escaping parent |

**`scripts/mcp-smoke.py`:** R-01, R-02, R-03, R-05, R-06 and R-07 at the protocol level, and
R-11's headline case: `pratica_create_board` with no `dryRun` leaves no `.canvas` behind.

**Review only:**

- R-04, the `perg` wiring;
- R-19, the timeline site;
- R-20, the registry line and `PG-151`;
- R-21, the ledger entry;
- R-11's «no rescan»;
- §D7's `EmbedTable` memo.

**Builds:** `Pergamenum`, `perg` and `pergamenum-mcp` all build, since shared sources changed.

## Proposed `CLAUDE.md` chain-index entry

- **ADR-0063** — Closes `PG-256`/#570 (Audit Fable chain 3) and `PG-151`/#280: a negative or
  unreadable `limit` is one usage sentence from `Sources/Connector` on both connectors (`0` answers
  empty; `VaultSession.search`'s append-then-test off-by-one fixed), a malformed MCP `cursor` is
  JSON-RPC `-32602` with no overflow trap, and no `ToolArguments` reader traps on a huge number. The
  flag parser refuses an option whose value starts with `--`, `--flag=value` and a bare `--`
  (`--option=--value` is the escape hatch, `-1` stays a value). `VaultSession.createBoard(named:in:)`
  validates with the Workspace rule (moved to `FolderName.validate` in `Sources/Core`), spells the
  path through `CanvasStore.boardFilePath`, pre-checks a taken name as a filter so a rehearsal tells
  the truth, and writes through `writeFile(…, expectingAbsent: true)`, a new precondition on the
  `.canvas` door (ADR-0057 §D3's rule), so `pratica_create_board` honours `dryRun` and journals; undo
  of the creation is declined, the journal never deletes; unlike `CanvasStore.createBoard` it creates
  a missing parent folder, as `createNote` does. The app's two board creations stay on the store on
  purpose. The three «create and link» summaries name the created file in `note`. `importFile`,
  `CanvasStore.createFolder`, folder rename/trash, the pratica timeline and `Attachment` resolve
  through `VaultBoundary`; `Attachment` gains a `within:` form and the editor's `EmbedTable` builds
  its boundary once per root, so no symlink resolution is added per keystroke.
  `VaultBoundary.url(for:)` joins `.claude/protected-interfaces`. 31 residual root-relative sites are
  filed, not fixed. Extends ADR-0007 §D6, ADR-0041 §D1/§D2, ADR-0057 §D3, ADR-0043 §D7/§D8; amends
  none → `docs/adr/0063-connector-input-hardening.md`

## References

- **This chain:** `SPEC.md` (Approved 2026-09-26), `docs/plans/connector-input-hardening.md`.
- **Ledger and roadmap:** issue #570; `TODO.md:9` (`PG-256`) and `TODO.md:38` (`PG-151` → #280);
  `ROADMAP.md` §Chain 3, `:410` and `:947`.
- **ADRs:** ADR-0007 §D6; ADR-0025 §D1; ADR-0041 §D1/§D2 and its «Protected-interface proposal»;
  ADR-0043 §D1/§D7/§D8; ADR-0057 §D3; PG-168 (`requiringExistingFolder`).
- **MCP:** specification 2025-11-25, «Pagination › Error Handling»; `swift-sdk` 0.12.1,
  `Sources/MCP/Base/Error.swift` and `Sources/MCP/Server/Server.swift` in the installed checkout.

## Implementation notes

Recorded during `/build` on 2026-09-26, on `kepler/spec-su-chain-3-pg-225`, against `a6ce602`.
Gate G1 approved all four points (§D4.5, §D4.7, §D1.5, §D1.6), so nothing is left as a named gap.
Gate G2 approved writing the §D8 line; it is at the end of `.claude/protected-interfaces`,
verbatim.

### Departures from the plan's letter

- **A test captured `writeFile` as a function value.** The plan's contract table says the three
  `Sources` and thirteen `Tests` callers of `VaultSession.writeFile` all keep the default.
  `Tests/VaultAsyncCascadeTests.swift:227` does not: it captures `session.writeFile` as a bare
  function value, so the new defaulted parameter shows up in its type and the call site stopped
  compiling. It now passes `false` explicitly, the same mechanical change ADR-0046 §D5 made there
  when `expecting:` arrived. Its assertions are unchanged.
- **`perg` reads `--limit` before it resolves the vault.** `JournalCommands.log` and
  `SearchCommands.run` read the number first, so in `perg` too a malformed number is the first
  thing said, ahead of «vault mai aperto» or a vault that fails to open. This is §D1.1's ordering
  carried to the front end. It changes no outcome when the vault is fine.
- **`ToolArguments.checkedInt` refuses through the text rule.** An out-of-range `.double`, and any
  value that is not a number, string or null, goes through `VaultAPI.limit(parsing:named:)` with
  the value's printed form. The sentence therefore stays the one private builder's in
  `VaultReads.swift`, and the builder is not widened. None of those printed forms can read as an
  `Int`: a double past `Int`'s range prints in exponent form, and a bool, array, object or data
  value never prints as an integer.
- **`Attachment.byName` keeps the per-match resolution.** The walk starts at `boundary.root`, and
  the second resolution of the root is gone, as §D7 says. A file whose name matches is still
  resolved on its own before the prefix test, as it was before, so a symlinked file inside the
  vault that points outside it stays excluded. That resolution runs only on a name match on the
  by-name fallback, never once per candidate.
- **`importFile`'s refusal sentence** is `copia di <nome>: <violation>`, the prefix its existing
  copy-failure problem already uses.
- **Fixture queries.** The plan's tables name `"Uno"` (`ConnectorTests`) and `"Nota"` (the smoke
  stage) as the matching search query. Neither fixture's text contains those words as body text,
  so both use `"Corpo"`, which the two fixtures do contain. A positive control
  (`limit: nil` answers one hit) pins that the query matches.

### Verification

- `xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS'
  -only-testing:PergamenumTests test`: 3731 tests in 189 suites passed, with 5 known issues, all
  in `HostedViewPrototypeTests` and unrelated to this chain. All 34 new tests passed, and so did the adjusted cascade test.
- `perg` and `pergamenum-mcp` build. `scripts/mcp-smoke.py` passes every stage, including the new
  `hardening` stage: 91 checks, «tutto a posto».
- A manual `perg` probe on a scratch vault covered four refusals, each exiting 1 (`.usage`) and
  writing nothing: `journal log --limit -1`, `search … --limit abc`,
  `note new Titolo --folder --dry-run` and `note new Titolo --dry-run=true`.
- `rg -n "root\.appending\(path:" Sources` gives 31 lines in 21 files, as §D9 predicted.
- SwiftLint on the touched files reports no error. The new warnings are `file_length` on
  `VaultPraticheLinks.swift` (388 → 416 lines) and on `Tests/ConnectorTests.swift` (358 → 459),
  and `optional_data_string_conversion` on the `String(decoding:as:)` §D4 prescribes. Also new:
  a `large_tuple` in the new R-14 test. `VaultDisk.swift` and `FolderFileOperations.swift` were
  already past 400 lines and were not split.
