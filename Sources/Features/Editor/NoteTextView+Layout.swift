import AppKit

/// How many layouts took each path, and why the last whole one was whole (ADR-0093 §D1). A test seam
/// and a diagnostic, as `RestyleLog` is: nothing branches on it.
struct LayoutLog: Equatable, Sendable {
    /// Why a settle laid out the document range.
    enum WholeReason: Equatable, Sendable {
        case everythingOwed, widthChanged, foreignDelegate, lengthMismatch, killSwitch
    }

    var whole: Int = 0
    var ranged: Int = 0
    var empty: Int = 0
    /// Ranged settles in which an owed range could not be made an `NSTextRange`, so everything is owed
    /// again instead of the range being dropped.
    var unconverted: Int = 0
    var lastWholeReason: WholeReason?
    var lastRanges: [NSRange] = []
}

/// The part of TextKit's layout of the note that is no longer valid since the last grow-to-fit:
/// nothing, some ranges, or everything (ADR-0093 §D1). Owned by `NoteTextView.Coordinator`, fed by the
/// storage's processed edits (`hear`) and by the one door for a whole-document invalidation
/// (`invalidateWholeDocument(of:)`), and settled by `growToFitTheText` (`settle`).
///
/// A reference type because several parties write it: the storage callback, the grow-to-fit and the
/// three controllers' door calls (ADR-0074 §D2). It holds no text and is not persisted.
@MainActor
final class LayoutDebt {
    enum Owed: Equatable {
        case everything
        /// Sorted and disjoint, in the text as it now is.
        case ranges([NSRange])
    }

    private(set) var owed: Owed = .everything
    private(set) var log = LayoutLog()
    /// The container width the last layout was made at, nil until the first.
    private var laidOutWidth: CGFloat?
    /// The horizontal inset the last layout was made at, nil until the first. Past the readable-width
    /// cap the container is as wide as the cap whatever the pane does, so a resize moves only this.
    private var laidOutInset: CGFloat?
    /// The storage length as of the last edit heard or the last layout, nil until either.
    private var heardLength: Int?

    init() {}

    /// One processed storage edit, in the post-fixing range (ADR-0093 §D2): the owed ranges move past
    /// it by `StorageEdit`'s rule, its own range is owed (a deletion's empty one as the paragraph it
    /// joined), and a range that covers the whole text is everything.
    func hear(_ edit: StorageEdit, in storage: NSTextStorage) {
        heardLength = storage.length
        guard case .ranges(let ranges) = owed else { return }
        var added = edit.range
        if added.length == 0 {
            let text = storage.string as NSString
            added = text.paragraphRange(for: NSRange(location: min(added.location, text.length), length: 0))
        }
        var moved = ranges.flatMap { edit.clipped($0) }
        if added.length > 0 { moved.append(added) }
        let merged = Self.merged(moved)
        if let first = merged.first, first.location == 0, first.length >= storage.length {
            owed = .everything
        } else {
            owed = .ranges(merged)
        }
    }

    /// Everything is owed: the first use, a reinstalled delegate (ADR-0093 §D2).
    func oweEverything() {
        owed = .everything
    }

    /// The one door for a whole-document invalidation of a note editor (ADR-0093 §D3): everything is
    /// owed, and TextKit is told so.
    func invalidateWholeDocument(of textView: NSTextView) {
        owed = .everything
        guard let manager = textView.textLayoutManager else { return }
        manager.invalidateLayout(for: manager.documentRange)
    }

    /// Lays out what is owed (ADR-0093 §D4): the document range for any `WholeReason`, otherwise each
    /// owed range widened by a character on each side (TextKit invalidates the paragraph after an
    /// attribute edit with it), otherwise nothing. Then nothing is owed and the width is recorded, unless
    /// an owed range could not be converted to an `NSTextRange` (or the layout manager has no content
    /// manager): that range was not laid out, so everything is owed again rather than forgotten.
    func settle(_ textView: NSTextView, delegateIsCoordinator: Bool, forcesWhole: Bool) {
        guard let manager = textView.textLayoutManager else { return }
        let width = textView.textContainer?.size.width
        let inset = textView.textContainerInset.width
        let length = textView.textStorage?.length ?? 0
        var unconverted = false
        defer {
            owed = unconverted ? .everything : .ranges([])
            laidOutWidth = width
            laidOutInset = inset
            heardLength = length
        }
        if let reason = wholeReason(
            delegateIsCoordinator: delegateIsCoordinator, forcesWhole: forcesWhole, width: width, inset: inset, length: length
        ) {
            manager.ensureLayout(for: manager.documentRange)
            log.whole += 1
            log.lastWholeReason = reason
            return
        }
        guard case .ranges(let ranges) = owed, !ranges.isEmpty else {
            log.empty += 1
            return
        }
        let widened = Self.merged(ranges.compactMap { range in
            let start = max(0, range.location - 1)
            let end = min(length, NSMaxRange(range) + 1)
            return end > start ? NSRange(location: start, length: end - start) : nil
        })
        if let content = manager.textContentManager {
            for range in widened {
                guard let start = content.location(content.documentRange.location, offsetBy: range.location),
                      let end = content.location(start, offsetBy: range.length),
                      let textRange = NSTextRange(location: start, end: end)
                else {
                    unconverted = true
                    continue
                }
                manager.ensureLayout(for: textRange)
            }
        } else if !widened.isEmpty {
            unconverted = true
        }
        if unconverted { log.unconverted += 1 }
        log.ranged += 1
        log.lastRanges = widened
    }

    /// Why the next layout has to be the document range, or nil when the owed ranges are all of it.
    private func wholeReason(
        delegateIsCoordinator: Bool, forcesWhole: Bool, width: CGFloat?, inset: CGFloat, length: Int
    ) -> LayoutLog.WholeReason? {
        if forcesWhole { return .killSwitch }
        if owed == .everything { return .everythingOwed }
        // The record heard nothing another delegate took, so it vouches for nothing (ADR-0093 §D5).
        if !delegateIsCoordinator { return .foreignDelegate }
        // The container width or the inset moved: assigning an inset invalidates the layout of the whole
        // note with no storage edit, and the container does not move when it does (ADR-0093 §C2).
        if let laidOutWidth, laidOutWidth != width { return .widthChanged }
        if let laidOutInset, laidOutInset != inset { return .widthChanged }
        if let heardLength, heardLength != length { return .lengthMismatch }
        return nil
    }

    /// `ranges` sorted, with overlapping and adjacent ones joined.
    private static func merged(_ ranges: [NSRange]) -> [NSRange] {
        var result: [NSRange] = []
        for range in ranges.sorted(by: { $0.location < $1.location }) {
            if let last = result.last, range.location <= NSMaxRange(last) {
                result[result.count - 1] = NSUnionRange(last, range)
            } else {
                result.append(range)
            }
        }
        return result
    }
}
