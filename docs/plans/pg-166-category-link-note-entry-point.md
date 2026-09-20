# PG-166 (#297): an entry point for linking a note to a category

## Gap

ADR-0047 §D5 made a category's "home" the note carrying `pergamenum-category: <slug>`.
`VaultSession.linkCategory`/`unlinkCategory` shipped and are tested (Task 6 of
`docs/plans/task-categories.md`), the inspector shows and unlinks an existing link, the
category view shows «Vai alla nota». `linkCategory` had no caller: nothing in the app could
create the link. The SPEC flow «Collega una nota…» is covered by no R-id, so the chain closed
green without it. This is an implementation gap in ADR-0047's R-06, not a new architectural
decision: no schema, no frontmatter key, no `IndexCache.schemaVersion` change, no protected
interface, no connector surface (categories stay read-only there). ADR-0047 is referenced,
not amended.

## Decisions

1. **Both sides get an entry point.** From the category: «Collega una nota…» / «Cambia
   nota…» / «Scollega la nota» in `CategoryView`'s header, and «Collega una nota…» in a
   category row's context menu, both opening `CategoryNotePicker`. From the note: a menu
   «Assegna una categoria…» in the inspector, shown where the unlink button shows once a
   category is set.
2. **A category has one home; linking displaces.** `linkCategory` alone would leave two
   notes claiming a slug, which is the `duplicateHome` lint finding. `setCategoryHome` links
   the new note first, then strips the key from every other claimant. A failed link returns
   before anything is stripped. A displaced note that cannot be rewritten is recorded and
   does not undo the link; the residue is the existing `duplicateHome` finding.
3. **One resolver.** `IndexSnapshot.notesClaimingCategory(_:)`/`homeNote(ofCategory:)` replace
   `CategoryView`'s private `homeNote(of:)`. `VaultSession+Search.swift`'s lint path is left
   alone: it inserts the note under lint into the set before sorting, a different question.

## Files

`Sources/Index/IndexSnapshot+Categories.swift`, `Sources/Vault/VaultSession+Categories.swift`,
`Sources/App/VaultController+Categories.swift`, `Sources/App/Navigation.swift`,
`Sources/App/RootView+Sheets.swift`, `Sources/Features/Tasks/CategoryNotePicker.swift` (new),
`Sources/Features/Tasks/CategoryView.swift`, `Sources/Features/Tasks/CategorySidebarSection.swift`,
`Sources/Features/Editor/VaultBrowser.swift`.

## Tests

`Tests/CategoryLintTests.swift` (displacement, an unrelated slug untouched, re-linking the
home is `.unchanged`, claimant ordering); `UITests/TaskCategoriesUITests.swift`
(`testLinkingANoteFromTheCategoryViewMakesItTheHome`).
