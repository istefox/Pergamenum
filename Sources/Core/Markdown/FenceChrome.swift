import Foundation

// ADR-0087 §D2 and §D6, plan docs/plans/note-workflow-n5.md, Task 1 (R-37).
//
// What the editor draws on a closed fence: its opening line as a header, its closing line quietly.
// Built over `CodeFence.regions(in:)`, never a second fence grammar. Foundation only (ADR-0001 §D1).

struct FenceChrome: Equatable, Sendable {
    /// The opening fence line, its line break excluded.
    var opening: Range<String.Index>
    /// The closing fence line, its line break excluded.
    var closing: Range<String.Index>
    /// The code between the fences; empty for a fence with nothing in it.
    var body: Range<String.Index>
    /// The declared language, as written, or nil.
    var language: String?
    /// How many lines the body holds; 0 for an empty fence.
    var lineCount: Int

    /// Every closed, non-`pergamenum-view` fence of `text`, in order.
    ///
    /// A region is closed when its body stops short of its end: an unclosed one runs both to the end
    /// of the text, the test `MarkdownStyler.viewBlockRuns` already makes. Regions that start inside
    /// the frontmatter are dropped, the filter the styler applies (a frontmatter holding a fence mark
    /// parts `CodeFence.regions` from the tokenizer's own fences).
    static func blocks(in text: String) -> [FenceChrome] {
        let bodyStart = NoteFrontmatter.range(in: text)?.upperBound ?? text.startIndex
        return CodeFence.regions(in: text).compactMap { region in
            region.range.lowerBound >= bodyStart ? FenceChrome(region: region, in: text) : nil
        }
    }

    /// The block whose opening line, body or closing line holds `utf16Offset`, if any.
    static func block(containing utf16Offset: Int, in text: String) -> FenceChrome? {
        let utf16 = text.utf16
        guard utf16Offset >= 0, utf16Offset <= utf16.count else { return nil }
        let index = utf16.index(utf16.startIndex, offsetBy: utf16Offset)
        return blocks(in: text).first { $0.opening.lowerBound <= index && index < $0.closing.upperBound }
    }

    /// «1 riga» or «N righe».
    var lineCountLabel: String { Self.lineCountLabel(lineCount) }

    /// The same label for a count read elsewhere (the editor's fence header, ADR-0087 §D6).
    static func lineCountLabel(_ lineCount: Int) -> String { lineCount == 1 ? "1 riga" : "\(lineCount) righe" }

    /// A closed region's chrome. The region's body runs to the closing line, so it ends with the
    /// last code line's break: the lines are counted by those breaks, and the last one is left out
    /// of `body`, which is what «Copia il blocco» copies.
    private static func chrome(of region: CodeFence.Region, in text: String) -> FenceChrome {
        let openingEnd = text[region.range].firstIndex(where: LineBreak.isTerminator) ?? region.range.upperBound
        let lineCount = text[region.body].filter(LineBreak.isTerminator).count
        var bodyEnd = region.body.upperBound
        if bodyEnd > region.body.lowerBound, LineBreak.isTerminator(text[text.index(before: bodyEnd)]) {
            bodyEnd = text.index(before: bodyEnd)
        }
        return FenceChrome(
            opening: region.range.lowerBound..<openingEnd,
            closing: region.body.upperBound..<region.range.upperBound,
            body: region.body.lowerBound..<bodyEnd,
            language: region.language,
            lineCount: lineCount
        )
    }
}

extension FenceChrome {
    /// One region's chrome, nil when the region is unclosed or a `pergamenum-view` block. The styler
    /// builds its spans through this over the fences it has already filtered, so a fragment of a
    /// note is never read for a frontmatter of its own. In an extension so the memberwise
    /// initialiser stays.
    init?(region: CodeFence.Region, in text: String) {
        guard region.language != ViewBlock.language, region.body.upperBound != region.range.upperBound
        else { return nil }
        self = Self.chrome(of: region, in: text)
    }
}
