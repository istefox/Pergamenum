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
    let onFollowLink: (String) -> Void
    /// Where a dropped file should be copied to, returning its file name for the
    /// embed (SPEC §5). Nil disables dropping.
    var onDropFile: ((URL) -> String?)?

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
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteTextView
        weak var textView: NSTextView?
        /// Guards the delegate callback from re-entering while styling rewrites
        /// attributes.
        private var isStyling = false

        init(parent: NoteTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isStyling, let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            applyStyling(to: textView, theme: parent.theme)

            if let completing = textView as? CompletingTextView, completing.shouldOfferCompletion() {
                completing.complete(nil)
            }
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard let url = link as? URL,
                  let title = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                      .queryItems?.first(where: { $0.name == "title" })?.value
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
    }
}

/// An `NSTextView` that completes note titles after `[[` and tags after `#`.
///
/// Uses AppKit's own completion list rather than a custom popup: it already handles
/// arrow keys, Escape, and placement near the insertion point, and matching that
/// behaviour by hand is how a completion list ends up feeling wrong.
final class CompletingTextView: NSTextView {
    var noteTitles: [String] = []
    var tagSuggestions: [String] = []
    /// Called with pasted text; returns true when it handled the paste itself.
    var onPasteURL: ((String) -> Bool)?
    /// Called with a dropped file, returning the name to embed (SPEC §5).
    var onDropFile: ((URL) -> String?)?

    /// Pasting a URL over a selection writes a markdown link (SPEC §5).
    override func paste(_ sender: Any?) {
        if let pasted = NSPasteboard.general.string(forType: .string),
           onPasteURL?(pasted) == true {
            return
        }
        super.paste(sender)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self], options: nil
        ) as? [URL] ?? []
        guard !urls.isEmpty, let onDropFile else { return super.performDragOperation(sender) }

        // Each dropped file is copied into the vault and embedded by name; the app
        // never links to a path outside the vault, which would break the day the file
        // moves or the disk is not mounted.
        let embeds = urls.compactMap(onDropFile).map(EditorEdits.embed(forFileNamed:))
        guard !embeds.isEmpty else { return super.performDragOperation(sender) }

        insertText(embeds.joined(separator: "\n"), replacementRange: selectedRange())
        return true
    }

    private enum Context {
        case wikilink(prefix: String)
        case tag(prefix: String)
    }

    /// True right after the user typed the trigger, so the list opens without a
    /// keyboard shortcut.
    func shouldOfferCompletion() -> Bool {
        completionContext() != nil
    }

    override var rangeForUserCompletion: NSRange {
        // The default is a word range, which stops at the space inside "Curva di
        // trasmissibilità" and would complete against the last word only.
        guard let context = completionContext() else { return super.rangeForUserCompletion }
        let cursor = selectedRange().location
        let length: Int = switch context {
        case .wikilink(let prefix): prefix.count
        case .tag(let prefix): prefix.count
        }
        return NSRange(location: cursor - length, length: length)
    }

    override func completions(
        forPartialWordRange charRange: NSRange,
        indexOfSelectedItem index: UnsafeMutablePointer<Int>?
    ) -> [String]? {
        guard let context = completionContext() else { return nil }
        index?.pointee = 0

        switch context {
        case .wikilink(let prefix):
            // Broken into steps: as one chained expression the type checker gives up.
            var scored: [(title: String, score: Int)] = []
            for title in noteTitles {
                guard let score = FuzzyMatch.score(query: prefix, candidate: title) else { continue }
                scored.append((title, score))
            }
            scored.sort { left, right in
                left.score == right.score ? left.title.count < right.title.count : left.score > right.score
            }
            let matches = scored.prefix(12).map(\.title)
            return matches.isEmpty ? nil : Array(matches)
        case .tag(let prefix):
            let matches = tagSuggestions.filter { $0.hasPrefix(prefix) }.prefix(12)
            return matches.isEmpty ? nil : Array(matches)
        }
    }

    /// Looks backwards from the cursor for a `[[` or `#` trigger on the current line.
    private func completionContext() -> Context? {
        let cursor = selectedRange().location
        guard cursor > 0 else { return nil }

        let text = string as NSString
        guard cursor <= text.length else { return nil }

        let lineRange = text.lineRange(for: NSRange(location: cursor, length: 0))
        let beforeCursor = text.substring(with: NSRange(
            location: lineRange.location, length: cursor - lineRange.location
        ))

        if let open = beforeCursor.range(of: "[[", options: .backwards) {
            let prefix = String(beforeCursor[open.upperBound...])
            // A closed link is not a completion context any more.
            if !prefix.contains("]]") { return .wikilink(prefix: prefix) }
        }
        if let hash = beforeCursor.range(of: "#", options: .backwards) {
            let prefix = String(beforeCursor[hash.lowerBound...])
            let precedingIndex = beforeCursor.index(before: hash.lowerBound)
            let atLineStart = hash.lowerBound == beforeCursor.startIndex
            let afterSpace = !atLineStart && beforeCursor[precedingIndex] == " "
            // `# ` opens a heading, not a tag, and a space ends the tag.
            if (atLineStart || afterSpace), !prefix.contains(" ") { return .tag(prefix: prefix) }
        }
        return nil
    }
}
