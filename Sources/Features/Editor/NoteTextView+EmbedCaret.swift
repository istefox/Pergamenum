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
            return replaceAtomically(range, with: "", in: textView)
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
    ///
    /// **The only mechanism either of this feature's two writes may use.** Backspace over
    /// a drawn embed calls it with `""` (ADR-0018 slice 3, Step 4) and the resize gesture's
    /// `mouseUp` calls it with the run rewritten to carry a size suffix (ADR-0019 §D7);
    /// generalising the deletion rather than writing a second edit path is what makes R-04
    /// - exactly one undo step per gesture, whatever its length - a property of there being
    /// only one edit rather than a rule someone has to keep. No `insertText`, no undo group
    /// opened by hand, and never a write through `parent.text`, which is the far end of the
    /// chain `didChangeText()` starts rather than a way into it.
    func replaceAtomically(_ range: NSRange, with replacement: String, in textView: NSTextView) -> Bool {
        let length = (textView.string as NSString).length
        guard NSMaxRange(range) <= length,
              textView.shouldChangeText(
                  inRanges: [NSValue(range: range)], replacementStrings: [replacement]
              )
        else { return false }
        textView.textStorage?.beginEditing()
        textView.textStorage?.replaceCharacters(in: range, with: replacement)
        textView.textStorage?.endEditing()
        textView.didChangeText()
        return true
    }

    /// Selects a drawn embed's whole run when the click landed on its picture (D5).
    ///
    /// False is what hands the click on to whoever is next in
    /// `NoteTextView.wire(_:to:)`'s chain, and then to `super` - the ordinary answer for
    /// every point of a note that is not a picture.
    func selectEmbed(at point: CGPoint, in textView: NSTextView) -> Bool {
        guard let run = drawnEmbedRun(at: point, in: textView) else { return false }
        textView.setSelectedRange(run)
        return true
    }

    /// The whole run of the drawn embed whose picture `point` landed on, or nil when it
    /// landed on none.
    ///
    /// The single fragment walk this file makes. `selectEmbed(at:in:)` asks for a
    /// selection and `embedMenu(at:in:)` asks for a menu, and both are the same question -
    /// *which picture, if any, does this point land on?* - so answering it twice is how a
    /// menu naming one embed while the selection highlighted another would come about.
    /// The same extraction `NoteTextView+EmbedResize.swift` already makes with
    /// `grabbedEmbed(at:in:)`, for the same reason.
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
    private func drawnEmbedRun(at point: CGPoint, in textView: NSTextView) -> NSRange? {
        guard decorations.hidesMarkup,
              let manager = textView.textLayoutManager, let content = manager.textContentManager
        else { return nil }
        let text = textView.string as NSString
        var hit: NSRange?
        _ = decoration(at: point, in: textView) { (fragment: NSTextLayoutFragment) in
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
            hit = run
            return true
        }
        return hit
    }

    /// The drawn embed's own context menu, or nil when the secondary click landed on no
    /// picture - which is what leaves `CompletingTextView.menu(for:)` to `super`, and the
    /// note with the contextual menu it has always had (ADR-0023 §D9, R-08).
    ///
    /// **The run is selected before the menu is built**, exactly as a primary click on the
    /// same picture would have selected it: a menu whose one entry is «Elimina» has to name
    /// something visible, and one opened over a picture while the selection stayed three
    /// paragraphs above would be asking about an embed nobody had pointed at.
    ///
    /// A stale run is refused here rather than at the write, and the entry is then never
    /// drawn at all: `EmbedContextMenu.deletionRange(forRun:textLength:)` is asked while the
    /// menu is being built, so a «Elimina» that could not write anything is not offered and
    /// then silently declined by `replaceAtomically(_:with:in:)`.
    func embedMenu(at point: CGPoint, in textView: NSTextView) -> NSMenu? {
        guard let run = drawnEmbedRun(at: point, in: textView),
              let range = EmbedContextMenu.deletionRange(
                  forRun: run, textLength: (textView.string as NSString).length
              )
        else { return nil }
        textView.setSelectedRange(run)
        let menu = NSMenu()
        for title in EmbedContextMenu.items() {
            let item = NSMenuItem(
                title: title, action: #selector(deleteEmbedFromMenu(_:)), keyEquivalent: ""
            )
            // An `NSMenuItem` holds its target weakly, so the target has to be something
            // that outlives the menu - the Coordinator is, SwiftUI keeping it for as long
            // as the view exists, and `MenuBarItem.entry(_:_:)` keeps its own alive for the
            // same reason. An entry whose target has gone greys itself out.
            item.target = self
            // Carried on the entry rather than kept on the Coordinator: what «Elimina»
            // deletes belongs to the click that opened this menu, and a pending deletion
            // held between the menu opening and a choice being made - or never made - is
            // state that can disagree with the note, which ADR-0018 §D3 keeps out of this
            // feature.
            item.representedObject = PendingEmbedDeletion(range: range, textView: textView)
            menu.addItem(item)
        }
        return menu
    }

    /// «Elimina», through the one edit path this feature's other two writes already take:
    /// the same `replaceAtomically(_:with:in:)` Backspace over a drawn embed calls with
    /// `""`, over the same range `EmbedNavigation` computes for it. The menu and the key
    /// are one deletion with two ways in, rather than two that agree today.
    @objc private func deleteEmbedFromMenu(_ sender: NSMenuItem) {
        guard let pending = sender.representedObject as? PendingEmbedDeletion else { return }
        _ = replaceAtomically(pending.range, with: "", in: pending.textView)
    }

    /// What one menu entry is about: the range the click already resolved and the view it
    /// resolved it in, so the action reads back exactly what was on screen when the menu
    /// opened rather than asking the layout a second question.
    private struct PendingEmbedDeletion {
        let range: NSRange
        let textView: NSTextView
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
