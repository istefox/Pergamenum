import AppKit

/// Where a clicked link leads. Its own file because `NoteTextView.Coordinator`'s body is at
/// the length the linter allows (n1-seams R-12, R-13 added the tag and day arms).
extension NoteTextView.Coordinator {
    /// "Apri collegamento"'s menu action, which calls this directly to bypass the Cmd gate of
    /// `textView(_:clickedOnLink:at:)` (`NoteTextView+Coordinator.swift`). Not a click: a
    /// shared title chosen from that menu gets the sheet, not a second menu at a point the
    /// first one has just left (ADR-0083 §D2).
    @discardableResult
    func performLinkNavigation(_ link: Any) -> Bool {
        performLinkNavigation(link, how: .replace, fromClick: false)
    }

    /// The routing body, with the how and where it came from (ADR-0083 §D2). `view` is the text
    /// view a click landed in, where its menu is anchored; nil falls back to the coordinator's.
    /// The variants apply to note targets only: an external URL opens in the browser, a file
    /// embed keeps its Quick Look preview, a tag or a day keeps N1's routing (ADR-0083 §D1).
    @discardableResult
    func performLinkNavigation(_ link: Any, how: LinkOpening, fromClick: Bool, in view: NSView? = nil) -> Bool {
        guard let url = link as? URL,
              let target = MarkdownAttributedText.clickTarget(for: url)
        else { return false }

        switch target {
        case .external(let url):
            NSWorkspace.shared.open(url)
        case .embed(let name):
            parent.vault.onOpenEmbed?(name)
        case .note(let title):
            return follow(title, how: how, fromClick: fromClick, in: view ?? textView)
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

    /// A note title through the open-link door (ADR-0083 §D5). With no `links.follow` behind the
    /// editor, a plain follow is `onFollowLink(title)` as it always was and a variant does
    /// nothing. A choice handed back to a click becomes a menu at the click's point.
    private func follow(_ title: String, how: LinkOpening, fromClick: Bool, in view: NSView?) -> Bool {
        guard let follow = parent.links.follow else {
            guard how == .replace else { return false }
            parent.onFollowLink(title)
            return true
        }
        let request = LinkRequest(target: title, how: how, sourcePath: parent.vault.notePath, fromClick: fromClick)
        // Only a click has a point to anchor a menu to; any other follow is given the sheet.
        guard case .choose(let choices) = follow(request), fromClick, !choices.isEmpty, let view else {
            return true
        }
        let menu = LinkChoiceMenu.menu(title: title, choices: choices) { [weak self] choice in
            self?.parent.links.choose?(choice, how)
        }
        linkChoiceMenus.present(menu, at: clickPoint(in: view), in: view)
        return true
    }

    /// Where the click that is being followed landed, in `view`'s coordinates: the current
    /// event's location when it belongs to `view`'s window, the view's origin otherwise.
    private func clickPoint(in view: NSView) -> NSPoint {
        guard let event = NSApp.currentEvent, let window = view.window, event.window === window else {
            return .zero
        }
        return view.convert(event.locationInWindow, from: nil)
    }
}
