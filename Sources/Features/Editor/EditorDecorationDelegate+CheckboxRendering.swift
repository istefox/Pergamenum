import AppKit

/// The checkbox-rendering half of `EditorDecorationDelegate`'s substitution mechanism, split
/// out on its own the way `EditorDecorationDelegate+ListRendering.swift` already is (ADR-0028,
/// PG-086; plan `2026-08-31-pg-074-give-the-to-do-tool-an-interactiv`).
extension EditorDecorationDelegate {
    /// The checkbox branch of the substitution in `textContentStorage(_:textParagraphWith:)`:
    /// draws a task line's state marker as a real checkbox glyph
    /// (`TaskGlyphRendering.glyph(for:)`) in place of the coloured `[ ]`/`[x]`/`[>]`/`[-]`
    /// characters, collapsing the rest of the five-character marker (`- [`, `]`) into
    /// `collapsedFont` so the glyph is the only thing on screen where the marker was.
    ///
    /// One character out, one character in, never more - `listParagraph(at:storage:)`'s own
    /// invariant, and for the same reason: the displayed paragraph keeps its stored length
    /// (`NSTextContentManager.h:120`).
    ///
    /// Nil - leaving the raw source on screen exactly as today - whenever there is nothing to
    /// draw: no checkbox marker at this offset, the paragraph revealed because the caret is in
    /// it, or the marker gone stale against the real characters since the last styling pass.
    func checkboxParagraph(at range: NSRange, storage: NSTextStorage) -> NSTextParagraph? {
        guard !revealedParagraphs.contains(range.location) else { return nil }
        let markers = hiddenMarkers[range.location] ?? []
        guard let marker = markers.first(where: { $0.kind == .checkbox }),
              NSMaxRange(marker.range) <= range.length
        else { return nil }

        let text = storage.string as NSString
        let markerRange = NSRange(
            location: range.location + marker.range.location, length: marker.range.length
        )
        guard let state = Self.stillSpellsATaskMarker(text, at: markerRange) else { return nil }

        let copy = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: range))
        // The state character sits at offset 3 of the five-character marker (`- [x]`):
        // dash, space, opening bracket, state, closing bracket.
        copy.replaceCharacters(
            in: NSRange(location: marker.range.location + 3, length: 1),
            with: String(TaskGlyphRendering.glyph(for: state))
        )
        copy.addAttribute(
            .font, value: Self.collapsedFont,
            range: NSRange(location: marker.range.location, length: 3)
        )
        copy.addAttribute(
            .font, value: Self.collapsedFont,
            range: NSRange(location: marker.range.location + 4, length: 1)
        )
        // The paragraph's other markers, collapsed exactly as the generic path in the main
        // file would have collapsed them - `listParagraph`'s own reasoning, restated here:
        // this branch returns early, and a bold task line has to render both its checkbox
        // and its hidden `**` in the one paragraph the hook is allowed to hand back.
        for other in Self.survivors(among: markers.filter { $0.kind != .checkbox }, of: range, in: text) {
            copy.addAttribute(.font, value: Self.collapsedFont, range: other.range)
        }
        return NSTextParagraph(attributedString: copy)
    }

    /// Whether `range` still spells a whole task marker - `- [ ]`/`- [x]`/`- [>]`/`- [-]`, five
    /// characters exactly - read from the text as it is right now, and which state it names.
    /// The re-validation `checkboxParagraph(at:storage:)` needs before it draws, the same
    /// re-read `stillSpellsAListMarker` performs for a list item and for the same reason: the
    /// table is filled by the last styling pass, this is a later layout pass, and the two can
    /// go stale against each other.
    private static func stillSpellsATaskMarker(_ text: NSString, at range: NSRange) -> TaskItem.State? {
        guard range.location >= 0, range.length == 5, NSMaxRange(range) <= text.length else { return nil }
        let candidate = Array(text.substring(with: range))
        guard candidate.count == 5,
              candidate[0] == "-" || candidate[0] == "*",
              candidate[1] == " ", candidate[2] == "[", candidate[4] == "]"
        else { return nil }
        switch candidate[3] {
        case "x", "X": return .done
        case ">": return .rescheduled
        case "-": return .cancelled
        case " ": return .open
        default: return nil
        }
    }
}
