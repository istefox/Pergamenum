import AppKit

/// Where a clicked link leads. Its own file because `NoteTextView.Coordinator`'s body is at
/// the length the linter allows (n1-seams R-12, R-13 added the tag and day arms).
extension NoteTextView.Coordinator {
    /// The actual link-target routing, shared by the Cmd-gated delegate method
    /// (`textView(_:clickedOnLink:at:)`, `NoteTextView+Coordinator.swift`) and
    /// "Apri collegamento"'s menu action, which calls this directly to bypass that gate.
    @discardableResult
    func performLinkNavigation(_ link: Any) -> Bool {
        guard let url = link as? URL,
              let target = MarkdownAttributedText.clickTarget(for: url)
        else { return false }

        switch target {
        case .external(let url):
            NSWorkspace.shared.open(url)
        case .embed(let name):
            parent.vault.onOpenEmbed?(name)
        case .note(let title):
            parent.onFollowLink(title)
        // Reported, not acted on: where a tag or a day opens is the pane's business
        // (`CommandActions.open(tag:)`/`open(day:)`, n1-seams R-12, R-13). No surface behind
        // the editor (nil) means the click opens nothing and the caret is placed instead.
        case .tag(let tag):
            guard let onOpenTag = parent.vault.onOpenTag else { return false }
            onOpenTag(tag)
        case .day(let day):
            guard let onOpenDay = parent.vault.onOpenDay else { return false }
            onOpenDay(day)
        }
        return true
    }
}
