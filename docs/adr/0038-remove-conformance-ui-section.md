# ADR-0038: The Conformità UI surfaces are removed; the linter stays CLI/MCP-only

- Status: accepted
- Date: 2026-09-10
- Topic slug: `remove-conformance-ui-section`
- Amends **SPEC §4.7** ("Linter di conformità") and **SPEC §10**'s Vista menu list, which named
  a dedicated in-app pane. Amends the **M6 acceptance criterion** (SPEC §13) only in how it is
  verified (via `perg lint`, not a pane), not in what it requires.
- Does not reopen **CLAUDE.md Principle 5** ("Harness conformance"): the schema is still the
  app's native shape, enforced at write time (closed tag/frontmatter vocabularies, blocking
  entry outside the table). This ADR is about the retrospective review surface only.
- Does not touch the protected interface **`VaultAPI.LintFinding`** (ADR-0053).

## Context

Stefano: "la sezione CONFORMITÀ non fa più parte dello scopo di questa app" — the review pane
is out of scope. Investigating where it actually lives found two separate UI surfaces, not one:

1. The dedicated "Conformità" pane (sidebar LAVORO group), reached via the Vista menu or
   Ctrl+Cmd+5, running the linter on the whole vault on request and listing non-conformant
   notes.
2. A `CONFORMITÀ` block inside every open note's right inspector (`VaultBrowser.swift`),
   recomputed on every note open, showing that one note's own violations. Stefano flagged this
   one directly as not making sense to keep showing.

Both call into the same rule engine `VaultSession` exposes
(`violations(path:title:text:)`, `Sources/Vault/VaultSession+Search.swift`), which also backs
`perg lint` and the MCP `lint` tool. That engine is the actual implementation of Principle 5 —
it is also what the tag editor consults to block a value outside the closed vocabulary at
typing time. Removing the UI review surfaces does not touch any of that.

## Decision

**Remove both UI surfaces; keep the engine, `perg lint`, and the MCP `lint` tool untouched.**

- The dedicated pane (`Sources/Features/Conformance/ConformanceView.swift`), its sidebar entry,
  Vista-menu item, and the two shortcut-catalogue commands (`.paneConformance`,
  `.runConformanceCheck`) are deleted.
- The inspector's `CONFORMITÀ` block and its backing `VaultController.violations(for: OpenNote)`
  wrapper are deleted.
- `VaultController.violations(forRecordAt:)` is kept: it is a one-line delegation to the session
  with its own test coverage (`Tests/URLSchemeTests.swift`) unrelated to either UI surface, and
  deleting it would force rewriting tests that have nothing to do with this decision.
- `ConformanceText` (the violation-to-Italian-sentence formatter) is kept: `RenameNoteSheet`
  (`NoteRowMenu.swift`) reuses it to show a bad title's violations while renaming, which is
  active input validation, not a conformance report.
- Ctrl+Cmd+5, freed by removing `.paneConformance`, is left unbound rather than reassigned to
  the next pane: `ShortcutCommand`'s raw values are the keys of the overrides file, and
  renumbering would silently move a binding a user had changed for a different pane
  (`ShortcutCommand.swift`'s own standing rule, §D-note on `paneDiary`'s placement).

## What stays, and why

- `perg lint` and the MCP `lint` tool: a developer/assistant-facing capability, independent of
  whether the app itself has a review pane. No external consumer asked for this to go away, and
  `VaultAPI.LintFinding` is a protected interface other tooling may depend on.
- The rule engine itself (`NoteName`, `FrontmatterRules`, `TagRules`, `RelatedSection`): this is
  Principle 5, not a feature layered on top of it.
- The closed-vocabulary block at tag-entry time: a different enforcement point (write time, not
  review time) that this decision does not touch.

## Consequence

SPEC §4.7 and §10 need a one-line amendment each to stop describing a Vista that no longer
exists; the linter's own rules and CLI/MCP surface are unchanged. PROJECT_BRIEF.md's "in scope"
line is updated to say the linter is CLI/MCP, not "conformance linter" unqualified.
