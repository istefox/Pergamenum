# ADR-0059: Stable note ids live in a registry file in the vault, not in the index

- Status: proposed, on the branch `kepler/230-pg-130-fix-notestate-noteids`. Accepted when that
  branch merges to `main`.
- Date: 2026-09-25. Written **before** the implementation, against `48ca1b5d` (clean tree). Every
  line number below was read from that tree. None is recalled from the ticket.
- **Numbering note:** `0058` is the highest file under `docs/adr/`, and
  `git log --all -- 'docs/adr/0059*'` returns nothing. `git log HEAD..origin/main` is empty against
  the local `origin/main` ref. That ref was not fetched while this was written, so check it again
  before merging.
- Source: `TODO.md` **`PG-130`** → issue **#230**. Stefano settled two things before this record,
  and it registers them without reopening them:
  1. **The route stays, and a real stable id is implemented.**
  2. **The id must survive every rename and move the app performs, and may break only on a rename
     or move made outside it** (Finder, another editor). This is the caveat already written in
     SPEC §9 (line 396) and in ADR-0001 §D2 (`docs/adr/0001-initial-architecture.md:73-76`).
- **Departs from the ticket's framing, on purpose and measured.** `PG-130` proposed "an index field
  plus a `schemaVersion` bump", and the brief for this chain restated it as three steps: a field on
  `StoredRecord`, an id generated at first indexing, and `RouteState.noteIDs` filled from the
  snapshot. The Context below shows that an id stored in the index cannot meet decision 2, and that
  it would make principle 3 false. The decided requirement wins over the suggested mechanism. The
  departure is gate A of the plan.
- **Amends ADR-0001 §D2's last paragraph and two SPEC rows (§9 `note?id=`, §14 Frontmatter), on
  where the id lives only.** The two decisions those texts actually made still hold: the id is not
  in the frontmatter, and it breaks on a rename outside the app. ADR-0001's body is not rewritten.
  It gets a scope note at its head, which is ADR-0047 §D12's precedent (§D10).
- **Reopens nothing else.** `IndexCache.schemaVersion` stays at 4, and no protected interface
  changes. The frontmatter gets no key, and neither closed schema is touched. The one new thing on
  disk is one file in `.pergamenum/`, the directory that SPEC §4.1 already reserves for app
  configuration that is not derived state.
- **Connectors:** `perg` and `pergamenum-mcp` keep the registry in step, because they share the
  rename door that keeps it in step (§D9). They expose no id: no tool, no flag, no payload key.
- **GUI-test budget: zero.** Everything below can be observed in-process, on `VaultSession` and
  `VaultController`.

---

## Context

### What is broken

`pergamenum://note?id=<id>` parses (`Sources/Core/URLScheme/PergamenumURL.swift:47-54`) and is
handled (`Sources/App/VaultController+Routes.swift:51-59`):

```swift
case .noteID(let id):
    // IDs live in the index, not in the frontmatter (SPEC §9), so an unknown
    // one means the note was renamed outside the app.
    guard let path = routeState.noteIDs[id] else {
        recordProblem("nessuna nota con id \(id)")
        return false
    }
    openNote(at: path)
    return true
```

`RouteState.noteIDs` (`:154-155`) is read on that line and written nowhere. `rg noteIDs Sources`
returns exactly `:54` and `:155`. No id exists anywhere: `StoredRecord`
(`Sources/Index/IndexCache.swift:259`) has no id field, and `NoteRecord`'s `id` is its path
(`Sources/Vault/NoteStore.swift:38`, `var id: String { relativePath }`). So the route has returned
false on every call since M6, and nothing produces a link it could answer. No test covers the
handling: `Tests/URLSchemeTests.swift:9` only parses the route.

A second defect sits under the first. `.note(path:)` checks that the file exists before it opens a
tab (`:41-47`), but `.noteID` does not (`:58`). An id that resolved to a path with no file behind it
would open a tab on nothing.

### Why the index cannot hold the id: measured, not argued

These facts were read from the code, in the order a rename exercises them.

1. **The index row has no identity that survives a move.** `VaultSession.moveFile`
   (`Sources/Vault/VaultSession+Journal.swift:62-101`) calls `VaultDisk.moveFile`
   (`Sources/Vault/VaultDisk.swift:380-406`). That returns a removal of the old path and an insertion
   of a record **derived from scratch** at the new one. `IndexSnapshot` is keyed by path
   (`Sources/Index/IndexSnapshot.swift:52-59`). Nothing carries anything across.
2. **Every in-app rename or move ends with a full rescan.** See
   `Sources/App/VaultController+Files.swift:52-55,77-80`, `VaultController+Folders.swift:70`, and
   `VaultController+Move.swift:192`. `rescan()` (`Sources/Vault/VaultSession.swift:323-348`) loads
   `cache.db` keyed by path, scans, **replaces** the whole snapshot, then saves every row again.
   `IndexCache.save` has no other caller. An id held only in memory is gone on the next rescan, and
   an id held in `cache.db` sits under the *old* path, which the scanner never asks for again.
