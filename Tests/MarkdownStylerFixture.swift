import AppKit
import Foundation
@testable import Pergamenum

/// Shared helpers for the MarkdownStyler suites (moved out of `MarkdownStylerTests.swift`
/// when it was split; PG-144 Task 1).
enum MarkdownStylerFixture {
    static func spans(_ text: String) -> [MarkdownStyler.Span] {
        MarkdownStyler.spans(in: text).map(\.span)
    }

    static func styled(_ text: String, _ span: MarkdownStyler.Span) -> String? {
        guard let match = MarkdownStyler.spans(in: text).first(where: { $0.span == span }) else { return nil }
        return String(text[match.range])
    }

    /// Every range whose span `match` accepts, as the text it covers, in emission order (plan
    /// `note-workflow-n5.md`, Task 3: a count and a text per span, never a canonical dump).
    static func styledAll(_ text: String, where match: (MarkdownStyler.Span) -> Bool) -> [String] {
        MarkdownStyler.spans(in: text).filter { match($0.span) }.map { String(text[$0.range]) }
    }

    /// The same ranges in UTF-16 offsets, the unit the editor's tables are keyed in.
    static func utf16Ranges(_ text: String, where match: (MarkdownStyler.Span) -> Bool) -> [NSRange] {
        MarkdownStyler.spans(in: text).filter { match($0.span) }.map { NSRange($0.range, in: text) }
    }
}

/// The in-process editor the N5 hosted suites share (plan `note-workflow-n5.md`, Task 3): a real
/// `CompletingTextView` in an offscreen window, wired to a real `NoteTextView.Coordinator` the way
/// `TranscludedLineTests` and `HiddenFrontmatterPass` wire theirs, `hidesMarkup` on, the note styled,
/// the caret placed and the reveal applied before the first layout, so the fragments read back are
/// the ones the app would draw for that caret. Kept in this fixture file, which Task 3 lists, so the
/// suites do not each grow a copy (ADR-0051).
@MainActor
enum N5Editor {
    struct Built {
        let textView: CompletingTextView
        let coordinator: NoteTextView.Coordinator
        /// Kept alive so `undoManager` resolves for the length of a test.
        let window: NSWindow
        let theme: Theme
    }

    /// `text` styled in a 600 pt wide editor. `caret` is a UTF-16 offset, nil for the start of the note.
    static func build(
        _ text: String,
        hidesMarkup: Bool = true,
        revealsInlineSpans: Bool = false,
        width: CGFloat = 600,
        caret: Int? = nil,
        theme: Theme = .emergency,
        vault: NoteTextView.VaultInputs = .init(),
        outline: NoteTextView.OutlineInputs = .init()
    ) -> Built {
        let view = NoteTextView(
            text: .constant(text), theme: theme, noteTitles: [], tagSuggestions: [],
            hidesMarkup: hidesMarkup, revealsInlineSpans: revealsInlineSpans,
            onFollowLink: { _ in }, vault: vault, outline: outline
        )
        let coordinator = view.makeCoordinator()
        let textView = CompletingTextView(usingTextLayoutManager: true)
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 24, height: 20)
        textView.frame = CGRect(x: 0, y: 0, width: width, height: 800)
        textView.textContainer?.size = CGSize(width: width - 48, height: CGFloat.greatestFiniteMagnitude)
        coordinator.textView = textView
        textView.delegate = coordinator
        textView.textContentStorage?.delegate = coordinator.decorations
        textView.textLayoutManager?.delegate = coordinator.decorations
        textView.string = text
        let window = NSWindow(
            contentRect: textView.frame, styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentView = textView
        coordinator.applyStyling(to: textView, theme: theme)
        textView.setSelectedRange(NSRange(location: caret ?? 0, length: 0))
        coordinator.applyReveal(to: textView)
        textView.textLayoutManager?.ensureLayout(for: textView.textLayoutManager!.documentRange)
        return Built(textView: textView, coordinator: coordinator, window: window, theme: theme)
    }

    /// Every laid-out fragment, keyed by the UTF-16 offset of its paragraph.
    static func fragments(_ built: Built) -> [Int: NSTextLayoutFragment] {
        guard let manager = built.textView.textLayoutManager,
              let content = manager.textContentManager
        else { return [:] }
        var byOffset: [Int: NSTextLayoutFragment] = [:]
        manager.enumerateTextLayoutFragments(
            from: manager.documentRange.location, options: [.ensuresLayout]
        ) { fragment in
            byOffset[content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location)] = fragment
            return true
        }
        return byOffset
    }

    /// The paragraph starting at `offset` as the layout would receive it: the delegate's substitution,
    /// or the stored paragraph when the delegate substitutes nothing.
    static func displayed(_ built: Built, at offset: Int) -> NSAttributedString? {
        guard let storage = built.textView.textContentStorage, let text = built.textView.textStorage else { return nil }
        let range = (text.string as NSString).paragraphRange(for: NSRange(location: offset, length: 0))
        if let substituted = built.coordinator.decorations.textContentStorage(storage, textParagraphWith: range) {
            return substituted.attributedString
        }
        return text.attributedSubstring(from: range)
    }

    /// Whether the character at `offset` of the paragraph at `paragraph` is drawn collapsed.
    static func isConcealed(_ built: Built, paragraph: Int, at offset: Int) -> Bool {
        guard let shown = displayed(built, at: paragraph), offset - paragraph < shown.length else { return false }
        let font = shown.attribute(.font, at: offset - paragraph, effectiveRange: nil) as? NSFont
        return font == EditorDecorationDelegate.collapsedFont
    }

    /// The length the paragraph at `offset` has in the store and the length it has once displayed.
    static func lengths(_ built: Built, at offset: Int) -> (stored: Int, displayed: Int) {
        guard let text = built.textView.textStorage else { return (-1, -1) }
        let range = (text.string as NSString).paragraphRange(for: NSRange(location: offset, length: 0))
        return (range.length, displayed(built, at: offset)?.length ?? -1)
    }
}
