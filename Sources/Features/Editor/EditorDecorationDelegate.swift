import AppKit
import OSLog

/// Everything the editor draws that is not the note's own characters: folded sections kept
/// out of the layout, the headings that say how much they are hiding, the notes a
/// transclusion shows underneath its source line, and, since ADR-0018 slice 3, the picture
/// an embed line draws in place of its own `![[…]]`/`![alt](…)` syntax.
///
/// The mechanism is `NSTextContentManagerDelegate.shouldEnumerateTextElement`, whose header
/// in the macOS 26.5 SDK says returning NO makes an element "skipped from the enumeration",
/// and whose companion `enumerateTextElementsFromLocation` says an implementation may "hide
/// some elements from the layout". Measured offscreen before this was written: hiding two
/// paragraphs of six took the laid-out fragments from 6 to 4 and the height from 96 to 64;
/// then confirmed on screen in a real editor, which was the part the offscreen stack could
/// not answer.
///
/// Not a zero-width font, which is what collapses the *delimiters* of a line: a `\n` at
/// size 0.01 still breaks the line, so a folded section would be a stack of empty rows.
///
/// The other half of why this mechanism is the right one: the folded lines are not in the
/// layout at all, so `NSTextSelectionNavigation` never walks into them. Arrow-down from the
/// heading lands on the next visible line. Nothing to skip by hand - unlike the zero-width
/// route, where the caret stops twice inside a run that occupies no space.
///
/// Not `@MainActor`: Swift 6 refuses both conformances ("crosses into main actor-isolated
/// code"), so this object holds plain values and is fed from the view.
/// One object because a text view has one content-storage delegate and one layout-manager
/// delegate; four features - folding, transclusion, marker hiding and, since ADR-0018
/// slice 3, embeds - kept as four separate inputs so none can quietly depend on another's
/// state.
/// One hidden delimiter, at its range relative to its paragraph's start, and what kind
/// it is - which decides how `EditorDecorationDelegate` re-validates it before drawing.
/// An embed's marker covers its whole `![[…]]`/`![alt](…)` run, never the paragraph's own
/// trailing newline - probe 6 measured that including it makes no observable difference,
/// and the project's discipline is not to touch more than the minimum anyway.
struct HiddenMarker: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case heading, emphasis, embed
        /// A list item's whole opening run - its indentation **and** its `- `/`1. ` marker
        /// (ADR-0028; plan `2026-08-29-wysiwyg-markdown-in-workspace`, Task 3).
        ///
        /// The one kind here whose range does not start at the marker character: it starts
        /// at its paragraph's own start, so that the indentation is inside the range. Two
        /// things depend on that. The indent characters cannot be collapsed if they are
        /// outside the range, and the item's nesting level is read back out of them - a
        /// `.list` marker carries no level of its own, because the characters are the
        /// level and the table can go stale between a styling pass and a layout pass.
        case list
        /// A task line's whole `- [ ]`/`- [x]`/`- [>]`/`- [-]` marker (§7.1), drawn as a
        /// real checkbox glyph in place of the coloured bracket characters. Anchored at the
        /// span itself, not at its paragraph's start - unlike `.list`, a checkbox's
        /// indentation is not part of what this kind collapses.
        case checkbox
        /// A blockquote line's opening `>` run (ADR-0029 §D1; plan
        /// `2026-09-02-editor-wysiwyg-unification`, Task 2) - like `.list`, anchored at its
        /// paragraph's own start so the run's own level can be re-derived from the live
        /// characters rather than carried on the marker, which would go stale between a
        /// styling pass and a layout pass.
        case blockquote
        /// One `~~` delimiter of a strikethrough run - the exact twin of `.emphasis`.
        case strikethrough
        /// A wikilink's or a CommonMark link's own bracket run - `[[`/`]]`, or `[`/`](url)` -
        /// never the label/target text between them. Drawn hidden with a hover tooltip
        /// naming where it goes (R-04).
        case link
        /// A whole thematic-break line (`---`, `***`, `___`, ...), collapsed into
        /// `collapsedFont` and drawn by a `HorizontalRuleFragment` rather than left as three
        /// invisible characters - the one construct here that cannot length-preserve into a
        /// full-width line the way the other three can.
        case rule
        /// A GFM table's own header-line pipe syntax (ADR-0029 §D4; plan
        /// `2026-09-02-editor-wysiwyg-unification`, Task 4) - anchored at the header
        /// paragraph's own start, the same convention `.list` and `.blockquote` use, since
        /// the table's real shape is re-read from the live characters through
        /// `GFMTable.parse` rather than carried on the marker. Never the delimiter row or a
        /// body row: those leave the layout entirely through `apply(tableRows:)` (D5), a
        /// fifth input kept deliberately separate from `hiddenLineOffsets`.
        case table
        /// A `pergamenum-view` fence's own opening-line run (ADR-0033 §D1/§D4; plan
        /// `2026-09-06-pg-099-views-board-renderer-orphaned-by`, Task 2) - anchored at the
        /// opening fence paragraph's own start, the same convention `.table` uses, since the
        /// fence's real shape is re-read from the live characters through a fresh fence parse
        /// rather than carried on the marker. Never the body lines or the closing fence line:
        /// those leave the layout entirely through `apply(viewBlockLines:)`, a sixth input
        /// kept deliberately separate from both `hiddenLineOffsets` and `tableRowOffsets`
        /// (ADR §Context C4: unlike a table, whose last hidden row is its own last body row,
        /// a fence has no equivalent - it ends at a line of backticks that must leave the
        /// layout too, or it would sit under the drawn attachment as stray text).
        case viewBlock
    }

    let range: NSRange
    let kind: Kind
}

