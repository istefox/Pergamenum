import AppKit

/// The line skeleton `applyTables` and `applyViewBlocks` both run (ADR-0071 §D8): the anchor
/// paragraph's `HiddenMarker`, and the hidden line starts from the anchor paragraph's `end` to
/// the end of the recognised range. Each construct keeps what differs - the grid store keyed
/// by offset, the host store keyed by ordinal, the change check and the refresh.
struct HiddenBlockLines {
    /// One hidden line after the anchor paragraph. `contentsEnd` is there because a view block
    /// reads its body off these lines, and the closing fence is the one whose contents end where
    /// the recognised range does.
    struct Line: Equatable {
        let start: Int
        let contentsEnd: Int
    }

    /// Over `0 ..< contentsEnd - start` of the anchor paragraph, or nil when the paragraph is
    /// empty (`contentsEnd <= start`) - the caller then skips the construct.
    let marker: HiddenMarker?
    /// The paragraphs from the anchor paragraph's `end` to `NSMaxRange(range)`, in order.
    let lines: [Line]

    /// The hidden line starts, in order.
    var starts: [Int] { lines.map(\.start) }

    init(text: NSString, anchor: Int, range: NSRange, kind: HiddenMarker.Kind) {
        var start = 0, end = 0, contentsEnd = 0
        text.getParagraphStart(
            &start, end: &end, contentsEnd: &contentsEnd,
            for: NSRange(location: anchor, length: 0)
        )
        // Anchored at the anchor paragraph's own start and covering its markup alone, the
        // convention `.list` and `.blockquote` already use - never the whole run, which spans
        // paragraphs the delegate is asked about one at a time.
        marker = contentsEnd > start
            ? HiddenMarker(range: NSRange(location: 0, length: contentsEnd - start), kind: kind)
            : nil

        var walked: [Line] = []
        var cursor = end
        while cursor < NSMaxRange(range) {
            var lineStart = 0, lineEnd = 0, lineContentsEnd = 0
            text.getParagraphStart(
                &lineStart, end: &lineEnd, contentsEnd: &lineContentsEnd,
                for: NSRange(location: cursor, length: 0)
            )
            walked.append(Line(start: cursor, contentsEnd: lineContentsEnd))
            guard lineEnd > cursor else { break }
            cursor = lineEnd
        }
        lines = walked
    }
}

/// The one rule for a caret inside a line that has just left the layout: it goes to the target
/// its owner names (ADR-0071 §D8). Folding, tables and view blocks differ only in the owner.
enum CaretRescue {
    /// Where the caret goes, or nil when it stays. Judged on `selection.location` alone, as the
    /// three copies it replaces do: the paragraph the selection starts in is the one tested.
    /// `owner` receives that paragraph's start.
    static func target(
        for selection: NSRange, hidden: Set<Int>, in text: NSString, owner: (Int) -> Int?
    ) -> Int? {
        guard !hidden.isEmpty else { return nil }
        let caret = selection.location
        guard caret <= text.length else { return nil }
        let line = text.paragraphRange(for: NSRange(location: caret, length: 0)).location
        guard hidden.contains(line) else { return nil }
        return owner(line)
    }

    /// `setSelectedRange` then `scrollRangeToVisible`, on an empty range at `offset`; nothing
    /// for nil.
    @MainActor
    static func place(_ offset: Int?, in textView: NSTextView) {
        guard let offset else { return }
        textView.setSelectedRange(NSRange(location: offset, length: 0))
        textView.scrollRangeToVisible(NSRange(location: offset, length: 0))
    }
}
