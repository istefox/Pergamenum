import AppKit

/// The size grammar, the resolve/clamp arithmetic and the handle's geometry for a drawn
/// embed's resize gesture (ADR-0019: "A drawn embed is resized by dragging it, and the
/// size is written into the note"). Plan
/// `docs/superpowers/plans/2026-08-23-ridimensionamento-maniglie-embed-editor.md`, Task 2.
///
/// Pure, modelled on `EmbedNavigation`/`Tests/EmbedNavigationTests.swift`: no `NSTextView`
/// state beyond an `NSTextContainer` read for its size, no `@MainActor`, nothing that
/// needs a window to run. ADR-0019 §D3 names three callers of the one clamp this type
/// carries - `EmbedAttachment.attachmentBounds` (what is drawn, Task 3), the drag's own
/// per-frame overlay (what is shown while dragging, Tasks 5-6) and the `mouseUp` commit
/// that formats the suffix (what is written, Task 7) - so that R-05 cannot disagree with
/// itself between the picture, the overlay and the file.
///
/// **Nothing here rewrites a recogniser.** `Attachment.embed(inLine:)` has been splitting
/// the wikilink's inner text on `|` and discarding the suffix since M1, and it stays
/// untouched: it lives in `Sources/Core`, compiled into `perg` and `pergamenum-mcp`, and
/// neither connector draws (ADR-0019 §D1). The reading below is the editor's own, beside
/// `embedRun(inLine:)` where the rest of the editor's embed recognition already lives, and
/// it tolerates the same leading indentation that function does.
enum EmbedResize {
    /// What an embed's own run says about its size, read by `written(inRun:)` - `nil`
    /// answers "no suffix at all", never a third case (ADR-0019 §D1, §D7).
    enum Written: Equatable {
        case width(CGFloat)
        case both(CGFloat, CGFloat)
    }

    /// One step of the drag gesture (ADR-0019 §D6), each carrying the point the mouse
    /// event reports, in the text view's own coordinate space.
    enum Phase {
        case began(CGPoint)
        case moved(CGPoint)
        case ended(CGPoint)
    }

    /// ADR-0019 §D3's geometric floor on either dimension. A constant, not a design
    /// token - the company of `TranscludedRendition.padding`/`.maximumBodyHeight`, not
    /// `ThemeEngine`.
    static let minimumSide: CGFloat = 80

    /// The column a drawn embed's width is clamped against: the live container's own
    /// width minus twice its line-fragment padding (ADR-0019 §D3) - the same source
    /// `applyTransclusions` already reads from `textView.textContainer?.size.width`, read
    /// fresh on every layout pass rather than pushed in and left to go stale across a
    /// window resize.
    ///
    /// No container, or one whose width is not a finite number - which is what a
    /// container that does not track its view's width reports - is *no constraint*,
    /// never a narrow one: `attachmentBounds` is asked for a size during passes where
    /// the container is nil, and answering `0` there would draw every picture at the
    /// floor for one frame.
    static func column(of textContainer: NSTextContainer?) -> CGFloat {
        guard let textContainer else { return .greatestFiniteMagnitude }
        let width = textContainer.size.width
        guard width.isFinite else { return .greatestFiniteMagnitude }
        return width - 2 * textContainer.lineFragmentPadding
    }

    /// Reads `|W` or `|WxH` off an embed's own run text (the marker substring
    /// `EditorDecorationDelegate.embedParagraph(at:storage:)` already re-reads through
    /// `stillSpellsAnEmbed`) - the wikilink spelling only. `![alt](file.est)` and a bare
    /// `![[file.est]]` both answer `nil`, and so does any suffix that is not exactly an
    /// integer width or an integer `WxH` pair with a lowercase `x` (ADR-0019 §D1, §D7).
    static func written(inRun run: String) -> Written? {
        guard let suffix = wikilink(inRun: run)?.suffix else { return nil }
        return parsed(suffix: suffix)
    }

