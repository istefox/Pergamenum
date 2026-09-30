import AppKit
@testable import Pergamenum

/// Shared layout and substitution helpers for the MarkupHiding* suites (moved out of
/// `MarkupHidingTests.swift` when it was split; PG-144 Task 1).
enum MarkupHidingFixture {
    struct Frame {
        let offset: Int
        let frame: CGRect
    }

    @MainActor
    static func frames(
        text: String,
        markers: [Int: [HiddenMarker]],
        hidesMarkup: Bool,
        revealed: Set<Int> = []
    ) -> (frames: [Frame], length: Int) {
        let content = NSTextContentStorage()
        let layout = NSTextLayoutManager()
        content.addTextLayoutManager(layout)
        let container = NSTextContainer(size: CGSize(width: 400, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layout.textContainer = container

        let delegate = EditorDecorationDelegate()
        delegate.apply(hiddenMarkers: markers, hidingMarkup: hidesMarkup)
        _ = delegate.apply(revealedParagraphs: revealed)
        content.delegate = delegate

        content.textStorage?.setAttributedString(
            NSAttributedString(
                string: text,
                attributes: [.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)]
            )
        )
        layout.ensureLayout(for: layout.documentRange)

        var collected: [Frame] = []
        layout.enumerateTextLayoutFragments(
            from: layout.documentRange.location, options: [.ensuresLayout]
        ) { fragment in
            let offset = content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location)
            collected.append(Frame(offset: offset, frame: fragment.layoutFragmentFrame))
            return true
        }
        // The length is the whole point: the file must not gain or lose a character.
        return (collected, content.textStorage?.length ?? -1)
    }

    /// Drives the hook by hand over the first paragraph of `note`, the way AppKit itself
    /// would when laying it out - for the tests that check the hook's return value directly
    /// rather than a measured frame.
    @MainActor
    static func substitutedParagraph(
        _ delegate: EditorDecorationDelegate, note: String, at location: Int = 0
    ) -> NSTextParagraph? {
        let storage = NSTextContentStorage()
        storage.textStorage?.setAttributedString(NSAttributedString(string: note))
        let range = (note as NSString).paragraphRange(for: NSRange(location: location, length: 0))
        return delegate.textContentStorage(storage, textParagraphWith: range)
    }

    /// `substitutedParagraph` above with the delegate built in - the whole configuration a
    /// list case needs is the marker table, the setting and the reveal set, so a test that
    /// spells out three lines of setup per assertion is a test whose fixture is harder to read
    /// than the rule it pins (ADR-0028; plan `2026-08-29-wysiwyg-markdown-in-workspace`,
    /// Task 3).
    @MainActor
    static func displayedParagraph(
        _ note: String,
        markers: [HiddenMarker],
        at location: Int = 0,
        hidesMarkup: Bool = true,
        revealed: Set<Int> = [],
        spans: [Int: [NSRange]] = [:],
        revealsInlineSpans: Bool = false
    ) -> NSTextParagraph? {
        let delegate = EditorDecorationDelegate()
        delegate.apply(hiddenMarkers: [location: markers], hidingMarkup: hidesMarkup)
        _ = delegate.apply(revealedParagraphs: revealed)
        _ = delegate.apply(revealedSpans: spans)
        delegate.apply(revealsInlineSpans: revealsInlineSpans)
        return substitutedParagraph(delegate, note: note, at: location)
    }

    /// The length of `note`'s paragraph starting at `location` (the first paragraph by
    /// default), the number a substitution of it must return unchanged.
    static func firstParagraphLength(of note: String, at location: Int = 0) -> Int {
        (note as NSString).paragraphRange(for: NSRange(location: location, length: 0)).length
    }
}
