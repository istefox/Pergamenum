# ADR-0017: The derived stores leave the vault; what a person chose stays in it

- Status: accepted. This record landed on `main` via PR #82 (merge `336d8b3`,
  2026-08-21); its implementation (`PG-004`) via PR #83 (merge `9fe5a45`, 2026-08-22).
- Date: 2026-08-21. Written from `PG-004` as widened the same day, without an interview:
  every question it raises is answerable from the code and from principles 3 and 6, and
  the one place a person's preference decides something (D3's migration of `history/`) is
  called out for acceptance rather than assumed.
- Supersedes: nothing. **Amends ADR-0011 §D3** (which puts `history/` under `.pergamenum/`)
  and **ADR-0007 §D6** (which puts the journal there), and moves what SPEC §6.5, §10 and
  §12 name as `.pergamenum/thumbnails/` and `.pergamenum/cache.db`.
- Depends on: ADR-0012 §D6 and §D10, whose criterion this ADR reuses rather than invents.

## Context

`.pergamenum/` holds eight things: `settings.json`, `vocabolari.json`, `themes/`,
`thumbnails/`, `cache.db`, `starred.json`, `history/` (ADR-0011) and `ai-journal/`
(ADR-0007, ADR-0016). Principle 6 puts the vault in iCloud Drive on purpose, so all eight
sync, and **nothing in this codebase excludes any of them from anything** - grepped and
confirmed: no `NSURLIsExcludedFromBackupKey`, no `URLResourceValues.isExcludedFromBackup`,
no ubiquity call of any kind. `VaultLayout.isExcludedDirectory` is about a different
subject entirely: it stops `VaultScanner` walking dot-directories, so the private
directory is not indexed as notes. It has never said anything about sync or backup.

**`PG-004`'s own framing is half right, and correcting it changes the answer.** The
symptom it names - "the conflict files accumulate in the vault the user reads" - is the
weakest part of the case. `VaultScanner` calls `enumerator.skipDescendants()` on
`.pergamenum` (`VaultScanner.swift:63`), so a conflict copy in there is invisible to the
note list, to search and to the linter. Three sharper problems are the real ones:

- **`cache.db` is a live SQLite file inside a synced folder.** Opened
  `SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE` in the default rollback-journal mode
  (`IndexCache.open(create:)`), which means a transient `cache.db-journal` beside it that
  iCloud knows nothing about. iCloud uploads the pieces of a transaction independently and
  on its own schedule. A database is not a document and syncing it as one is the textbook
  way to get a torn file.
- **`history/` and `thumbnails/` are the write-heavy ones, and both are pure derivation.**
  `NoteHistory.record` writes a file on **every** note save and then thins that note's
  directory, which is a write plus a burst of deletes per save, forever, with no expiry
  (ADR-0011 §D4). `ThumbnailStore` writes a PNG per file per size bucket. Between them
  they are almost all of the bytes and almost all of the churn, and none of it is content.
- **A conflict copy is silently dropped by the very code that would have to notice it.**
  `NoteHistory.snapshots(for:)` skips a filename it cannot parse, `StarredStore.load()`
  reads `starred.json` and nothing else, `IndexCache.load()` returns nothing at all for a
  file it cannot open. Every one of those is correct defensiveness on its own and
  collectively they mean an iCloud conflict costs data with no message anywhere.

**The criterion for what moves already exists in this repo, and it is not "app data versus
user data".** ADR-0012 settled it twice in opposite directions on purpose: starred notes go
in the vault (§D6) because which notes matter is a fact about the vault; open tabs go in
`UserDefaults` (§D10) because which notes are open is a fact about this desk. `PinnedTagsStore`
follows §D10 and says so in its header. This ADR applies the same question to the remaining
eight and finds that four of them have been on the wrong side of it since they were written.

**A stable per-vault identifier also already exists, and it is a path.**
`RecentVaults.remember` and `PinnedTagsStore.key(for:)` both key on
`root.resolvingSymlinksInPath().standardizedFileURL.path(percentEncoded: false)`. It works
for a `UserDefaults` key and it is the wrong thing for a directory name: it contains
separators, and it changes when the folder is renamed - which for `UserDefaults` costs a
list of pinned tags and for `history/` would cost every snapshot the vault has.

