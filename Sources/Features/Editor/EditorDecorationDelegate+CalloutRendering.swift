import AppKit

/// The quote and callout half of `EditorDecorationDelegate`'s fragment choice (ADR-0087 §D7, §D8),
/// and the callout title line's displayed copy. Its own file because the main one sits against its
/// length cap (plan N5, Realignment 8).
///
/// Nothing here is a second callout grammar: the styling pass recorded which line is a title
/// (`.calloutMarker`) and which lines are quote lines (`.blockquote`), keyed by paragraph start and
/// shifted with every other marker (ADR-0091 §D6). A body line is a quote line whose run, walked up
/// through those markers, starts at a title line, the token layer's own rule.
extension EditorDecorationDelegate {
    /// How far a callout's title starts past the quote column: the room its symbol is drawn in.
    var calloutTitleInset: CGFloat { (proseFont.pointSize * 1.6).rounded() }

    /// One quote step at the prose size (`EditorGutter.quoteColumn`'s).
    var quoteStep: CGFloat { EditorGutter.quoteStepInEms * proseFont.pointSize }

    /// A callout title line's displayed copy at a gutter: the marker collapsed by the generic path's
    /// copy, the title in the type colour and `font.prose` semibold, the content hung past the symbol.
    /// Revealed, the `> [!type]` run hangs from the same column, so the title does not move. Nil
    /// without a gutter (a card records no callout marker, R-38) or for a stale marker.
    func calloutTitleParagraph(at range: NSRange, storage: NSTextStorage) -> NSTextParagraph? {
        guard gutter > 0, let marker = marker(of: .calloutMarker, at: range) else { return nil }
        let text = storage.string as NSString
        let markerRange = NSRange(location: range.location + marker.range.location, length: marker.range.length)
        guard let header = Self.calloutHeader(text, at: markerRange) else { return nil }

        let copy = collapsedCopy(at: range, storage: storage)
            ?? NSMutableAttributedString(attributedString: storage.attributedSubstring(from: range))
        let revealed = revealedParagraphs.contains(range.location)
        if !revealed {
            let title = NSRange(location: NSMaxRange(marker.range), length: copy.length - NSMaxRange(marker.range))
            copy.addAttributes(
                [.font: constructStyle.calloutTitleFont, .foregroundColor: constructStyle.accent(of: header.kind)],
                range: title
            )
        }
        hangQuote(
            copy, level: 1, displayedRun: revealed ? text.substring(with: markerRange) : "", inset: calloutTitleInset
        )
        return NSTextParagraph(attributedString: copy)
    }

    /// The fragment of a quote line or a callout title line off the caret, at a gutter: a
    /// `QuoteBarFragment` (with its callout piece when the line is a body line) or a
    /// `CalloutTitleFragment`; nil anywhere else, a card included (it keeps its `▏` glyphs).
    func quoteFragment(for textElement: NSTextElement, at start: Int) -> NSTextLayoutFragment? {
        guard hidesMarkup, gutter > 0, !revealedParagraphs.contains(start),
              let storage = (textElement.textContentManager as? NSTextContentStorage)?.textStorage
        else { return nil }
        let text = storage.string as NSString
        let markers = hiddenMarkers[start] ?? []

        if let marker = markers.first(where: { $0.kind == .blockquote }) {
            let range = NSRange(location: start + marker.range.location, length: marker.range.length)
            guard let level = Self.stillSpellsABlockquoteMarker(text, at: range) else { return nil }
            let fragment = QuoteBarFragment(textElement: textElement, range: textElement.elementRange)
            fragment.level = level
            fragment.callout = calloutPiece(at: start, in: text)
            fragment.style = constructStyle
            fragment.gutter = gutter
            fragment.step = quoteStep
            return fragment
        }

        guard let marker = markers.first(where: { $0.kind == .calloutMarker }),
              let header = Self.calloutHeader(
                  text, at: NSRange(location: start + marker.range.location, length: marker.range.length)
              )
        else { return nil }
        let fragment = CalloutTitleFragment(textElement: textElement, range: textElement.elementRange)
        fragment.kind = header.kind
        fragment.isFolded = header.fold == .fixed || !foldsCallouts
            ? nil : CalloutFold.isFolded(header.fold, toggled: toggledCallouts.contains(start))
        fragment.calloutOffset = start
        fragment.hasTitle = Self.calloutHasTitle(text, from: start + marker.range.location)
        fragment.hasBody = isQuoteLine(after: start, in: text)
        fragment.style = constructStyle
        fragment.gutter = gutter
        fragment.step = quoteStep
        fragment.titleInset = calloutTitleInset
        return fragment
    }

