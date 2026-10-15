import Foundation
@testable import Pergamenum

// ADR-0091 §D2, §D4 and §D5, plan docs/plans/per-paragraph-restyle.md, Task 1.
//
// The pure model of the editor's styling state, for `IncrementalStylerPropertyTests`: the text, a
// `RestyleScope`, the spans in emission order, the merged unspellable ranges and the paragraph-spacing
// ranges. It does what the coordinator will do, with nothing of AppKit in it:
//
// - `apply(_:over:)` turns a string edit into a `StorageEdit`, records it on the scope, and shifts the
//   spans and ranges with `StorageEdit`'s rules;
// - `restyle()` takes the scope's decision. `.full` recomputes everything with `spans(in:)`; `.lines(r)`
//   styles the fragment `r` with `FragmentContext(listSeed: scope.listSeed(at: r.location),
//   readsFrontmatter: r.location == 0)`, splices its spans, unspellable ranges and spacing in, and
//   absorbs the fragment's map;
// - `full(of:)` is the oracle: the whole text styled the way today's `applyStyling` reads it;
// - `coverage(_:)` renders a span list canonically as runs, each with the ordered stack of spans over
//   it. The styler applies spans in emission order and "later wins" is the only overlap rule, so equal
//   coverage means equal attributes.

struct ModelSpan: Equatable {
    var range: NSRange
    var span: MarkdownStyler.Span
}

/// A run of the text and the spans that cover it, in emission order.
struct CoverageRun: Equatable {
    var range: NSRange
    var stack: [MarkdownStyler.Span]
}

/// What a restyle leaves behind that the property test compares.
struct StylingState {
    var spans: [ModelSpan]
    var unspellable: [NSRange]
    var spacing: [NSRange]
}

struct IncrementalStylerModel {
    private(set) var text: String
    private(set) var scope: RestyleScope
    private(set) var state: StylingState

    init(text: String) {
        self.text = text
        scope = RestyleScope(text: text)
        state = Self.full(of: text)
    }

    // MARK: Edits

    /// Replaces `range` of the text with `replacement`, as a text storage would, and records it.
    mutating func apply(_ replacement: String, over range: NSRange) {
        let new = (text as NSString).replacingCharacters(in: range, with: replacement)
        let length = (replacement as NSString).length
        let edit = StorageEdit(range: NSRange(location: range.location, length: length), delta: length - range.length)
        scope.record(edit, in: new as NSString)
        state.spans = state.spans.compactMap { item in
            edit.shifted(item.range).map { ModelSpan(range: $0, span: item.span) }
        }
        state.unspellable = state.unspellable.flatMap { edit.clipped($0) }
        state.spacing = state.spacing.compactMap { edit.shifted($0) }
        text = new
    }

    // MARK: Restyle

    /// The decision the scope took for the edits applied since the last restyle, after the state it
    /// describes has been brought up to date; nil when nothing was applied.
    @discardableResult
    mutating func restyle() -> RestyleScope.Decision? {
        guard let decision = scope.take() else { return nil }
        switch decision {
        case .full:
            state = Self.full(of: text)
            scope = RestyleScope(text: text)
        case .lines(let dirty):
            let fragment = (text as NSString).substring(with: dirty)
            let context = MarkdownStyler.FragmentContext(
                listSeed: scope.listSeed(at: dirty.location), readsFrontmatter: dirty.location == 0
            )
            let styled = MarkdownStyler.spans(inFragment: fragment, context: context)
            let inFragment = Self.state(of: styled, in: fragment, offset: dirty.location)

            state.spans = state.spans.filter { !Self.intersects($0.range, dirty) } + inFragment.spans
            state.unspellable = MarkdownStyler.spliced(
                state.unspellable, replacing: dirty, with: inFragment.unspellable
            )
            let spacing = ProseParagraphSpacing.paragraphRanges(
                inFragment: fragment, offset: dirty.location, spans: styled
            )
            state.spacing = (state.spacing.filter { !Self.intersects($0, dirty) } + spacing)
                .sorted { $0.location < $1.location }
            scope.absorb(StructureMap(text: fragment), at: dirty.location, replacing: dirty)
        }
        return decision
    }

    private static func intersects(_ lhs: NSRange, _ rhs: NSRange) -> Bool {
        lhs.location < NSMaxRange(rhs) && rhs.location < NSMaxRange(lhs)
    }

    // MARK: The oracle

    /// The whole text styled the way `applyStyling(to:theme:)` reads it: every span, the merged
    /// ranges the spell checker skips, and the lines that take the paragraph gap.
    static func full(of text: String) -> StylingState {
        let styled = MarkdownStyler.spans(in: text)
        var result = state(of: styled, in: text, offset: 0)
        result.spacing = ProseParagraphSpacing.paragraphRanges(in: text, spans: styled)
        return result
    }

