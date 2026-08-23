import AppKit

/// The caret, Backspace/Delete and a click, taught the run a drawn embed occupies
/// (ADR-0018 slice 3, Step 4; D5's exception to the caret rule, for a picture rather
/// than a delimiter).
///
/// Wired the same way `onClickInMargin` already is: `CompletingTextView.claimsCommand`
/// for the keyboard half, a third check in `NoteTextView.wire(_:to:)`'s
/// `onClickInMargin` chain for the mouse half. `EmbedNavigation` is the pure core this
/// file feeds from `EditorDecorationDelegate.drawnEmbedRange(atParagraphStart:in:)` -
/// never the whole document, matching `applyReveal`'s own restraint: the keyboard half
/// runs on every arrow key.
extension NoteTextView.Coordinator {
    /// A keyboard command the completion panel did not already claim, translated to
    /// what `EmbedNavigation` needs - `nil` for every selector this feature has no
    /// opinion about, which is what leaves `CompletingTextView.doCommand(by:)` to try
    /// `super` next.
    private enum EmbedCommand {
        case move(EmbedNavigation.Direction, extending: Bool)
        case delete(EmbedNavigation.DeleteDirection)
    }

    private static func embedCommand(for selector: Selector) -> EmbedCommand? {
        switch selector {
        case #selector(NSResponder.moveLeft(_:)): .move(.left, extending: false)
        case #selector(NSResponder.moveRight(_:)): .move(.right, extending: false)
        case #selector(NSResponder.moveLeftAndModifySelection(_:)): .move(.left, extending: true)
        case #selector(NSResponder.moveRightAndModifySelection(_:)): .move(.right, extending: true)
        case #selector(NSResponder.deleteBackward(_:)): .delete(.backward)
        case #selector(NSResponder.deleteForward(_:)): .delete(.forward)
        default: nil
        }
    }

    /// Answers a keyboard command, or defers to `super` by returning `false` - `true`
    /// only when the caret actually meets a drawn embed's edge in a way `EmbedNavigation`
    /// recognises.
    ///
    /// **R4, the guard that matters most in this file:** `decorations.hidesMarkup` is
    /// checked here *and* inside `drawnEmbedRange` itself, because this function's own
    /// check is an optimisation and the delegate's is the one that must never be
    /// skipped - the failure mode of getting this wrong is Backspace eating twenty-seven
    /// characters of visible prose in one keystroke, which reads as file corruption
    /// rather than a missing feature.
    func claimsEmbedCommand(_ selector: Selector, in textView: NSTextView) -> Bool {
        guard decorations.hidesMarkup, let command = Self.embedCommand(for: selector) else { return false }
        let text = textView.string as NSString
        let selection = textView.selectedRange()
        let runs = drawnEmbedRuns(near: selection, in: text)
        guard !runs.isEmpty else { return false }

        switch command {
        case .move(let direction, let extending):
            guard let moved = EmbedNavigation.moved(
                selection: selection, direction: direction, extending: extending, drawnRuns: runs
            ) else { return false }
            textView.setSelectedRange(moved)
            return true
        case .delete(let direction):
            guard let range = EmbedNavigation.deletionRange(
                selection: selection, direction: direction, drawnRuns: runs, textLength: text.length
            ) else { return false }
            return deleteAtomically(range, in: textView)
        }
    }

    /// The drawn embed ranges near enough to `selection` to matter for
    /// `EmbedNavigation`: the paragraph each of `selection`'s two edges sits in, and the
    /// one right before each, since a run's own left edge can equal either a paragraph's
    /// start (the ordinary case) or, indentation tolerated (`embedRun(inLine:)`),
    /// somewhere just inside it.
    ///
    /// Never the whole document: at most four dictionary lookups through
    /// `drawnEmbedRange(atParagraphStart:in:)`, the same cost class `applyReveal`
    /// already pays on every arrow key.
    private func drawnEmbedRuns(near selection: NSRange, in text: NSString) -> [NSRange] {
        var starts: Set<Int> = []
        for edge in [selection.location, NSMaxRange(selection)] {
            starts.insert(text.paragraphRange(for: NSRange(location: edge, length: 0)).location)
            if edge > 0 {
                starts.insert(text.paragraphRange(for: NSRange(location: edge - 1, length: 0)).location)
            }
        }
        return starts.compactMap { decorations.drawnEmbedRange(atParagraphStart: $0, in: text) }
    }

