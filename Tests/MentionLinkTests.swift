import Foundation
import Testing
@testable import Pergamenum

// ADR-0084 §D3 («Collega» writes the link the person was shown), SPEC R-26, plan
// docs/plans/note-workflow-n3.md Task 1.
//
// `UnlinkedMentions.firstMention` finds the mention in the original text and `MentionLink.rewrite`
// turns it into a link; the diff the sheet shows and the bytes that land come from these two, so
// they are pinned without a vault. The last test ties the new scan to the old one: the list of
// mentions and the link «Collega» writes must not disagree about which mention is the first.

/// The NSString substring a range names: how the editor and `rewrite` read an `NSRange`.
private func substring(_ text: String, _ range: NSRange) -> String {
    (text as NSString).substring(with: range)
}

// MARK: - firstMention: the range is in the original text

@Test func theRangeIsUTF16OverTheOriginalTextEvenAfterADecomposedAccentAndAnEmoji() throws {
    // `e` + combining acute is two UTF-16 units and one Character; the emoji is two units and one
    // Character: a range counted in Characters would land two places short of the mention.
    let text = "Cafe\u{0301} \u{1F600} e poi la Curva di taratura.\n"

    let mention = try #require(UnlinkedMentions.firstMention(of: ["Curva di taratura"], in: text))

    #expect(substring(text, mention.range) == "Curva di taratura")
    #expect(mention.matched == "Curva di taratura")
}

@Test func aDecomposedAccentInTheMatchedTextIsPartOfTheRange() throws {
    let text = "Parliamo della trasmissibilita\u{0300} del segnale.\n"

    let mention = try #require(UnlinkedMentions.firstMention(of: ["trasmissibilità"], in: text))

    #expect(mention.matched == "trasmissibilita\u{0300}")
    #expect(substring(text, mention.range) == mention.matched)
}

@Test func aCaseDifferenceMatchesAndKeepsTheTextAsWritten() throws {
    let text = "Prima riga.\nUna CURVA di taratura nuova.\n"

    let mention = try #require(UnlinkedMentions.firstMention(of: ["curva di taratura"], in: text))

    #expect(mention.matched == "CURVA di taratura")
    #expect(substring(text, mention.range) == "CURVA di taratura")
    #expect(mention.line == "Una CURVA di taratura nuova.")
}

@Test func anAliasIsAMentionAndTheLineIsTrimmed() throws {
    let text = "---\ndate: 2026-10-07\ntags:\n  - type-note\n---\n\n   Il tornante di prova.\n"

    let mention = try #require(UnlinkedMentions.firstMention(of: ["Curva", "tornante"], in: text))

    #expect(mention.matched == "tornante")
    #expect(substring(text, mention.range) == "tornante")
    #expect(mention.line == "Il tornante di prova.")
}

@Test func theEarliestLineWinsWhateverTheOrderOfTheNames() throws {
    let text = "Riga uno parla di Beta.\nRiga due parla di Alfa.\n"

    let mention = try #require(UnlinkedMentions.firstMention(of: ["Alfa", "Beta"], in: text))

    #expect(mention.matched == "Beta")
}

// MARK: - firstMention: what is not a mention

@Test func onlyWholeWordsAreMentions() {
    let text = "Una curvatura, il Curva2 e la precurva non sono la nota.\n"

    #expect(UnlinkedMentions.firstMention(of: ["Curva"], in: text) == nil)
}

@Test func aNameInsideAWikilinkIsNotAMentionButTheNextOneOutsideIs() throws {
    let text = "Vedi [[Curva]] e [[Altra|Curva]], poi la Curva da sola.\n"

    let mention = try #require(UnlinkedMentions.firstMention(of: ["Curva"], in: text))

    #expect(substring(text, mention.range) == "Curva")
    #expect(mention.range.location > (text as NSString).range(of: "poi la ").location)
}

@Test func aNameOnlyInsideWikilinksIsNoMention() {
    #expect(UnlinkedMentions.firstMention(of: ["Curva"], in: "Solo [[Curva]] e ![[Curva]].\n") == nil)
}

@Test func aNameInTheFrontmatterIsNotAMention() {
    let text = """
    ---
    date: 2026-10-07
    tags:
      - type-note
    aliases:
      - Curva
    related:
      - "[[Curva]]"
    ---

    Corpo senza il nome.
    """

    #expect(UnlinkedMentions.firstMention(of: ["Curva"], in: text) == nil)
}

@Test func aNameInsideAFencedCodeBlockIsNotAMention() {
    // ADR-0084 §D3's narrowing, new behaviour: writing `[[…]]` into code would change code.
    let text = "Prima.\n```swift\nlet curva = Curva()\n```\nDopo.\n"

    #expect(UnlinkedMentions.firstMention(of: ["Curva"], in: text) == nil)
}

@Test func aNameInsideAnInlineCodeSpanIsNotAMentionButTheProseAfterItIs() throws {
    let text = "Il tipo `Curva` è codice, la Curva è prosa.\n"

    let mention = try #require(UnlinkedMentions.firstMention(of: ["Curva"], in: text))

    #expect(mention.range.location > (text as NSString).range(of: "è codice").location)
}

