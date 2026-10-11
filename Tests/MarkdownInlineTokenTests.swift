import Foundation
import Testing
@testable import Pergamenum

// ADR-0082 §D1, plan docs/plans/pg-385-n2-page.md, Task 2 (PG-385, R-18).
//
// `MarkdownInlineParser.tokens(in:)`: the inline scanner, unchanged in its rules, reporting
// ranges. Red until Task 3 declares the real token layer (the stub answers `[]`). Ranges are
// compared as the text they cover. Where the plan names a construct but not the exact shape of
// its delimiter ranges, only the part the SPEC states is pinned (the payload, the range, that
// the delimiters are the delimiters); the corpus (`StylerGoldenTests`) pins the rest.

private func tokens(_ text: String) -> [MarkdownInlineToken] {
    MarkdownInlineParser.tokens(in: text[...])
}

private func slice(_ text: String, _ range: Range<String.Index>) -> String {
    String(text[range])
}

private func delimiters(of token: MarkdownInlineToken, in text: String) -> [String] {
    switch token.kind {
    case .code(let ranges), .strong(let ranges), .emphasis(let ranges), .strikethrough(let ranges):
        ranges.map { slice(text, $0) }
    default:
        []
    }
}

@Suite struct MarkdownInlineTokens {
    // MARK: Delimited spans

    // (n2-page R-18)
    @Test func strongCarriesItsTwoDelimiters() throws {
        let text = "**forte**"
        let token = try #require(tokens(text).first)
        #expect(tokens(text).count == 1)
        guard case .strong = token.kind else {
            Issue.record("not strong: \(token.kind)")
            return
        }
        #expect(slice(text, token.range) == "**forte**")
        #expect(delimiters(of: token, in: text) == ["**", "**"])
    }

    // (n2-page R-18)
    @Test func emphasisCarriesItsTwoDelimiters() throws {
        let text = "*corsivo*"
        let token = try #require(tokens(text).first)
        guard case .emphasis = token.kind else {
            Issue.record("not emphasis: \(token.kind)")
            return
        }
        #expect(slice(text, token.range) == "*corsivo*")
        #expect(delimiters(of: token, in: text) == ["*", "*"])
    }

    // (n2-page R-18)
    @Test func strikethroughCarriesItsTwoDelimiters() throws {
        let text = "~~barrato~~"
        let token = try #require(tokens(text).first)
        guard case .strikethrough = token.kind else {
            Issue.record("not strikethrough: \(token.kind)")
            return
        }
        #expect(delimiters(of: token, in: text) == ["~~", "~~"])
    }

    // (n2-page R-18)
    @Test func codeCarriesItsTwoDelimiters() throws {
        let text = "`codice`"
        let token = try #require(tokens(text).first)
        guard case .code = token.kind else {
            Issue.record("not code: \(token.kind)")
            return
        }
        #expect(slice(text, token.range) == "`codice`")
        #expect(delimiters(of: token, in: text) == ["`", "`"])
    }

    // MARK: Flanking (PG-347, #762)

    // (n2-page R-18) `_a_` is emphasis, with its underscores as delimiters.
    @Test func anUnderscorePairAtWordBoundariesIsEmphasis() throws {
        let text = "_a_"
        let token = try #require(tokens(text).first)
        guard case .emphasis = token.kind else {
            Issue.record("not emphasis: \(token.kind)")
            return
        }
        #expect(delimiters(of: token, in: text) == ["_", "_"])
    }

    // (n2-page R-18) `file_name_here`, `2 * 3 * 4` and `nome_file_lungo` read as plain text.
    @Test(arguments: ["file_name_here", "nome_file_lungo", "2 * 3 * 4", "a_b_c e snake_case_name"])
    func intrawordUnderscoresAndSpacedStarsProduceNoEmphasis(_ text: String) {
        for token in tokens(text) {
            switch token.kind {
            case .emphasis, .strong:
                Issue.record("\(text): \(token.kind) over \(slice(text, token.range))")
            default:
                break
            }
        }
    }

    // (n2-page R-18) And the same text with a real pair next to it still finds the pair.
    @Test func aRealPairBesideAnIntrawordUnderscoreIsFoundAlone() throws {
        let text = "file_name_here e _vero_"
        let found = tokens(text).filter { if case .emphasis = $0.kind { true } else { false } }
        #expect(found.count == 1)
        #expect(slice(text, try #require(found.first).range) == "_vero_")
    }

    // MARK: Precedence: code, then wikilink, then link, then emphasis

