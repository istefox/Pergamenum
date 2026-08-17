import AppKit
import SwiftUI

/// Everything the editor's `NSTextView` needs a delegate for: styling, completion, the
/// slash menu, links, folding and the caret.
///
/// In a file of its own because `NoteTextView` grew past the length and the type-body
/// length SwiftLint warns at when folding arrived. The struct is now the inputs and the
/// two `NSViewRepresentable` methods; everything that happens *afterwards* is here.
extension NoteTextView {
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
        /// The same, for the index's jumps: without it every later view update would
        /// scroll back to the last heading clicked.
        var lastScrollRequest = 0
        /// Folding lives here rather than on the view: it is a fact about this text view's
        /// layout, and the view struct is rebuilt on every update (M8).
        let folding = FoldingDelegate()
        /// The fold already applied, so an unchanged one does not invalidate the layout on
        /// every view update.
        private var lastFoldLayout = NoteFolding.Layout()
        /// The index entry the caret was last reported to be in. Kept so the callback
        /// fires when it *changes*, not on every arrow key.
        private var lastOutlineEntry: Int??

        init(parent: NoteTextView) {
            self.parent = parent
        }

        /// Takes the caret to a line the index pointed at.
        ///
        /// The caret and not only the scroller: arriving at a section and typing should
        /// write there, and a view that scrolled without moving the insertion point would
        /// send the next keystroke back where it came from.
        func scroll(_ textView: NSTextView, to range: NSRange) {
            let length = (textView.string as NSString).length
            guard range.location <= length else { return }
            let clamped = NSRange(location: range.location, length: min(range.length, length - range.location))
            textView.setSelectedRange(NSRange(location: clamped.location, length: 0))
            textView.scrollRangeToVisible(clamped)
            textView.window?.makeFirstResponder(textView)
        }

        /// Reports which index entry the caret is inside, and only when it changes.
        ///
        /// This runs on every cursor movement, so publishing the offset itself would put
        /// a SwiftUI update behind every arrow key. The entry changes far less often than
        /// the caret does.
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let caret = textView.selectedRange().location
            let entry = parent.outlineRanges.lastIndex { $0.location <= caret }
            guard lastOutlineEntry != .some(entry) else { return }
            lastOutlineEntry = entry
            parent.onOutlineEntryChanged?(entry)
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

        /// Recomputes the fold and makes the layout read it again.
        ///
        /// `edited(.editedAttributes,…)` is what re-runs the content manager's enumeration
        /// without a character changing - the same trick the reveal-on-caret probe used in
        /// the TextKit study. Skipped entirely when nothing is folded and nothing was, so
        /// an ordinary note pays nothing for this.
        func applyFolding(to textView: NSTextView, folded: Set<Int>, theme: Theme) {
            guard folding.isFolding || !folded.isEmpty else { return }
            let layout = NoteFolding.layout(in: textView.string, foldedEntries: folded)
            guard layout != lastFoldLayout else { return }
            lastFoldLayout = layout

            folding.badgeColor = NSColor(theme.color(.textTertiary))
            folding.badgeBackground = NSColor(theme.color(.backgroundTertiary))
            folding.apply(hiddenLines: layout.hiddenLineOffsets, foldedHeadings: layout.foldedHeadings)

            let length = (textView.string as NSString).length
            textView.textContentStorage?.textStorage?.edited(
                .editedAttributes, range: NSRange(location: 0, length: length), changeInLength: 0
            )
            if let manager = textView.textLayoutManager {
                manager.invalidateLayout(for: manager.documentRange)
            }
            rescueCaret(in: textView, from: layout)
        }

        /// Moves the caret out of a section that has just been folded.
        ///
        /// The folded lines are not in the layout, so a caret left inside one is an
        /// insertion point with nowhere to be drawn and nowhere to type. It goes to the
        /// heading that swallowed it, which is where a person would look for it.
        private func rescueCaret(in textView: NSTextView, from layout: NoteFolding.Layout) {
            guard !layout.hiddenLineOffsets.isEmpty else { return }
            let text = textView.string as NSString
            let caret = textView.selectedRange().location
            guard caret <= text.length else { return }
            let line = text.paragraphRange(for: NSRange(location: caret, length: 0)).location
            guard layout.hiddenLineOffsets.contains(line) else { return }

            let heading = layout.foldedHeadings.keys.filter { $0 <= caret }.max() ?? 0
            textView.setSelectedRange(NSRange(location: heading, length: 0))
            textView.scrollRangeToVisible(NSRange(location: heading, length: 0))
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

        /// The spans that need more than a colour: a font, a background, a link.
        ///
        /// Everything else falls to `colorToken(for:)`, and the `default` here is safe for
        /// the reason that switch has no default of its own: a span added later reaches it
        /// and the compiler asks what colour it is.
        private func attributes(for span: MarkdownStyler.Span, theme: Theme) -> [NSAttributedString.Key: Any] {
            switch span {
            case .heading(let level):
                [
                    .font: NSFont.systemFont(ofSize: max(15, 24 - CGFloat(level) * 2), weight: .semibold),
                    .foregroundColor: NSColor(theme.color(.textPrimary)),
                ]
            case .bold:
                [.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)]
            case .italic:
                [.obliqueness: 0.2]
            case .codeBlock:
                // Only a background. The colour is left to whatever the grammar found
                // inside, and to `textPrimary` where it found nothing - a fence in a
                // language nobody wrote a grammar for still reads as code because of
                // this, which is the whole fallback.
                [.backgroundColor: NSColor(theme.color(.surfaceSunken))]
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
            default:
                [.foregroundColor: NSColor(theme.color(Self.colorToken(for: span)))]
            }
        }

        /// Every span's colour, the six above included even though they never arrive here.
        /// No `default`, on purpose: this is the one table that must stay exhaustive.
        private static func colorToken(for span: MarkdownStyler.Span) -> ColorToken {
            switch span {
            case .heading, .bold, .italic, .codeBlock: .textPrimary
            case .frontmatter, .code, .annotation: .textSecondary
            case .linkSyntax: .textTertiary
            case .tag, .linkTarget, .embedTarget: .accentPrimary
            case .codeToken(let token): token.colorToken
            case .taskMarker(let done): done ? .taskDone : .taskOpen
            case .scheduled: .taskScheduled
            case .due: .taskOverdue
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