/// A web address is not prose: `[[…]]` written into a URL or a markdown link breaks the link, and
/// `perg note link-mention` writes without anyone looking at a diff.
@Test(arguments: [
    ("un indirizzo nudo", "Vedi https://esempio.it/curva per i dettagli.\n"),
    ("un indirizzo www", "Vedi www.esempio.it/curva per i dettagli.\n"),
    ("l'etichetta di un link", "Vedi [Curva](altro.md) per i dettagli.\n"),
    ("la parte url di un link", "Vedi [dettagli](https://esempio.it/curva) qui.\n"),
    ("un link con lo stesso nome", "Vedi [Curva](Curva.md) qui.\n"),
    ("un'immagine", "Vedi ![Curva](curva.png) qui.\n"),
    ("un link in corsivo", "Vedi *[Curva](altro.md)* qui.\n"),
])
func aNameInsideAWebAddressOrAMarkdownLinkIsNotAMention(name: String, text: String) {
    #expect(UnlinkedMentions.firstMention(of: ["Curva"], in: text) == nil, "\(name)")
}

@Test func theSameNameInPlainProseOnAnotherLineIsStillFoundBesideAnAddress() throws {
    let text = "Vedi https://esempio.it/curva e [Curva](Curva.md).\nLa Curva è prosa.\n"

    let mention = try #require(UnlinkedMentions.firstMention(of: ["Curva"], in: text))

    #expect(mention.line == "La Curva è prosa.")
    #expect(substring(text, mention.range) == "Curva")
    #expect(mention.range.location > (text as NSString).range(of: "\n").location)
}

@Test func theProseAfterALinkOnTheSameLineIsStillAMention() throws {
    let text = "Vedi [altro](altro.md) e poi la Curva.\n"

    let mention = try #require(UnlinkedMentions.firstMention(of: ["Curva"], in: text))

    #expect(mention.range.location > (text as NSString).range(of: "poi").location)
}

/// A tag or an annotation is not prose: «Collega» on `#client-curva` would write
/// `#client-[[Curva|curva]]`, which is no longer a tag.
@Test(arguments: [
    ("un tag", "Pratica #client-curva aperta.\n"),
    ("un tag a inizio riga", "#client-curva\n"),
    ("un'annotazione", "Fatto @done(curva) ieri.\n"),
])
func aNameInsideATagOrAnAnnotationIsNotAMention(name: String, text: String) {
    #expect(UnlinkedMentions.firstMention(of: ["Curva"], in: text) == nil, "\(name)")
}

@Test func theSameNameInPlainProseOnAnotherLineIsStillFoundBesideATag() throws {
    let text = "Pratica #client-curva aperta.\nLa Curva è prosa.\n"

    let mention = try #require(UnlinkedMentions.firstMention(of: ["Curva"], in: text))

    #expect(mention.line == "La Curva è prosa.")
    #expect(substring(text, mention.range) == "Curva")
    #expect(mention.range.location > (text as NSString).range(of: "\n").location)
}

// MARK: - rewrite

private func mention(_ matched: String, in text: String) -> UnlinkedMentions.Mention {
    let range = (text as NSString).range(of: matched)
    return UnlinkedMentions.Mention(range: range, matched: matched, line: text)
}

@Test func anExactMatchBecomesTheBareLink() {
    let text = "Parliamo della Curva di taratura oggi."

    let rewritten = MentionLink.rewrite(
        text, mention: mention("Curva di taratura", in: text), title: "Curva di taratura"
    )

    #expect(rewritten == "Parliamo della [[Curva di taratura]] oggi.")
}

@Test func aCaseDifferenceBecomesALinkWithTheTextAsDisplay() {
    let text = "Parliamo della curva di taratura oggi."

    let rewritten = MentionLink.rewrite(
        text, mention: mention("curva di taratura", in: text), title: "Curva di taratura"
    )

    #expect(rewritten == "Parliamo della [[Curva di taratura|curva di taratura]] oggi.")
}

@Test func anAccentDifferenceBecomesALinkWithTheTextAsDisplay() {
    let text = "La trasmissibilita del segnale."

    let rewritten = MentionLink.rewrite(
        text, mention: mention("trasmissibilita", in: text), title: "Trasmissibilità"
    )

    #expect(rewritten == "La [[Trasmissibilità|trasmissibilita]] del segnale.")
}

@Test func anAliasBecomesALinkWithTheAliasAsDisplay() {
    let text = "Il tornante di prova."

    let rewritten = MentionLink.rewrite(text, mention: mention("tornante", in: text), title: "Curva")

    #expect(rewritten == "Il [[Curva|tornante]] di prova.")
}

@Test func rewriteTouchesOnlyTheMentionAndEverythingElseIsByteForByte() {
    let text = "---\ndate: 2026-10-07\n---\n\nCafe\u{0301} \u{1F600}\r\nUna Curva qui.\r\nE un'altra Curva là.\n"

    let rewritten = MentionLink.rewrite(text, mention: mention("Curva", in: text), title: "Curva")

    #expect(
        rewritten == "---\ndate: 2026-10-07\n---\n\nCafe\u{0301} \u{1F600}\r\n"
            + "Una [[Curva]] qui.\r\nE un'altra Curva là.\n"
    )
}