    /// One undoable step, on the exact model of `NoteTextView+Matches.swift`'s own
    /// `apply(_:to:)`: `shouldChangeText` first, `beginEditing`/`replaceCharacters`/
    /// `endEditing`/`didChangeText()` after, and a stale range - the document moved on
    /// since `range` was computed - skipped rather than trusted, even though this call
    /// is synchronous end to end and the discipline is the same regardless.
    private func deleteAtomically(_ range: NSRange, in textView: NSTextView) -> Bool {
        let length = (textView.string as NSString).length
        guard NSMaxRange(range) <= length,
              textView.shouldChangeText(inRanges: [NSValue(range: range)], replacementStrings: [""])
        else { return false }
        textView.textStorage?.beginEditing()
        textView.textStorage?.replaceCharacters(in: range, with: "")
        textView.textStorage?.endEditing()
        textView.didChangeText()
        return true
    }

    /// Selects a drawn embed's whole run when the click landed on its picture (D5).
    ///
    /// `NSTextLayoutFragment.frameForTextAttachmentAtLocation:` answers in the
    /// fragment's own coordinate system (its header, verbatim) and `layoutFragmentFrame`
    /// is already in the text container's - the same two-space arithmetic
    /// `TranscludedLineFragment.renditionFrame` and
    /// `FoldedHeadingFragment.badgeFrame(at:)` already do, by adding a fragment-relative
    /// offset to a container-relative origin. `decoration(at:in:claimedBy:)` is reused
    /// rather than walked again by hand: every fragment here is a plain
    /// `NSTextLayoutFragment` (Step 3 draws an embed without a custom subclass), so the
    /// generic parameter is instantiated as the base class itself, and the claim closure
    /// below is what tells an embed's paragraph from an ordinary one.
    func selectEmbed(at point: CGPoint, in textView: NSTextView) -> Bool {
        guard decorations.hidesMarkup,
              let manager = textView.textLayoutManager, let content = manager.textContentManager
        else { return false }
        let text = textView.string as NSString
        return decoration(at: point, in: textView) { (fragment: NSTextLayoutFragment) in
            let paragraphStart = content.offset(
                from: content.documentRange.location, to: fragment.rangeInElement.location
            )
            guard let run = decorations.drawnEmbedRange(atParagraphStart: paragraphStart, in: text),
                  let attachmentLocation = content.location(
                      content.documentRange.location, offsetBy: run.location
                  )
            else { return false }
            guard let picture = Self.drawnPictureFrame(at: attachmentLocation, in: fragment),
                  picture.contains(Self.inContainer(point, of: textView))
            else { return false }
            textView.setSelectedRange(run)
            return true
        }
    }

    /// A drawn embed's picture, in the text container's own coordinates, or nil when the
    /// attachment at `location` occupies no space in `fragment` - which is what a
    /// paragraph that is not drawing a picture answers.
    ///
    /// Extracted rather than written twice: `handleRect(forEmbedAt:in:)`
    /// (`NoteTextView+EmbedResize.swift`, ADR-0019 §D6) needs the same frame the click
    /// above hit-tests against, and a handle whose corner disagreed with the picture's
    /// own corner by one rounding of the same two additions is the defect that would be
    /// hardest to see and hardest to explain. The two spaces are the same pair
    /// `TranscludedLineFragment.renditionFrame` and `FoldedHeadingFragment.badgeFrame(at:)`
    /// already bridge: `frameForTextAttachmentAtLocation:` answers in the fragment's own
    /// coordinate system (its header, verbatim) and `layoutFragmentFrame` is already in
    /// the container's.
    static func drawnPictureFrame(
        at location: any NSTextLocation, in fragment: NSTextLayoutFragment
    ) -> CGRect? {
        let local = fragment.frameForTextAttachment(at: location)
        guard !local.isEmpty else { return nil }
        let frame = fragment.layoutFragmentFrame
        return local.offsetBy(dx: frame.minX, dy: frame.minY)
    }
}
