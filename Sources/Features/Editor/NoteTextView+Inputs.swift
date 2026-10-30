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

    /// The outline's inputs: the store, the jump to an entry, and folding.
    struct OutlineInputs {
        /// Called with the index entry the caret is in, only when it changes, so the caret's
        /// position does not have to travel up on every arrow key. The entry is read from the
        /// coordinator's outline store (ADR-0096 §D7).
        var onOutlineEntryChanged: ((Int?) -> Void)?
        /// A line the index asked to be taken to (M8). The fourth one-shot input, and it
        /// follows the same shape as the other three: consumed once, then reported as applied.
        var scrollRequest: Navigation.OutlineJump?
        var onScrollApplied: () -> Void = {}
        /// Whether the frontmatter block is left out of the layout (`NoteTab.hidesFrontmatter`).
        /// Applied by the same pass as the folds, which is why it rides in this group.
        var hidesFrontmatter = false
        /// Called with the UTF-16 offset of the heading whose fold badge was clicked (PG-021) -
        /// the folded heading's own live layout offset, never re-derived through an entry's ordinal.
        /// `OutlinePane`'s chevron reaches the same `VaultController.toggleFold`, so a section
        /// opened from the editor and one opened from the sidebar are one gesture with two doors,
        /// both handing it an offset.
        var onToggleFold: ((Int) -> Void)?
        /// The column's outline store (ADR-0096 §D6): the coordinator splices and rebuilds it, and the
        /// sidebar reads its rows. Nil where no column owns one (Oggi, Diario, a test); the coordinator
        /// then keeps a private one.
        var store: OutlineStore?
        /// The revision of the text the model holds now, asked when a pass runs, so the store can be
        /// stamped with the revision it describes. Read live, never captured.
        var currentRevision: (() -> TextRevision?)?
        /// The folded sections (M8) as the heading offsets the tab keeps (`NoteTab.foldedEntries`,
        /// `FoldStateOrdinalIndexStalenessTests`), which the coordinator turns into the ordinals
        /// `NoteFolding` reads through the store's map, against the text it just styled, so an edit
        /// that moves a heading cannot re-target the wrong section (ADR-0096 §D7).
        var foldedOffsets: Set<Int> = []
        /// The callouts whose fold the person flipped (`NoteTab.toggledCallouts`, ADR-0087 §D8), as
        /// their title lines' offsets, read fresh against the text by the fold pass.
        var toggledCallouts: Set<Int> = []
        /// Called with a callout's title offset when its chevron is clicked (`VaultController.
        /// toggleCallout`). Nil in the Diario and Oggi editors, which draw each file's default.
        var onToggleCallout: ((Int) -> Void)?
        /// Called with the flipped callouts' title offsets once an edit moved them, so the tab keeps
        /// them on the titles they were set on (`VaultController.setToggledCallouts`, ADR-0091 §D6).
        var onCalloutsMoved: ((Set<Int>) -> Void)?
    }

    /// What the editor needs to follow, preview and offer a link (ADR-0083 §D2, §D3, §D6, §D7),
    /// grouped as `vault` and `find` are. Empty by default: with `follow` nil the Coordinator falls
    /// back to `onFollowLink(title)` for `.replace` and ignores the click variants, so a text view
    /// with no vault behind it behaves as it always did.
    struct LinkInputs {
        /// A request to follow a link, answered with `.done` or the choice to put in front of the
        /// person (`CommandActions.follow`).
        var follow: ((LinkRequest) -> LinkFollowOutcome)?
        /// A row of that choice picked from the menu at the click, with the click's how.
        var choose: ((LinkChoice, LinkOpening) -> Void)?
        /// What the Cmd+hover preview shows for a note title and its optional section.
        var preview: ((String, String?) -> LinkPreviewContent?)?
        /// The followable link under the caret, reported when it changes.
        var onCaretLinkChanged: ((URL?) -> Void)?
        /// «Crea «X»» chosen from the `[[` popup: the title to offer to the composer.
        var offerCreation: ((String) -> Void)?
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
        /// The tab in front in this column. One text view serves every tab of a column, and two
        /// tabs can show the same note with identical text (`openNoteInNewTab` does not dedupe), so
        /// the path alone cannot tell that the tab changed. Nil where there is no tab behind the
        /// editor (the diary, the today pane).
        var tabID: UUID?
        /// The vault's render cache for embedded files - the same `ThumbnailStore` reading
        /// mode's `EmbeddedFileView` reads, so a picture is rendered once and shared between
        /// the two surfaces rather than duplicated.
        var thumbnails: ThumbnailStore?
        /// How a `![[nota]]` reaches the note it names (ADR-0010). Nil where there is no vault
        /// behind the editor, and then the line stays the plain link it was.
        ///
        /// Handed in by the three editor hosts - `EditorColumn+Text.swift`'s `vaultInputs(for:)`,
        /// `TodayView` and `DiaryView` - each as `TransclusionSource.live(for:)`, the one factory
        /// over a vault (ADR-0098 §D4), and read by `NoteTextView+Transclusion.swift`'s
        /// `TransclusionController`, which resolves each `![[nota]]` it scans through it.
        var transclusions: TransclusionSource?
        /// Where a `pergamenum-view` fence's rows come from (ADR-0033 §D9, plan
        /// `2026-09-06-pg-099-views-board-renderer-orphaned-by`, Task 7). Nil where there is no
        /// vault behind the editor - the same permissive default `vaultRoot`/`thumbnails` take.
        ///
        /// Handed in by the three editor hosts - `EditorColumn+Text.swift`'s `editing(_:)`,
        /// `TodayView` and `DiaryView` - each as `ViewQuerySource.live(for:)`, the one factory
        /// over a vault (ADR-0082 §D8), and read by `NoteTextView+ViewBlocks.swift`'s
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

    /// What the editor reports about, and is asked to do with, the selection (ADR-0085 §D8,
    /// ADR-0086 §D4; read by `NoteTextView+SelectionReport.swift`). Empty by default, so a
    /// text view with no vault behind it behaves as it always did.
    struct SelectionInputs {
        /// A one-shot request to put the caret at an absolute UTF-16 offset: the daily note's
        /// `{{cursor}}`, a template applied, a composed note's body caret. Applied once, then
        /// reported through `onCaretApplied`.
        var caretRequest: CaretRequest?
        var onCaretApplied: () -> Void = {}
        /// The non-empty selection, once per change, and nil once when it collapses. A bare caret
        /// moving, or typing with one, reports nothing.
        var onSelectionChanged: ((NSRange?) -> Void)?

        struct CaretRequest: Equatable {
            let id: Int
            let offset: Int
        }
    }
}
