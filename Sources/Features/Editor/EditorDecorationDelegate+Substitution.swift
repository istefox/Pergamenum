import AppKit

/// The two steps every attachment-drawing branch of the decoration delegate repeats
/// (ADR-0071 §D8, last paragraph). Both are non-isolated on purpose: the delegate is not
/// `@MainActor` and these run on the layout path.
extension EditorDecorationDelegate {
    /// The paragraph's marker of `kind` that still fits inside `range.length`, read from
    /// `hiddenMarkers[range.location]`. Nil when there is none or when its `NSMaxRange`
    /// runs past the paragraph. A zero-length marker is returned: the caller's guard
    /// decides what that means.
    ///
    /// The list, quote and checkbox branches read `hiddenMarkers[range.location]` again after
    /// this call, for the survivors they collapse (and the quote's link tooltips). That second
    /// read agrees with this one only because nothing writes `hiddenMarkers` between the two
    /// on the synchronous layout path: its one writer is `apply(hiddenMarkers:hidingMarkup:)`.
    func marker(of kind: HiddenMarker.Kind, at range: NSRange) -> HiddenMarker? {
        // The first marker of that kind, then the fit: a first one that runs past the
        // paragraph refuses the lookup rather than letting a later one of the same kind answer.
        guard let marker = (hiddenMarkers[range.location] ?? []).first(where: { $0.kind == kind }),
              NSMaxRange(marker.range) <= range.length
        else { return nil }
        return marker
    }

    /// Replaces the first character of `marker` (paragraph-relative) with `"\u{FFFC}"`,
    /// sets `.attachment` on it, and gives the rest of the marker `collapsedFont` when the
    /// marker is longer than one character. The paragraph's length never changes.
    static func substituteAttachment(
        _ attachment: NSTextAttachment, over marker: HiddenMarker, in copy: NSMutableAttributedString
    ) {
        let attachmentRange = NSRange(location: marker.range.location, length: 1)
        let restRange = NSRange(location: attachmentRange.location + 1, length: marker.range.length - 1)
        // A substitution, not an insertion: one character out, one in, the paragraph's own
        // length unmoved - `NSTextContentManager.h:120`'s constraint, which the table, view
        // block and embed branches all keep through this one place.
        copy.replaceCharacters(in: attachmentRange, with: "\u{FFFC}")
        copy.addAttribute(.attachment, value: attachment, range: attachmentRange)
        if restRange.length > 0 {
            copy.addAttribute(.font, value: collapsedFont, range: restRange)
        }
    }
}