    /// `styled`, whose indices belong to `text`, as model spans `offset` units into the note, and the
    /// merged unspellable ranges of them. Spacing is left empty: it is asked of each path apart.
    private static func state(of styled: [MarkdownStyler.StyledRange], in text: String, offset: Int) -> StylingState {
        let length = (text as NSString).length
        var spans: [ModelSpan] = []
        var unspellable: [NSRange] = []
        for item in styled {
            let range = NSRange(item.range, in: text)
            guard range.location != NSNotFound, NSMaxRange(range) <= length, range.length > 0 else { continue }
            let shifted = NSRange(location: range.location + offset, length: range.length)
            spans.append(ModelSpan(range: shifted, span: item.span))
            if MarkdownStyler.suppressesSpellCheck(item.span) { unspellable.append(shifted) }
        }
        return StylingState(spans: spans, unspellable: MarkdownStyler.merged(unspellable), spacing: [])
    }

    // MARK: Coverage

    /// The text as runs, each with the ordered stack of spans that covers it, adjacent equal runs
    /// joined. A span list and another with the same coverage give every character the same
    /// attributes.
    static func coverage(_ spans: [ModelSpan]) -> [CoverageRun] {
        let valid = spans.filter { $0.range.length > 0 }
        let cuts = Set(valid.flatMap { [$0.range.location, NSMaxRange($0.range)] }).sorted()
        let byStart = valid.indices.sorted { valid[$0].range.location < valid[$1].range.location }

        var runs: [CoverageRun] = []
        var active: [Int] = []
        var next = 0
        for (start, end) in zip(cuts, cuts.dropFirst()) {
            while next < byStart.count, valid[byStart[next]].range.location <= start {
                let index = byStart[next]
                active.insert(index, at: active.firstIndex { $0 > index } ?? active.endIndex)
                next += 1
            }
            active.removeAll { NSMaxRange(valid[$0].range) <= start }
            guard !active.isEmpty else { continue }
            let stack = active.map { valid[$0].span }
            if let last = runs.last, NSMaxRange(last.range) == start, last.stack == stack {
                runs[runs.count - 1].range.length += end - start
            } else {
                runs.append(CoverageRun(range: NSRange(location: start, length: end - start), stack: stack))
            }
        }
        return runs
    }
}

// MARK: - Random edits

/// A fixed generator: the same seed gives the same edits on every machine.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

/// Edits drawn from an alphabet of structure: the SPEC's characters, and the tokens that open, close
/// and join the constructs the widening has to know about.
struct EditGenerator {
    var generator: SplitMix64
    private let atoms: [String]
    private let tokens: [String]
    private var inverse: (range: NSRange, replacement: String)?

    /// A cap on the text's size, so a run stays under 4 KB and a note cannot grow without bound.
    static let maxBytes = 3000

    /// The SPEC's alphabet: backtick, `|`, `-`, `#`, `[`, `]`, `>`, digits, spaces, newline, letters.
    static let structuralAtoms: [String] = [
        "a", "b", "c", "d", "e", "x", "ò", "é", "0", "1", "2", "7", " ", " ", " ", "\n", "\n", "\n", "`", "|", "-", "#",
        "[", "]", ">", ".",
    ]
    /// And the tokens a structure is made of.
    static let structuralTokens: [String] = [
        "```", "~~~", "```pergamenum-view\n", "---", "[[", "]]", "![[", "| --- |", "- ", "1. ", "> ", "\t", "\r\n",
        "\u{2028}", "\r", "*", "_", "~", "!", "| a | b |\n", "- [ ] ", "  - ", "# ", "**",
        // A closed code span. Since ADR-0087 §D5 a backtick run closes only at a run of the same length
        // (CommonMark), so the alphabet's lone backticks stopped pairing into spans on their own and
        // most texts held none: the non-vacuity floor of `expectEqualToFullRestyle` failed on five seeds.
        // This restores the generator's coverage of inline code; no assertion moved. `==x==` is the
        // other span ADR-0087 added to the inline grammar, and the closed emphasis runs are the spans
        // the same texts carry, so the alphabet draws them whole as well.
        "`x`", "==x==", "**x**", "*x*", "~~x~~",
    ]
    /// The text a structural run starts from: a closed code span, a highlight, strong and emphasis
    /// runs, so the first steps compare styled texts and not empty span lists (`proseStart`'s reason).
    /// Nothing here opens a fence, a table, a link or frontmatter: the run's edits do that.
    static let structuralStart = "`uno` ==due== **tre** *quattro*\n\n> citazione\n"
    /// Prose only: nothing here opens a fence, a table, a link or a block of frontmatter, so every edit
    /// is a local one. Lists, headings, quotes, emphasis and tags are line-local and stay in.
    static let proseAtoms: [String] = [
        "a", "b", "c", "d", "e", "x", "ò", "é", "0", "1", "2", "7", " ", " ", " ", "\n", "\n", "#", ">", ".", "*", "_",
        "!",
    ]
    static let proseTokens: [String] = ["1. ", "# ", "> ", "\t", "\r\n", "\u{2028}", "\r", "**", "  ", "#tag-uno "]
    /// The text a prose run starts from. Started from an empty text, the prose alphabet drifts to
    /// 40 to 100 bytes of mostly plain letters, and half of the restyles then compare two empty span
    /// lists (`expectEqualToFullRestyle`'s non-vacuity floor failed on five seeds). This one holds a
    /// heading, emphasis, a tag, nested list items, an ordered list and a quote, with no fence, no
    /// table, no bracket and no `---`, so it is line-local like the alphabet.
    static let proseStart = """
    # Titolo della prova

    Paragrafo con **grassetto**, *corsivo* e #tag-uno nel mezzo.

    - primo punto
      - figlio annidato
    1. uno
    2. due

    > citazione di prova

    Ultima riga di prosa.

    """

