import AppKit

/// The bar that floats over a selection, and everything it can do to one (SPEC §10, M8).
///
/// Its own file for the reason `+CaretRect`, `+Context` and `+Pasteboard` are theirs: the text
/// view is at the length the linter allows and this is a self-contained piece of it - when the
/// bar appears, what it says about the selection, and what each button writes.
extension CompletingTextView {
    /// Shows the bar over the selection, or takes it away.
    ///
    /// Called from `textViewDidChangeSelection`, which runs on **every arrow key**, so this
    /// does its own work and publishes nothing up to SwiftUI - the discipline the outline's
    /// callback already keeps in the same method.
    func refreshFormatBar(theme: Theme) {
        let selection = selectedRange()
        guard selection.length > 0, !isInsideCodeFence(selection), !isEmbedMarker(selection)
        else {
            formatBar.hide()
            return
        }
        if isInsideTable(selection) {
            // AppKit's own undo re-selects exactly the range `replaceAtomically` replaced
            // (§D7's atomic commit, over the table's whole multi-line source) - a table has no
            // inline formatting of its own, so leaving that selection standing draws nothing
            // but a wall-to-wall highlight over the grid. Collapsing to the end is what a
            // cursor landing after any other undo already looks like; `setSelectedRange` fires
            // this method again, but a zero-length range short-circuits at the guard above
            // before `isInsideTable` runs a second time.
            formatBar.hide()
            setSelectedRange(NSRange(location: NSMaxRange(selection), length: 0))
            return
        }
        let anchor = formatBarAnchor(selection)
        formatBar.show(
            applied: appliedFormats(over: selection),
            selectionRect: anchor.rect,
            preferring: anchor.side,
            over: window,
            theme: theme
        )
    }

    /// No bar over a picture: `selectEmbed(at:in:)` (ADR-0018 slice 3) selects the whole
    /// `![[foto.png]]` marker as ordinary text, so this selection reaches here just like
    /// any other - and bold/italic/list markers wrapped around a picture's own marker are
    /// meaningless, not merely inapplicable. Reuses `Attachment.embed(inLine:)`, the same
    /// pure predicate `EditorDecorationDelegate` already applies to a marker line, rather
    /// than a second reading of what counts as an embed.
    private func isEmbedMarker(_ selection: NSRange) -> Bool {
        guard selection.location != NSNotFound,
              NSMaxRange(selection) <= (string as NSString).length
        else { return false }
        let marker = (string as NSString).substring(with: selection)
            .trimmingCharacters(in: .whitespaces)
        return Attachment.embed(inLine: marker) != nil
    }

    /// No bar over a table: `NoteTextView+Coordinator.swift`'s atomic commit
    /// (`replaceAtomically` over the table's whole source range, §D7) leaves AppKit's own
    /// undo re-selecting exactly that range, which is bold/italic-shaped text markup applied
    /// to nothing - a table's source has no inline formatting of its own. Reuses
    /// `EditorDecorationDelegate.tableRun(in:atParagraphStart:)`, the one implementation of
    /// "is there still a table here" (`+TableRendering.swift`'s own doc comment), keyed the
    /// same way `CompletingTextView+Accessibility.swift`'s `drawnTableGrids()` already reads
    /// `decorations.tableViews`.
    private func isInsideTable(_ selection: NSRange) -> Bool {
        guard let decorations = textContentStorage?.delegate as? EditorDecorationDelegate,
              !decorations.tableViews.isEmpty
        else { return false }
        let text = string as NSString
        return decorations.tableViews.keys.contains { offset in
            guard let run = EditorDecorationDelegate.tableRun(in: text, atParagraphStart: offset)
            else { return false }
            return NSIntersectionRange(run.range, selection).length > 0
                || NSLocationInRange(selection.location, run.range)
        }
    }

    /// No bar inside ``` ``` ```: there `**` is two asterisks in a program, not emphasis.
    /// Through `CodeFence.regions`, the same call that keeps `#` from being a tag in there.
    private func isInsideCodeFence(_ selection: NSRange) -> Bool {
        let text = string
        return CodeFence.regions(in: text).contains { region in
            let fence = NSRange(region.range, in: text)
            return fence.location != NSNotFound && NSIntersectionRange(fence, selection).length > 0
        }
    }

    private func appliedFormats(over selection: NSRange) -> Set<InlineFormat> {
        let text = string
        return Set(InlineFormat.allCases.filter {
            InlineFormat.isApplied($0, in: text, over: selection)
        })
    }

    /// The line the bar hangs off, and which side of it.
    ///
    /// **The last line of the selection, not the first.** Anchoring to the first was the plan's
    /// decision and it was wrong the moment it was looked at: dragging from a heading down
    /// through a paragraph put the bar at the top of the note, centimetres from where the
    /// mouse had stopped. The end of the selection is where the hand is.
    ///
    /// The side follows from that. A one-line selection keeps the mockup's answer, above it,
    /// where nothing of the selection is covered. A selection spanning several lines takes the
    /// other side: above its last line is the middle of the selection, which is the one place
    /// the bar must not be.
    func formatBarAnchor(_ selection: NSRange) -> (rect: NSRect, side: PanelPlacement.Side) {
        let end = max(selection.location, NSMaxRange(selection) - 1)
        let lastLine = NSRange(location: end, length: min(1, (string as NSString).length - end))
        let rect = rectOnScreen(lastLine)
        let isOneLine = rectOnScreen(NSRange(location: selection.location, length: 1)).minY == rect.minY
        return (rect, isOneLine ? .above : .below)
    }

    private func rectOnScreen(_ range: NSRange) -> NSRect {
        let fromInputClient = firstRect(forCharacterRange: range, actualRange: nil)
        if fromInputClient.height > 0 { return fromInputClient }
        // TextKit 2 answers a zero rectangle for a range it has not laid out yet, which is the
        // same trap `caretRectOnScreen` documents - and a zero rectangle sent to a placement
        // rule puts the bar in the corner of the screen.
        return caretRectOnScreen()
    }

    /// Performs what a button asked for, as one undoable change.
    func applyFormat(_ action: FormatBar.Action) {
        let selection = selectedRange()
        guard selection.length > 0 else { return }
        let text = string

        let edit: (text: String, selection: NSRange)
        switch action {
        case let .format(format):
            edit = InlineFormat.toggled(format, in: text, over: selection)
        case .wikilink:
            edit = InlineFormat.wrapped(text, over: selection, in: "[[", "]]")
        case .link:
            // The caret lands between the brackets rather than after them: the address is the
            // part that still has to be typed, and a link written with an empty one is a link
            // that goes nowhere.
            let selected = (text as NSString).substring(with: selection)
            let replacement = "[\(selected)]()"
            edit = (
                (text as NSString).replacingCharacters(in: selection, with: replacement),
                NSRange(location: selection.location + (replacement as NSString).length - 1, length: 0)
            )
        }
        guard edit.text != text else { return }
        replaceWholeText(with: edit.text, selecting: edit.selection)
    }

    /// Writes `replacement` through AppKit rather than into `string`, so one press is one undo.
    private func replaceWholeText(with replacement: String, selecting selection: NSRange) {
        let whole = NSRange(location: 0, length: (string as NSString).length)
        guard shouldChangeText(in: whole, replacementString: replacement) else { return }
        textStorage?.replaceCharacters(in: whole, with: replacement)
        didChangeText()
        setSelectedRange(selection)
    }
}
