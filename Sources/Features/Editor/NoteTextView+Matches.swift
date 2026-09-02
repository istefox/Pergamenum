import AppKit

/// Painting the find bar's matches on the note (SPEC §10, M8).
///
/// **Rendering attributes, not text attributes.** Under TextKit 2 a temporary attribute -
/// one that colours what is drawn without belonging to the string - lives on the
/// `NSTextLayoutManager`, which is where the spell checker's own underline turned out to be
/// on 2026-08-18. Two things follow, and both are the reason this is not a call to
/// `textStorage.addAttribute`:
///
/// - `applyStyling` calls `setAttributes` over the whole note on every keystroke, so a
///   highlight written into the storage would be wiped by the next character typed;
/// - a highlight in the storage is a change to the note's attributed string, and this
///   editor's document is its text. Nothing that is only a way of looking at the note
///   belongs in it.
extension NoteTextView.Coordinator {
    /// Draws `matches`, with the one at `current` told apart from the rest.
    ///
    /// Every match takes `accentMuted`; the current one takes `accentPrimary` with `onAccent`
    /// text, which is the mockup's answer and adds no token to the theme files. Telling *a*
    /// match from *the* match is the whole of navigating results, and it is the one thing a
    /// find does that nothing else in the editor does.
    func applyMatches(to textView: NSTextView, matches: [NSRange], current: Int?, theme: Theme) {
        guard let layout = textView.textLayoutManager,
              let content = layout.textContentManager
        else { return }

        // Cleared over the whole document first, and not over the previous matches: the text
        // may have changed since they were painted, so the ranges that carried the colour are
        // not necessarily the ranges that would be cleared.
        let whole = content.documentRange
        layout.removeRenderingAttribute(.backgroundColor, for: whole)
        layout.removeRenderingAttribute(.foregroundColor, for: whole)
        guard !matches.isEmpty else { return }

        for (index, match) in matches.enumerated() {
            guard let range = textRange(match, in: content) else { continue }
            let isCurrent = index == current
            layout.addRenderingAttribute(
                .backgroundColor,
                value: NSColor(theme.color(isCurrent ? .accentPrimary : .accentMuted)),
                for: range
            )
            if isCurrent {
                layout.addRenderingAttribute(
                    .foregroundColor, value: NSColor(theme.color(.onAccent)), for: range
                )
            }
        }
    }

    /// The `NSTextRange` an `NSRange` names, or nil where it names nothing.
    ///
    /// Nil is a real case rather than defensive noise: the matches were computed against the
    /// text as it was when the search last ran, and a keystroke between then and here moves
    /// every offset after it.
    private func textRange(_ range: NSRange, in content: NSTextContentManager) -> NSTextRange? {
        guard let start = content.location(content.documentRange.location, offsetBy: range.location),
              let end = content.location(start, offsetBy: range.length)
        else { return nil }
        return NSTextRange(location: start, end: end)
    }
}

// MARK: - Replacing

extension NoteTextView.Coordinator {
    /// Performs `replacements` as one undoable change.
    ///
    /// One undo group and not one per match: replace-all is a single act as far as the person
    /// who pressed «Tutti» is concerned, and forty presses of Cmd+Z to get back is not an undo.
    ///
    /// The order is the caller's and is load-bearing - **last match first**. Applied from the
    /// top, the first replacement moves every range after it by the difference in length and
    /// the second one lands in the wrong place; from the bottom, nothing an earlier range
    /// depends on has moved yet. `FindSession.replacements(in:)` is where that order is made.
    /// Whether this exact batch (by value: same ranges, same replacement text, same order)
    /// is the one `apply(_:to:)` just applied - see `lastAppliedReplacements`'s doc comment.
    func alreadyApplied(_ replacements: [(range: NSRange, text: String)]) -> Bool {
        replacements.map(\.range) == lastAppliedReplacements
            && replacements.map(\.text) == lastAppliedReplacementTexts
    }

    func apply(_ replacements: [(range: NSRange, text: String)], to textView: NSTextView) {
        guard !replacements.isEmpty else { return }
        lastAppliedReplacements = replacements.map(\.range)
        lastAppliedReplacementTexts = replacements.map(\.text)
        let length = (textView.string as NSString).length
        let ranges = replacements.map(\.range)
        let strings = replacements.map(\.text)
        // Every range checked against the text as it is now: these were computed when the
        // search last ran, and a keystroke since then moves the offsets after it. One stale
        // range would otherwise raise out of an AppKit call rather than be skipped.
        guard ranges.allSatisfy({ NSMaxRange($0) <= length }) else { return }
        let values = ranges.map { NSValue(range: $0) }
        guard textView.shouldChangeText(inRanges: values, replacementStrings: strings) else { return }

        textView.textStorage?.beginEditing()
        for (range, text) in replacements {
            textView.textStorage?.replaceCharacters(in: range, with: text)
        }
        textView.textStorage?.endEditing()
        textView.didChangeText()
    }
}