## Decision

**D1. Four stores leave `.pergamenum/` and four stay. The line is derivation, not size and
not write frequency.**

Out of the vault: **`cache.db`, `thumbnails/`, `history/`, `ai-journal/`.**
Staying in the vault: **`settings.json`, `vocabolari.json`, `themes/`, `starred.json`.**

The frequency question `PG-004` asks - how often is it rewritten, is losing it harmless -
is the right question for *urgency* and the wrong one for *membership*. It ranks the work
correctly: `cache.db` and `history/` are rewritten on every save and are what will produce
a conflict first. It does not draw the line, because it puts `ai-journal/` (rarely written,
harmless to lose by its own header) on the same side as `starred.json` (rarely written,
harmless to lose by ADR-0012 §D6's own admission), and those two belong on opposite sides.

The question that does draw it is ADR-0012's: **is this a fact about the vault, or a fact
about one machine's work on it?**

- `cache.db` - derived from a vault scan and never the source of truth (principle 3).
  Syncing it is syncing a rebuildable file at the cost of the one failure mode that could
  make it lie. Out.
- `thumbnails/` - derived from the PDFs and images it renders; `ThumbnailStore.clearCacheOnDisk()`
  already deletes the whole directory as an ordinary user action. The other Mac re-renders
  in a second. Out. **`PG-004` does not name this one and it is the largest by bytes.**
- `history/` - not derived from the vault (its own header says so: unlike `cache.db` it
  cannot be rebuilt, the old versions are genuinely gone) but derived from **this machine's
  sequence of saves**. ADR-0011 is titled "local version history" and means it. Two Macs
  editing the same vault have two different, both-correct histories, and there is no useful
  way to merge them. Out.
- `ai-journal/` - a record of what a connector did on this machine, undone by a command a
  person types on this machine. An undo offered on Mac B for a write made on Mac A would
  pass its own hash guard and still be the wrong offer. Out.
- `settings.json`, `vocabolari.json`, `themes/`, `starred.json` - every one of them is a
  choice somebody made about this vault, and principle 6 wants all four on the iPad. The
  daily folder, the harness vocabulary replica (SPEC §4.6), the theme and the stars follow
  the notes. In.

The blanket answer - move all of `.pergamenum/` - is rejected on exactly that: it would
break principle 6 for the four things principle 6 is for, and would reverse ADR-0012 §D6
sixty commits after accepting it. The opposite blanket answer - keep everything and set a
backup-exclusion flag - is rejected in D4.

**D2. The four go to `~/Library/Application Support/it.stefer.pergamenum/vaults/<vaultID>/`,
resolved through `FileManager`, with the bundle identifier as a literal constant.**

Three things here are decisions rather than spelling:

**The directory is asked for, not built.** `FileManager.default.url(for: .applicationSupportDirectory,
in: .userDomainMask, appropriateFor: nil, create: true)`, never a string joined onto
`NSHomeDirectory()`. The app is not sandboxed in v1, so the two agree today; if it is ever
sandboxed the call returns the container and everything keeps working, while the built
string would point outside it.

**`it.stefer.pergamenum` is written out as a constant on `VaultLayout`, never read from
`Bundle.main.bundleIdentifier`.** The three binaries that compile these files have three
different identifiers - `it.stefer.pergamenum`, `.cli`, `.mcp` (`Project.swift:112,183,200`)
- and a `.commandLineTool` product may have no bundle identifier at all. Deriving it would
give `perg` its own private cache and its own private journal, and `perg undo` would look
for the entry the app wrote and not find it. This is the single easiest way to get this
change wrong and it would fail silently.

**`<vaultID>` is a UUID, minted once per vault and stored in `settings.json`.** A new
optional key on `VaultSettings`, which costs no migration by construction: `init(from:)`
decodes every key with `decodeIfPresent` and falls back, precisely so the struct can grow
(it already has, for `spellCheck`, `rollover` and `patronSaint`). Minted during open,
before `IndexCache` and the other three are constructed, because they need it.

Rejected: **a hash of the resolved root path.** It is what the codebase already uses for
`UserDefaults` keys and it is the wrong identity here, because it is not stable under the
one event that matters. Renaming `~/Labs` to `~/Vault` in the Finder would silently orphan
every snapshot the vault has - a folder rename costing a year of version history, with no
error anywhere.

Rejected: **adopting an orphaned state directory whose recorded root no longer exists.**
It handles a rename without touching the vault, and it fails in a worse way than it fixes:
delete vault A, open new vault B, and B adopts A's history, showing versions of notes
nobody ever wrote into it.

Rejected: **a marker file inside `.pergamenum/`.** It works, and `settings.json` is already
that file. A second reserved name for a UUID would be a new thing to sync, a new thing to
document, and a new thing to be missing.

The known flaw of an id in a file is a **duplicated** vault: copy the folder and both copies
carry the same id and write into one state directory. Mitigated rather than prevented: the
state directory holds a small `vault.json` naming the root it was last opened at, and a vault
whose id resolves to a directory pointing at a *different, still-existing* folder is reported
through `problems` and the pointer updated. The two histories interleave, nothing is lost,
and the person is told - the same shape as `VaultScanner`'s iCloud placeholder report, which
also chose to name a normal-but-surprising state instead of swallowing it.

The directory is named by the UUID and not by anything readable, which is a real cost:
`.pergamenum/history/` mirrors note paths so a person can read it by eye (ADR-0011 §D3) and
this cannot, because readability and stability under a rename are in direct conflict here.
`vault.json` is the compensation - one small file per directory saying which vault it is.

**D3. Two are migrated by moving, two are thrown away and rebuilt. Nothing is deleted before
its replacement is readable.**

Run once per vault on first open after this ships, keyed on the state directory not existing
yet, and idempotent.

- **`cache.db`: not migrated.** Removed at the old location and rebuilt at the new one on the
  scan that open performs anyway. Copying a file whose entire contract is that it can be
  recreated would be work done to preserve nothing (principle 3). The SQLite sidecars
  (`-journal`, `-wal`, `-shm`) go with it.
- **`thumbnails/`: not migrated.** Removed, re-rendered on demand. `clearCacheOnDisk()` is
  the same act and it is already a button.
- **`history/`: migrated, by move, and this is the one that matters.** These snapshots are
  the only copy - `NoteHistory`'s own header says the vault does not remember what a note
  looked like before its last save. `FileManager.moveItem`, falling back to copy-then-verify-
  then-remove; if both fail the old directory is left exactly where it is and the failure is
  reported. **An interrupted migration must leave the snapshots somewhere**, so the removal
  is always last. Starting fresh here was considered and refused: it is a silent, permanent,
  user-visible loss delivered by an update nobody asked for, and it is avoidable for about
  thirty lines.
- **`ai-journal/`: migrated, by move, on the same machinery.** Not strictly needed - its
  header says losing it loses nothing the vault still holds - but the code is written for
  `history/` regardless, and an `undo` that stops working on the day the app updates is a
  surprise for exactly the person who armed the connector deliberately.

`~/Labs` has a `cache.db` today for certain, and `history/` since M9 shipped; `ai-journal/`
only if a connector was ever armed against it. The migration handles the absent ones by
doing nothing.

**Conflict copies already on disk are reported, not deleted.** If `.pergamenum/` holds a
`cache 2.db` or a `starred 2.json`, the migration names it in `problems` and leaves it. An
upgrade that deletes files it did not itself write is not a thing this app does, and the
one place a conflict copy could hold something real - a `starred 2.json` from the other Mac
- is precisely the one nobody should throw away on the app's initiative.

**D4. `isExcludedFromBackup` is set on the new Application Support directory, and on nothing
inside the vault. It is in scope, and it is not the answer to `PG-004`.**

One line at directory creation, and the benefit is real but small: Time Machine should not
be carrying a rebuildable index and a tree of regenerable PNGs.

**It is set on nothing inside the vault, because the four that stay there are exactly the
four a person would want back from a backup.** Excluding `.pergamenum/` wholesale to catch
the cache would take the settings, the vocabulary, the themes and the stars with it.

The reason this is a footnote and not the decision: **the key governs backup, and iCloud
Drive synchronisation is not backup.** A file inside an iCloud Drive folder is the sync
payload; a flag saying "do not back this up" is not understood by iCloud Drive as "do not
sync this", and there is no documented resource key that means the latter. Stated as the
reasoning that makes the exclusion insufficient rather than as a measurement - **the plan
must verify it by hand on a real iCloud vault before relying on either half of it.** D1
does not rest on it either way: the four stores leave because they are derived, and that
argument holds whatever the key turns out to do.

**D5. `PG-004` is answered here and closed by the implementation, not by this file. The SPEC
amendment is debt on `PG-015`.**

An ADR is a decision and the exposure is on disk until the code moves. `PG-004` stays open
with its text rewritten to point here and to name the slices below; it closes when the
migration has shipped and `~/Labs` has been looked at by hand. `PG-003`, already folded into
it, stays closed.

SPEC §12 names `.pergamenum/cache.db`, §6.5 names `.pergamenum/thumbnails/`, and the tree at
§85 describes `.pergamenum/` as holding "cache, thumbnail, impostazioni, vocabolari". All
three stop being true. Following ADR-0011's own precedent rather than the letter of CLAUDE.md's
working agreement, the amendment is filed onto `PG-015` with the sections already waiting
there instead of blocking this.

## Slices

Three, each usable on its own.

1. **The resolver and the two free ones.** `VaultState` (the Application Support path, the
   `vaultID` in `settings.json`, `vault.json`, D4's exclusion), `cache.db` and `thumbnails/`
   moved by deletion-and-rebuild. Nothing can be lost in this slice, which is why it is first.
2. **`history/` and `ai-journal/`.** The move-with-fallback of D3 and the conflict-copy report.
3. **`perg`/`pergamenum-mcp` parity.** Both compile all four stores; the connectors must resolve
   the identical directory as the app, and `scripts/mcp-smoke.py` plus a `perg journal_log`
   against a real vault is how that gets confirmed rather than assumed.

## Consequences

- **Four types lose `init(root:)` and that reaches the test suite before it reaches the app.**
  `NoteHistory`, `WriteJournal`, `ThumbnailStore` and `IndexCache` are constructed from the
  vault root in nine test files. If they resolve Application Support internally, **the suite
  writes into the real `~/Library/Application Support/it.stefer.pergamenum/`** - the exact
  failure `RecentVaults.volatile()` and `PinnedTagsStore.volatile()` exist to prevent, now
  with files instead of defaults, and with `.claude/test-cmd` running it at the end of every
  turn. The resolver must take an injectable base and the tests must pass a temporary one.
- **Whatever file holds the resolver must be added to `sharedSources` by hand**, or both
  connector builds break naming the compiler rather than the cause (CLAUDE.md). It must not
  import SwiftUI, for the same reason.
- **"Delete `.pergamenum/` to reset the app" stops being true**, and it was a true and useful
  instruction. After this, resetting means deleting a directory under Application Support,
  and deleting `.pergamenum/` throws away settings, vocabulary, themes and stars while leaving
  the index and the history intact - the opposite of what somebody typing it would expect.
- **A vault handed to somebody else, or opened on the iPad, arrives with no history and no
  thumbnails.** That is what ADR-0011 already promised by calling it local; it becomes visible
  here for the first time.
- **`.pergamenum/` becomes a directory a person could reasonably read.** Four small text files
  and a themes folder, no binaries, no churn - which also means it is now a sensible thing to
  keep in git if the vault is in one, where before the index would have made that absurd.
- **`VaultLayout` currently knows six of the eight names**; `"history"` and `"ai-journal"` are
  string literals inside their own types. The split is a good moment to have one enum describe
  what is in the vault and another describe what is beside it, rather than to spread the new
  paths the same way.
- **ADR-0012 §D6 and §D10 are untouched and are the precedent this leans on.** Stars stay in
  the vault, tabs stay in `UserDefaults`, pinned tags stay in `UserDefaults`. This ADR adds a
  third location and the question that sorts between them is unchanged.
- **`clearCache()` and `clearCacheOnDisk()` keep working** and keep meaning what they meant;
  only the URL they are handed changes.
- **Nothing about the note scanner changes.** `isExcludedDirectory` still skips dot-directories
  and still has nothing to do with sync - a distinction `PG-004` conflated and this ADR does
  not fix by touching it.
