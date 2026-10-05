import AppKit
import Foundation

// Twenty-two of `NoteTextView`'s inputs, grouped by the consumer that reads them (PG-144 Task 5).
// Defaults exactly as the corresponding `NoteTextView` properties carried before the grouping, so
// a text view built without a vault behind it behaves as it always did.

extension NoteTextView {
    /// The find bar's inputs: the request to open it, what it found, and the edits and jump it asks
    /// for. `replacements` is ordered last match first by whoever builds it (`FindSession`).
    struct FindInputs {
        /// Raised by the Modifica menu; opens the find bar (SPEC §10, M8). Answered with the
        /// selection there was at that moment, which is the search's scope - captured once, the
        /// way AppKit's own bar did it, rather than followed: a scope tracking the caret would
        /// shrink to nothing as soon as the search moved the selection onto a match.
        var findRequest: FindRequest?
        var onFindApplied: (NSRange) -> Void = { _ in }
        /// What the find bar found, and which one the stepper is on. Drawn as a colour on the
        /// layout manager rather than on the text - see `NoteTextView+Matches`.
        var matches: [NSRange] = []
        var currentMatch: Int?
        /// Replacements to perform, and then report as performed. The one-shot shape `insertion`
        /// already has. **Ordered last match first** by whoever builds them, so that applying one
        /// does not move the ranges of those still to come.
        var replacements: [(range: NSRange, text: String)]?
        var onReplacementsApplied: () -> Void = {}
        /// The match the stepper moved onto, to be brought into view. Its own input rather than
        /// the index's `outline.scrollRequest`: that one carries an `ordinal` the reading view
        /// counts blocks by, and a find match has no position in the index to report. Borrowing
        /// the type would mean filling that field with a number that means nothing.
        var matchJump: NSRange?
    }

    /// The outline's inputs: the entries as line ranges, the jump to one, and folding.
    struct OutlineInputs {
        /// The index's entries, as line ranges. Handed to the text view so it can say which
        /// one the caret is in without the caret's position having to travel up on every
        /// arrow key.
        var outlineRanges: [NSRange] = []
        var onOutlineEntryChanged: ((Int?) -> Void)?
        /// A line the index asked to be taken to (M8). The fourth one-shot input, and it
        /// follows the same shape as the other three: consumed once, then reported as applied.
        var scrollRequest: Navigation.OutlineJump?
        var onScrollApplied: () -> Void = {}
        /// The index entries whose sections are folded (M8). Held by each heading's own UTF-16
        /// character offset, not by ordinal position: an edit elsewhere in the note can shift
        /// which array position a heading sits at between one SwiftUI render pass and the next,
        /// and a fold anchored to a position rather than to the heading itself would silently
        /// re-target the wrong section (PG-021 follow-up, `FoldStateOrdinalIndexStalenessTests`).
        var foldedEntries: Set<Int> = []
        /// Whether the frontmatter block is left out of the layout (`NoteTab.hidesFrontmatter`).
        /// Applied by the same pass as the folds, which is why it rides in this group.
        var hidesFrontmatter = false
        /// Called with the UTF-16 offset of the heading whose fold badge was clicked (PG-021) -
        /// the folded heading's own live layout offset, never re-derived through `outlineRanges`.
        /// `OutlinePane`'s chevron reaches the same `VaultController.toggleFold`, so a section
        /// opened from the editor and one opened from the sidebar are one gesture with two doors,
        /// both handing it an offset.
        var onToggleFold: ((Int) -> Void)?
    }

