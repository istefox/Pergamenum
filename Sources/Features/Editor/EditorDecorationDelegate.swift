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
    }

    let range: NSRange
    let kind: Kind
}

final class EditorDecorationDelegate: NSObject, NSTextContentStorageDelegate,
                                      NSTextLayoutManagerDelegate, @unchecked Sendable {
    /// The UTF-16 offset at which each hidden line begins. A set, because this is asked
    /// once per paragraph on every layout pass.
    nonisolated(unsafe) private var hiddenLineOffsets: Set<Int> = []
    /// Folded heading line offset to the number of lines it is hiding, which is what the
    /// badge says.
    nonisolated(unsafe) private var foldedHeadings: [Int: Int] = [:]
    nonisolated(unsafe) var badgeColor: NSColor = .secondaryLabelColor
    nonisolated(unsafe) var badgeBackground: NSColor = .quaternaryLabelColor
    /// The colour a drawn embed's resize handle is painted in (ADR-0019 §D5), pushed in
    /// from a token the same way `badgeColor` above is and handed on to `EmbedAttachment`.
    nonisolated(unsafe) var handleColor: NSColor = .secondaryLabelColor
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
    nonisolated(unsafe) private var hiddenMarkers: [Int: [HiddenMarker]] = [:]
    /// Paragraphs currently drawn in full, because the caret's paragraph, a non-empty
    /// selection, an active IME composition or the find bar's current match touches them
    /// (ADR-0018 §D2). Keyed the same way as `headingMarkers`.
    nonisolated(unsafe) private var revealedParagraphs: Set<Int> = []
    /// The vault's `hidesMarkup` setting. `false` makes
    /// `textContentStorage(_:textParagraphWith:)` a no-op, i.e. today's behaviour - hiding
    /// markup is fully reversible with a toggle rather than a revert.
    nonisolated(unsafe) var hidesMarkup = false
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

    func textContentManager(
        _ textContentManager: NSTextContentManager,
        shouldEnumerate textElement: NSTextElement,
        options: NSTextContentManager.EnumerationOptions
    ) -> Bool {
        guard !hiddenLineOffsets.isEmpty, let range = textElement.elementRange else { return true }
        return !hiddenLineOffsets.contains(offset(of: range.location, in: textContentManager))
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

        guard let hidden = foldedHeadings[start] else { return standard }
        let fragment = FoldedHeadingFragment(textElement: textElement, range: textElement.elementRange)
        fragment.hiddenLines = hidden
        // Carried so a click on the badge can say which section it means (PG-021).
        fragment.headingOffset = start
        fragment.badgeColor = badgeColor
        fragment.badgeBackground = badgeBackground
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

        guard !revealedParagraphs.contains(range.location),
              let markers = hiddenMarkers[range.location], !markers.isEmpty
        else { return nil }

        let survivors = Self.survivors(among: markers, of: range, in: storage.string as NSString)
        guard !survivors.isEmpty else { return nil }

        let copy = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: range))
        for marker in survivors {
            copy.addAttribute(.font, value: Self.collapsedFont, range: marker.range)
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
    /// above and the list branch below, which returns early and would otherwise leave a
    /// bold list item's `**` on screen (ADR-0028, the SPEC's coexistence case).
    private static func survivors(
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

    /// The list branch of the substitution above: draws a list item's opening run the way
    /// a reader expects it - the unordered marker character replaced by
    /// `ListMarkerRendering.glyph(for:)`, an ordered marker's digits left exactly as the
    /// file spells them (ADR-0028 §D4), the indentation it hangs at collapsed into
    /// `collapsedFont` so the paragraph style is the only thing indenting the line, and
    /// `ListMarkerRendering.paragraphStyle(level:font:)` applied over the whole displayed
    /// paragraph.
    ///
    /// One character out, one character in, never more: the displayed paragraph keeps its
    /// stored length, which is `NSTextContentManager.h:120`'s constraint and the reason a
    /// bullet can only ever *replace* a marker rather than be inserted before it.
    ///
    /// Nil - leaving the raw source on screen exactly as today - whenever there is nothing
    /// to draw: no list marker at this offset, the paragraph revealed because the caret is
    /// in it (R-03), or the marker gone stale against the real characters since the last
    /// styling pass.
    private func listParagraph(at range: NSRange, storage: NSTextStorage) -> NSTextParagraph? {
        guard !revealedParagraphs.contains(range.location) else { return nil }
        let markers = hiddenMarkers[range.location] ?? []
        guard let marker = markers.first(where: { $0.kind == .list }),
              NSMaxRange(marker.range) <= range.length
        else { return nil }

        let text = storage.string as NSString
        let markerRange = NSRange(
            location: range.location + marker.range.location, length: marker.range.length
        )
        guard let item = Self.stillSpellsAListMarker(text, at: markerRange) else { return nil }

        let copy = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: range))
        // A substitution, not an insertion: one character out, one in, the paragraph's own
        // length unmoved - `NSTextContentManager.h:120`'s constraint, the same one the
        // embed branch above keeps. Nil for an ordered marker, whose own digits are the
        // rendered ordinal and are therefore left exactly as the file spells them
        // (ADR-0028 §D4).
        if let glyph = ListMarkerRendering.glyph(for: item.kind) {
            copy.replaceCharacters(
                in: NSRange(location: marker.range.location + item.indent, length: 1),
                with: String(glyph)
            )
        }
        if item.indent > 0 {
            copy.addAttribute(
                .font, value: Self.collapsedFont,
                range: NSRange(location: marker.range.location, length: item.indent)
            )
        }
        // The paragraph's other markers, collapsed exactly as the generic path below would
        // have collapsed them: this branch returns early, and a list item whose text is
        // bold has to render both its bullet and its hidden `**` in the one paragraph the
        // hook is allowed to hand back.
        for other in Self.survivors(among: markers.filter { $0.kind != .list }, of: range, in: text) {
            copy.addAttribute(.font, value: Self.collapsedFont, range: other.range)
        }
        copy.addAttribute(
            .paragraphStyle,
            value: ListMarkerRendering.paragraphStyle(
                level: item.level, font: Self.bodyFont(of: copy, after: marker.range)
            ),
            // The whole displayed paragraph, not only the marker: an item that wrapped
            // would otherwise lose its indentation on its second line (R-05).
            range: NSRange(location: 0, length: copy.length)
        )
        return NSTextParagraph(attributedString: copy)
    }

    /// The font a list item's own text is drawn in, read from the character just past its
    /// marker - the one place in the paragraph guaranteed to be neither indentation nor
    /// marker, and so to carry the body font `ListMarkerRendering.paragraphStyle` steps in
    /// proportion to. The system font when the storage carries no font at all, which is
    /// what an offscreen harness building a paragraph out of a bare string has.
    private static func bodyFont(of paragraph: NSAttributedString, after marker: NSRange) -> NSFont {
        let probe = NSMaxRange(marker)
        guard probe < paragraph.length,
              let font = paragraph.attribute(.font, at: probe, effectiveRange: nil) as? NSFont
        else { return .systemFont(ofSize: NSFont.systemFontSize) }
        return font
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

    /// Whether `range` still spells a list item's whole opening run - an optional
    /// indentation of spaces and tabs, then `- `/`* `/`+ ` or `12. `/`12) `, and never a
    /// checkbox - read from the text as it is right now, with the three things drawing it
    /// needs: how much of that run is indentation, which kind of marker closes it, and how
    /// deep it therefore is.
    ///
    /// Returns a value rather than a `Bool`, the way `stillSpellsAnEmbed` above does and
    /// unlike the heading and emphasis re-checks: those two say *whether* to collapse a
    /// range, this one also says *what* to draw over it. The level is derived here, from
    /// the characters, and never carried on the marker - `HiddenMarker.Kind.list` has no
    /// level field precisely because a table entry can go stale between a styling pass and
    /// a layout pass, and an indentation read one pass late would indent the wrong item.
    ///
    /// The rule is `listMarkerSpan`'s own, restated (a space is one column, a tab four,
    /// one level per two columns, capped at six): that function's grammar is private to
    /// `MarkdownStyler.swift` and this re-read has to happen against the live characters
    /// anyway, which is what the whole `stillSpells` family exists for. The checkbox
    /// refusal is restated with it for the same reason it is restated there - `- [ ] fai`
    /// is a task line, and its rendering is not this one (ADR-0028 §D2, R-06).
    private static func stillSpellsAListMarker(_ text: NSString, at range: NSRange) -> ListItem? {
        guard range.location >= 0, range.length > 0, NSMaxRange(range) <= text.length else { return nil }
        let candidate = text.substring(with: range)
        let indent = candidate.prefix(while: { $0 == " " || $0 == "\t" })
        let marker = candidate.dropFirst(indent.count)
        guard let first = marker.first else { return nil }

        let kind: MarkdownStyler.Span.ListKind
        if first == "-" || first == "*" || first == "+" {
            // Exactly the marker and its one trailing space, nothing else: a range that
            // covers more than that is not the run the styling pass recorded.
            guard marker.count == 2, marker.last == " " else { return nil }
            if first != "+", Self.checkboxFollows(range, in: text) { return nil }
            kind = .bullet
        } else {
            let digits = marker.prefix(while: { $0.isASCII && $0.isNumber })
            let afterDigits = marker.dropFirst(digits.count)
            guard !digits.isEmpty, afterDigits.count == 2,
                  let delimiter = afterDigits.first, delimiter == "." || delimiter == ")",
                  afterDigits.last == " "
            else { return nil }
            kind = .ordered
        }

        let columns = indent.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
        return ListItem(indent: indent.count, kind: kind, level: min(1 + columns / 2, 6))
    }

    /// What a live re-read of a list marker's run says about drawing it: how many of its
    /// characters are indentation to collapse, which kind of marker closes it, and how deep
    /// the item sits. A value rather than the three-part tuple it replaced, because all
    /// three are read at one call site and `indent` and `level` are both plain `Int`s that
    /// a tuple would let a caller swap without a word from the compiler.
    private struct ListItem {
        /// In UTF-16 units, the same space `HiddenMarker.range` is measured in - and equal
        /// to the character count, since only spaces and tabs are counted into it.
        let indent: Int
        let kind: MarkdownStyler.Span.ListKind
        let level: Int
    }

    /// Whether the three characters after a `- `/`* ` marker spell a checkbox's `[ ]`,
    /// which is what makes the line a task rather than a list item. Read past the marker's
    /// own range on purpose: the range is the marker, and `- ` is a marker either way -
    /// only what follows it tells the two apart.
    private static func checkboxFollows(_ marker: NSRange, in text: NSString) -> Bool {
        let start = NSMaxRange(marker)
        guard start + 3 <= text.length else { return false }
        // By character and not by UTF-16 unit: three units are not always three characters,
        // and a range that cuts a surrogate pair in half must answer «no checkbox» rather
        // than trap on the subscript.
        let brackets = Array(text.substring(with: NSRange(location: start, length: 3)))
        return brackets.count == 3 && brackets[0] == "[" && brackets[2] == "]"
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