    init(seed: UInt64, atoms: [String] = EditGenerator.structuralAtoms, tokens: [String] = EditGenerator.structuralTokens) {
        generator = SplitMix64(seed: seed)
        self.atoms = atoms
        self.tokens = tokens
    }

    private mutating func piece() -> String {
        if Int.random(in: 0..<5, using: &generator) == 0 { return tokens.randomElement(using: &generator)! }
        return atoms.randomElement(using: &generator)!
    }

    private mutating func pieces(_ count: ClosedRange<Int>) -> String {
        (0..<Int.random(in: count, using: &generator)).map { _ in piece() }.joined()
    }

    /// The UTF-16 offset of every grapheme boundary of `text`, 0 and the length included.
    private static func boundaries(of text: String) -> [Int] {
        var offsets = [0]
        var offset = 0
        for character in text {
            offset += character.utf16.count
            offsets.append(offset)
        }
        return offsets
    }

    /// The next edit of `text`: an insert, a delete, a multi-line paste, the inverse of the previous
    /// edit (an undo), or one at offset 0, at the end, or into an empty text.
    mutating func next(for text: String) -> (range: NSRange, replacement: String) {
        let edit = draw(for: text)
        let old = (text as NSString).substring(with: edit.range)
        inverse = (NSRange(location: edit.range.location, length: (edit.replacement as NSString).length), old)
        return edit
    }

    private mutating func draw(for text: String) -> (range: NSRange, replacement: String) {
        let offsets = Self.boundaries(of: text)
        let length = offsets.last ?? 0
        func at(_ index: Int) -> NSRange { NSRange(location: offsets[index], length: 0) }

        if text.isEmpty { return (NSRange(location: 0, length: 0), pieces(1...4)) }
        if text.utf8.count > Self.maxBytes {
            let from = Int.random(in: 0..<offsets.count, using: &generator)
            let to = min(offsets.count - 1, from + Int.random(in: 100...600, using: &generator))
            return (NSRange(location: offsets[from], length: offsets[to] - offsets[from]), "")
        }

        let roll = Int.random(in: 0..<100, using: &generator)
        let index = Int.random(in: 0..<offsets.count, using: &generator)
        switch roll {
        case 0..<42:
            return (at(index), piece())
        case 42..<62:
            let to = min(offsets.count - 1, index + Int.random(in: 1...3, using: &generator))
            return (NSRange(location: offsets[index], length: offsets[to] - offsets[index]), "")
        case 62..<72:
            let to = min(offsets.count - 1, index + Int.random(in: 0...12, using: &generator))
            return (NSRange(location: offsets[index], length: offsets[to] - offsets[index]), pieces(2...7))
        case 72..<84:
            if let inverse, NSMaxRange(inverse.range) <= length {
                return (inverse.range, inverse.replacement)
            }
            return (at(index), piece())
        case 84..<89:
            return (NSRange(location: 0, length: 0), piece())
        case 89..<94:
            return (NSRange(location: length, length: 0), piece())
        default:
            // Replace a whole line's worth: where a line's kind changes under the edit.
            let to = min(offsets.count - 1, index + Int.random(in: 1...8, using: &generator))
            return (NSRange(location: offsets[index], length: offsets[to] - offsets[index]), piece())
        }
    }
}
