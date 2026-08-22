import AppKit
import OSLog

/// Everything the editor draws that is not the note's own characters: folded sections kept
/// out of the layout, the headings that say how much they are hiding, and the notes a
/// transclusion shows underneath its source line.
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
/// delegate; two features, kept as two separate inputs so neither can quietly depend on the
/// other's state.
/// One hidden delimiter, at its range relative to its paragraph's start, and what kind
/// it is - which decides how `EditorDecorationDelegate` re-validates it before drawing.
struct HiddenMarker: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case heading, emphasis
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
    /// A transcluded note, by the UTF-16 offset of the line that names it. Measured and
    /// styled on the main actor and handed over as a value, because this object cannot be
    /// `@MainActor` - Swift 6 refuses both conformances if it is.
    nonisolated(unsafe) private var renditions: [Int: TranscludedRendition] = [:]
    /// A paragraph's hidden markers - a heading's `#`s and the space after them, or an
    /// emphasis run's opening and closing `*`/`**` - each relative to its own paragraph's
    /// start, not to the document (ADR-0018 §D1). Filled by `applyStyling`'s walk over
    /// `MarkdownStyler.spans(in:)`, the same one that already knows where every marker
    /// is. One table for both kinds rather than two: the two features this object already
    /// carries (folding, transclusion) are kept as separate inputs, but a heading marker
    /// and an emphasis marker are the same feature - hiding - with two sources.
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
    /// How many markers the last styling pass registered, heading and emphasis alike -
    /// what a test reads to confirm `applyStyling` populated the table, the same way
    /// `isFolding` reads `foldedHeadings` for the folding half of this file.
    var hiddenMarkerCount: Int { hiddenMarkers.values.reduce(0) { $0 + $1.count } }

    func apply(renditions: [Int: TranscludedRendition]) {
        self.renditions = renditions
        Logger.folding.notice("transclusioni: \(renditions.count, privacy: .public) rese")
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
        guard hidesMarkup, !revealedParagraphs.contains(range.location),
              let markers = hiddenMarkers[range.location], !markers.isEmpty,
              let storage = textContentStorage.textStorage
        else { return nil }

        // Re-read from the real characters rather than trust the table: it is filled by
        // the last styling pass, this is a later layout pass, and the two can go stale
        // between each other. Silently collapsing prose would be the failure mode here,
        // not a crash. Each marker is checked on its own, so one gone stale does not
        // cancel the others in the same paragraph.
        let survivors = markers.filter { marker in
            NSMaxRange(marker.range) <= range.length &&
                Self.stillSpells(
                    marker.kind,
                    storage.string as NSString,
                    at: NSRange(location: range.location + marker.range.location, length: marker.range.length)
                )
        }
        guard !survivors.isEmpty else { return nil }

        let copy = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: range))
        for marker in survivors {
            copy.addAttribute(.font, value: Self.collapsedFont, range: marker.range)
        }
        return NSTextParagraph(attributedString: copy)
    }

    private static func stillSpells(_ kind: HiddenMarker.Kind, _ text: NSString, at range: NSRange) -> Bool {
        switch kind {
        case .heading: stillSpellsAHeadingMarker(text, at: range)
        case .emphasis: stillSpellsAnEmphasisMarker(text, at: range)
        }
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
