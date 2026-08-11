# ADR-0001: Initial architecture

- **Status**: Accepted
- **Date**: 2026-08-11
- **Context**: SPEC v2.2 (`docs/20260811_Pergamenum_SpecApp.md`), milestone M0

## Context

The specification fixes the product surface, the binding principles (§3), the file
formats and the milestone order. It deliberately leaves the internal structure open.
Three questions block M1 and one blocks M0, so they are settled here before any
feature code is written.

The binding principles constrain every answer below. Restated because they are the
reason for the choices, not decoration: files on disk are the source of truth, the
index is a rebuildable cache, no network call exists anywhere, and the vault must
stay readable by Obsidian at all times.

## Decision

### D1 - Target structure: one app target, folder-enforced layers

A single `Pergamenum` app target plus its test target. Layering is expressed as
folders under `Sources/`, not as separate Tuist targets or SPM modules.

```
Sources/
  App/            @main entry, Scenes, commands (menu bar), app-level wiring
  DesignSystem/   tokens, ThemeEngine, reusable styled components
  Core/           value types and pure logic with no framework dependency:
                  frontmatter, tags, wikilinks, task syntax, naming rules
  Vault/          file system access, FSEvents watcher, readers and writers
  Index/          GRDB store, schema, queries, reconciliation
  Features/       one folder per user-facing area:
                  Editor/, Workspace/, Tasks/, Calendar/, Conformance/, Search/
```

Dependency direction is one-way: `Features` may use `Core`, `Vault`, `Index` and
`DesignSystem`; `Core` depends on nothing but the standard library; `Vault` and
`Index` depend on `Core` only. Nothing depends on `Features`.

**Why not separate modules.** Separate Tuist targets buy compile-time enforcement of
those arrows and cost a rebuild of the manifest, cross-module `public` annotations
on every shared symbol, and slower incremental builds for a single-developer app.
The arrows above are enforced by review instead. This is reversible: extracting
`Core` into its own target later is mechanical, and the folder boundary is exactly
the seam to cut along. Extracting it now would be paying for a problem that does not
exist yet.

**Consequence for the linter.** `Core` holding the convention rules with no framework
import means the frontmatter, tag and wikilink validators are directly unit-testable
without a vault on disk. That is where the SPEC §4 rules live.

### D2 - Index: GRDB, rebuildable, never authoritative

`.pergamenum/cache.db` holds notes, links, backlinks, tags, tasks and thumbnail
references. Schema versioned through GRDB `DatabaseMigrator`.

Three rules follow from principle 3 (SPEC §3):

1. **Deleting the database loses nothing.** A full vault scan reconstructs it. The
   app must therefore be able to run a cold scan at acceptable speed, and "rebuild
   index" is a user-facing command (SPEC §12, Advanced settings).
2. **A migration failure is not a data-loss event.** When a migration cannot be
   applied, the app deletes the database and rebuilds from scratch rather than
   attempting recovery. This is the correct fail direction only because of rule 1,
   and it removes an entire class of migration code from the project.
3. **Writes go to files first, index second.** A task completed from any view writes
   the markdown file, and the index updates from the resulting file change. The index
   is never written directly as the primary effect of a user action, because a crash
   between the two writes must leave the file correct, never the cache.

Note IDs for `pergamenum://note?id=` live in the index, not in frontmatter: the
closed 4-key schema (SPEC §4.3) has no room for an `id` key. The consequence, already
noted in SPEC §9, is that the ID is stable only while the file is not renamed outside
the app.

### D3 - External change reconciliation: FSEvents, debounce, content hash

An FSEvents stream on the vault root, coalescing at 200 ms. On each batch:

1. Ignore paths inside `.pergamenum/` other than settings, to avoid feeding the
   watcher its own cache writes.
2. For each changed path, compare the file's modification date and size against the
   index row. Unchanged on both, skip. Otherwise re-read and re-index.
3. **A write performed by the app is not special-cased by suppressing events.** The
   app records the content hash it just wrote; when the resulting event arrives, the
   hash matches and the reindex is a no-op. Suppression windows are timing-dependent
   and lose genuine external edits that land inside the window; a hash comparison is
   not.
4. An external edit to a file currently open in the editor with unsaved changes
   raises a conflict prompt. It never merges silently and never discards either side
   without the user choosing. This is rare enough that the prompt is acceptable and
   dangerous enough that silence is not.

### D4 - Theming: DTCG tokens, bundled defaults, vault-level overrides

Required by SPEC §11.3, which fixes the format. This ADR settles only where the files
live and how they load.

- The two default themes ship in the app bundle as resources.
- On first vault open, they are copied to `.pergamenum/themes/` if absent. The user
  can then edit them or add more; the app never overwrites an existing file there.
- `ThemeEngine` resolves the active theme from settings and appearance, parses the
  DTCG JSON into a `Theme` value, and publishes it through the SwiftUI Environment.
- A token file that fails to parse falls back to the bundled default and surfaces a
  visible error. It never crashes and never renders an untokenized view.
- **Token resolution is total.** `Theme` exposes every token as a non-optional
  property, because a view asking for a colour must always get one. A missing token
  in a user file resolves to the bundled default's value for that token.

The consequence is the rule already stated in CLAUDE.md: a view that names a colour
or a font without going through a token does not pass review. Making that mechanical
rather than aspirational is the reason `Theme` has no escape hatch back to raw
`Color` literals.

## Alternatives considered

**SwiftData instead of GRDB for the index.** Rejected. SwiftData's model is
persistence as the source of truth, which is the opposite of principle 1; the index
here is a disposable derived artifact and its schema is relational and query-shaped
(backlinks, tag joins, task date ranges). GRDB also allows the drop-and-rebuild
migration policy in D2, which SwiftData does not make straightforward.

**Feature modules as Tuist targets from day one.** Rejected for now, see D1.

**Suppressing FSEvents during app writes.** Rejected, see D3.3.

**Deriving light and dark themes from a single token file with modifiers.** Rejected.
Two complete files are longer and mean a dark theme is designed rather than computed,
which is what "both first class from day one" (SPEC §11.2) asks for.

## Consequences

- M0 delivers the token files, `ThemeEngine`, the `Theme` value type and a demo view
  proving runtime switching. No vault access yet.
- M1 can start on `Core` (pure convention logic, fully unit-testable) in parallel with
  `Vault`, because D1 puts no framework dependency between them.
- The GRDB dependency enters `Tuist/Package.swift` at M1, not M0.
  **Update 2026-08-11 (M1):** deferred again. The index is held in memory and rebuilt
  by a cold scan on open. Everything D2 requires of it holds - disposable, derived
  from the files, never written as the primary effect of a user action - so the choice
  between memory and SQLite is a question about cold-scan cost on the real Labs vault,
  which has not been measured yet. Adding the dependency before the measurement would
  be paying for a problem that may not exist; `NoteIndex` keeps a query-shaped surface
  so the storage can change underneath it. Revisit once the scan is timed on the real
  vault, which the app now reports after every scan.
- Reversibility is preserved on the two decisions most likely to be wrong: D1 can be
  split into modules along existing folder seams, and D2's schema can change freely
  because the database is disposable by construction.