3. **The scanner discards a cached row whenever the file changes.** `VaultScanner.isUnchanged`
   (`Sources/Vault/VaultScanner.swift:200-206`) compares size and modification date. Any edit
   therefore re-derives the record, and the id with it, unless new code copies it across by path on
   every edit.
4. **The cache is thrown away by design, often.** Each of these drops every row:
   - «Svuota cache e ricostruisci» (`VaultSession.clearCache`, `:352-355`);
   - every future `schemaVersion` bump (`IndexCache.load`, `:46`, returns nothing for another
     schema);
   - a database that will not open;
   - a different Mac. Since ADR-0017, `cache.db` lives per machine in
     `~/Library/Application Support/it.stefer.pergamenum/vaults/<id>/`.

   So a link copied on one Mac would never resolve on another, even with the vault shared through
   iCloud Drive (principle 6).
5. **Keeping it there anyway would make three binding texts false.** Principle 3 says that deleting
   the cache loses nothing. SPEC §12 (line 479) says the index is "mai la fonte di verità".
   ADR-0001 §D2 rule 1 says "deleting the database loses nothing". An id is not derivable from any
   file. It is minted, and the links pasted into DEVONthink, Mail or Calendar depend on it. Once it
   lives in the cache, deleting the cache loses data.

Points 1 to 3 could each be patched by carrying the id by hand. Points 4 and 5 cannot be patched:
they are what "rebuildable" means. SPEC §9's "registrato nell'indice" was written before any of
this machinery existed (M6, "never implemented on the producer side", per `PG-130`). The sentence's
real content is its second half: not in the frontmatter, and breaks on an external rename.

### Where a fact like this already lives in this repo

ADR-0012 §D6/§D10 gives the test, reused rather than invented by ADR-0017 §D1: is this a fact about the vault, or about one machine's work? Which
note a pasted link names is a fact about the vault. It must hold on every Mac that opens the vault,
and on the iPad the vault may reach through iCloud. The repo already has two stores of that kind,
and both are next to the settings in `.pergamenum/`:

- **`starred.json`** (ADR-0012 §D6, `Sources/Vault/StarredStore.swift`). Its path-follow calls,
  `moveStar`/`forgetStar`, are already made at every door where a note moves or leaves:
  - `VaultSession+Files.swift:44,67,82`;
  - `VaultSession+Folders.swift:29-31,40-42`;
  - `VaultSession+Move.swift:150-152,176`.
- **`categories.json`** (ADR-0047 §D2, `Sources/Vault/CategoryRegistryStore.swift`). It adds the rule
  that matters for data that exists nowhere else: a file that does not decode is reported and never
  overwritten.

ADR-0052 adds the third rule this design needs. A store held in memory and saved back must know
what it was read from. Here there are three processes (the app, `perg`, `pergamenum-mcp`), and each
can rename a note, so a copy held in memory is the exact risk ADR-0052 describes.

### Every door through which a note moves or leaves: the inventory

`rg "FileManager.default.(moveItem|trashItem)" Sources` returns thirteen hits, and
`rg "session\.(renameFolder|trashFolder|moveItems|renameNote|moveNote|trashNote)"` covers every
facade call. Four of the thirteen never change where a note lives:

- `BoardFileOperations.swift:155,277` move a `.canvas` file;
- `BoardFileOperations.swift:192` trashes one;
- `PraticaSyncEngine+Folder.swift:84` trashes a corrupt attachment.

The other nine sit behind these doors:

| Door | File | Reached from |
|---|---|---|
| `VaultSession.moveFile(from:to:)` | `VaultSession+Journal.swift:62` (shared) | `renameNote`, `moveNote` (`+Files.swift:28,58`), the note branch of `moveItems` (`+Move.swift:118`), connector undo of a move (`+Journal.swift:320`) |
| `VaultSession.trashFile(at:)` | `+Journal.swift:112` (shared) | `trashNote` (`+Files.swift:78`) |
| `VaultSession.renameFolder` | `+Folders.swift:22` (app only) | `VaultController+Folders.swift:56` |
| `VaultSession.trashFolder` | `+Folders.swift:38` (app only) | `VaultController+Folders.swift:87` |
| `moveItems`, folder branch | `+Move.swift:143-154` (app only) | `VaultController+Move.swift:43` |
| `PraticaFileOperations.moveFiles` / `moveBack` | `Sources/Features/Pratiche/PraticaFileOperations.swift:139,279` | «Sposta in…» on a message and its undo |
| `PraticaFileOperations.trash` / `restore` | same file, `:40`, `:82` | «Escludi», «Rigenera», and their undo |

---

## Decision

### §D1: The ids live in `.pergamenum/note-ids.json`

This is a new file next to `starred.json` and `categories.json`, named by a new constant,
`VaultLayout.noteIDsFile = "note-ids.json"`. Version 1 has this shape:

```json
{
  "notes" : {
    "3f2c9a4e-8b1d-4c67-9e2a-5d1b7c0e4f13" : "01 Progetti/Nota.md"
  },
  "version" : 1
}
```

- **Keyed by id.** The route looks up in that direction, and JSON object keys make one path per id
  hold by construction. The rule "one id per path" is enforced by the value type (§D4).
