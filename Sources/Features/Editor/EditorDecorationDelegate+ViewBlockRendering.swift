import AppKit
import SwiftUI

/// The view-block half of `EditorDecorationDelegate`'s re-read machinery (ADR-0033 §D1/§D6/§D7;
/// plan `2026-09-06-pg-099-views-board-renderer-orphaned-by`, Task 5) - split out on its own
/// the way `+TableRendering.swift`/`+QuoteRendering.swift`/`+ListRendering.swift`/
/// `+CheckboxRendering.swift` already are.
///
/// This file's job, once real, is `EditorDecorationDelegate+TableRendering.swift`'s own: the
/// static "is a closed, still-valid fence really here" check that both the drawing pass and a
/// later commit-style read can share without re-implementing the rule twice.
extension EditorDecorationDelegate {
    /// The view-block branch of the substitution in `textContentStorage(_:textParagraphWith:)`:
    /// swaps the opening fence line's first character for `\u{FFFC}` carrying a
    /// `ViewBlockAttachment` wrapping `viewBlockHosts[range.location]`, and collapses the rest
    /// of that line into `collapsedFont` - one character out, one in, the paragraph's own
    /// length unmoved (`NSTextContentManager.h:120`), `tableParagraph(at:storage:)`'s own
    /// arithmetic and `embedParagraph`'s before it.
    ///
    /// Nil whenever there is nothing to draw at all: the hatch is closed (`hidesMarkup` off,
    /// §D12), no `.viewBlock` marker at this offset, no host vended for it yet, or the fence
    /// no longer closed at this offset (§D6). The raw fenced source stays on screen in every
    /// one of those cases, matching every other branch of the substitution chain when it has
    /// nothing to draw (`embedParagraph` with no rendition, `tableParagraph` with a stale
    /// marker).
    ///
    /// **A closed fence whose body fails to parse still draws** (ADR §D7 follow-up, reversing
    /// R-08's original "no attachment, no error UI"): the host vended for it carries the raw
    /// source, and `RenderedViewBlock` re-parses that source itself and renders its own
    /// `failed(_:)` error card - the same one already shown on the transclusion, export and
    /// Viste-pane surfaces. This function does not distinguish the two cases; it only asks
    /// whether the fence is still closed, and the host already knows which card to draw.
    ///
    /// **It does not honour `revealedParagraphs`**, for `tableParagraph`'s own reason and one
    /// of its own: a drawn block is not a delimiter that reveals under the caret, and this
    /// construct's reveal is keyed on the fence's whole source range against the live
    /// selection rather than per paragraph (ADR §D4) - so it is decided one layer up, in
    /// `applyViewBlocks`, which simply registers nothing for a revealed fence.
    func viewBlockParagraph(at range: NSRange, storage: NSTextStorage) -> NSTextParagraph? {
        guard hidesMarkup else { return nil }
        let markers = hiddenMarkers[range.location] ?? []
        guard let marker = markers.first(where: { $0.kind == .viewBlock }),
              marker.range.length > 0,
              NSMaxRange(marker.range) <= range.length,
              let host = viewBlockHosts[range.location]
        else {
            return nil
        }

        // The re-read, in this branch's own currency: not "is this range still spelled the
        // same" but "is the fence still closed starting here" - the whole shape, because a
        // view block's meaning spans several paragraphs (`stillSpells` answers `false` for
        // `.viewBlock` precisely so this branch owns the question, exactly as it does for
        // `.table`). A closed-but-unparseable fence still answers non-nil here (ADR §D7
        // follow-up): the host already carries the raw source, and `RenderedViewBlock` draws
        // its own error card from it - this guard only re-checks the fence is still closed.
        let text = storage.string as NSString
        guard Self.viewBlockRun(in: text, atParagraphStart: range.location) != nil else {
            return nil
        }

        let copy = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: range))
        let attachmentRange = NSRange(location: marker.range.location, length: 1)
        let restRange = NSRange(location: attachmentRange.location + 1, length: marker.range.length - 1)

        let attachment = ViewBlockAttachment()
        // A conditional cast rather than a stored `NSHostingView`: this object is handed a
        // plain `NSView` (`apply(viewBlockHosts:)`) because that is all it needs to know
        // about a host it never builds. Everything the app registers comes from
        // `ViewBlockHostStore` and casts through; anything else draws an empty attachment
        // rather than refusing to substitute, which keeps the length arithmetic above the
        // one thing this branch is actually responsible for.
        attachment.hostView = host as? NSHostingView<AnyView>
        copy.replaceCharacters(in: attachmentRange, with: "\u{FFFC}")
        copy.addAttribute(.attachment, value: attachment, range: attachmentRange)
        if restRange.length > 0 {
            copy.addAttribute(.font, value: Self.collapsedFont, range: restRange)
        }
        return NSTextParagraph(attributedString: copy)
    }

    /// The view block whose opening fence starts exactly at `offset`, read from the
    /// characters as they are right now, with the UTF-16 range of its whole source (opening
    /// backticks through closing ones, inclusive) beside it.
    ///
    /// `tableRun(in:atParagraphStart:)`'s own shape (`EditorDecorationDelegate+TableRendering.swift`):
    /// `static`, in UTF-16, and taking an `NSString` rather than reading `self` - the drawing
    /// side is on no actor at all and a future commit-style caller would be `@MainActor`, so
    /// nothing here may touch this object's state, and both sides already hold the text as an
    /// `NSString`.
    ///
    /// Nil whenever there is nothing left to draw at all: the fence is not closed at this
    /// offset any more (ADR §D6, C5 - `CodeFence.regions(in:)`'s own precondition, re-read
    /// here rather than trusted from the last styling pass). A **closed** fence always answers
    /// non-nil, whether or not its body parses through `ViewBlock.parse` - `block` is nil when
    /// it doesn't (ADR §D7 follow-up: the caller still gets a range to hide the body/closing
    /// lines behind, and the host it vends renders `RenderedViewBlock`'s own error card from
    /// the raw source, rather than the fence silently reverting to plain text).
    ///
    /// The walk stops at the first line that marks a fence, which is `CodeFence.regions`'
    /// own alternating grammar read one block at a time - so the two agree about where a
    /// block ends without this having to run over the whole note, however long it is
    /// (`tableRun`'s own reason for walking rather than parsing from `offset` to the end).
    static func viewBlockRun(
        in text: NSString, atParagraphStart offset: Int
    ) -> (block: ViewBlock?, range: NSRange)? {
        guard offset >= 0, offset < text.length else { return nil }

        // The opening line, which must start exactly here - a fence moved by an edit above
        // it no longer opens where the last styling pass recorded - and must declare this
        // language. `CodeFence.language(declaredBy:)` rather than a literal prefix test, so
        // the rule that `MarkdownStyler.viewBlockRuns` filtered on is the same one here.
        var start = 0, end = 0, contentsEnd = 0
        text.getParagraphStart(
            &start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: offset, length: 0)
        )
        guard start == offset else { return nil }
        let opening = text
            .substring(with: NSRange(location: start, length: contentsEnd - start))
            .trimmingCharacters(in: .whitespaces)
        guard CodeFence.language(declaredBy: opening) == ViewBlock.language else { return nil }

        var body: [String] = []
        var cursor = end
        while cursor < text.length {
            var lineStart = 0, lineEnd = 0, lineContentsEnd = 0
            text.getParagraphStart(
                &lineStart, end: &lineEnd, contentsEnd: &lineContentsEnd,
                for: NSRange(location: cursor, length: 0)
            )
            let line = text.substring(with: NSRange(location: lineStart, length: lineContentsEnd - lineStart))
            if CodeFence.marks(line.trimmingCharacters(in: .whitespaces)) {
                // Closed (ADR §D6) is the only precondition this optional answers any more -
                // a parse failure (ADR §D7 follow-up) still returns the range, with `block`
                // nil, so the caller can still hide the body/closing lines and vend a host
                // that draws the error card instead of leaving raw source on screen.
                let range = NSRange(location: offset, length: lineContentsEnd - offset)
                let block = try? ViewBlock.parse(body.joined(separator: "\n"))
                return (block, range)
                // Through the closing fence line's own last character, its trailing newline
                // excluded - `tableRun`'s own convention, and what `applyViewBlocks` walks
                // to collect the lines that leave the layout.
            }
            body.append(line)
            guard lineEnd > cursor else { break }
            cursor = lineEnd
        }
        // No closing fence line at all: ADR §D6's precondition failing, which is the state
        // every note is in for as long as it takes to type the second row of backticks.
        return nil
    }
}