    // (n2-page R-18) Code swallows what is inside it.
    @Test func codeComesBeforeEverythingElse() {
        let text = "`[[Nota]] **no** [a](b)`"
        let result = tokens(text)
        #expect(result.count == 1)
        if case .code = result.first?.kind {} else { Issue.record("not code: \(String(describing: result.first?.kind))") }
    }

    // (n2-page R-18) A wikilink's target, then a link's url.
    @Test func aWikilinkAndALinkCarryTheirTargets() throws {
        let wiki = try #require(tokens("[[Nota|alias]]").first)
        guard case .wikilink(let target, let syntax) = wiki.kind else {
            Issue.record("not a wikilink: \(wiki.kind)")
            return
        }
        #expect(target == "Nota")
        #expect(!syntax.isEmpty)

        let link = try #require(tokens("[testo](https://x.it/a)").first)
        guard case .link(let url, let linkSyntax) = link.kind else {
            Issue.record("not a link: \(link.kind)")
            return
        }
        #expect(url == "https://x.it/a")
        #expect(!linkSyntax.isEmpty)
    }

    // (n2-page R-18) An embed's target is the file, never its size suffix.
    @Test func anEmbedCarriesItsTargetWithoutTheSizeSuffix() throws {
        let embed = try #require(tokens("![[foto.png|300]]").first)
        guard case .embed(let target, let syntax) = embed.kind else {
            Issue.record("not an embed: \(embed.kind)")
            return
        }
        #expect(target == "foto.png")
        #expect(!syntax.isEmpty)
    }

    // (n2-page R-18) ADR-0077 §D5: a link's label is parsed, so emphasis inside it is a token.
    @Test func aLinkLabelCarryingEmphasisYieldsTheLinkAndTheEmphasis() throws {
        let text = "[testo con *enfasi* dentro](https://x.it)"
        let result = tokens(text)
        let link = try #require(result.first { if case .link = $0.kind { true } else { false } })
        #expect(slice(text, link.range) == text)
        let emphasis = try #require(result.first { if case .emphasis = $0.kind { true } else { false } })
        #expect(slice(text, emphasis.range) == "*enfasi*")
        #expect(link.range.contains(emphasis.range.lowerBound), "the emphasis is inside the link's range")
    }

    // MARK: The app's own conventions

    // (n2-page R-18)
    @Test func aTagIsATokenWithItsText() throws {
        let text = "con #project-av45 dentro"
        let token = try #require(tokens(text).first)
        #expect(token.kind == .tag("#project-av45"))
        #expect(slice(text, token.range) == "#project-av45")
    }

    // (n2-page R-18) `>date`, `!date` and `@annotation`.
    @Test func aScheduledADueAndAnAnnotationAreTokens() throws {
        let text = "x >2026-10-04 y !2026-10-09 z @done(2026-10-01)"
        let result = tokens(text)
        let scheduled = try #require(result.first { $0.kind == .scheduled })
        #expect(slice(text, scheduled.range) == ">2026-10-04")
        let due = try #require(result.first { $0.kind == .due })
        #expect(slice(text, due.range) == "!2026-10-09")
        let annotation = try #require(result.first { $0.kind == .annotation })
        #expect(slice(text, annotation.range) == "@done(2026-10-01)")
    }

    // MARK: Ranges index the note

    // (n2-page R-18) `tokens(in:)` takes a `Substring`, so its ranges are valid in the whole
    // note: a substring shares its base string's indices.
    @Test func everyRangeIndexesTheBaseStringOfAMidNoteSubstring() throws {
        let note = "prima riga con **non qui**\nseconda **forte** e [[Nota]] e #tag e `codice`\nterza"
        let secondLine = note.split(separator: "\n", omittingEmptySubsequences: false)[1]
        let result = MarkdownInlineParser.tokens(in: secondLine)

        #expect(!result.isEmpty)
        let strong = try #require(result.first { if case .strong = $0.kind { true } else { false } })
        #expect(String(note[strong.range]) == "**forte**")
        for token in result {
            #expect(token.range.lowerBound >= secondLine.startIndex && token.range.upperBound <= secondLine.endIndex)
            #expect(!note[token.range].contains("\n"))
        }
        let tag = try #require(result.first { $0.kind == .tag("#tag") })
        #expect(String(note[tag.range]) == "#tag")
        let code = try #require(result.first { if case .code = $0.kind { true } else { false } })
        #expect(String(note[code.range]) == "`codice`")
    }
}
