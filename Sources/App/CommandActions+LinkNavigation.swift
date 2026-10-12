import AppKit

/// A wikilink target - a note title or a `^[[board.canvas]]` marker - resolved and navigated
/// to, in the one place every clickable surface now reaches through `@Environment
/// (CommandActions.self)` (issue #188): the note editor's Cmd+click (`EditorColumnView.
/// follow(title:)`), the Workspace `.text` card's Cmd+click (`StickyTextCard`), and the
/// "Task collegati" panel's link chip, which is where this body lived before
/// (`TasksView+Row.swift`) and now delegates to this one instead of keeping a second copy
/// ADR-0039 exists specifically to avoid.
extension CommandActions {
    /// The open-link door (ADR-0083 §D1). A surface with no live point to anchor a menu to calls
    /// this, so a shared title or a creatable dangling one raises the sheet
    /// (`Navigation.linkChoice`) rather than opening the first match.
    func open(link target: String, how: LinkOpening = .replace, from sourcePath: String? = nil) {
        _ = follow(LinkRequest(target: target, how: how, sourcePath: sourcePath, fromClick: false))
    }

    /// «Vai al link» (ADR-0084 §D2): the caret on the first line of the open note holding
    /// `[[target]]`, through the outline's own jump. The line is read off the buffer on screen,
    /// not the file, so an unsaved edit above it does not send the caret to the wrong line.
    ///
    /// A target the index still lists but the buffer no longer holds (an unsaved edit took the
    /// link out) does nothing, on purpose: the saved text's line number would land on whatever the
    /// buffer now has there, and the row leaves the list with the next save.
    func goToLink(target: String) {
        guard let text = vault.openNote?.text,
              let line = UnresolvedTargets.firstLine(linking: target, in: text),
              let range = NoteJump.lineRange(line, in: text)
        else { return }
        navigation.jumpToLine(
            range: NSRange(range, in: text), ordinal: NoteJump.ordinal(of: range.lowerBound, in: text)
        )
    }
}

// MARK: - ADR-0083 §D1, §D3, §D5, §D6 (PG-386, N3 session B)

/// One request to follow a link, from a click or from the keyboard (ADR-0083 §D2, §D3).
struct LinkRequest: Equatable, Sendable {
    let target: String
    let how: LinkOpening
    let sourcePath: String?
    /// True for a click, which can anchor a menu at the pointer; false for the keyboard and
    /// «Apri collegamento», which get the sheet instead.
    let fromClick: Bool
}

/// What following a link did: finished, or needs the person to choose first.
enum LinkFollowOutcome: Equatable, Sendable {
    case done
    case choose([LinkChoice])
}

/// The choice `Navigation.linkChoice` carries to the sheet `RootView` hosts (ADR-0083 §D5).
struct LinkChoiceRequest: Identifiable, Equatable {
    let id: UUID
    let title: String
    let choices: [LinkChoice]
    let how: LinkOpening
    let sourcePath: String?
}

extension CommandActions {
    /// Follows a link, or asks which one (ADR-0083 §D5). One resolution for every surface:
    /// a board opens in the Workspace whatever the how, a unique note opens the way the how says
    /// and puts the Note pane in front, and several notes or a creatable dangling title are a
    /// choice - handed back to a click, which anchors a menu at its point, and put in the sheet
    /// for everything else. Nothing opens the first match.
    func follow(_ request: LinkRequest) -> LinkFollowOutcome {
        let destination = vault.linkDestination(for: request.target)
        switch destination {
        case .note(let path):
            open(notePath: path, how: request.how)
        case .board(let path):
            vault.routeState.pendingCanvas = (path, nil)
        case .missingBoard(let name):
            vault.recordProblem("board non trovata: \(name)")
        // A Cmd+click on a title no note answers to and that cannot be one (`[[Nota.md]]`,
        // `[[Cartella/Nota]]`) used to do nothing at all, indistinguishable from a click that
        // never arrived (PG-356): say so.
        case .missing(let title, creatable: false):
            vault.recordProblem("nota non trovata: \(title)")
        case .ambiguous, .missing:
            let choices = LinkChoice.entries(for: destination)
            if request.fromClick { return .choose(choices) }
            navigation.linkChoice = LinkChoiceRequest(
                id: UUID(), title: request.target, choices: choices, how: request.how,
                sourcePath: request.sourcePath
            )
        }
        return .done
    }