// MARK: - Agreement with the scan the inspector's list uses

/// One entry per shape of line, named. A text, not a bare line, because a fence takes several.
private let scanCorpus: [(name: String, text: String)] = [
    ("prosa semplice", "Parliamo della Curva di taratura oggi.\n"),
    ("riga indentata", "      Curva di taratura, indentata.\n"),
    ("maiuscole e accenti", "CURVA DI TARATURA e trasmissibilita.\n"),
    ("parola intera", "La curvatura di taratura non c'entra.\n"),
    ("dentro un wikilink", "Già [[Curva di taratura]] linkata.\n"),
    ("wikilink e poi prosa", "[[Curva di taratura]] e poi la Curva di taratura.\n"),
    ("frontmatter", "---\ndate: 2026-10-07\naliases:\n  - Curva di taratura\n---\n\nSenza il nome.\n"),
    ("seconda riga", "Niente qui.\nMa qui la Curva di taratura.\n"),
    ("nessun nome", "Una riga qualsiasi.\n"),
    ("codice inline", "Il tipo `Curva di taratura` soltanto.\n"),
    ("blocco di codice", "```\nCurva di taratura\n```\n"),
    ("link markdown", "Vedi [Curva di taratura](altro.md) soltanto.\n"),
    ("indirizzo nudo", "Vedi https://esempio.it/trasmissibilita soltanto.\n"),
    ("tag inline", "Il #topic-trasmissibilita soltanto.\n"),
    ("annotazione", "Fatto @done(trasmissibilità) soltanto.\n"),
]

/// The deliberate differences (ADR-0084 §D3): the old scan read code, web links (markdown links
/// and bare addresses) and inline tags and annotations as prose, the new one does not. These
/// entries, by name, are the only ones where the two answers may disagree.
private let narrowedLines: Set<String> = [
    "codice inline", "blocco di codice", "link markdown", "indirizzo nudo", "tag inline", "annotazione",
]

/// The old scan, kept here as the oracle: the first body line, split on "\n", for which the
/// per-line `mentions` is true, trimmed. Written out rather than called through
/// `firstMentionLine`, because that function becomes `firstMention(of:in:)?.line` (ADR-0084 §D3)
/// and an oracle that follows the code under test proves nothing.
private func oldFirstMentionLine(of names: [String], in text: String) -> String? {
    NoteDocument.parse(text).body
        .components(separatedBy: "\n")
        .first { UnlinkedMentions.mentions(names, in: $0) }?
        .trimmingCharacters(in: .whitespaces)
}

@Test func theMentionLineAndTheOldScanAgreeExceptOnTheNarrowings() {
    let names = ["Curva di taratura", "trasmissibilità"]

    for entry in scanCorpus {
        let new = UnlinkedMentions.firstMention(of: names, in: entry.text)?.line
        let old = oldFirstMentionLine(of: names, in: entry.text)

        if narrowedLines.contains(entry.name) {
            #expect(old != nil, "«\(entry.name)»: la vecchia scansione lo leggeva come prosa")
            #expect(new == nil, "«\(entry.name)»: non è una menzione")
        } else {
            #expect(new == old, "«\(entry.name)»: la scansione e il link devono scegliere la stessa menzione")
        }
    }
}

// MARK: - (coverage) rules the doc comment of `firstMention` states and no test pinned

/// (coverage) "Two names starting at one place give the longer match", whatever the order of the names.
@Test func twoNamesStartingAtOnePlaceGiveTheLongerMatchInEitherOrder() throws {
    let text = "Oggi la Curva di taratura è pronta.\n"

    let shortFirst = try #require(UnlinkedMentions.firstMention(of: ["Curva", "Curva di taratura"], in: text))
    let longFirst = try #require(UnlinkedMentions.firstMention(of: ["Curva di taratura", "Curva"], in: text))

    #expect(shortFirst.matched == "Curva di taratura")
    #expect(longFirst.matched == "Curva di taratura")
    #expect(shortFirst == longFirst)
}

/// (coverage) The line of a mention ends at a CRLF too, and carries neither the `\r` nor the next line.
@Test func aMentionsLineEndsAtACarriageReturnLineFeed() throws {
    let text = "Prima riga.\r\nUna Curva qui.\r\nTerza riga.\r\n"

    let mention = try #require(UnlinkedMentions.firstMention(of: ["Curva"], in: text))

    #expect(mention.line == "Una Curva qui.")
    #expect(substring(text, mention.range) == "Curva")
}

/// (coverage) A blank name never matches, and neither does an empty list of names.
@Test func aBlankNameOrNoNameIsNoMention() {
    let text = "Una riga con parole.\n"

    #expect(UnlinkedMentions.firstMention(of: ["", "   "], in: text) == nil)
    #expect(UnlinkedMentions.firstMention(of: [], in: text) == nil)
}
