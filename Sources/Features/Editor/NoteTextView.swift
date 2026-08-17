import AppKit
import SwiftUI

/// The markdown editor: an `NSTextView` on TextKit 2, wrapped for SwiftUI.
///
/// SwiftUI's `TextEditor` cannot style ranges, place a completion list, or make a
/// wikilink clickable, all three of which M1 needs, so this is the AppKit bridge
/// SPEC §3 anticipates.
struct NoteTextView: NSViewRepresentable {
    @Binding var text: String
    let theme: Theme
    /// Titles offered when completing after `[[`.
    let noteTitles: [String]
    /// Tags offered when completing after `#`, most used first.
    let tagSuggestions: [String]
    /// The slash menu's catalogue, already filtered to what can run (M8). Passed in
    /// rather than built here: whether a command can run is a fact about the app, and
    /// the editor is not the place that knows it.
    var editorCommands: [EditorCommand] = []
    var onRunCommand: ((ShortcutCommand) -> Void)?
    let onFollowLink: (String) -> Void
    /// Called with the file name inside `![[foto.png]]` when the embed is clicked. The
    /// editor shows the syntax, not the picture (SPEC §5), so this is how the file
    /// itself is reached from here.
    var onOpenEmbed: ((String) -> Void)?
    /// Where a dropped file should be copied to, returning its file name for the
    /// embed (SPEC §5). Nil disables dropping.
    var onDropFile: ((URL) -> String?)?
    /// Called with the PNG bytes of an image pasted from the clipboard, returning the
    /// name it was written into the vault under. A screenshot has no file to drop, so
    /// without this it could not enter a note at all.
    var onPasteImage: ((Data) -> String?)?
    /// Text the Inserisci menu asked for, applied at the cursor and then reported as
    /// applied so it is not inserted twice on the next view update (SPEC §10).
    var insertion: (text: String, cursorBack: Int)?
    var onInsertionApplied: () -> Void = {}
    /// Raised by the Modifica menu; opens AppKit's own find bar.
    var findRequest: FindRequest?
    var onFindApplied: () -> Void = {}
    /// Bumped when the cursor should move into the editor, which is what makes a note
    /// created in the composer open ready to be typed into.
    var focusRequest = 0

    enum FindRequest { case find, replace }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = CompletingTextView(usingTextLayoutManager: true)
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        // Smart substitutions would rewrite `- [ ]`, `>2026-08-15` and `--` into
        // characters the task and frontmatter parsers do not accept, silently making
        // a conformant note non-conformant as the user types.
        textView.isContinuousSpellCheckingEnabled = false
        textView.textContainerInset = NSSize(width: 24, height: 20)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        // Trova e Sostituisci of SPEC §10: AppKit's find bar already does incremental
        // search, replace-all and the scope of the current text view.
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.linkTextAttributes = [:]
        textView.onPasteURL = { [weak textView] pasted in
            guard let textView, let selectionRange = textView.selectedRanges.first as? NSRange,
                  selectionRange.length > 0
            else { return false }
            let selected = (textView.string as NSString).substring(with: selectionRange)
            guard let replacement = EditorEdits.markdownLink(pasting: pasted, over: selected) else {
                return false
            }
            textView.insertText(replacement, replacementRange: selectionRange)
            return true
        }
        textView.onDropFile = { url in context.coordinator.parent.onDropFile?(url) }
        textView.onPasteImage = { data in context.coordinator.parent.onPasteImage?(data) }
        // Through the coordinator like the other three: the closure is read when the
        // command runs, so it is the current one and not the one this view was built with.
        textView.onRunCommand = { command in context.coordinator.parent.onRunCommand?(command) }

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        context.coordinator.textView = textView
        textView.string = text
        context.coordinator.applyStyling(to: textView, theme: theme)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? CompletingTextView else { return }
        context.coordinator.parent = self
        textView.noteTitles = noteTitles
        textView.tagSuggestions = tagSuggestions
        textView.editorCommands = editorCommands

        // Only touch the text when the model diverges from what is on screen:
        // reassigning it unconditionally would reset the cursor on every keystroke.
        if textView.string != text {
            let selection = textView.selectedRange()
            textView.string = text
            textView.setSelectedRange(NSRange(
                location: min(selection.location, (text as NSString).length),
                length: 0
            ))
        }
        context.coordinator.applyStyling(to: textView, theme: theme)

        if let insertion {
            // After the text sync above, so the insertion is not overwritten by the
            // model value that predates it.
            textView.insertText(insertion.text, replacementRange: textView.selectedRange())
            let cursor = textView.selectedRange().location - insertion.cursorBack
            textView.setSelectedRange(NSRange(location: max(0, cursor), length: 0))
            onInsertionApplied()
        }

        if focusRequest != context.coordinator.lastFocusRequest {
            context.coordinator.lastFocusRequest = focusRequest
            context.coordinator.takeFocus()
        }

