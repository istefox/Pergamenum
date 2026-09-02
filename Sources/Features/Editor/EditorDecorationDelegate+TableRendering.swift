import AppKit

/// Tracer-bullet probe for ADR-0029 §D16 probe 2 (Step 4.5) - not Task 4's real table
/// branch, which reads `GFMTable` ranges out of `MarkdownStyler.spans(in:)` (Task 3, not
/// built yet). This probe recognises one fixed trigger word instead, so the one mechanism
/// under test - a real `TableAttachment` reaching a real `CompletingTextView` through the
/// same length-preserving substitution `embedParagraph(at:storage:)` already performs
/// (`EditorDecorationDelegate.swift:339`) - can be exercised without Task 3's grammar.
extension EditorDecorationDelegate {
    /// The paragraph text (trailing newline excluded) that triggers the probe grid. Type
    /// this alone on a line, with `hidesMarkup` on (the default), to see it render.
    static let tableProbeTrigger = "tableprobe"

    /// Registers the one grid this probe ever draws - handed over from the Coordinator, on
    /// the main actor, the same crossing `apply(embeds:)` already makes (ADR §D6: "the
    /// delegate carries a reference and calls nothing").
    func apply(tableGridView view: TableGridView?) {
        tableGridView = view
    }

    /// The probe's own branch of `textContentStorage(_:textParagraphWith:)`'s substitution:
    /// swaps the trigger word's first character for `\u{FFFC}` carrying a `TableAttachment`,
    /// collapsing the rest - one character out, one in, the paragraph's own length unmoved,
    /// exactly `embedParagraph(at:storage:)`'s arithmetic. Nil whenever there is nothing to
    /// draw: no grid registered yet, or the paragraph is not exactly the trigger word.
    func tableParagraph(at range: NSRange, storage: NSTextStorage) -> NSTextParagraph? {
        guard let gridView = tableGridView else { return nil }
        let text = storage.string as NSString
        let line = text.substring(with: range)
        let body = line.hasSuffix("\n") ? String(line.dropLast()) : line
        guard body == Self.tableProbeTrigger else { return nil }

        let copy = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: range))
        let attachmentRange = NSRange(location: 0, length: 1)
        let restRange = NSRange(location: 1, length: Self.tableProbeTrigger.count - 1)

        let attachment = TableAttachment()
        attachment.gridView = gridView
        copy.replaceCharacters(in: attachmentRange, with: "\u{FFFC}")
        copy.addAttribute(.attachment, value: attachment, range: attachmentRange)
        if restRange.length > 0 {
            copy.addAttribute(.font, value: Self.collapsedFont, range: restRange)
        }
        return NSTextParagraph(attributedString: copy)
    }
}