    /// What the vault behind the editor provides. Nil or a no-op when no vault is open.
    struct VaultInputs {
        /// The vault an embed's target is resolved in (ADR-0018 slice 3). Nil where there is
        /// no vault behind the editor - the same permissive default `spellCheck` and
        /// `hidesMarkup` take - and then `![[foto.png]]` stays unresolved, exactly today's
        /// behaviour.
        var vaultRoot: URL?
        /// The open note's own path, so a relative embed target is looked up beside it
        /// first, the same as `Attachment.resolve` already does for reading mode
        /// (`MarkdownReadingView.notePath`).
        var notePath = ""
        /// The vault's render cache for embedded files - the same `ThumbnailStore` reading
        /// mode's `EmbeddedFileView` reads, so a picture is rendered once and shared between
        /// the two surfaces rather than duplicated.
        var thumbnails: ThumbnailStore?
        /// How a `![[nota]]` reaches the note it names (ADR-0010). Nil where there is no vault
        /// behind the editor, and then the line stays the plain link it was.
        var transclusions: TransclusionSource?
        /// Where a `pergamenum-view` fence's rows come from (ADR-0033 §D9, plan
        /// `2026-09-06-pg-099-views-board-renderer-orphaned-by`, Task 7). Nil where there is no
        /// vault behind the editor - the same permissive default `vaultRoot`/`thumbnails` take,
        /// and deliberately what `DiaryView`/`TodayView` and every existing call site still get
        /// without change, since neither passes this property (ADR Consequences).
        ///
        /// Handed in by `EditorColumn+Text.swift`'s `editing(_:)`, which owns the app's only
        /// `ViewQuerySource`, and read by `NoteTextView+ViewBlocks.swift`'s
        /// `ViewBlockController.refresh`, which passes it - with `notePath`/`vaultRoot`/`thumbnails`,
        /// `onFollowLink` as the block's `onOpenNote` and a caret-placing `onEditSource` - into
        /// `ViewBlockHostStore.rootView(...)` on every styling pass. That call is the whole of
        /// what makes a drawn fence run its query in the editor (R-04, R-07, R-09); without it
        /// the block draws its "Nessun vault dietro questa vista" branch.
        var queries: ViewQuerySource?
        /// Raised when "Modifica query" is tapped in a drawn `pergamenum-view` fence's header
        /// (ADR-0034 §D1/§D2, R-01/R-02/R-03). Nil where there is no vault behind the editor - the
        /// same permissive default `queries` takes - and then the control simply is not drawn
        /// (`RenderedViewBlock.onEditQuery`'s own nil-means-no-control rule).
        ///
        /// Built per fence, per styling pass, by `NoteTextView+ViewBlocks.swift`'s
        /// `ViewBlockController.refresh`, which is the one place that turns `ViewBlockHostStore.rootView`'s
        /// plain `() -> Void` trigger into a `ViewQueryEditRequest` carrying the fence's current body
        /// and a commit closure anchored on its opening offset.
        var onEditQuery: ((ViewQueryEditRequest) -> Void)?
        /// Called with the file name inside `![[foto.png]]` when its raw syntax is clicked -
        /// `hidesMarkup` off, or the run not yet collapsed into a picture. Once ADR-0018
        /// slice 3 draws the picture in the run's place, a click there selects it instead
        /// (`selectEmbed(at:in:)`) and never reaches this callback; unlike a heading or
        /// emphasis marker, the caret alone never brings the raw text back (D5).
        var onOpenEmbed: ((String) -> Void)?
        /// Called with the tag of a `#client-acme` that was Cmd+clicked, and with the day of a
        /// valid `>2026-10-12` / `!2026-10-12` (n1-seams R-12, R-13). Nil where there is no vault
        /// behind the editor, and a Cmd+click on one then opens nothing.
        var onOpenTag: ((Tag) -> Void)?
        var onOpenDay: ((CalendarDate) -> Void)?
        /// Where a dropped file should be copied to, returning its file name for the
        /// embed (SPEC §5). Nil disables dropping.
        var onDropFile: ((URL) -> String?)?
        /// Called with the PNG bytes of an image pasted from the clipboard, returning the
        /// name it was written into the vault under. A screenshot has no file to drop, so
        /// without this it could not enter a note at all.
        var onPasteImage: ((Data) -> String?)?
    }
}
