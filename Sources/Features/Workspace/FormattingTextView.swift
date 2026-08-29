import AppKit

/// The Workspace card's own `NSTextView` (ADR-0027 §D1).
///
/// A sibling of `CompletingTextView`, never a fork of it: the note editor's view carries about
/// forty inputs - titles, tags, slash commands, emoji, embeds, transclusions, folding, find
/// matches, outline ranges - and a canvas card has none of them. Nothing is extracted from that
/// class, which is also what keeps the protected `CompletingTextView+Pasteboard.swift` outside
/// this chain's blast radius (ADR-0027 §D9).
///
/// What it is for: draw a card's markdown source with `CardTextAttributes`, report where its
/// selection is **in its own coordinates**, and leave editing on Esc. Cmd+B/Cmd+I and the
/// formatting edits themselves arrive in the next slice; this file deliberately stops short of
/// them.
final class FormattingTextView: NSTextView {
    /// Esc: leave editing (SPEC §6.3).
    ///
    /// The card's editing surface used to be a SwiftUI `TextEditor` with an `.onKeyPress(.escape)`
    /// over it. A key press only reaches that modifier while SwiftUI's focus system holds the
    /// keyboard, and once an `NSTextView` is first responder AppKit does - so the handler has to
    /// live where the responder is, or Esc silently stops leaving the card.
    var onCancel: (() -> Void)?

    /// Read from the raw event rather than from `cancelOperation(_:)`, which is what the key
    /// looks like it should arrive as: AppKit's standard key bindings send Esc inside a text view
    /// to `complete:`, word completion, so the responder method that reads as its obvious home is
    /// not reliably called at all. A card has no completion to offer, so the key is taken here and
    /// never passed on.
    private static let escapeKeyCode: UInt16 = 53

    override func keyDown(with event: NSEvent) {
        guard event.keyCode == Self.escapeKeyCode else { return super.keyDown(with: event) }
        onCancel?()
    }

    /// The rectangle the current selection occupies, in **this view's own coordinates**.
    ///
    /// View-local on purpose and never a screen coordinate (ADR-0027 §D5): the board wraps its
    /// content in `.scaleEffect(zoom, anchor: .topLeading)` plus a `pan` offset, and a rectangle
    /// taken from `firstRect(forCharacterRange:)` - the way `FormatBarPanel` places the note
    /// editor's bar - is a screen rectangle that may know nothing about either. A card adds its
    /// own board origin to what this returns and the board overlay draws at `p * zoom + pan`, the
    /// transform `BoardMarquee` and `BoardGuides` already use.
    ///
    /// `nil` when there is no selection to point at: a caret is not a selection, and the floating
    /// bar exists only while there is one.
    func selectionFrameInView() -> CGRect? {
        let selection = selectedRange()
        guard selection.length > 0,
              let layoutManager = textLayoutManager,
              let contentManager = layoutManager.textContentManager,
              let start = contentManager.location(contentManager.documentRange.location, offsetBy: selection.location),
              let end = contentManager.location(start, offsetBy: selection.length),
              let range = NSTextRange(location: start, end: end)
        else { return nil }

        var union: CGRect?
        layoutManager.enumerateTextSegments(in: range, type: .selection) { _, frame, _, _ in
            union = union.map { $0.union(frame) } ?? frame
            return true
        }
        // The segments come back in the text container's space; the inset between the container
        // and the view is exactly `textContainerOrigin`, so adding it is the whole conversion.
        let origin = textContainerOrigin
        return union?.offsetBy(dx: origin.x, dy: origin.y)
    }

    // MARK: - Selection formatting (ADR-0027 §D1, plan
    // `2026-08-28-unificare-nota-e-testo-in-un-solo-strume` Task 5, R-03/R-04/R-05)

    /// Wraps or unwraps the current selection in `format`'s markdown markers.
    ///
    /// `InlineFormat.toggled` is reused verbatim, never reimplemented (C4 in the plan): it
    /// already carries the `isLongerMarker` guard against `****text**` and the two-shape
    /// unwrap rule (markers inside a drag-selection, markers outside a double-click selection).
    /// This method's own job is only the one-edit-per-press idiom that turns the pure result
    /// into a single undo step - `shouldChangeText(in:replacementString:)` →
    /// `textStorage.replaceCharacters` → `didChangeText()` → `setSelectedRange`, copied verbatim
    /// from `CompletingTextView+FormatBar.swift:103-109` rather than extracted from it: that
    /// file is a declared protected interface under `Sources/Features/Editor/`, outside this
    /// chain's edits (ADR §D9).
    func toggleInlineFormat(_ format: InlineFormat) {
        fatalError("not implemented")
    }

    /// Applies `format`'s line prefix (bullet/numbered/heading) to every line the current
    /// selection touches, via `LineFormat.toggled` (Task 2) through the same one-edit-per-press
    /// idiom as `toggleInlineFormat(_:)` above.
    func toggleLineFormat(_ format: LineFormat) {
        fatalError("not implemented")
    }

    /// Cmd+B → `.bold`, Cmd+I → `.italic`, every other key or modifier combination → `nil`.
    ///
    /// A pure mapping, deliberately taking the flags and the character apart from a whole
    /// `NSEvent`, so `performKeyEquivalent(with:)`'s own routing can be asserted without
    /// dispatching a live event through the responder chain - unreliable off-screen, and not
    /// what R-04 is actually about (plan Task 5: "assert against the key-event → action
    /// mapping, not against a real keystroke").
    ///
    /// `modifierFlags` is expected already masked to `.deviceIndependentFlagsMask`
    /// (`ShortcutSettings.swift:162`'s own convention for reading a key event's modifiers).
    /// Exactly `.command` and no more is what R-04's "no collision with any existing
    /// `ShortcutCommand` binding" requires: `newBoard` is Cmd+Shift+B and `toggleInspector` is
    /// Cmd+Opt+I (`ShortcutCommand.swift:215`, `:276`), so a stray Shift or Option held down
    /// alongside B/I must resolve to neither format here and fall through to those bindings.
    static func inlineFormat(
        forKeyEquivalent characters: String, modifierFlags: NSEvent.ModifierFlags
    ) -> InlineFormat? {
        fatalError("not implemented")
    }

    /// Routes Cmd+B/Cmd+I to `toggleInlineFormat(_:)` while the view is editable; returns
    /// `false` for everything else, letting the event fall through to
    /// `BoardChrome.swift:118-128`'s bare-key tool-shortcut suppression - a different and
    /// unaffected path, since a tool shortcut carries no modifier at all and Cmd+B/Cmd+I always
    /// carry one.
    ///
    /// Stubbed to `false` unconditionally rather than `fatalError`: this override sits in the
    /// live key-event path of every editable card text view, including ordinary typing in a
    /// hand-run Debug build, and a `fatalError` here would crash that flow the moment any
    /// Cmd-anything key event reached the view - not only a test that calls the method on
    /// purpose. `inlineFormat(forKeyEquivalent:modifierFlags:)` above is the stub the red tests
    /// actually target for R-04; this override is filled in alongside it.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        false
    }
}
