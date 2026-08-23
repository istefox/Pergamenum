import AppKit
import SwiftUI

/// An `NSTextView` that completes note titles after `[[`, headings after `[[Nota#`, tags
/// after `#`, and the command catalogue after `/`.
///
/// All four are drawn in one `CompletionPanel`. The first three used AppKit's own
/// completion list, which was the right way to start - arrow keys, Escape and scrolling
/// came free - and turned out to place itself where it liked: near the bottom edge of the
/// window over the caret's own line, or off the screen entirely (PG-023). This view owns
/// the keys in exchange, in `doCommand(by:)`, and the panel places itself.
final class CompletingTextView: NSTextView {
    var noteTitles: [String] = []
    var tagSuggestions: [String] = []
    /// The slash menu's catalogue, already filtered to what can run right now (M8).
    /// Set from the SwiftUI layer, because whether a command can run is a fact about the
    /// app and not about the text.
    var editorCommands: [EditorCommand] = []
    /// Runs a command the app owns. The text view never performs one itself.
    var onRunCommand: ((ShortcutCommand) -> Void)?
    /// The panel every completion is drawn in. Owned here because it lives and dies with
    /// the text view it opens over, and configured lazily so that choosing a row by mouse
    /// lands in the same place as choosing it by Return.
    private(set) lazy var completionPanel: CompletionPanel = {
        let panel = CompletionPanel()
        panel.onChoose = { [weak self] item in self?.apply(item) }
        return panel
    }()
    /// Where the trigger was when the user pressed Escape, so the panel does not come back
    /// on the next keystroke of the same word. AppKit's list used to remember this for the
    /// three completions it served; now nothing else will.
    private var dismissedLocation: Int?
    /// One accessibility element per paragraph currently drawing an embed, by paragraph
    /// offset - built and kept current by the `accessibilityChildren()` override in
    /// `CompletingTextView+Accessibility.swift` (ADR-0018 slice 3, Step 6 fix). Reused
    /// rather than rebuilt on every query: VoiceOver tracks an element's identity, and
    /// recreating it each call made it flicker in the run this fix measured against. Not
    /// `private`: the override that owns this cache lives in its own file, at the length
    /// the linter already caps this one at.
    var embedAccessibilityElements: [Int: NSAccessibilityElement] = [:]
    /// Called with pasted text; returns true when it handled the paste itself.
    var onPasteURL: ((String) -> Bool)?
    /// Called with the PNG bytes of a pasted image; returns the name it was saved under.
    var onPasteImage: ((Data) -> String?)?
    /// Called with a dropped file, returning the name to embed (SPEC §5).
    var onDropFile: ((URL) -> String?)?
    /// The headings of a note, for completing `[[Nota#`. Nil where there is no vault to
    /// look one up in, and then the section context simply offers nothing.
    var noteSections: ((String) -> [String])?
    /// The format bar, owned here for the same reason the completion panel is: it lives and
    /// dies with the text view it floats over (M8).
    private(set) lazy var formatBar: FormatBarPanel = {
        let bar = FormatBarPanel()
        bar.onChoose = { [weak self] action in self?.applyFormat(action) }
        return bar
    }()