    /// Whether a size could be written into `run` at all - the wikilink spelling, with or
    /// without a suffix already on it. ADR-0019 §D7: `![alt](file.est)` draws exactly as it
    /// does today and gets no handle, because Obsidian's verified sizing syntax exists only
    /// for `![[…]]` and SPEC's scope forbids inventing a second one.
    ///
    /// **This is the gate `.began` asks before it claims a press**
    /// (`NoteTextView+EmbedResize.swift`), and it goes through the same `wikilink(inRun:)`
    /// `rewritten(run:to:natural:)` does on purpose: a handle offered on a run the commit
    /// would then refuse is a gesture that ends in nothing, which reads as a broken drag
    /// rather than as a spelling that has no size syntax. `written(inRun:)` cannot answer
    /// this - it returns nil for a bare `![[foto.png]]` too, and that one *is* resizable.
    static func isSizable(run: String) -> Bool {
        wikilink(inRun: run) != nil
    }

    /// ADR-0019 §D3's one clamp, called from every one of its three sites: no written
    /// size resolves `natural` width-clamped to `column` with height scaled
    /// proportionally; `.width` clamps to `[minimumSide, column]` with height scaled
    /// proportionally to `natural`'s own aspect ratio; `.both` clamps its width the same
    /// way and its height to `[minimumSide, .infinity)` only, the free-aspect-ratio case.
    static func resolved(written: Written?, natural: CGSize, column: CGFloat) -> CGSize {
        let ratio = aspectRatio(of: natural)
        switch written {
        case nil:
            // R-06's starting size: today's behaviour plus a clamp, and *only* a clamp -
            // a picture smaller than the floor keeps its own size, because nobody asked
            // for it to be made bigger.
            let width = min(natural.width, ceiling(of: column))
            return CGSize(width: width, height: width * ratio)
        case .width(let requested):
            let width = clamped(width: requested, column: column)
            return CGSize(width: width, height: width * ratio)
        case .both(let requestedWidth, let requestedHeight):
            return CGSize(
                width: clamped(width: requestedWidth, column: column),
                height: max(minimumSide, requestedHeight)
            )
        }
    }

    /// The suffix `rewritten(run:to:natural:)` writes for `size`: `"W"` when its height is
    /// the proportional height for `W` (against `natural`'s aspect ratio) within a point
    /// after rounding, `"WxH"` otherwise - integers, lowercase `x`, the two forms ADR-0019
    /// §D7 verified and no third.
    static func suffix(for size: CGSize, natural: CGSize) -> String? {
        guard size.width.isFinite, size.height.isFinite, size.width >= 1, size.height >= 1 else { return nil }
        let width = size.width.rounded()
        let height = size.height.rounded()
        let proportional = (width * aspectRatio(of: natural)).rounded()
        guard abs(height - proportional) > 1 else { return "\(Int(width))" }
        return "\(Int(width))x\(Int(height))"
    }

    /// `run` rewritten to carry `size`'s suffix (`suffix(for:natural:)`) in place of
    /// whatever it already has - replacing an existing suffix rather than appending a
    /// second, adding one where `run` has none. `nil` when there is nothing to write: the
    /// CommonMark spelling (ADR-0019 §D7, no sizing syntax was verified for it) or a
    /// `size` that resolves to the same suffix `run` already carries - the zero-movement
    /// case ADR-0019 §D6 sends to `selectEmbed` instead of a write.
    static func rewritten(run: String, to size: CGSize, natural: CGSize) -> String? {
        guard let link = wikilink(inRun: run),
              let suffix = suffix(for: size, natural: natural),
              suffix != link.suffix
        else { return nil }
        // The whitespace the run sits in is given back untouched: the range Task 7
        // replaces is `drawnEmbedRange`'s, and an indented embed keeps its indentation.
        return link.leading + "![[" + link.target + "|" + suffix + "]]" + link.trailing
    }

    /// The 14-point square painted into the picture's own bottom-right corner, inset 3
    /// points from each edge (ADR-0019 §D5) - always inside `frame`, which is the property
    /// that keeps `frameForTextAttachment(at:)`, and therefore the click hit-test and the
    /// embed's accessibility frame, byte-identical to the geometry without a handle.
    static func handleRect(in frame: CGRect) -> CGRect {
        CGRect(
            x: frame.maxX - handleInset - handleSide,
            y: frame.maxY - handleInset - handleSide,
            width: handleSide,
            height: handleSide
        )
    }

