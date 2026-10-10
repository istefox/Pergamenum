import AppKit

// ADR-0083 §D3 (PG-386, N3 session B). Its own file because `NoteTextView.Coordinator`'s body is at
// the length the linter allows: `textViewDidChangeSelection` calls this in one line.

extension NoteTextView.Coordinator {
    /// What the links need after an edit has been styled, in one line for the Coordinator: the
    /// preview closes, and the caret's link is reported again. `textViewDidChangeSelection` may
    /// run before `applyStyling` has rewritten `.editorLink`, so it can report the link as it was
    /// before the keystroke; `claimCaretLink` keeps the second report from repeating the first.
    func linksDidChange(in textView: NSTextView) {
        if parent.links.preview != nil { linkPreview.textChanged() }
        reportLinkAtCaret(in: textView)
    }

    /// Reports the followable link at the caret through `links.onCaretLinkChanged`, and only when
    /// it changed, the way the outline entry is reported: this runs on every arrow key.
    ///
    /// The rule is `LinkAtCaret.pick` over the caret paragraph's `.editorLink` runs (the URL a
    /// click follows) and `WikilinkParser`'s source ranges there. A file embed's run is left out:
    /// its preview is a click on a drawn picture, not something the keyboard follows.
    func reportLinkAtCaret(in textView: NSTextView) {
        guard let report = parent.links.onCaretLinkChanged, let storage = textView.textStorage else { return }
        let text = storage.string as NSString
        let caret = textView.selectedRange().location
        guard caret <= text.length else { return }
        let paragraph = text.paragraphRange(for: NSRange(location: caret, length: 0))

        var runs: [LinkAtCaret.Run] = []
        storage.enumerateAttribute(.editorLink, in: paragraph) { value, range, _ in
            guard let url = value as? URL else { return }
            if case .embed = MarkdownAttributedText.clickTarget(for: url) { return }
            runs.append(LinkAtCaret.Run(range: range, url: url))
        }
        let source = text.substring(with: paragraph)
        let wikilinks = WikilinkParser.links(in: source).map { link in
            let local = NSRange(link.range, in: source)
            return NSRange(location: paragraph.location + local.location, length: local.length)
        }

        let url = LinkAtCaret.pick(caret: caret, runs: runs, wikilinks: wikilinks)
        guard requests.claimCaretLink(url) else { return }
        report(url)
    }
}