    /// Called when this text view takes the keyboard, so the column it belongs to can take
    /// the focus with it (ADR-0012 D4).
    ///
    /// **A click on the text is not a click SwiftUI sees.** The column carries a tap gesture
    /// for exactly this, and an `NSTextView` swallows the mouse before it gets there - so
    /// clicking into the right hand note left the focus on the left, and Cmd+F, the note list
    /// and the inspector all went on answering for the other half.
    var onTakeFocus: (() -> Void)?

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { onTakeFocus?() }
        return became
    }

    /// Called with a click in the view's own coordinates, before the text view does
    /// anything with it; returns true when it handled it. This is how a transcluded note
    /// drawn under a line is opened (ADR-0010): the drawing is not text, so no character
    /// carries a link attribute and `clickedOnLink` never fires for it.
    var onClickInMargin: ((CGPoint) -> Bool)?

    /// Claims a keyboard command before the ordinary editing behaviour gets it, while the
    /// completion panel is closed - the panel's own keys in `doCommand(by:)` below still
    /// win when it is open, since choosing a suggestion outranks crossing an embed the
    /// caret happens to sit beside. Set by `NoteTextView.wire(_:to:)` to
    /// `claimsEmbedCommand(_:in:)` (ADR-0018 slice 3, Step 4), the same closure shape
    /// `onClickInMargin` already has and for the same reason: this view has exactly one
    /// owner, and a closure makes that owner's identity a non-issue.
    var claimsCommand: ((Selector) -> Bool)?

    /// True where the caret is in one of the three contexts that offer candidate strings
    /// rather than commands.
    ///
    /// `completionContext()` is private and is the rule the whole feature turns on, so this
    /// and `shouldOpenSlashMenu` exist to make it assertable: between them they say which
    /// of the two shapes the panel takes, and the pair can never both be true.
    func shouldOfferCompletion() -> Bool {
        switch completionContext() {
        case .wikilink, .section, .tag: true
        case .slash, .emoji, nil: false
        }
    }

    // MARK: The completion panel (M8)

    /// Whether what is under the caret is the emoji trigger.
    ///
    /// The third of the three predicates, and it exists for the same reason as the other two:
    /// `completionContext()` is private, and without a way to ask the rule directly a test can
    /// only watch the panel - which stays shut both when the rule says no and when the query
    /// simply matches nothing. That is not a test of the rule, and it was written that way
    /// once: removing "at the start of a line or after a space" left it green, because `30`
    /// in `14:30` matches no emoji either way.
    func shouldOfferEmoji() -> Bool {
        if case .emoji = completionContext() { return true }
        return false
    }

    /// Whether what is under the caret would open the command list.
    ///
    /// The counterpart of `shouldOfferCompletion`, and the thing the trigger's tests assert
    /// on: opening the real panel needs a window, and the rule is what has to be right.
    func shouldOpenSlashMenu() -> Bool {
        guard let location = slashLocation() else { return false }
        return location != dismissedLocation
    }

    /// Escape closes the panel **and leaves the text alone**, which needs both halves said.
    ///
    /// Deleting the `/` on dismissal was the alternative and it is a trap: a person
    /// writing `/usr/local` would lose the character, retype it, and reopen the menu -
    /// a literal slash at the start of a line would be unwritable. It is also against
    /// this app's own precedent, ADR-0008 §D3, where a capture dismissed by accident
    /// keeps what was typed.
    ///
    /// So the trigger stays and the dismissal is remembered instead. Without this the panel
    /// reopened on the very next keystroke, because the context was still the same context
    /// - Escape closed it for exactly as long as the user did not type.
    func dismissCompletion() {
        dismissedLocation = triggerLocation()
        completionPanel.hide()
    }

    /// Where the `/` that would open the command list sits, or nil when there is none.
    private func slashLocation() -> Int? {
        guard case .slash = completionContext() else { return nil }
        return triggerLocation()
    }

    /// Where what is being completed begins, whichever of the four contexts it is.
    ///
    /// The same number `rangeForUserCompletion` starts at, and deliberately taken from it:
    /// two ways of computing where a completion starts is one way too many.
    private func triggerLocation() -> Int? {
        guard completionContext() != nil else { return nil }
        return rangeForUserCompletion.location
    }

    /// Opens, updates or closes the panel for whatever is under the caret now.
    ///
    /// Called on every keystroke. Closing is as important as opening: the panel has to go
    /// the moment the context stops being one, or it hangs over a note nobody is filtering
    /// any more.
    func refreshCompletion(theme: Theme) {
        guard let context = completionContext() else {
            // Out of every context: forget the dismissal too, so the next trigger opens the
            // panel as the first one did.
            dismissedLocation = nil
            completionPanel.hide()
            return
        }
        guard triggerLocation() != dismissedLocation else { return }

        let items: [CompletionItem]
        let query: String
        switch context {
        case .slash(let prefix):
            query = String(prefix.dropFirst())
            items = EditorCommand.matching(query, in: editorCommands).map(CompletionItem.command)
        case .emoji(let prefix):
            query = String(prefix.dropFirst())
            items = EmojiCatalogue.matching(query).map { .emoji(glyph: $0.glyph, name: $0.name) }
        case .wikilink(let prefix), .section(_, let prefix), .tag(let prefix):
            query = prefix
            let symbol = context.symbol
            items = (completions(
                forPartialWordRange: rangeForUserCompletion, indexOfSelectedItem: nil
            ) ?? []).map { .text($0, symbol: symbol) }
        }

        // Nothing matched, and the trigger has nothing to say about it: the panel goes. One
        // rule for all five rather than a guard inside two of the cases, which is where the
        // `:` list came to vanish mid-word while the command list stayed and explained itself
        // - the same list, two answers to the same question. `Context.noMatch` is where the
        // difference is decided and why.
        guard !items.isEmpty || context.noMatch != nil else {
            completionPanel.hide()
            return
        }

        completionPanel.show(
            CompletionPanel.Content(items: items, query: query, noMatch: context.noMatch),
            caretRect: caretRectOnScreen(),
            over: window,
            theme: theme
        )
    }

    /// The keys the menu owns while it is open, and only while it is open.
    ///
    /// Handled here rather than in the panel because the panel never becomes key: the text
    /// view keeps first responder throughout, which is what lets typing carry on filtering
    /// the list. Anything not in this list falls through, so every other key still edits
    /// the note.
    override func doCommand(by selector: Selector) {
        guard completionPanel.isVisible else {
            if let claimsCommand, claimsCommand(selector) { return }
            super.doCommand(by: selector)
            return
        }
        switch selector {
        case #selector(moveUp(_:)):
            completionPanel.moveSelection(by: -1)
        case #selector(moveDown(_:)):
            completionPanel.moveSelection(by: 1)
        case #selector(insertNewline(_:)), #selector(insertTab(_:)):
            if let selected = completionPanel.selected { apply(selected) }
        // Escape reaches a text view as either of these depending on what else is
        // installed, so both are caught rather than the one that happened to work.
        case #selector(cancelOperation(_:)), #selector(complete(_:)):
            dismissCompletion()
        default:
            super.doCommand(by: selector)
        }
    }

    /// Replaces what was typed with what the chosen row produces.
    ///
    /// The single place a choice is acted on, whether it arrived by Return, by Tab or by a
    /// click on the row. One edit, so undo takes the whole thing back rather than peeling
    /// it a character at a time. The panel closes first: a command that opens a panel or
    /// changes pane would otherwise leave a list floating over whatever it opened.
    private func apply(_ item: CompletionItem) {
        let range = rangeForUserCompletion
        completionPanel.hide()

        switch item {
        // The bare string, which is what AppKit's list inserted: `[[Nota` is left open for
        // the person to close, and a heading replaces only what follows the `#`.
        case .text(let value, _):
            insertText(value, replacementRange: range)
        // The glyph alone. The `:` and the name were how it was reached, not what was meant,
        // and nothing shortcode-shaped is left in the file for Obsidian to read differently.
        case .emoji(let glyph, _):
            insertText(glyph, replacementRange: range)
        case .command(let command):
            switch command.action {
            case .insert(let text, let cursorBack):
                insertText(text, replacementRange: range)
                // Counted in UTF-16, which is what an `NSRange` is measured in: `count` on a
                // String would put the caret in the wrong place the first time a template
                // carries an emoji.
                let end = range.location + (text as NSString).length
                setSelectedRange(NSRange(location: max(range.location, end - cursorBack), length: 0))
            case .app(let appCommand):
                // The typed `/prefisso` goes first: the command may open a panel or move to
                // another pane, and coming back to find `/oggi` still in the note reads as
                // the menu having failed.
                insertText("", replacementRange: range)
                onRunCommand?(appCommand)
            }
        }
    }

    override func resignFirstResponder() -> Bool {
        completionPanel.hide()
        return super.resignFirstResponder()
    }

    override var rangeForUserCompletion: NSRange {
        // The default is a word range, which stops at the space inside "Curva di
        // trasmissibilità" and would complete against the last word only.
        guard let context = completionContext() else { return super.rangeForUserCompletion }
        let cursor = selectedRange().location
        let length: Int = switch context {
        case .wikilink(let prefix): prefix.count
        // Only what follows the `#`: the note's name is already right, and replacing it
        // too would delete what the completion is a completion *of*.
        case .section(_, let prefix): prefix.count
        case .tag(let prefix): prefix.count
        case .slash(let prefix): prefix.count
        // The `:` goes too, as the tag's `#` does: what is written is the glyph alone.
        case .emoji(let prefix): prefix.count
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
        case .section(let note, let prefix):
            return sections(of: note, matching: prefix)
        case .tag(let prefix):
            let matches = tagSuggestions.filter { $0.hasPrefix(prefix) }.prefix(12)
            return matches.isEmpty ? nil : Array(matches)
        case .emoji:
            // Same as `.slash`: built from a catalogue in `refreshCompletion`, never here.
            return nil
        case .slash:
            // The command list is built from the catalogue in `refreshCompletion`, not from
            // here. Reached only if something else asks the text view to complete - Escape
            // does, on some configurations - and nil is what stops AppKit's own list, which
            // this panel replaced, from appearing over it.
            return nil
        }
    }
}