    /// The 22-point square around `handleRect(in:)` that a mouse-down has to land in to
    /// claim the drag rather than fall through to `selectEmbed` (ADR-0019 §D6) - the
    /// ordinary allowance for a small control, bigger than the paint.
    static func handleHitRect(in frame: CGRect) -> CGRect {
        let grown = (handleHitSide - handleSide) / 2
        return handleRect(in: frame).insetBy(dx: -grown, dy: -grown)
    }

    /// The square ADR-0019 §D5 paints, the inset it is painted at, and the square §D6
    /// hit-tests. Private: three call sites, all above, and a handle whose paint and hit
    /// target disagreed would be the one defect this geometry exists to rule out.
    private static let handleSide: CGFloat = 14
    private static let handleInset: CGFloat = 3
    private static let handleHitSide: CGFloat = 22

    /// An embed run taken apart into the four pieces `rewritten(run:to:natural:)` puts
    /// back together, or `nil` for anything that is not the wikilink spelling.
    private struct Wikilink {
        /// The indentation the run was found with, and whatever followed it.
        var leading: String
        var trailing: String
        /// The inner text before the first `|` - the file, exactly as the note wrote it.
        var target: String
        /// The inner text after the first `|`, or `nil` when there is no pipe at all.
        /// Unvalidated on purpose: `written(inRun:)` decides whether it is a size, and
        /// `rewritten` only needs to know what it would be replacing.
        var suffix: String?
    }

    private static func wikilink(inRun run: String) -> Wikilink? {
        guard let start = run.firstIndex(where: { !$0.isWhitespace }),
              let last = run.lastIndex(where: { !$0.isWhitespace })
        else { return nil }
        let end = run.index(after: last)
        let trimmed = run[start..<end]
        guard trimmed.hasPrefix("![["), trimmed.hasSuffix("]]") else { return nil }
        let inner = trimmed.dropFirst(3).dropLast(2)
        guard !inner.contains("[["), !inner.contains("]]") else { return nil }
        let parts = inner.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        let target = String(parts[0])
        guard !target.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return Wikilink(
            leading: String(run[run.startIndex..<start]),
            trailing: String(run[end...]),
            target: target,
            suffix: parts.count > 1 ? String(parts[1]) : nil
        )
    }

    /// `"300"` and `"300x200"` and nothing else. A capital `X`, a dangling separator, a
    /// negative number, a non-ASCII digit and a word all answer `nil` rather than a
    /// guess: Obsidian's own syntax is what SPEC verified, and a suffix this app cannot
    /// read is a suffix it draws at the natural size instead of inventing one.
    private static func parsed(suffix: String) -> Written? {
        let parts = suffix.split(separator: "x", maxSplits: 1, omittingEmptySubsequences: false)
        guard let width = positiveInteger(parts[0]) else { return nil }
        guard parts.count > 1 else { return .width(width) }
        guard let height = positiveInteger(parts[1]) else { return nil }
        return .both(width, height)
    }

    private static func positiveInteger(_ text: Substring) -> CGFloat? {
        guard !text.isEmpty, text.allSatisfy({ $0.isASCII && $0.isNumber }),
              let value = Int(text), value > 0
        else { return nil }
        return CGFloat(value)
    }

    /// `natural`'s height per point of width. A rendition with no area - a placeholder
    /// that failed to draw, a PDF page of zero size - is treated as square rather than
    /// divided by, so no arithmetic here can produce a `NaN` that reaches a layout pass.
    private static func aspectRatio(of natural: CGSize) -> CGFloat {
        guard natural.width > 0, natural.height > 0, natural.width.isFinite, natural.height.isFinite
        else { return 1 }
        return natural.height / natural.width
    }

    private static func clamped(width: CGFloat, column: CGFloat) -> CGFloat {
        min(max(width, minimumSide), ceiling(of: column))
    }

    /// The column, never below the floor. `[80, column]` is an empty interval for a
    /// container narrower than 80 points, and an empty interval clamps to nothing
    /// usable: the floor wins, and R-05's "never past the column" holds for every column
    /// wide enough to contain a picture at all.
    private static func ceiling(of column: CGFloat) -> CGFloat {
        max(column, minimumSide)
    }
}