final class EditorDecorationDelegate: NSObject, NSTextContentStorageDelegate,
                                      NSTextLayoutManagerDelegate, @unchecked Sendable {
    /// The UTF-16 offset at which each hidden line begins. A set, because this is asked
    /// once per paragraph on every layout pass.
    nonisolated(unsafe) private var hiddenLineOffsets: Set<Int> = []
    /// Every table's own delimiter-row and body-row start offsets (ADR-0029 §D5; plan
    /// `2026-09-02-editor-wysiwyg-unification`, Task 4) - the fifth input, deliberately
    /// never merged into `hiddenLineOffsets`: folding a heading and drawing a table are
    /// two different reasons a paragraph leaves the layout, and `apply(tableRows:)`
    /// clearing this set must never clear a fold in progress, nor the reverse. The header
    /// row is never in here - it stays in the layout, carrying the `TableAttachment`.
    nonisolated(unsafe) private var tableRowOffsets: Set<Int> = []
    /// Every view block's own body-line and closing-fence start offsets (ADR-0033 §D1; plan
    /// `2026-09-06-pg-099-views-board-renderer-orphaned-by`, Task 2) - the sixth input, on
    /// the same terms as the fifth above and for the same reason: three separate sets, so
    /// that clearing one can never clear another. The opening fence line is never in here -
    /// it stays in the layout, carrying the `ViewBlockAttachment`. The closing fence line
    /// always is, which is the one place the arithmetic differs from a table's (ADR
    /// §Context C4: a table ends at its own last body row, a fence ends at a line of
    /// backticks that would otherwise sit under the drawn block as stray text).
    nonisolated(unsafe) private var viewBlockLineOffsets: Set<Int> = []
    /// Folded heading line offset to the number of lines it is hiding, which is what the
    /// badge says.
    nonisolated(unsafe) private var foldedHeadings: [Int: Int] = [:]
    nonisolated(unsafe) var badgeColor: NSColor = .secondaryLabelColor
    nonisolated(unsafe) var badgeBackground: NSColor = .quaternaryLabelColor
    /// The colour a drawn embed's resize handle is painted in (ADR-0019 §D5), pushed in
    /// from a token the same way `badgeColor` above is and handed on to `EmbedAttachment`.
    nonisolated(unsafe) var handleColor: NSColor = .secondaryLabelColor
    /// The colour a `HorizontalRuleFragment` paints its line in (ADR-0029 §D1), pushed in
    /// from a token exactly the way `badgeColor` and `handleColor` above are - a view that
    /// uses a colour without going through a token does not pass review (CLAUDE.md).
    nonisolated(unsafe) var ruleColor: NSColor = .separatorColor
    /// The page's own body face (ADR-0030 §D1/§D5), pushed in from `ProseTypography.prose(_:)`
    /// exactly the way `badgeColor`/`handleColor`/`ruleColor` above are: this object is not
    /// `@MainActor` and cannot read `Theme` itself, so `applyStyling` resolves the token once
    /// and hands the finished `NSFont` in. The system-face default is what a delegate built by
    /// an offscreen harness draws with; the app overwrites it on every styling pass.
    nonisolated(unsafe) var proseFont: NSFont = .systemFont(ofSize: NSFont.systemFontSize)
    /// The fold badge's own face (ADR-0030 §D1/§D5), handed on to `FoldedHeadingFragment` in
    /// `textLayoutManager(_:textLayoutFragmentFor:in:)` beside `badgeColor`/`badgeBackground`,
    /// in place of the literal 10pt system face the fragment drew before this task - pushed in
    /// the same way `proseFont` above is, never resolved by the fragment itself.
    nonisolated(unsafe) var badgeFont: NSFont = .systemFont(ofSize: 10, weight: .regular)
    /// The checkbox glyph's own face (ADR-0030 §D1/§D5), pushed in from
    /// `ProseTypography.checkbox(_:)` beside `proseFont`/`badgeFont` above. Nil - the default -
    /// leaves `checkboxParagraph(at:storage:)` drawing the glyph at the surrounding run's own
    /// size, exactly as before this property existed; an offscreen harness that never calls
    /// `applyStyling` gets that, not a crash.
    nonisolated(unsafe) var checkboxFont: NSFont?
    /// A transcluded note, by the UTF-16 offset of the line that names it. Measured and
    /// styled on the main actor and handed over as a value, because this object cannot be
    /// `@MainActor` - Swift 6 refuses both conformances if it is.
    nonisolated(unsafe) private var renditions: [Int: TranscludedRendition] = [:]
    /// An embed's resolved picture, or the fact that it could not be drawn, by the
    /// paragraph offset of the line that names it - the same key space `hiddenMarkers`
    /// below uses. `EmbedTable` (ADR-0018 slice 3, Step 2) measures and resolves it on the
    /// main actor and hands over a finished value, the exact crossing `renditions` above
    /// already makes: this object cannot be `@MainActor`, so it never calls back into
    /// `EmbedTable` or `ThumbnailStore`.
    nonisolated(unsafe) private var embedRenditions: [Int: EmbedRendition] = [:]
    /// A paragraph's hidden markers - a heading's `#`s and the space after them, an
    /// emphasis run's opening and closing `*`/`**`, or an embed's own whole run - each
    /// relative to its own paragraph's start, not to the document (ADR-0018 §D1). Filled
    /// by `applyStyling`'s walk over `MarkdownStyler.spans(in:)`, the same one that already
    /// knows where every marker is. One table for all three kinds rather than three: the
    /// other features this object carries (folding, transclusion) are kept as separate
    /// inputs, but a heading marker, an emphasis marker and an embed's run are the same
    /// feature - hiding - with three sources.
    ///
    /// Not `private`: `listParagraph(at:storage:)` in `EditorDecorationDelegate+ListRendering.swift`
    /// reads it too (ADR-0028, Task 3).
    nonisolated(unsafe) var hiddenMarkers: [Int: [HiddenMarker]] = [:]
    /// Paragraphs currently drawn in full, because the caret's paragraph, a non-empty
    /// selection, an active IME composition or the find bar's current match touches them
    /// (ADR-0018 §D2). Keyed the same way as `headingMarkers`.
    ///
    /// Not `private`: `listParagraph(at:storage:)` in `EditorDecorationDelegate+ListRendering.swift`
    /// reads it too (ADR-0028, Task 3).
    nonisolated(unsafe) var revealedParagraphs: Set<Int> = []
    /// The vault's `hidesMarkup` setting. `false` makes
    /// `textContentStorage(_:textParagraphWith:)` a no-op, i.e. today's behaviour - hiding
    /// markup is fully reversible with a toggle rather than a revert.
    nonisolated(unsafe) var hidesMarkup = false
    /// The grid already vended for each table, by its header paragraph's own offset - the
    /// same finished-value hand-over `embedRenditions` already makes (ADR-0029 §D6): this
    /// object cannot be `@MainActor`, so it never asks `TableGridStore` for one itself, and
    /// a dictionary rather than a single optional because a note can hold more than one
    /// table at once. Not `private`: `tableParagraph(at:storage:)` in
    /// `EditorDecorationDelegate+TableRendering.swift` reads it.
    nonisolated(unsafe) var tableViews: [Int: TableGridView] = [:]
    /// The host already vended for each view block, by its opening fence paragraph's own
    /// offset - the same finished-value hand-over `tableViews` above makes (ADR-0033 §D2:
    /// *"the delegate carries a reference and calls nothing"*). Typed `NSView` rather than
    /// `NSHostingView<AnyView>` because that is all this object needs to know about it: the
    /// Coordinator owns `ViewBlockHostStore`, builds the SwiftUI root view and pushes it in,
    /// and this object - which cannot be `@MainActor` - only hands the reference to the
    /// attachment. Not `private`: `viewBlockParagraph(at:storage:)` in
    /// `EditorDecorationDelegate+ViewBlockRendering.swift` reads it.
    nonisolated(unsafe) var viewBlockHosts: [Int: NSView] = [:]
    /// Small enough to draw as nothing while still breaking the line the way a real
    /// character does - unlike a `\n` at this size, which is why folding uses a different
    /// mechanism: this hides a delimiter mid-paragraph, not a whole paragraph.
    nonisolated(unsafe) static let collapsedFont = NSFont.monospacedSystemFont(ofSize: 0.01, weight: .regular)

    var isFolding: Bool { !foldedHeadings.isEmpty }
    /// How many markers the last styling pass registered, heading, emphasis and embed
    /// alike - what a test reads to confirm `applyStyling` populated the table, the same
    /// way `isFolding` reads `foldedHeadings` for the folding half of this file.
    var hiddenMarkerCount: Int { hiddenMarkers.values.reduce(0) { $0 + $1.count } }

    func apply(renditions: [Int: TranscludedRendition]) {
        self.renditions = renditions
        Logger.folding.notice("transclusioni: \(renditions.count, privacy: .public) rese")
    }

    /// Registers where every embed has resolved to, so far - called both after an
    /// ordinary styling pass and, later, when a still-pending render lands
    /// (`EmbedTable.setRenditions`, ADR-0018 slice 3): the delegate has no other way to
    /// learn a picture is ready, since it cannot itself watch the actor that renders one.
    func apply(embeds: [Int: EmbedRendition]) {
        embedRenditions = embeds
        Logger.folding.notice("embed: \(embeds.count, privacy: .public) rese")
    }

    func apply(hiddenLines: Set<Int>, foldedHeadings headings: [Int: Int]) {
        hiddenLineOffsets = hiddenLines
        foldedHeadings = headings
        Logger.folding.notice(
            "pieghe: \(headings.count, privacy: .public) sezioni, \(hiddenLines.count, privacy: .public) righe"
        )
    }

    /// Registers a table's delimiter-row and body-row offsets as out of the layout - the
    /// fifth producer of `shouldEnumerate`'s refusal, deliberately its own setter rather
    /// than a second parameter on `apply(hiddenLines:foldedHeadings:)` above (ADR §D5):
    /// *"two producers on one setter is precisely what the delegate's own header forbids."*
    /// An empty set here clears only the table rows, never a fold already registered, and
    /// the reverse holds too - `apply(hiddenLines:foldedHeadings:)` never touches this one.
    func apply(tableRows offsets: Set<Int>) {
        tableRowOffsets = offsets
        Logger.folding.notice("tabelle: \(offsets.count, privacy: .public) righe nascoste")
    }

    /// Registers the grid view already vended for each table, by its header offset - the
    /// same finished-value hand-over `apply(embeds:)` makes. Called from the Coordinator,
    /// which owns `TableGridStore` (ADR-0029 §D6); this object never builds a view itself.
    func apply(tableViews views: [Int: TableGridView]) {
        tableViews = views
    }

    /// Registers a view block's body-line and closing-fence offsets as out of the layout -
    /// the sixth producer of `shouldEnumerate`'s refusal (plan
    /// `2026-09-06-pg-099-views-board-renderer-orphaned-by`, Task 2), deliberately never
    /// merged into `hiddenLineOffsets` or `tableRowOffsets` - the same isolation
    /// `apply(tableRows:)`'s own header already states, extended to a third input rather
    /// than restated as a special case of the second.
    ///
    /// Guarded on the set itself rather than unconditional, which the other two hidden-line
    /// setters can afford not to be: `applyViewBlocks`'s own `hidesMarkup`-off branch calls
    /// this on **every** keystroke (ADR §D12 - the escape hatch has to reach the enumeration
    /// refusal, so it cannot skip the call the way `clearTables()` does), and an unguarded
    /// setter would write one `notice` per keystroke for a note that has no view block in it
    /// at all. The same shape, and the same reason, as `apply(hiddenMarkers:hidingMarkup:)`
    /// below.
    func apply(viewBlockLines offsets: Set<Int>) {
        guard offsets != viewBlockLineOffsets else { return }
        viewBlockLineOffsets = offsets
        Logger.folding.notice("blocchi vista: \(offsets.count, privacy: .public) righe nascoste")
    }

    /// Registers the host view already vended for each view block, by its opening fence's
    /// own paragraph offset - the same finished-value hand-over `apply(tableViews:)` makes.
    ///
    /// Called from the Coordinator, which owns `ViewBlockHostStore` (ADR §D3); this object
    /// never builds a view itself and never asks that store for one.
    func apply(viewBlockHosts hosts: [Int: NSView]) {
        viewBlockHosts = hosts
    }

    /// Registers where the hidden markers are and whether they should be hidden at all.
    ///
    /// Guarded rather than unconditional: `applyStyling` calls this on every keystroke and
    /// every SwiftUI update, and logging on each of those would drown the one line per
    /// fold this file otherwise writes.
    func apply(hiddenMarkers markers: [Int: [HiddenMarker]], hidingMarkup hides: Bool) {
        guard markers != hiddenMarkers || hides != hidesMarkup else { return }
        hiddenMarkers = markers
        hidesMarkup = hides
        let count = markers.values.reduce(0) { $0 + $1.count }
        Logger.folding.notice(
            "marcatori: \(count, privacy: .public), nascondi=\(hides, privacy: .public)"
        )
    }

    /// Sets which paragraphs are drawn in full, and returns the ones that changed since
    /// the last call - what the caller invalidates, never the whole document. No logging:
    /// this fires on every paragraph-crossing arrow key, and `notice` persists by default,
    /// which would be noise.
    func apply(revealedParagraphs paragraphs: Set<Int>) -> Set<Int> {
        let changed = revealedParagraphs.symmetricDifference(paragraphs)
        revealedParagraphs = paragraphs
        return changed
    }

    // MARK: Hiding

    /// Refuses to enumerate a folded line, a table's own delimiter/body row, or a view
    /// block's body/closing-fence line - the union of three independently-set inputs
    /// (ADR-0029 §D5, ADR-0033 §D1), never one merged into another.
    ///
    /// Three sets consulted here rather than one filled from three places, because that is
    /// what makes each setter's own empty set clear only its own lines: a fold and a drawn
    /// block are two different reasons a paragraph is out of the layout, and a note can be
    /// in both states at once.
    func textContentManager(
        _ textContentManager: NSTextContentManager,
        shouldEnumerate textElement: NSTextElement,
        options: NSTextContentManager.EnumerationOptions
    ) -> Bool {
        guard !hiddenLineOffsets.isEmpty || !tableRowOffsets.isEmpty || !viewBlockLineOffsets.isEmpty,
              let range = textElement.elementRange
        else { return true }
        let start = offset(of: range.location, in: textContentManager)
        return !hiddenLineOffsets.contains(start)
            && !tableRowOffsets.contains(start)
            && !viewBlockLineOffsets.contains(start)
    }

    // MARK: Marking

    func textLayoutManager(
        _ textLayoutManager: NSTextLayoutManager,
        textLayoutFragmentFor location: NSTextLocation,
        in textElement: NSTextElement
    ) -> NSTextLayoutFragment {
        let standard = NSTextLayoutFragment(textElement: textElement, range: textElement.elementRange)
        guard let manager = textLayoutManager.textContentManager else { return standard }
        let start = offset(of: location, in: manager)

        if let rendition = renditions[start] {
            let fragment = TranscludedLineFragment(
                textElement: textElement, range: textElement.elementRange
            )
            fragment.rendition = rendition
            return fragment
        }

        // A rule is the one ADR-0029 construct a length-preserving substitution cannot
        // serve: three characters cannot span a column however they are drawn (§D1). Its
        // own characters are collapsed by the generic path in
        // `textContentStorage(_:textParagraphWith:)` and the line itself is drawn here, the
        // shape `FoldedHeadingFragment` and `TranscludedLineFragment` are the two working
        // instances of. Re-validated against the element's own characters for the same
        // reason every other decoration is: this is a later pass than the one that recorded
        // the marker.
        if hidesMarkup, !revealedParagraphs.contains(start),
           (hiddenMarkers[start] ?? []).contains(where: { $0.kind == .rule }),
           let paragraph = textElement as? NSTextParagraph,
           MarkdownBlockParser.isRule(
               paragraph.attributedString.string.trimmingCharacters(in: .whitespacesAndNewlines)
           ) {
            let fragment = HorizontalRuleFragment(
                textElement: textElement, range: textElement.elementRange
            )
            fragment.ruleColor = ruleColor
            return fragment
        }

        guard let hidden = foldedHeadings[start] else { return standard }
        let fragment = FoldedHeadingFragment(textElement: textElement, range: textElement.elementRange)
        fragment.hiddenLines = hidden
        // Carried so a click on the badge can say which section it means (PG-021).
        fragment.headingOffset = start
        fragment.badgeColor = badgeColor
        fragment.badgeBackground = badgeBackground
        fragment.badgeFont = badgeFont
        return fragment
    }

    // MARK: Revealing

    /// Substitutes a heading's paragraph with one whose marker is drawn at a font too
    /// small to be seen, never removing or replacing a character - the same
    /// `NSTextContentStorageDelegate` hook `TransclusionLayoutTests` measured a
    /// *displayed* paragraph differing from the *stored* one through
    /// (`docs/20260817_TextKit2_live_editing.md`).
    func textContentStorage(
        _ textContentStorage: NSTextContentStorage,
        textParagraphWith range: NSRange
    ) -> NSTextParagraph? {
        guard hidesMarkup, let storage = textContentStorage.textStorage else { return nil }

        // The embed branch, first and unconditionally on `revealedParagraphs`: a drawn
        // embed does not reveal on caret the way a heading/emphasis marker does (D5's
        // deliberate exception to D2), or the caret passing over the line, or Backspace
        // reaching it, would fight the redraw one character at a time instead of meeting
        // a picture to delete whole (ADR-0018 slice 3, Step 3; Step 4 is what makes the
        // caret and Backspace actually treat it that way).
        if let embedded = embedParagraph(at: range, storage: storage) {
            return embedded
        }

        // The list branch, beside the embed one and under the same length rule: a marker
        // is *substituted*, never inserted or removed (ADR-0028 §D2). Unlike the embed
        // branch above, it must honour `revealedParagraphs` - a list marker reveals on the
        // caret's paragraph the way a heading's does (R-03) - which is why its own guards
        // belong inside it rather than being borrowed from the ones below: a paragraph
        // carrying a list marker cannot fall through to the generic, font-collapsing path,
        // or its `- ` would be hidden outright instead of being drawn as a bullet.
        if let list = listParagraph(at: range, storage: storage) {
            return list
        }

        // The checkbox branch, beside the list one and under the same length rule: a
        // task's state character is *substituted*, never inserted or removed (§7.1). Like
        // list, it honours `revealedParagraphs` internally so a task line reveals on the
        // caret's paragraph, and it must run before the generic path below or its `[ ]`
        // would be hidden outright instead of drawn as a checkbox.
        if let checkbox = checkboxParagraph(at: range, storage: storage) {
            return checkbox
        }

        // The blockquote branch, beside the list one and under the same length rule: each
        // `>` is *substituted* by a bar, never inserted or removed (ADR-0029 §D1). Like
        // list and checkbox it honours `revealedParagraphs` internally, and it must run
        // before the generic path below or its `>` would be hidden outright instead of
        // being drawn as one bar per level.
        if let quote = quoteParagraph(at: range, storage: storage) {
            return quote
        }

        // The table branch, beside the quote one and under the same length rule (ADR-0029
        // §D4; plan `2026-09-02-editor-wysiwyg-unification`, Task 4): the header line's own
        // pipe syntax is *substituted* for a `TableAttachment`, never inserted or removed.
        // It does not honour `revealedParagraphs` the way list/checkbox/blockquote do - a
        // drawn table does not reveal on caret, D5's exception for a grid the same way it
        // is for a drawn embed (ADR-0018 §D5).
        if let table = tableParagraph(at: range, storage: storage) {
            return table
        }

        // The view-block branch, beside the table one and under the same length rule
        // (ADR-0033 §D1): the opening fence line's own backticks are *substituted* for a
        // `ViewBlockAttachment`, never inserted or removed. Like the table branch it does
        // not honour `revealedParagraphs` - this construct's reveal is keyed on the fence's
        // whole source range one layer up (§D4) - and like it, it must run before the
        // generic path below, which would otherwise collapse the opening line's characters
        // outright instead of drawing a block in their place.
        if let viewBlock = viewBlockParagraph(at: range, storage: storage) {
            return viewBlock
        }

        guard !revealedParagraphs.contains(range.location),
              let markers = hiddenMarkers[range.location], !markers.isEmpty
        else { return nil }

        let survivors = Self.survivors(among: markers, of: range, in: storage.string as NSString)
        guard !survivors.isEmpty else { return nil }

        let copy = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: range))
        for marker in survivors {
            copy.addAttribute(.font, value: Self.collapsedFont, range: marker.range)
        }
        // Over the whole run and not only over the brackets: what is left on screen once
        // they are collapsed is the label, and the label is what a person hovers (R-04).
        for tooltip in Self.linkTooltips(among: survivors, of: range, in: storage.string as NSString) {
            copy.addAttribute(.toolTip, value: tooltip.target, range: tooltip.range)
        }
        return NSTextParagraph(attributedString: copy)
    }

    /// The markers of `paragraph` that may still be drawn - re-read from the real
    /// characters rather than trusted: the table is filled by the last styling pass, this
    /// is a later layout pass, and the two can go stale against each other. Silently
    /// collapsing prose would be the failure mode here, not a crash. Each marker is checked
    /// on its own, so one gone stale does not cancel the others in the same paragraph.
    ///
    /// Shared by the two paths that collapse a marker into `collapsedFont`: the generic one
    /// above and the list branch in `EditorDecorationDelegate+ListRendering.swift`, which
    /// returns early and would otherwise leave a bold list item's `**` on screen (ADR-0028,
    /// the SPEC's coexistence case). Not `private` for that reason.
    static func survivors(
        among markers: [HiddenMarker], of paragraph: NSRange, in text: NSString
    ) -> [HiddenMarker] {
        markers.filter { marker in
            NSMaxRange(marker.range) <= paragraph.length &&
                stillSpells(
                    marker.kind,
                    text,
                    at: NSRange(
                        location: paragraph.location + marker.range.location, length: marker.range.length
                    )
                )
        }
    }

    /// The embed's own branch of the substitution above: swaps the run's first character
    /// for `NSAttachmentCharacter` in the *displayed* copy only, the one mechanism probe 6
    /// found TextKit 2 actually recognises (`EmbedAttachmentProbeTests` - an `.attachment`
    /// attribute kept over the original `!` is never asked for its bounds or its image at
    /// all). Nil, leaving the raw syntax on screen exactly as today, whenever there is
    /// nothing yet to draw: no embed marker at this offset, no rendition yet because
    /// `EmbedTable`'s render is still in flight, or the marker gone stale against the real
    /// characters since the last styling pass.
    private func embedParagraph(at range: NSRange, storage: NSTextStorage) -> NSTextParagraph? {
        guard let rendition = embedRenditions[range.location],
              let marker = (hiddenMarkers[range.location] ?? []).first(where: { $0.kind == .embed }),
              NSMaxRange(marker.range) <= range.length
        else { return nil }

        let text = storage.string as NSString
        let markerRange = NSRange(location: range.location + marker.range.location, length: marker.range.length)
        guard let embed = Self.stillSpellsAnEmbed(text, at: markerRange, rendition: rendition) else { return nil }

        let copy = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: range))
        let attachmentRange = NSRange(location: marker.range.location, length: 1)
        let restRange = NSRange(location: attachmentRange.location + 1, length: marker.range.length - 1)

        // An `EmbedAttachment` rather than a plain `NSTextAttachment`, so the picture is
        // drawn at the size the run itself asks for (ADR-0019 §D2). Both facts it needs
        // are already here and neither is a new input: the run's own text is the exact
        // substring `stillSpellsAnEmbed` just re-read above, and the natural size is the
        // rendition's own picture - the placeholder's, for `.missing`. This object still
        // learns nothing about the container or the column; `attachmentBounds` reads those
        // from the live `NSTextContainer` at layout time, which is why it can, and this
        // cannot.
        let attachment = EmbedAttachment()
        switch rendition {
        case .drawn(let image):
            attachment.image = image
            // The written size and the handle are both a *picture's* affordances, and they
            // are set in the one branch that has a picture. A `.missing` placeholder is
            // refused by the same `guard case .drawn` the hit test uses, so the paint, the
            // hit target and the drawn size cannot disagree (ADR-0019 §D8) - and a note
            // that says `![[foto.png|900]]` about a file the vault no longer has draws the
            // 28-point broken-image glyph at 28 points, not that glyph blown up to 900.
            // `natural` for this branch is the placeholder's own size, and a `written` of
            // nil is what makes `EmbedResize.resolved` hand it back untouched.
            attachment.written = EmbedResize.written(inRun: text.substring(with: markerRange))
            attachment.handleColor = handleColor
        case .missing:
            attachment.image = Self.missingEmbedImage
        }
        attachment.natural = attachment.image?.size ?? .zero

        // A substitution, not an insertion: one character out, one in, the paragraph's
        // own length unmoved - `NSTextContentManager.h:120`'s own constraint, the same one
        // the hiding branch below keeps by never touching length at all.
        copy.replaceCharacters(in: attachmentRange, with: "\u{FFFC}")
        copy.addAttribute(.attachment, value: attachment, range: attachmentRange)
        // `.accessibilityAttachment`'s value is documented as "id - corresponding element"
        // (`NSAccessibilityConstants.h`), the same shape `NSAccessibilityLinkTextAttribute`
        // has - a plain label string here, not the element itself. It used to be an
        // `NSAccessibilityElement` built right at this call site, with `parent: nil`
        // because nothing here has an `NSView` to give it one: `EditorDecorationDelegate`
        // is not `@MainActor` and holds no text view (`NoteTextView+Embeds.swift:32-38`
        // says why). That element never became a stop for VoiceOver - a dump of the real
        // accessibility tree showed no `Image` node and no `editor-embed` identifier at
        // all, because `NSAccessibilityElement.h`'s own header says its vendor "must
        // maintain ownership of the NSAccessibilityElements", and nothing here ever called
        // `accessibilityAddChildElement:` to give AppKit one to keep. The element that
        // actually reaches VoiceOver now lives in `CompletingTextView`'s own
        // `accessibilityChildren()` override (`CompletingTextView+Accessibility.swift`),
        // built from this same label the moment the real text view is asked, not pushed in
        // from here ahead of time.
        copy.addAttribute(.accessibilityAttachment, value: embed.alt ?? embed.target, range: attachmentRange)
        if restRange.length > 0 {
            copy.addAttribute(.font, value: Self.collapsedFont, range: restRange)
        }
        return NSTextParagraph(attributedString: copy)
    }

    /// Whether a drawn embed's run sits at this exact paragraph-start offset right now,
    /// and its absolute range when it does - the same validity `embedParagraph(at:
    /// storage:)` requires before it draws one, asked from outside for the caret and
    /// click rules of Step 4 (ADR-0018 slice 3): they must act on a picture that is
    /// actually on screen this instant, never on a stale table entry and never on raw
    /// text with `hidesMarkup` off - which is why the check is repeated here rather than
    /// left to the caller alone (R4 of the plan: the failure mode of skipping it is
    /// Backspace eating visible prose whole).
    ///
    /// `offset` is a candidate paragraph-start, the same key space `embedRenditions` and
    /// `hiddenMarkers` already use - not "the paragraph containing an arbitrary
    /// location". An offset that is not itself a paragraph's start simply misses both
    /// dictionaries and answers nil, which is the right answer for a location inside a
    /// paragraph's own body.
    func drawnEmbedRange(atParagraphStart offset: Int, in text: NSString) -> NSRange? {
        guard hidesMarkup,
              let rendition = embedRenditions[offset],
              let marker = (hiddenMarkers[offset] ?? []).first(where: { $0.kind == .embed })
        else { return nil }
        let markerRange = NSRange(location: offset + marker.range.location, length: marker.range.length)
        guard Self.stillSpellsAnEmbed(text, at: markerRange, rendition: rendition) != nil else { return nil }
        return markerRange
    }

    /// A minimal placeholder for a `.missing` embed - already decided for this slice: a
    /// file the vault does not have is drawn as broken, not left as raw syntax, which
    /// already means "still rendering" everywhere else in this file. `secondaryLabelColor`
    /// for the same reason `badgeColor` defaults to it: a themed tint can replace this
    /// later without this delegate gaining a dependency it does not otherwise need.
    private static let missingEmbedImage: NSImage = {
        let size = NSSize(width: 28, height: 28)
        guard let symbol = NSImage(systemSymbolName: "photo.badge.exclamationmark", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 20, weight: .regular))
        else { return NSImage(size: size) }
        symbol.isTemplate = true
        let tinted = NSImage(size: size)
        tinted.lockFocus()
        symbol.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .sourceOver, fraction: 1)
        NSColor.secondaryLabelColor.set()
        NSRect(origin: .zero, size: size).fill(using: .sourceAtop)
        tinted.unlockFocus()
        return tinted
    }()

    private static func stillSpells(_ kind: HiddenMarker.Kind, _ text: NSString, at range: NSRange) -> Bool {
        switch kind {
        case .heading: stillSpellsAHeadingMarker(text, at: range)
        case .emphasis: stillSpellsAnEmphasisMarker(text, at: range)
        // Never handled here: an embed marker is drawn only by the dedicated
        // `embedParagraph(at:storage:)` branch above, which re-validates it with
        // `stillSpellsAnEmbed` before this generic, font-collapsing path ever sees the
        // paragraph (ADR-0018 slice 3, Step 3).
        case .embed: false
        // Never handled here either, and for the same structural reason `.embed` above is
        // not: a list marker is drawn by its own dedicated `listParagraph(at:storage:)`
        // branch, which re-reads the characters through `stillSpellsAListMarker` because it
        // needs what they say - the indent's width and the item's level - and not merely
        // whether they are still there. Answering anything but `false` here would let a
        // `.list` entry into the generic collapsing loop, which would hide the `- ` outright
        // instead of turning it into a bullet (ADR-0028 §D4).
        case .list: false
        // Never handled here either, for the same structural reason as `.list`: a
        // checkbox marker is drawn by its own dedicated `checkboxParagraph(at:storage:)`
        // branch, re-validated through `stillSpellsATaskMarker`.
        case .checkbox: false
        // Never handled here, for the same structural reason as `.list`: a blockquote's `>`
        // run is drawn by its own dedicated `quoteParagraph(at:storage:)` branch, which
        // re-reads the characters through `stillSpellsABlockquoteMarker` because it needs
        // what they *say* - the level, i.e. how many bars to draw - and not merely whether
        // they are still there. Letting a `.blockquote` entry into this generic collapsing
        // loop would hide the `>` outright instead of substituting a bar for it (ADR-0029 §D1).
        case .blockquote: false
        // The three ADR-0029 constructs the generic, font-collapsing path *does* serve: two
        // `~~` delimiters are the exact twin of `.emphasis`, a link's brackets are collapsed
        // and nothing is put in their place, and a rule's own characters are collapsed with
        // the line itself drawn by `HorizontalRuleFragment` at layout time.
        case .strikethrough: stillSpellsAStrikethroughMarker(text, at: range)
        case .link: stillSpellsALinkDelimiter(text, at: range)
        case .rule: stillSpellsARule(text, at: range)
        // Never handled here, for the same structural reason as `.list`/`.blockquote`: a
        // table's own re-validation reads the *whole* `GFMTable` shape back from the live
        // characters (`GFMTable.parse`), not merely whether a marker range is still
        // spelled - the coder's own branch inside `tableParagraph(at:storage:)` (Task 4).
        case .table: false
        // Never handled here, for the same structural reason as `.table`: a view block's
        // own re-validation reads the whole fence shape back from the live characters, not
        // merely whether a marker range is still spelled - the coder's own branch inside
        // `viewBlockParagraph(at:storage:)` (plan
        // `2026-09-06-pg-099-views-board-renderer-orphaned-by`, Task 5).
        case .viewBlock: false
        }
    }

    /// Whether `range` still spells a whole embed line - `![[file.est]]` or
    /// `![alt](file.est)` - read from the text as it is right now, and, for a rendition
    /// already known to be `.missing`, that it still names the same file: the one case
    /// this delegate can check identity for, since a `.drawn` rendition carries no name of
    /// its own to compare against (`EmbedRendition`, ADR-0018 slice 3, Step 2).
    private static func stillSpellsAnEmbed(
        _ text: NSString, at range: NSRange, rendition: EmbedRendition
    ) -> Attachment.Embed? {
        guard range.location >= 0, NSMaxRange(range) <= text.length,
              let embed = Attachment.embed(inLine: text.substring(with: range))
        else { return nil }
        if case .missing(let name) = rendition, embed.target != name { return nil }
        return embed
    }

    /// Whether `range` still spells one to six `#`s followed by exactly one space, read
    /// from the text as it is right now.
    private static func stillSpellsAHeadingMarker(_ text: NSString, at range: NSRange) -> Bool {
        guard range.location >= 0, NSMaxRange(range) <= text.length else { return false }
        let candidate = text.substring(with: range)
        guard candidate.hasSuffix(" ") else { return false }
        let hashes = candidate.dropLast()
        return !hashes.isEmpty && hashes.count <= 6 && hashes.allSatisfy { $0 == "#" }
    }

    /// Whether `range` still spells exactly one or two `*`, read from the text as it is
    /// right now.
    private static func stillSpellsAnEmphasisMarker(_ text: NSString, at range: NSRange) -> Bool {
        guard range.location >= 0, NSMaxRange(range) <= text.length else { return false }
        let candidate = text.substring(with: range)
        return (candidate.count == 1 || candidate.count == 2) && candidate.allSatisfy { $0 == "*" }
    }

    /// Whether `range` still spells exactly `~~` - the emphasis re-check's twin, one
    /// character pair over (ADR-0029 §D1).
    private static func stillSpellsAStrikethroughMarker(_ text: NSString, at range: NSRange) -> Bool {
        guard range.location >= 0, NSMaxRange(range) <= text.length else { return false }
        let candidate = text.substring(with: range)
        return candidate.count == 2 && candidate.allSatisfy { $0 == "~" }
    }

    /// Whether `range` still spells a whole thematic break - `MarkdownBlockParser.isRule`'s
    /// grammar, asked of the live characters rather than restated (ADR-0029 §D1).
    private static func stillSpellsARule(_ text: NSString, at range: NSRange) -> Bool {
        guard range.location >= 0, range.length > 0, NSMaxRange(range) <= text.length else { return false }
        return MarkdownBlockParser.isRule(text.substring(with: range))
    }

    private func offset(of location: NSTextLocation, in manager: NSTextContentManager) -> Int {
        manager.offset(from: manager.documentRange.location, to: location)
    }
}

extension Logger {
    /// One line per fold, at `notice` and not `info`: the default level is what is actually
    /// persisted to the log store, which cost a round of debugging to rediscover. This is a
    /// feature whose failure mode is "nothing happens", so it has to leave a trace.
    static let folding = Logger(subsystem: "it.stefer.pergamenum", category: "folding")
}