    /// The callout a quote line at `start` is a body line of, and where in the card it sits; nil for
    /// a line of a plain quote.
    func calloutPiece(at start: Int, in text: NSString) -> (kind: CalloutKind, piece: CalloutPiece)? {
        guard start > 0, let head = calloutTitle(above: start, in: text),
              let title = (hiddenMarkers[head] ?? []).first(where: { $0.kind == .calloutMarker }),
              let kind = Self.calloutHeader(
                  text, at: NSRange(location: head + title.range.location, length: title.range.length)
              )?.kind
        else { return nil }
        let isFirst = text.paragraphRange(for: NSRange(location: start - 1, length: 0)).location == head
        let isLast = !isQuoteLine(after: start, in: text)
        let piece: CalloutPiece = switch (isFirst, isLast) {
        case (true, true): .only
        case (true, false): .first
        case (false, true): .last
        case (false, false): .middle
        }
        return (kind, piece)
    }

    /// The paragraph start of the title line heading the run of quote lines `start` is in, or nil for
    /// a plain quote's line. Walked up through the markers, stopping at a line already walked: every
    /// line walked keeps its answer in `calloutRunHeads` until the markers change, so a run of N quote
    /// lines laid out in one pass costs N steps, not N squared.
    func calloutTitle(above start: Int, in text: NSString) -> Int? {
        var walked = [start]
        var cursor = start
        var head: Int?
        while cursor > 0 {
            let previous = text.paragraphRange(for: NSRange(location: cursor - 1, length: 0)).location
            if let known = calloutRunHeads[previous] {
                head = known
                break
            }
            let markers = hiddenMarkers[previous] ?? []
            if markers.contains(where: { $0.kind == .calloutMarker }) {
                head = previous
                break
            }
            guard markers.contains(where: { $0.kind == .blockquote }) else { break }
            walked.append(previous)
            cursor = previous
        }
        for line in walked { calloutRunHeads[line] = .some(head) }
        return head
    }

    /// The header a `.calloutMarker` range still spells, or nil when it went stale.
    static func calloutHeader(_ text: NSString, at range: NSRange) -> Callout.Header? {
        guard stillSpellsAConstructMarker(.calloutMarker, text, at: range) else { return nil }
        return Callout.header(inLine: text.substring(with: range))
    }

    /// Whether the title line whose marker starts at `markerStart` writes a title after it.
    static func calloutHasTitle(_ text: NSString, from markerStart: Int) -> Bool {
        let line = text.paragraphRange(for: NSRange(location: markerStart, length: 0))
        let rest = text.substring(with: NSRange(location: markerStart, length: NSMaxRange(line) - markerStart))
        return Callout.header(inLine: rest.trimmingCharacters(in: .newlines))?.title != nil
    }

    /// Whether the paragraph after the one at `start` is a quote line (`.blockquote` recorded on it).
    func isQuoteLine(after start: Int, in text: NSString) -> Bool {
        let next = NSMaxRange(text.paragraphRange(for: NSRange(location: start, length: 0)))
        return next < text.length && (hiddenMarkers[next] ?? []).contains { $0.kind == .blockquote }
    }
}
