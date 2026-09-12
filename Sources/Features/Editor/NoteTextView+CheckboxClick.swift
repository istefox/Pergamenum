import AppKit

/// The note editor's half of PG-074's click-to-toggle checkbox, wired through
/// `CompletingTextView.onToggleCheckbox` (`CompletingTextView+Pasteboard.swift`'s
/// `mouseDown`, asked before `super`). Mirrors
/// `Sources/Features/Workspace/FormattingTextView.claimsCheckbox` on purpose: same fragment
/// walk, same re-validation of the raw characters, same glyph-rect hit test - the two surfaces
/// must agree pixel-for-pixel on what counts as "the checkbox", not merely on what a checkbox
/// click means.
extension NoteTextView.Coordinator {
    /// Whether a task line's checkbox glyph is under `point`, toggling its state when one is.
    ///
    /// **Not gated on any editability flag** - a task list you must double-click into before
    /// ticking a box is not the interactive list SPEC §6.4 asks for (the same call
    /// `FormattingTextView.claimsCheckbox`'s own comment records). The click still has to land
    /// on the glyph's own drawn rect, never merely somewhere on the task's line: everywhere else
    /// falls through to `super.mouseDown`, caret placement and reveal-on-caret exactly as before
    /// this feature existed.
    ///
    /// The write goes through `replaceAtomically(_:with:in:)`
    /// (`NoteTextView+EmbedCaret.swift`), the app's one edit path, so the toggle costs one undo
    /// step - never `VaultController.toggle(_:)`, which writes through the vault session and
    /// would ignore an unsaved edit sitting in this buffer.
    func toggleCheckbox(at point: CGPoint, in textView: NSTextView) -> Bool {
        guard let manager = textView.textLayoutManager else { return false }
        let origin = textView.textContainerOrigin
        let inContainer = CGPoint(x: point.x - origin.x, y: point.y - origin.y)
        let text = textView.string as NSString

        var handled = false
        manager.enumerateTextLayoutFragments(
            from: manager.documentRange.location, options: [.ensuresLayout]
        ) { fragment in
            let range = fragment.rangeInElement
            let offset = manager.offset(from: manager.documentRange.location, to: range.location)
            let length = manager.offset(from: range.location, to: range.endLocation)
            guard length > 0, offset >= 0, offset + length <= text.length,
                  let stateOffset = Self.checkboxStateOffset(
                      in: text.substring(with: NSRange(location: offset, length: length))
                  )
            else { return true }

            guard let stateStart = manager.location(range.location, offsetBy: stateOffset),
                  let stateEnd = manager.location(stateStart, offsetBy: 1),
                  let stateRange = NSTextRange(location: stateStart, end: stateEnd)
            else { return true }

            var glyphFrame: CGRect?
            manager.enumerateTextSegments(in: stateRange, type: .standard) { _, frame, _, _ in
                glyphFrame = frame
                return true
            }
            guard let glyphFrame, glyphFrame.contains(inContainer) else { return true }

            handled = toggleTaskLine(atParagraphOffset: offset, in: textView)
            return false
        }
        return handled
    }

    /// The offset, within a paragraph's own text, of the state character in its task marker -
    /// dash-or-star, space, `[`, state, `]`, after any leading indentation. Nil for a line that
    /// is not a task line, or one too short to hold a whole five-character marker.
    ///
    /// Restated from `FormattingTextView.checkboxStateOffset(in:)` rather than shared: that file
    /// is the Workspace card's, outside this feature's edits, and a shared helper would mean
    /// editing it (the same call `NoteTextView+Transclusion.decoration(in:claimedBy:)`'s own
    /// comment makes about `claimsFoldBadge`).
    private static func checkboxStateOffset(in paragraph: String) -> Int? {
        let indent = paragraph.prefix { $0 == " " || $0 == "\t" }.count
        let characters = Array(paragraph)
        guard characters.count >= indent + 5,
              characters[indent] == "-" || characters[indent] == "*",
              characters[indent + 1] == " ", characters[indent + 2] == "[", characters[indent + 4] == "]"
        else { return nil }
        return indent + 3
    }

    /// Toggles the task line whose paragraph starts at `offset`, writing through
    /// `replaceAtomically(_:with:in:)` so the edit is one undo step. False when the line no
    /// longer parses as a task by the time the write is attempted - the fragment walk above
    /// re-reads the raw characters just before this call, but a stale offset is still handled
    /// the same way every other write path in this file handles one: declined, not guessed.
    private func toggleTaskLine(atParagraphOffset offset: Int, in textView: NSTextView) -> Bool {
        let text = textView.string as NSString
        let lineRange = text.lineRange(for: NSRange(location: offset, length: 0))
        let line = text.substring(with: lineRange)
        // `TaskParser.parse(line:...)` stores its argument verbatim as `TaskItem.rawLine`
        // (`TaskParser.swift:56`), and every other producer of a `rawLine` in this codebase -
        // the index scan `VaultController.toggle(_:)` reads from - hands it over without a
        // trailing terminator. `lineRange` includes one (`NSString.lineRange(for:)`'s own
        // contract), so it has to come off here or `TaskParser.line(for:settingState:today:)`
        // appends `@done(...)` after an embedded `\n` instead of after the task's own text -
        // `trimmingTrailingWhitespace()` strips spaces and tabs, never a newline sitting mid-
        // string once another line's `" @done(...)"` prefix is added.
        let hasTrailingNewline = line.hasSuffix("\n")
        let content = hasTrailingNewline ? String(line.dropLast()) : line
        guard let task = TaskParser.parse(line: content, sourcePath: "", lineIndex: 0) else { return false }

        let newState: TaskItem.State = task.state == .done ? .open : .done
        var newLine = TaskParser.line(for: task, settingState: newState, today: .today)
        if hasTrailingNewline { newLine += "\n" }

        return replaceAtomically(lineRange, with: newLine, in: textView)
    }
}