        if let findRequest {
            textView.window?.makeFirstResponder(textView)
            textView.performTextFinderAction(
                NSMenuItem(title: "", action: nil, keyEquivalent: "").withFinderTag(
                    findRequest == .find ? .showFindInterface : .showReplaceInterface
                )
            )
            onFindApplied()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteTextView
        weak var textView: NSTextView?
        /// Guards the delegate callback from re-entering while styling rewrites
        /// attributes.
        private var isStyling = false
        /// The same guard for the completion list.
        ///
        /// `complete(nil)` puts the first candidate into the text as it opens the list,
        /// and that edit calls `textDidChange` straight back. The context is still a
        /// completion one - `#area-training` is a tag prefix like `#a` was - so the
        /// list was offered again, and again, until the stack ran out and the app
        /// died. Typing a `#` at the start of any line was enough.
        private var isCompleting = false
        /// The focus request already honoured, so the cursor is not stolen back on
        /// every subsequent update.
        var lastFocusRequest = 0

        init(parent: NoteTextView) {
            self.parent = parent
        }

        /// Puts the cursor in the editor.
        ///
        /// Retried once on the next pass because a text view built during this same
        /// update is not in a window yet, and `makeFirstResponder` on no window is a
        /// silent no-op - the note would open with the caret nowhere.
        func takeFocus() {
            guard let textView, textView.window?.makeFirstResponder(textView) != true else { return }
            Task { @MainActor [weak self] in
                guard let textView = self?.textView else { return }
                textView.window?.makeFirstResponder(textView)
            }
        }

        func textDidChange(_ notification: Notification) {
            guard !isStyling, let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            applyStyling(to: textView, theme: parent.theme)

            guard let completing = textView as? CompletingTextView else { return }
            // The slash menu first and unconditionally: it has to close when the context
            // stops being one, not only open when it starts.
            completing.refreshSlashMenu(theme: parent.theme)

            guard !isCompleting, completing.shouldOfferCompletion() else { return }
            isCompleting = true
            defer { isCompleting = false }
            completing.complete(nil)
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard let url = link as? URL,
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            else { return false }

            if components.host == Self.embedHost,
               let name = components.queryItems?.first(where: { $0.name == "name" })?.value {
                parent.onOpenEmbed?(name)
                return true
            }
            guard let title = components.queryItems?
                .first(where: { $0.name == "title" })?.value
            else { return false }
            parent.onFollowLink(title)
            return true
        }

        /// Rewrites the whole attribute run. Notes are small enough that styling the
        /// full text on each keystroke stays imperceptible, and a visible-range
        /// optimisation would have to be re-run on every scroll to avoid unstyled
        /// text appearing as the user moves through the note.
        func applyStyling(to textView: NSTextView, theme: Theme) {
            guard let storage = textView.textStorage else { return }
            isStyling = true
            defer { isStyling = false }

            let text = textView.string
            let full = NSRange(location: 0, length: (text as NSString).length)

            storage.beginEditing()
            storage.setAttributes([
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                .foregroundColor: NSColor(theme.color(.textPrimary)),
            ], range: full)

            for styled in MarkdownStyler.spans(in: text) {
                let nsRange = NSRange(styled.range, in: text)
                guard nsRange.location != NSNotFound, NSMaxRange(nsRange) <= full.length else { continue }
                storage.addAttributes(attributes(for: styled.span, theme: theme), range: nsRange)
            }
            storage.endEditing()
        }

        private func attributes(for span: MarkdownStyler.Span, theme: Theme) -> [NSAttributedString.Key: Any] {
            switch span {
            case .frontmatter:
                [.foregroundColor: NSColor(theme.color(.textSecondary))]
            case .heading(let level):
                [
                    .font: NSFont.systemFont(ofSize: max(15, 24 - CGFloat(level) * 2), weight: .semibold),
                    .foregroundColor: NSColor(theme.color(.textPrimary)),
                ]
            case .bold:
                [.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)]
            case .italic:
                [.obliqueness: 0.2]
            case .code:
                [.foregroundColor: NSColor(theme.color(.textSecondary))]
            case .linkSyntax:
                [.foregroundColor: NSColor(theme.color(.textTertiary))]
            case .linkTarget(let target):
                [
                    .foregroundColor: NSColor(theme.color(.accentPrimary)),
                    .link: linkURL(for: target),
                    .cursor: NSCursor.pointingHand,
                ]
            case .embedTarget(let target):
                [
                    .foregroundColor: NSColor(theme.color(.accentPrimary)),
                    .link: embedURL(for: target),
                    .cursor: NSCursor.pointingHand,
                ]
            case .tag:
                [.foregroundColor: NSColor(theme.color(.accentPrimary))]
            case .taskMarker(let done):
                [.foregroundColor: NSColor(theme.color(done ? .taskDone : .taskOpen))]
            case .scheduled:
                [.foregroundColor: NSColor(theme.color(.taskScheduled))]
            case .due:
                [.foregroundColor: NSColor(theme.color(.taskOverdue))]
            case .annotation:
                [.foregroundColor: NSColor(theme.color(.textSecondary))]
            }
        }

        /// Encodes the target as a query item so a title containing `/`, `?` or `#`
        /// survives the round-trip through `URL`.
        private func linkURL(for target: String) -> URL {
            var components = URLComponents()
            components.scheme = AppInfo.urlScheme
            components.host = "note"
            components.queryItems = [URLQueryItem(name: "title", value: target)]
            return components.url ?? URL(string: "\(AppInfo.urlScheme)://note")!
        }

        /// The same trick for an embedded file. A different host, because the click
        /// leads somewhere else: a file to preview rather than a note to open.
        private func embedURL(for target: String) -> URL {
            var components = URLComponents()
            components.scheme = AppInfo.urlScheme
            components.host = Self.embedHost
            components.queryItems = [URLQueryItem(name: "name", value: target)]
            return components.url ?? URL(string: "\(AppInfo.urlScheme)://\(Self.embedHost)")!
        }

        static let embedHost = "embed"
    }
}

private extension NSMenuItem {
    /// `performTextFinderAction` reads the sender's tag, so the action has to arrive
    /// wearing one.
    func withFinderTag(_ action: NSTextFinder.Action) -> NSMenuItem {
        tag = action.rawValue
        return self
    }
}
