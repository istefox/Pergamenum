import Foundation

/// Wrapping a selection in markdown, and unwrapping it again (SPEC §10, M8).
///
/// The editor could not do this at all: `EditorCommand.Action.insert` writes at the caret, so
/// every entry in the slash catalogue starts something new and none of them surrounds
/// something already written.
///
/// Foundation only. This is under `Sources/Core`, which both connectors compile, so an
/// `import AppKit` here breaks `perg` and `pergamenum-mcp` rather than this file.
enum InlineFormat: String, CaseIterable, Sendable {
    // Ordered longest marker first, and that order is load-bearing rather than tidy: `*` is a
    // prefix of `**`, so a scan that met italic first would call every bold word italic.
    case bold
    case strikethrough
    case italic
    case code

    var marker: String {
        switch self {
        case .bold: "**"
        case .strikethrough: "~~"
        case .italic: "*"
        case .code: "`"
        }
    }

    /// Whether `range` is already wrapped in this format, which is what lights the button.
    ///
    /// True in both of the two shapes a person can produce, because both have to un-wrap:
    /// double-clicking `parola` inside `**parola**` selects the word and leaves the markers
    /// outside it, while dragging across the whole thing puts them inside.
    static func isApplied(_ format: Self, in text: String, over range: NSRange) -> Bool {
        wrapping(format, in: text, over: range) != nil
    }

    /// The note after toggling `format` over `range`, and where the selection ends up.
    ///
    /// The selection afterwards covers the same words whichever of the two shapes it started
    /// as, because otherwise the second press of the same button would act on something
    /// different from the first and toggling would not round-trip.
    static func toggled(
        _ format: Self, in text: String, over range: NSRange
    ) -> (text: String, selection: NSRange) {
        let haystack = text as NSString
        let clamped = NSIntersectionRange(range, NSRange(location: 0, length: haystack.length))
        // An empty selection is a no-op rather than a bare pair of markers: pressing bold with
        // nothing selected would otherwise leave `****` in the note and the caret in the middle
        // of it, which is a state nobody asked for and has to be deleted by hand.
        guard clamped.length > 0 else { return (text, range) }

        if let wrapped = wrapping(format, in: text, over: clamped) {
            return unwrapped(format, in: haystack, removing: wrapped)
        }
        let marker = format.marker
        let selected = haystack.substring(with: clamped)
        let replaced = haystack.replacingCharacters(
            in: clamped, with: marker + selected + marker
        )
        return (
            replaced,
            NSRange(location: clamped.location + (marker as NSString).length, length: clamped.length)
        )
    }

    /// Surrounds a selection with a pair that is not a toggle - `[[` and `]]`, whose opening
    /// and closing differ, and which have nothing to un-wrap because a wikilink is a thing you
    /// make rather than a style you turn on.
    static func wrapped(
        _ text: String, over range: NSRange, in opening: String, _ closing: String
    ) -> (text: String, selection: NSRange) {
        let haystack = text as NSString
        let clamped = NSIntersectionRange(range, NSRange(location: 0, length: haystack.length))
        guard clamped.length > 0 else { return (text, range) }
        let selected = haystack.substring(with: clamped)
        return (
            haystack.replacingCharacters(in: clamped, with: opening + selected + closing),
            NSRange(
                location: clamped.location + (opening as NSString).length, length: clamped.length
            )
        )
    }

    // MARK: Which of the two shapes

    /// The range **including** the markers, when `range` is wrapped in `format`. Nil when it
    /// is not.
    private static func wrapping(
        _ format: Self, in text: String, over range: NSRange
    ) -> NSRange? {
        let haystack = text as NSString
        let clamped = NSIntersectionRange(range, NSRange(location: 0, length: haystack.length))
        guard clamped.length > 0 else { return nil }
        let marker = format.marker as NSString

        // Markers inside the selection: `**parola**` selected whole.
        if clamped.length >= marker.length * 2 {
            let opening = NSRange(location: clamped.location, length: marker.length)
            let closing = NSRange(location: NSMaxRange(clamped) - marker.length, length: marker.length)
            if haystack.substring(with: opening) == marker as String,
               haystack.substring(with: closing) == marker as String,
               !isLongerMarker(format, in: haystack, opening: opening, closing: closing, inward: true) {
                return clamped
            }
        }

        // Markers outside it: `parola` selected inside `**parola**`.
        let before = NSRange(location: clamped.location - marker.length, length: marker.length)
        let after = NSRange(location: NSMaxRange(clamped), length: marker.length)
        guard before.location >= 0, NSMaxRange(after) <= haystack.length,
              haystack.substring(with: before) == marker as String,
              haystack.substring(with: after) == marker as String,
              !isLongerMarker(format, in: haystack, opening: before, closing: after, inward: false)
        else { return nil }
        return NSRange(location: before.location, length: clamped.length + marker.length * 2)
    }

    /// Whether what looks like this format's marker is really the tail of a longer one.
    ///
    /// The trap this exists for: `**parola**` is bold, and asking whether it is *italic* finds
    /// a `*` on each side and says yes. A bold word that reports itself italic lights the wrong
    /// button and, worse, un-wraps by removing one asterisk of two and leaving `*parola*`.
    ///
    /// `inward` distinguishes the two shapes `wrapping(_:in:over:)` calls this from: with
    /// `**parola**` selected whole (inward), the second `*` of a longer marker sits further
    /// *into* the selection than `opening`/`closing` already found - `**` opening is markers
    /// `[0,1)` and `[0,2)` both start at the same point. With `parola` selected inside
    /// `**parola**` (outward), it sits further *outside* the selection - `**` before `parola`
    /// is markers `[-2,-1)` and `[-2,0)` both end at the same point. Checking the same direction
    /// for both shapes finds nothing for whichever shape it's wrong for, exactly the bug this
    /// parameter exists to close: the inward case used the outward formula and never matched.
    private static func isLongerMarker(
        _ format: Self, in haystack: NSString, opening: NSRange, closing: NSRange, inward: Bool
    ) -> Bool {
        allCases.contains { longer in
            let candidate = longer.marker as NSString
            guard candidate.length > (format.marker as NSString).length,
                  candidate.hasSuffix(format.marker)
            else { return false }
            let extra = candidate.length - (format.marker as NSString).length
            let wider = inward
                ? NSRange(location: opening.location, length: candidate.length)
                : NSRange(location: opening.location - extra, length: candidate.length)
            let widerClosing = inward
                ? NSRange(location: closing.location - extra, length: candidate.length)
                : NSRange(location: closing.location, length: candidate.length)
            guard wider.location >= 0, NSMaxRange(wider) <= haystack.length,
                  widerClosing.location >= 0, NSMaxRange(widerClosing) <= haystack.length
            else { return false }
            return haystack.substring(with: wider) == candidate as String
                && haystack.substring(with: widerClosing) == candidate as String
        }
    }

    private static func unwrapped(
        _ format: Self, in haystack: NSString, removing wrapped: NSRange
    ) -> (text: String, selection: NSRange) {
        let marker = (format.marker as NSString).length
        let inner = NSRange(location: wrapped.location + marker, length: wrapped.length - marker * 2)
        let kept = haystack.substring(with: inner)
        return (
            haystack.replacingCharacters(in: wrapped, with: kept),
            NSRange(location: wrapped.location, length: inner.length)
        )
    }
}