- **Ids are lowercase UUID v4** (`UUID().uuidString.lowercased()`). A lookup lowercases its input,
  so an id pasted in upper case still resolves.
- **Pretty-printed, sorted keys, atomic write**, the same encoder settings as
  `CategoryRegistryStore.save`. A vault kept in git then diffs cleanly: a rename is one changed
  line.
- **The index is not touched.** `StoredRecord`, `IndexCache.schemaVersion` (4) and `IndexSnapshot`
  stay as they are. Deleting `cache.db` or pressing «Svuota cache» leaves every id where it was.
- The pure logic is a value type, `NoteIDRegistry`, in `Sources/Core/Vault/NoteIDRegistry.swift`
  (Foundation only, next to `MovedNote`). The disk half is `NoteIDStore`, in
  `Sources/Vault/NoteIDStore.swift`, in the shape of `CategoryRegistryStore`.

### §D2: An id is minted when a link needs it, exactly once, through one door

`VaultSession.mintNoteID(for relativePath: String) -> String?`, in the new
`Sources/Vault/VaultSession+NoteIDs.swift`. It is synchronous on the main actor, as the starred and
category stores are. The file is small, and `CommandActions.copyLinkToOpenNote()` stays synchronous
as a result.

- It returns the path's existing id if there is one, and writes nothing.
- Otherwise it mints one (`NoteIDRegistry.makeID()`), saves it, and returns it. **It returns an id
  only once that id is on disk.** If the save fails, it records a problem and returns `nil`. An id
  handed out but never stored would be a link that can never resolve.
- It refuses, and returns `nil`, in these cases:
  - a path that is not `.md`;
  - a path that `VaultBoundary` rejects (`store.url(for:)` throws);
  - a path with no file behind it;
  - a registry that cannot be read (§D3);
  - `isDryRun`, unless the id already exists.
- **An id is never regenerated for a path that has one.** Every copy of a note's link hands out the
  same id.

It has one production caller in this chain: «Copia link Pergamenum» (§D8). **Nothing is minted at
indexing time.** A scan never writes the registry, and neither does the watcher. See Alternative 5
for why "at first indexing", as the brief worded it, was not taken.

### §D3: No copy in memory. Every door reads the file, changes it, and writes it

The session holds no registry. `noteIDStore` is a computed property,
`NoteIDStore(root: root)`, in `VaultSession+NoteIDs.swift`. Because of that,
`Sources/Vault/VaultSession.swift` is not touched at all. It is already 646 lines, and its class body
runs from line 27 to line 477.

Every door does the same four things: `load()`, apply one pure change, compare the result with what
was loaded, and `save` only if they differ.

- **A change that leaves the registry as it was writes nothing.** A vault where nobody ever copied a
  link never gains the file, however many renames it sees.
- **The four load states.** `NoteIDStore.load()` returns the registry with one of
  `absent`, `loaded`, `malformed` or `evicted`:
  - `absent`: there is neither a file nor an iCloud placeholder. This reads as an empty registry,
    and a door may create the file.
  - `loaded`: the file decoded, at `version == 1`.
  - `malformed`: the bytes do not decode, or the version is unknown.
  - `evicted`: there is no file, but the iCloud placeholder `.note-ids.json.icloud` is present. This
    is the placeholder form `VaultScanner.evictedNoteName` already recognises for notes.
- **A `malformed` or `evicted` registry is never written.** Every changing door refuses and records
  one problem that names the file. A read door answers `.unreadable` (§D7). This is
  `CategoryRegistryStore`'s rule, extended to eviction. If the first mint on an evicted file created
  a fresh one, iCloud would then create a conflict copy against the real file, and the ids would be
  lost.
- **The process gap this closes, and the one it leaves.**
  - Closed: the app, `perg` and `pergamenum-mcp` can all open the same vault at once, and each
    process's rename keeps the registry in step (§D9). Because every door re-reads, no process can
    write back an old copy over another's change. That is ADR-0052's lost update.
  - Left open: the gap between one door's read and its write, inside one synchronous call, is still
    there. There is no cross-process file lock. Hitting it needs two processes to change the
    registry within the same few milliseconds. This record names it and does not close it.

### §D4: Two rules, both pure, both covering notes and folders alike

On `NoteIDRegistry`:

- **`relocating(_ moves: [MovedNote])`**, for each move:
  - First it drops any entry already sitting at `new` or under `new/`. That entry is stale: an
    earlier note there was deleted outside the app, and the note arriving brings its own id.
  - Then it rewrites every entry whose path equals `old`, or starts with `old + "/"`, onto `new`.
- **`removing(_ paths: [String])`** drops every entry equal to a path or under `path + "/"`.
- **How paths are matched.**
  - Both sides are trimmed of leading and trailing `/`. An empty path (the vault root) matches
    nothing, so a bug can never relocate or forget the whole registry.
  - Paths are compared as exact strings. The app's paths all come from one source
    (`NoteRecord.relativePath`, `MovedNote`), so the same note has the same string at both ends.
  - The `+ "/"` guard keeps `Progetti/` from matching `Progetti 2/`.
