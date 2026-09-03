import AppKit

/// The table-rendering half of `EditorDecorationDelegate`'s substitution mechanism
/// (ADR-0029 §D4; plan `2026-09-02-editor-wysiwyg-unification`, Task 4), split out on its
/// own the way `+QuoteRendering.swift`/`+ListRendering.swift`/`+CheckboxRendering.swift`
/// already are - one self-contained concern, one `extension` file (`type_body_length`).
///
/// Replaces the Step 4.5 tracer-bullet probe that used to live here (a fixed trigger word,
/// "tableprobe", substituted for a `TableAttachment` with no grammar behind it) now that
/// probe 2 (ADR §D16) has already answered its one question - nested first-responder focus
/// inside an `NSTextAttachmentViewProvider` view works in a real `CompletingTextView`. This
/// file's own job is the real one: reading a `.table` `HiddenMarker` back and drawing the
/// grid `TableGridStore` already vended for it.
extension EditorDecorationDelegate {
    /// The table branch of the substitution in `textContentStorage(_:textParagraphWith:)`:
    /// swaps the header line's first character for `\u{FFFC}` carrying a `TableAttachment`
    /// wrapping `tableViews[range.location]`, and collapses the rest of the header line into
    /// `collapsedFont` - one character out, one in, the paragraph's own length unmoved,
    /// `embedParagraph(at:storage:)`'s own arithmetic (`NSTextContentManager.h:120`).
    ///
    /// Nil whenever there is nothing to draw: `hidesMarkup` off (§D9), no `.table` marker at
    /// this offset, no grid vended yet for it, or the marker gone stale against the real
    /// characters since the last styling pass.
    ///
    /// **It does not honour `revealedParagraphs`**, unlike the list, checkbox and blockquote
    /// branches and like the embed one: a drawn grid is not a delimiter that reveals under
    /// the caret (§D5's exception, ADR-0018 §D5's own). The caret never reaches the header
    /// line's pipes anyway - the delimiter and body rows are out of the layout and the header
    /// is one attachment character wide.
    func tableParagraph(at range: NSRange, storage: NSTextStorage) -> NSTextParagraph? {
        guard hidesMarkup else { return nil }
        let markers = hiddenMarkers[range.location] ?? []
        guard let marker = markers.first(where: { $0.kind == .table }),
              marker.range.length > 0,
              NSMaxRange(marker.range) <= range.length,
              let grid = tableViews[range.location]
        else { return nil }

        // The re-read every other branch of this file makes before it draws, in this one's
        // own currency: not "is this range still spelled the same" but "do the live
        // characters still parse as a table starting here" - the whole shape, because a
        // table is the one construct whose meaning spans several paragraphs and D8's reload
        // guard is about the shape, not about a delimiter (`stillSpells` answers `false` for
        // `.table` precisely so this branch owns the question).
        let text = storage.string as NSString
        guard Self.tableRun(in: text, atParagraphStart: range.location) != nil else { return nil }

        let copy = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: range))
        let attachmentRange = NSRange(location: marker.range.location, length: 1)
        let restRange = NSRange(location: attachmentRange.location + 1, length: marker.range.length - 1)

        let attachment = TableAttachment()
        attachment.gridView = grid
        // A substitution, not an insertion: one character out, one in, the paragraph's own
        // length unmoved - `NSTextContentManager.h:120`'s constraint and `embedParagraph`'s
        // own arithmetic, reused rather than restated.
        copy.replaceCharacters(in: attachmentRange, with: "\u{FFFC}")
        copy.addAttribute(.attachment, value: attachment, range: attachmentRange)
        if restRange.length > 0 {
            copy.addAttribute(.font, value: Self.collapsedFont, range: restRange)
        }
        return NSTextParagraph(attributedString: copy)
    }

    /// The table whose header line starts exactly at `offset`, read from the characters as
    /// they are right now, with the UTF-16 range of its whole source beside it.
    ///
    /// The one implementation of "is there still a table here", shared by the two passes
    /// that must agree about it: this file's own drawing branch above, and
    /// `NoteTextView+Tables.swift`'s commit (D8's reload guard). Two readings would be two
    /// answers, and the failure mode of them disagreeing is a commit writing over lines the
    /// grid is not drawing.
    ///
    /// `static`, in UTF-16, and taking an `NSString`: the drawing side is on no actor at all
    /// and the commit side is `@MainActor`, so nothing here may touch this object's state,
    /// and both sides already hold the text as an `NSString`.
    ///
    /// Nil when `offset` is not a paragraph's own start (a table moved by an edit above it no
    /// longer starts where the last pass recorded), or when the lines from there do not parse
    /// as a table at all (R-10: the pipes are prose).
    static func tableRun(in text: NSString, atParagraphStart offset: Int) -> (table: GFMTable, range: NSRange)? {
        guard offset >= 0, offset < text.length else { return nil }
        var lines: [String] = []
        var contentEnds: [Int] = []
        var cursor = offset

        // GFM's own end of a table - the first blank line or the first line with no pipe in
        // it - so the walk is the length of the table rather than of the note, however long
        // the note is. `GFMTable.parsed(header:rest:)` stops at exactly the same place; this
        // loop only avoids handing it the rest of the file to look at.
        while cursor < text.length {
            var start = 0, end = 0, contentsEnd = 0
            text.getParagraphStart(
                &start, end: &end, contentsEnd: &contentsEnd,
                for: NSRange(location: cursor, length: 0)
            )
            if lines.isEmpty, start != offset { return nil }
            let line = text.substring(with: NSRange(location: start, length: contentsEnd - start))
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, trimmed.contains("|") else { break }
            lines.append(line)
            contentEnds.append(contentsEnd)
            guard end > cursor else { break }
            cursor = end
        }

        guard let table = GFMTable.parse(lines[...]),
              table.lineRanges.count > 0, table.lineRanges.count <= contentEnds.count
        else { return nil }
        // The last body row's own end, its trailing newline excluded - R-05's "the blank line
        // after it excluded", which is also what a commit is entitled to write over.
        let last = contentEnds[table.lineRanges.count - 1]
        return (table, NSRange(location: offset, length: last - offset))
    }
}