    /// Opens a note whose path is already known (ADR-0083 §D1), and switches to the Note pane: a
    /// follow from Oggi, Diario or a Workspace card must not open the note behind the pane that
    /// is in front, and a note has no observer like the board's `pendingCanvas` to lean on.
    func open(notePath: String, how: LinkOpening) {
        vault.openNote(at: notePath, how: how)
        navigation.pane = .notes
    }

    /// Acts on one row of the choice (ADR-0083 §D5, §D6): opens its path the way the follow
    /// asked, or offers the title to the composer beside the source note, in the Note pane.
    func choose(_ choice: LinkChoice, how: LinkOpening, from sourcePath: String?) {
        switch choice.action {
        case .open(let path):
            open(notePath: path, how: how)
        case .create(let title):
            vault.offerNoteCreation(title: title, besideNoteAt: sourcePath)
            navigation.pane = .notes
        }
    }

    /// The editor's link inputs, wired to this window (ADR-0083 §D2, §D3, §D6, §D7). `column` is
    /// focused before any follow, as `EditorColumnView.focused(_:)` does, and `beforeFollow`
    /// runs after it (Diario's flush). Without a column (Oggi, Diario) the caret's link is
    /// reported nowhere: the keyboard follow acts on the Note pane's focused tab only.
    func linkInputs(
        from sourcePath: String?, column: Int?, beforeFollow: (() -> Void)? = nil
    ) -> NoteTextView.LinkInputs {
        let prepare = {
            if let column { self.vault.focusColumn(column) }
            beforeFollow?()
        }
        return NoteTextView.LinkInputs(
            follow: { request in
                prepare()
                return self.follow(request)
            },
            choose: { choice, how in
                prepare()
                self.choose(choice, how: how, from: sourcePath)
            },
            preview: { target, section in self.vault.linkPreviewContent(for: target, section: section) },
            onCaretLinkChanged: column.map { column in
                { url in self.vault.recordLinkAtCaret(url, inColumn: column) }
            },
            offerCreation: { title in
                self.vault.offerNoteCreation(title: title, besideNoteAt: sourcePath)
                self.navigation.pane = .notes
            }
        )
    }

    /// `runView`'s arm for the history and the link commands (ADR-0083 §D3, §D4).
    func runLinkOrHistory(_ command: ShortcutCommand) {
        switch command {
        case .followLink: followLinkAtCaret(how: .replace)
        case .followLinkInNewTab: followLinkAtCaret(how: .newTab)
        case .followLinkInOtherColumn: followLinkAtCaret(how: .otherColumn)
        case .goBack, .goForward: walkHistory(command)
        default: break
        }
    }

    /// Follows the link the editor reported at the focused tab's caret, decoded by the same
    /// `clickTarget(for:)` a click uses, so the keyboard and the pointer cannot disagree about
    /// what a link points at. A file embed is never reported, and has nothing to do here.
    private func followLinkAtCaret(how: LinkOpening) {
        guard let url = vault.linkAtCaret, let target = MarkdownAttributedText.clickTarget(for: url) else { return }
        switch target {
        case .note(let title):
            _ = follow(LinkRequest(
                target: title, how: how, sourcePath: vault.openNote?.relativePath, fromClick: false
            ))
        case .external(let url): NSWorkspace.shared.open(url)
        case .tag(let tag): open(tag: tag)
        case .day(let day): open(day: day)
        case .embed: break
        }
    }
}