- **Folders are handled by the folder's own pair, not by the list of notes it moved.** The session's
  folder doors pass `MovedNote(old: folder, new: newFolder)`, and the prefix rule reaches every
  entry under it. That includes a note that is only an iCloud placeholder, which is in no index and
  in no `movedNotes` list.

### §D5: Where the registry is kept in step, and where it is not

These doors keep the registry in step. Each call goes in the same place as the door's own
`moveStar`/`forgetStar`, or directly after the disk operation where the door has none:

| Door | Call | Reaches |
|---|---|---|
| `VaultSession.moveFile` (`+Journal.swift`, after `apply(mutations)` at `:80`) | `relocateNoteIDs([MovedNote(old: oldPath, new: newPath)])` | `renameNote`, `moveNote`, the note branch of `moveItems`, connector undo of a move, and `perg`/MCP rename and move |
| `VaultSession.trashFile` (after `apply([mutation])` at `:132`) | `forgetNoteIDs([relativePath])` | `trashNote`, in the app and in the connectors |
| `VaultSession.renameFolder` (`+Folders.swift:29-31`) | `relocateNoteIDs([MovedNote(old: relativePath, new: outcome.newPath)])` | folder rename |
| `VaultSession.trashFolder` (`+Folders.swift:40-42`) | `forgetNoteIDs([relativePath])` | folder trash |
| `moveItems`, folder branch (`+Move.swift:150-154`) | `relocateNoteIDs([MovedNote(old: move.item.path, new: folder.newPath)])` | a folder dragged or moved |
| `PraticaFileOperations.moveFiles` / `moveBack` | `vault.session?.relocateNoteIDs(…)` for the `.md` that moved, using `VaultScanner.relativePath(of:under:)` | «Sposta in…» on a message, and its undo |

`moveFile` and `trashFile` are the right level, rather than `renameNote`/`moveNote` where the stars
are followed. There are three reasons:

1. Both doors are after the dry-run return (`:68`, `:120`), so a rehearsal never touches the
   registry.
2. Both run only once the disk operation has succeeded.
3. `moveFile` is also the door connector undo uses (`+Journal.swift:320`). The id therefore follows
   an undone move, which the star does not do today. That gap is named as a follow-up, not fixed
   here.

**Never kept in step:**

- **The watcher** (`VaultSession+Watching`). An external rename reaches the app as a deletion and a
  creation, which is exactly the case decision 2 allows to break. Guessing a pairing would be
  Alternative 8.
- **A scan.** A scan never prunes the registry. A note absent from one scan may be evicted, or on a
  volume that is not mounted, and pruning it would lose its id for good.

### §D6: A trash forgets the id. A Pratiche trash does not

- **`trashNote` and `trashFolder` forget.** An entry left behind at a trashed path would be inherited
  by the next note created at that path, and an old link would open a note it never named. This
  matches `forgetStar`. An undo of a connector trash puts the note back **without** its id: the
  journal restores text, not registry lines. Named, not fixed.
- **«Escludi» and «Rigenera» do not forget.** `PraticaFileOperations.trash(filesOf:)` is plumbing:
  - «Escludi» can be undone, and a restore puts the file back at the same path;
  - «Rigenera» trashes and rewrites the same path within one gesture.

  Forgetting in either case would break a link the person never asked to break. If an excluded
  message is never restored, its id resolves to a missing file, and the route says so (§D7).

### §D7: The route asks the session, checks that the file is there, and says which case it hit

- **`RouteState.noteIDs` is deleted**, together with its doc comment
  (`VaultController+Routes.swift:154-155`). The route reads through to the session, the way `index`
  and `categories` already do (`Sources/App/VaultController.swift:18-25`). A copy on the controller
  would be a second copy of something the session owns. `recentNotePaths`'s own comment (`:85-88`)
  says why this repo does not keep one. A route that arrives before the vault is open is already
  held in `routeState.pending` and replayed after `open` (`:217-220`), so read-through covers the
  cold-launch case with no extra state.
- **`VaultSession.lookUpNote(id:) -> NoteIDLookup`**, where
  `enum NoteIDLookup: Equatable { case found(String), unknown, unreadable }`, gives three answers
  and three sentences. Tests assert on the outcome and on the id or path appearing in the recorded
  problem, not on exact wording:

  | Outcome | Route result and sentence |
  |---|---|
  | `.unknown` | false, with the existing sentence «nessuna nota con id …» |
  | `.unreadable` | false, with a sentence naming `note-ids.json` as unreadable |
  | `.found(path)` but the file is gone | false, with a sentence naming the id and the path, and saying the note was moved or deleted outside the app |

- **One existence check, shared by `.note` and `.noteID`.** The current `.note` check (`:42-43`)
  becomes a private helper that both cases call. The registry is a hand-editable file, so the path
  it returns is untrusted input. It goes through `store.url(for:)`, which is `VaultBoundary`
  (ADR-0041 §D1), exactly as a `file=` argument does. This also closes the latent defect from the
  Context: an id never opens a tab on a missing file.
- **The `.note(path:)` route does not change.**

### §D8: «Copia link Pergamenum» copies the id link

