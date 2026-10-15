import AppKit

/// ADR-0087 §D10's half of `EditorDecorationDelegate`: a resolved transclusion's source line is
/// its caption. Off the caret its characters are collapsed and `TranscludedLineFragment` draws
/// `da «Nota» › Sezione` in that row; with the caret on it, the line is the raw `![[…]]` as before.
/// Its own file because the main one sits against its length cap (plan N5, Realignment 8).
extension EditorDecorationDelegate {
    /// The displayed copy of a transcluded line off the caret: every character but the
    /// terminator at `collapsedFont`, and a line at least as tall as the caption drawn in it.
    /// Nil for a line with no rendition (an unresolved transclusion is drawn as before) or a
    /// revealed one.
    func transclusionParagraph(at range: NSRange, storage: NSTextStorage) -> NSTextParagraph? {
        guard renditions[range.location] != nil, !revealedParagraphs.contains(range.location) else { return nil }
        let line = (storage.string as NSString).substring(with: range)
        let length = (line.trimmingCharacters(in: .newlines) as NSString).length
        guard length > 0 else { return nil }
        let copy = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: range))
        copy.addAttribute(.font, value: Self.collapsedFont, range: NSRange(location: 0, length: length))
        let style = NSMutableParagraphStyle()
        if let current = copy.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle {
            style.setParagraphStyle(current)
        }
        style.minimumLineHeight = max(style.minimumLineHeight, TranscludedRendition.captionHeight)
        copy.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: copy.length))
        return NSTextParagraph(attributedString: copy)
    }

    /// The fragment a transcluded line is drawn by, told whether its row shows the caption: the
    /// same reveal test `transclusionParagraph(at:storage:)` collapses the line by.
    func transclusionFragment(
        for textElement: NSTextElement, rendition: TranscludedRendition, at start: Int
    ) -> TranscludedLineFragment {
        let fragment = TranscludedLineFragment(textElement: textElement, range: textElement.elementRange)
        fragment.rendition = rendition
        fragment.showsCaption = hidesMarkup && !revealedParagraphs.contains(start)
        return fragment
    }
}
