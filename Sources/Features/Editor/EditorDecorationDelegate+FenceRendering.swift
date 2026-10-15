import AppKit

/// The fence-chrome half of `EditorDecorationDelegate` (ADR-0087 §D6): which fence line is drawn by a
/// `CodeFenceFragment`, and in which role. The line's characters are collapsed by the generic path;
/// this only chooses the fragment, the rule's shape (`HorizontalRuleFragment`).
extension EditorDecorationDelegate {
    /// A `CodeFenceFragment` for the opening or closing line of a closed fence, off the caret, or nil.
    ///
    /// Re-validated against the element's own characters through `CodeFence.marks`, as the rule is:
    /// the marker table is from the last styling pass and this is a later layout pass. The header's
    /// language is read off the line itself, and its line count off the lines below it up to the
    /// next fence mark, which is where `CodeFence.regions` closes it - the marker carries neither.
    func fenceFragment(for textElement: NSTextElement, at start: Int) -> CodeFenceFragment? {
        let fenceKinds: Set<HiddenMarker.Kind> = [.fenceOpening, .fenceClosing]
        guard hidesMarkup, !revealedParagraphs.contains(start),
              let kind = (hiddenMarkers[start] ?? []).first(where: { fenceKinds.contains($0.kind) })?.kind,
              let paragraph = textElement as? NSTextParagraph
        else { return nil }
        let line = paragraph.attributedString.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard CodeFence.marks(line) else { return nil }

        let role: CodeFenceFragment.Role
        if kind == .fenceClosing {
            role = .closing
        } else {
            guard let storage = (textElement.textContentManager as? NSTextContentStorage)?.textStorage,
                  let lineCount = Self.fenceBodyLineCount(after: start, in: storage.string as NSString)
            else { return nil }
            role = .header(language: CodeFence.language(declaredBy: line), lineCount: lineCount)
        }
        let fragment = CodeFenceFragment(textElement: textElement, range: textElement.elementRange)
        fragment.role = role
        fragment.style = constructStyle
        return fragment
    }

    /// How many lines lie between the opening fence line at `start` and the next line that marks a
    /// fence, counted by the line breaks `FenceChrome` counts; nil when no line closes it.
    static func fenceBodyLineCount(after start: Int, in text: NSString) -> Int? {
        let opening = text.paragraphRange(for: NSRange(location: start, length: 0))
        let bodyStart = NSMaxRange(opening)
        var cursor = bodyStart
        while cursor < text.length {
            let line = text.paragraphRange(for: NSRange(location: cursor, length: 0))
            let trimmed = text.substring(with: line).trimmingCharacters(in: .whitespacesAndNewlines)
            if CodeFence.marks(trimmed) {
                let body = text.substring(with: NSRange(location: bodyStart, length: line.location - bodyStart))
                return body.filter(LineBreak.isTerminator).count
            }
            cursor = NSMaxRange(line)
        }
        return nil
    }
}