- `PergamenumLink.note(id:) -> URL?` builds `pergamenum://note?id=<id>` through the existing private
  `build(host:queryItems:)`.
- `VaultController.pergamenumLink(toNoteAt path: String) -> URL?`, in
  `VaultController+Routes.swift`:
  - it mints through the session (§D2) and returns the id link;
  - if the mint refuses, it returns the path link (`PergamenumLink.note(path:)`) and records one
    problem saying the link copied is the path form.

  A person who pressed the shortcut still gets a link that works today, and is told it will not
  survive a rename.
- `CommandActions.copyLinkToOpenNote()` (`Sources/App/CommandActions.swift:366-370`) calls it. The
  menu-bar item (`VaultCommands.swift:121`), Cmd+Shift+L, and the note row's context menu
  (`NoteRowMenu.swift:53` → `run(.copyLink, on:)`) all go through that one method, so one change
  covers all three surfaces.
- **This changes an observable contract.** The clipboard used to hold `note?file=…` and now holds
  `note?id=…`. `Tests/RowCommandTests.swift:94-105` asserts the old string and is updated in the
  same chain, for this reason. Adding a second command instead, and leaving this one alone, is a
  real option (Alternative 10). It is Stefano's choice, gate B of the plan, and it is asked before
  any test is written.
- **Path links stay where a path is the point:**
  - `perg app open note` (`Sources/CLI/Commands/AppCommands.swift:60`);
  - the MCP note resources (`Sources/MCPServer/VaultHost.swift:282`), whose URI is also what
    `scripts/mcp-smoke.py:466` checks;
  - the reminder notification's route (`Sources/Calendar/ReminderScheduler.swift:164`);
  - the Workspace card's own «Copia link», which copies a canvas link (`BoardCardMenu.swift:155`).

  Two comments stop being true and are corrected: `VaultHost.swift:271-273` ("the very link «Copia
  link Pergamenum» puts on the clipboard") and `AppCommands.swift:10-11`.

### §D9: The connectors compile the registry and keep it in step, and do nothing else with it

`VaultSession+Journal.swift` is in `sharedSources` (`Project.swift:134`), and §D5 puts the
keeping-in-step calls in its `moveFile`/`trashFile`. The doors those calls reach must therefore
build in `perg` and `pergamenum-mcp` too:

- `NoteIDRegistry.swift` is under `Sources/Core/**` and is covered by the glob;
- `Sources/Vault/NoteIDStore.swift` and `Sources/Vault/VaultSession+NoteIDs.swift` are named by
  hand in `sharedSources`. This is ADR-0007 §D2's rule, and the `CategoryRegistryStore.swift`
  entry with its comment (`:105-109`) is the precedent.

This is required, not a convenience. `perg note rename` and the MCP rename tool go through the
same `VaultSession.renameNote` the app uses. That is one of the writers decision 2 names. Without
these calls, one rename from Claude would silently break every id the app had minted for that note.

What `sharedSources` does **not** force: exposing the id. No tool, flag, payload key or
`perg app open note --id` is added. That stays out of scope as the brief says, and a future chain
can add it on top of `lookUpNote(id:)`.

### §D10: What this amends, and how the amendment is recorded

- **ADR-0001 §D2, last paragraph.** "Note IDs … live in the index" becomes "live in
  `.pergamenum/note-ids.json` (ADR-0059)". The body stays as written. A scope note at the head,
  in ADR-0047 §D12's form, points here.
- **SPEC §9, `note?id=` row** (line 396), and **SPEC §14, Frontmatter row** (line 512). Each gets
  an inline *Emendato 2026-09-25 (ADR-0059)* note. The id is recorded in
  `.pergamenum/note-ids.json` and not in the frontmatter or the index. It follows every rename and
  move the app performs, and is stable until the file is renamed outside the app. SPEC edits are a
  HITL gate.
- **SPEC §4.1's tree** already leaves out `starred.json` and `categories.json`, so it is not an
  exhaustive list. It is left alone.

---

## Alternatives considered

1. **An id field on `StoredRecord` with a `schemaVersion` bump**, the ticket's framing. Rejected on
   the measurements in Context:
   - A move re-derives the record at the new path.
   - Every in-app rename ends in a rescan that replaces the snapshot.
   - The scanner discards a changed row.
   - The cache is dropped by «Svuota cache», by the next bump, and by every other Mac.

   Carrying the id by hand through the first three is possible. The fourth is what makes the cache
   a cache. Holding the id there would also make principle 3, SPEC §12 and ADR-0001 §D2 rule 1
   false, and it would spend a bump of a protected interface on a field whose loss is data loss.
2. **A registry kept outside the vault**, either a table next to `cache.db` or a file in the
   per-vault state directory. This survives «Svuota cache» if it is kept apart from the database.
   Rejected: it is per machine (ADR-0017), so a link copied on one Mac fails on the other. ADR-0017
   §D1's criterion (reused from ADR-0012 §D6/§D10) puts a fact about the vault in the vault.
3. **A `pergamenum-id` frontmatter key.** This is the one design that also survives a rename outside
   the app. The `pergamenum-` prefix has precedent (ADR-0020, ADR-0032, ADR-0036, ADR-0047).
   Rejected, for these reasons:
   - SPEC §9 and §14 already decided against it.
   - Copying a link would become a write to the note. That note is usually the one open in front of
     the person, often with unsaved edits, which means ADR-0058's catch-up path on every copy.
   - Every file copy carries the id. `PraticaFileOperations.copyFiles` («Aggiungi anche a…») copies
     a message's `.md` verbatim, and so do a Finder duplicate and a template. Two notes would then
     answer to one id, and the route would open whichever the index met first.
   - Decision 2 accepts breakage outside the app, so the extra persistence buys nothing that was
     asked for.

   This is the design to revisit if that requirement ever widens.
4. **A file-system identity**: an extended attribute, or the APFS file id (the inode). Rejected:
   `NoteStore.write` saves with `.atomic` (`Sources/Vault/NoteStore.swift:160`), which Foundation
   documents as writing an auxiliary file and replacing the original with it. The saved file is a
   new file, so the id would change on the first edit.
5. **Minting at first indexing** (the brief's step 2). Rejected, for four reasons:
   - A scan would become a writer to the vault, which it never is today.
   - Every note would get an entry nobody links to, and every new note would add a registry write,
     synced through iCloud.
   - Two Macs indexing the same new note would each mint a different id at once, and iCloud would
     keep both as a conflict copy.
   - A note first seen by the watcher would need the watcher to write the registry, which §D5
     forbids.

   Minting when a link is copied gives the same guarantee (one id per note, minted once, never
   regenerated), and it writes only when a person asks for a link.
6. **A registry loaded once and held in memory on the session**, the `StarredStore` shape. Rejected:
   three processes keep this file in step (§D9), and a session saving back its old copy over a
   connector's rename is ADR-0052's lost update. For stars, losing one is a nuisance, and
   `CategoryRegistryStore`'s own header says as much. For ids, it breaks a pasted link.
7. **Filling `RouteState.noteIDs` from the snapshot** (the brief's step 4). Rejected: it would be a
   second copy of a mapping the session owns, stale the moment a connector renames a note. The
   read-through pattern already answers the one case the copy seemed to be for, a route that
   arrives before the vault is open.
8. **Finding a note again after a rename outside the app**, by title or content hash. Rejected:
   decision 2 allows the id to break there. A guess can open the wrong note, and
   `PergamenumRoute.init`'s own doc comment (`PergamenumURL.swift:31-32`) says that is worse than a
   link that reports it does not work.
9. **A hybrid link, `note?id=…&file=…`, falling back to the path.** Rejected:
   - The parser gives `file` precedence (`PergamenumURL.swift:48-51`), so the id would be ignored
     unless an existing parse contract were inverted.
   - The fallback would open whatever now sits at the old path. After an in-app rename that is
     another note or nothing, which is the wrong-note case again.
10. **A second command («Copia link stabile») next to an unchanged «Copia link Pergamenum».** This
    keeps the existing contract and the existing test, and lets the person choose per link.
    Rejected as the default: the links SPEC §9 exists for, pasted into DEVONthink, Mail and Calendar,
    are exactly the ones an in-app rename breaks today. Offering the durable one only behind a
    second command leaves the default fragile. This is a preference, not a fact, so it is gate B.

---

## Consequences

### Positive

- `pergamenum://note?id=` works for the first time. The id follows every rename, move, folder
  rename, folder move and batch move the app makes, and connector renames and moves too. It also
  survives «Svuota cache», reopening the vault, a `schemaVersion` bump, and a second Mac on the same
  iCloud vault.
- The index stays rebuildable. `IndexCache.schemaVersion` stays 4, and no protected interface
  moves.
- An id link no longer opens a tab on a missing file, and the route now says which of three things
  went wrong.
- A hand-edited registry is untrusted input, and it is routed through `VaultBoundary` like any other
  path.

### Negative

- **Keeping the registry in step is a call, not a resolver.** CLAUDE.md warns about this shape: a
  step that a new call site can forget will be forgotten by one. §D5 puts the calls at the lowest
  shared doors (`moveFile`, `trashFile`), so every current note rename, move or trash inherits
  them. The folder doors and Pratiche still need a hand-placed call, as the stars already do. A
  future verb that moves a `.md` file with `FileManager` directly would silently drop ids. The
  inventory in Context is the checklist for that.
- **Copying a link writes a file** the first time it is done for a note. A gesture that only read
  before now writes `.pergamenum/note-ids.json`, and that write reaches iCloud.
- **Id links are opaque.** A pasted `note?id=3f2c…` no longer tells a reader which note it names.
- **Entries at dead paths are never pruned** (§D5). If a note is deleted outside the app and a new
  note is later created at the same path by any means other than a move, the new note inherits the
  old id. A move onto that path clears it (§D4).
- **A connector undo of a trash restores the note without its id** (§D6).
- **Two Macs minting at the same moment** produce an iCloud conflict copy of `note-ids.json`. The
  app does not merge it. `VaultState.conflictCopies(of:in:)` already detects that shape for
  other files, and a follow-up could report it.

### Neutral

- Path links are unchanged for `perg app open note`, the MCP resources, reminder notifications and
  canvas cards (§D8). `scripts/mcp-smoke.py` needs no change.
- The reminder notification keeps a path route (`ReminderScheduler.swift:164`), so a reminder on a
  note renamed in the app between scheduling and firing still misses. Switching it to an id would
  mint for every scheduled note, which is Alternative 5's cost. This is named as a follow-up
  candidate.
- Stars still do not follow a connector undo of a move, a gap `moveStar`'s placement already had.
  Ids now do. This is named as a follow-up.

---

## Acceptance

Each item is a Swift Testing test in `PergamenumTests`. None uses a timer, a sleep or a gate. Where
a behaviour lives after an `await` in an unstructured `Task`, the test drives the session door or
calls `rescan()` explicitly (ADR-0046 §D11).

**The value type** (`Tests/NoteIDRegistryTests.swift`):

1. `makeID()` returns a lowercase string that `UUID(uuidString:)` accepts, with version nibble 4.
2. `assigning` then `path(forID:)`/`id(forPath:)` round-trips. An upper-case id resolves.
3. `assigning` a second id to a path drops the first. One id per path.
4. `relocating` moves an exact entry and leaves the others alone.
5. `relocating` a folder pair moves every entry under it, nested ones included. It does not move
   `Folder 2/x.md` or `Folder.md`.
6. `relocating` onto a destination holding a stale entry drops the stale entry.
7. `removing` a note path and a folder path drops exactly what they cover. An empty path matches
   nothing.
8. A literal version-1 JSON decodes to the expected registry, and encoding it back gives the same
   bytes. This pins the on-disk format.

**The store** (`Tests/NoteIDRegistryTests.swift`):

9. No file and no placeholder gives `.absent` and an empty registry. `save` creates
   `.pergamenum/note-ids.json`.
10. Undecodable bytes, or `"version": 2`, give `.malformed`.
11. Only a `.note-ids.json.icloud` placeholder gives `.evicted`.

**Keeping in step** (`Tests/NoteIDFollowTests.swift`). Tests seed the registry by writing the JSON
file directly, so they do not depend on minting:

12. `mintNoteID(for:)` returns an id and stores it. A second call returns the same id.
13. `mintNoteID(for:)` refuses a missing path, a `.canvas` path, and a path outside the vault. No
    file is created.
14. A rename in a vault with no registry creates no `note-ids.json`.
15. `renameNote` carries the id to the new path.
16. `moveNote` carries it.
17. `trashNote` forgets it.
18. `renameFolder` carries every id under the folder, including one for a path with no file behind
    it, which stands in for an evicted note.
19. `trashFolder` forgets every id under the folder.
20. `moveItems` with one note and one folder carries both.
21. A connector rename, followed by `VaultAPI.undo` of that operation, carries the id there and back.
22. A dry-run rename (`VaultAPI.arm(…, dryRun: true)`) leaves the registry bytes as they were.
23. With a malformed registry, a rename still succeeds, the registry bytes are unchanged, a problem
    is recorded, and `mintNoteID` returns `nil`.
24. Two sessions on one vault: session A mints for `a.md`, then session B (opened before the mint)
    renames `a.md`. Session A's lookup finds the new path. B then mints for `c.md`, and A's id is
    still there. This is the lost update §D3 rules out.
25. `PraticaFileOperations.moveFiles` carries a message note's id to the destination's `email/`,
    including when a name collision renames it. `moveBack` carries it home.

**The route** (`Tests/NoteIDRouteTests.swift`, through `VaultController.handle(_:)`):

26. A link from `pergamenumLink(toNoteAt:)`, parsed with `PergamenumRoute(url)`, opens the note.
27. After `await controller.renameNote(…)` and an explicit `await controller.rescan()`, the same id
    opens the renamed note.
28. The id still opens the note after `clearCache()`, and after closing and reopening the vault in a
    new controller.
29. An unknown id returns false, records a problem, and opens nothing.
30. An id whose file was moved with `FileManager` directly returns false, records a problem naming
    the path, and opens no tab.
31. A `.noteID` route handled before `open` is replayed after it and opens the note.

**The command** (`Tests/RowCommandTests.swift`, which already owns the `makeActions` helper,
ADR-0051):

32. `runningCopyLinkOnAClosedRowOpensItThenPutsItsLinkOnThePasteboard`, updated per §D8. The
    pasteboard holds `PergamenumLink.note(id:)` for the id the session stores for `b.md`. After an
    in-app rename, that string, parsed and handled, opens the renamed note.
33. With a malformed registry, the pasteboard holds the path link and a problem is recorded.

**The builder** (`Tests/URLSchemeTests.swift`):

34. `PergamenumLink.note(id:)` parses back to `.noteID(id)`.

---

## Protected-interface proposal

**One entry, for Stefano's approval.** It follows the `.claude/protected-interfaces` convention,
the same kind of Gate 2 proposal ADR-0032, ADR-0036 and ADR-0040 made for their on-disk shapes:

```text
Sources/Core/Vault/NoteIDRegistry.swift:NoteIDRegistry — added <date> per ADR-0059; the shape of `.pergamenum/note-ids.json` (version 1) and so of every `pergamenum://note?id=` link already pasted into another app; a silent change orphans every id in every vault
```

`interface-check.sh` sees signatures, not `Codable` keys. The real pin on the format is therefore
Acceptance test 8. The entry exists to stop a diff that removes or renames the type's members
without anyone noticing. `PergamenumLink.note(id:)` is **not** proposed: its output shape is also
pinned by test 34, and a new builder added next to it cannot break an existing link.

---

## References

- `TODO.md` `PG-130` → issue #230. Branch `kepler/230-pg-130-fix-notestate-noteids`.
- Plan: `docs/plans/pg-130-stable-note-id.md`.
- SPEC `docs/20260811_Pergamenum_SpecApp.md`: principle 3 (line 64), §4.1 (lines 85-103), §9
  (line 396), §12 (line 479), §14 (line 512).
- ADR-0001 §D2; ADR-0007 §D2/§D3/§D6; ADR-0012 §D6; ADR-0017 §D1; ADR-0032; ADR-0036; ADR-0040;
  ADR-0041 §D1; ADR-0046 §D11; ADR-0047 §D2/§D12; ADR-0051; ADR-0052; ADR-0058.

---

## Implementation notes (chain 2026-09-25)

Appended by the implementation chain whose plan is `docs/plans/pg-130-stable-note-id.md` (Task 7,
"if the implementation departs from the record, add a correction paragraph"). **Nothing above is
altered.** The implementation departs from the literal wording of the decision text in five places.
An independent review found each one and judged it correct. None of them changes a decision.

### 1. An existing file that cannot be read is `.malformed`, not `.absent`

§D3 cites `CategoryRegistryStore` as the shape, and that store's `load()` answers `.absent` whenever
`Data(contentsOf:)` fails, which includes a file that is on disk but cannot be read.
`NoteIDStore.load()` asks `fileExists` first. Only a missing file (with no placeholder) is `.absent`.
A file that exists and cannot be read joins the undecodable and unknown-version cases as
`.malformed`. This is stricter than the precedent, and it is what §D3's own rule needs: an
`.absent` registry is one a door may create, so an unreadable file read as absent would be replaced
by the next door's save with a registry holding only that door's entry. Acceptance test 10 covers
undecodable bytes and `"version": 2`. No test covers the unreadable-file case.

### 2. `relocating` spares entries the same move is about to carry

§D4 says each move first drops every entry at or under `new`, then rewrites every entry at or under
`old`. Taken literally, that order goes wrong when the two paths overlap, so that an entry lies
under both `new` and `old`. An example is a move whose destination lies inside its own source. The
first step would then discard, as stale, an entry the second step was about to carry.
`NoteIDRegistry.relocating` keeps an entry that `old` covers out of the stale drop
(`!covers(new, path) || covers(old, path)`). §D4's intent is unchanged: an entry left at the
destination by a note that went away outside the app is still dropped. No acceptance test pins the
overlapping case. Tests 4 to 6 exercise paths that do not overlap.

### 3. Two ids for one path: `id(forPath:)` answers the smallest

§D1 enforces "one id per path" through `assigning`. A hand-edited `note-ids.json` can still map two
ids to the same path, because JSON keys constrain only the id side. `NoteIDRegistry.id(forPath:)`
returns the lexicographically smallest of those ids (`keys.min()`). A dictionary's iteration order
is not stable, so any other choice could hand out different ids for the same note on different
calls. §D2's rule, "every copy of a note's link hands out the same id", holds even on a file the
app did not write. The other id keeps resolving through `path(forID:)`. No test pins this case.

### 4. The `.noteID` route is a private helper, not an inline case

§D7 describes the three outcomes and the shared existence check, but not where the code sits. The
existence check became the private `noteExists(at:in:)`, which §D7 asks for. The `.noteID` handling
became a second private helper, `openNote(id:in:)`, in `VaultController+Routes.swift`, and
`perform(_:)`'s case is a single `return openNote(id: id, in: store)`. The reason is SwiftLint's
`cyclomatic_complexity` rule, which runs at its default warning threshold of 10. At `48ca1b5d`,
`perform(_:)` already measured 11. An inline three-branch switch plus a guard would have raised it
further. With the helper it lints clean for that rule. The behaviour is §D7's as written.

### 5. Acceptance test 33 records two problems, not one

§D8 says a refused mint makes `pergamenumLink(toNoteAt:)` record "one problem" saying the copied
link is the path form. That holds for the refusals `mintNoteID` makes silently: a non-`.md` path,
a path outside the vault, a missing file, or a dry run. A malformed or evicted registry is different,
because `mintNoteID` itself records §D3's problem naming `note-ids.json` before it returns `nil`. The
controller then records §D8's path-form sentence. `VaultController.problems` reads through to the
session's, so one copy lands two sentences in the same list. A failed save does the same. Each rule
is applied as written, and the plan's "a problem is recorded" simply undercounted. Test 33
(`copyLinkWithAMalformedRegistryFallsBackToThePathLinkAndRecordsAProblem`) asserts the path link
and a problem that names `note-ids.json`. It does not assert a count.
