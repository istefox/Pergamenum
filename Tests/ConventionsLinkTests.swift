import Foundation
import Testing
@testable import Pergamenum

// Wikilinks, code that is not a wikilink, and the editor's paste and link edits.
// Split out of ConventionsTests.swift (PG-148, ADR-0051): the file had passed 800 lines across
// eleven MARK sections and no @Suite, so each section moved whole and none was edited.

// MARK: - Wikilinks

@Test func parsesEveryWikilinkForm() {
    let body = "Vedi [[Nota semplice]], [[Nota#Sezione]], [[Nota|testo]] e ![[schema.pdf]]."
    let links = WikilinkParser.links(in: body)

    #expect(links.map(\.target) == ["Nota semplice", "Nota", "Nota", "schema.pdf"])
    #expect(links[1].section == "Sezione")
    #expect(links[2].displayText == "testo")
    #expect(links[3].isEmbed)
    #expect(!links[0].isEmbed)
}

@Test func splitsSectionAndDisplayTextTogether() {
    let links = WikilinkParser.links(in: "[[Nota#Sezione|testo]]")
    #expect(links.count == 1)
    #expect(links[0].target == "Nota")
    #expect(links[0].section == "Sezione")
    #expect(links[0].displayText == "testo")
}

@Test func ignoresEmptyAndUnbalancedLinks() {
    #expect(WikilinkParser.links(in: "[[]] e [[   ]]").isEmpty)
    #expect(WikilinkParser.links(in: "[[non chiuso").isEmpty)
}

@Test func findsTheInnerLinkWhenBracketsNest() {
    let links = WikilinkParser.links(in: "testo [[a [[b]] coda")
    #expect(links.map(\.target) == ["b"])
}

@Test func rendersBackToSource() {
    for source in ["[[Nota]]", "[[Nota#Sezione]]", "[[Nota|testo]]", "![[file.pdf]]"] {
        #expect(WikilinkParser.links(in: source).first?.rendered == source)
    }
}

/// Issue #188 follow-up: `resolvedTitle` strips one wrapping pair of emphasis markers for
/// consumers that resolve a wikilink to an actual note (click navigation, backlinks, the
/// index) - but `target`/`rendered` stay the literal bracket interior, since
/// `NoteRename.rewritingLinks` rebuilds the source range from `rendered` on every rename, and
/// stripping there would silently drop a person's bold markers the next time the note is
/// renamed.
@Test func resolvedTitleStripsWrappingEmphasisWithoutChangingTargetOrRendered() {
    let link = WikilinkParser.links(in: "[[**Prova**]]").first!
    #expect(link.target == "**Prova**")
    #expect(link.resolvedTitle == "Prova")
    #expect(link.rendered == "[[**Prova**]]")
}

@Test func resolvedTitleLeavesAnOrdinaryTargetUnchanged() {
    let link = WikilinkParser.links(in: "[[Nota]]").first!
    #expect(link.resolvedTitle == "Nota")
}

// MARK: - Code is not a wikilink

@Test func ignoresBashTestSyntaxInAFencedBlock() {
    // Observed on the real Labs vault: `[[ ... ]]` is bash's test syntax, and every
    // shell snippet was filling the unresolved-links panel.
    let note = """
    Prima del blocco.

    ```bash
    if [[ "${esiti[*]}" == "0 0 0" ]]; then
      echo ok
    fi
    ```

    Dopo il blocco, un vero [[Collegamento]].
    """
    #expect(WikilinkParser.links(in: note).map(\.target) == ["Collegamento"])
}

@Test func ignoresTomlArrayOfTablesInAFencedBlock() {
    let note = """
    ```toml
    [[tool.mypy.overrides]]
    module = "x"
    ```
    """
    #expect(WikilinkParser.links(in: note).isEmpty)
}

@Test func ignoresInlineCodeSpans() {
    #expect(WikilinkParser.links(in: "usa `[[ -f file ]]` nel test").isEmpty)
    #expect(WikilinkParser.links(in: "`codice` e poi [[Vero link]]").map(\.target) == ["Vero link"])
}

@Test func treatsAnUnterminatedFenceAsRunningToTheEnd() {
    // The reader sees everything after the fence as code, so the parser must agree.
    let note = "testo\n\n```\n[[non un link]]\n"
    #expect(WikilinkParser.links(in: note).isEmpty)
}

@Test func stillFindsLinksAroundCode() {
    let note = """
    [[Uno]] prima.

    ```
    [[dentro]]
    ```

    [[Due]] dopo.
    """
    #expect(WikilinkParser.links(in: note).map(\.target) == ["Uno", "Due"])
}

@Test func doesNotCloseAFenceOnALineCarryingAnInfoString() {
    // Only the opening fence may carry text after the backticks; treating a
    // "``` qualcosa" line as a close would end the block early and expose its tail.
    let note = "```\n[[dentro]]\n``` non chiude\n[[ancora dentro]]\n```\n[[fuori]]"
    #expect(WikilinkParser.links(in: note).map(\.target) == ["fuori"])
}

@Test func inlineSpanMaskingSurvivesAFenceEarlierInTheNote() {
    // Regression from the real Labs vault: pairing backticks across the whole text
    // desynchronised on the three of each fence, so an inline span further down was
    // no longer recognised and `[[tool.mypy.overrides]]` was indexed as a link.
    let note = """
    ```python
    print("x")
    ```

    Attivalo per modulo con `[[tool.mypy.overrides]]` ed elenca i moduli.

    Un vero [[Collegamento]] resta tale.
    """
    #expect(WikilinkParser.links(in: note).map(\.target) == ["Collegamento"])
}

@Test func doesNotPairBackticksAcrossLines() {
    // An unclosed span must not swallow the next line's real link.
    let note = "riga con ` aperto\n[[Vero]]"
    #expect(WikilinkParser.links(in: note).map(\.target) == ["Vero"])
}

// MARK: - Editor edits

@Test func wrapsASelectionInAMarkdownLinkWhenAURLIsPasted() {
    #expect(EditorEdits.markdownLink(pasting: "https://vibrofer.it", over: "il sito")
        == "[il sito](https://vibrofer.it)")
    // Other schemes count too: the vault links out to Obsidian, DEVONthink and Mail.
    #expect(EditorEdits.markdownLink(pasting: "message://%3Cabc%3E", over: "la mail")
        == "[la mail](message://%3Cabc%3E)")
}

@Test func leavesAnOrdinaryPasteAlone() {
    // Nothing selected, or the pasted text is not a URL: a normal paste.
    #expect(EditorEdits.markdownLink(pasting: "https://vibrofer.it", over: "") == nil)
    #expect(EditorEdits.markdownLink(pasting: "testo normale", over: "selezione") == nil)
    // A bare host is more likely text than a link, and guessing rewrites what was typed.
    #expect(EditorEdits.markdownLink(pasting: "vibrofer.it", over: "selezione") == nil)
}

@Test func buildsAnEmbedFromAFileName() {
    // The name, not the path: a wikilink resolves by name, and a path breaks as soon
    // as the file is moved inside the app.
    #expect(EditorEdits.embed(forFileNamed: "schema.pdf") == "![[schema.pdf]]")
}

@Test(arguments: ["https://x.test", "obsidian://open?vault=Labs", "message://%3Ca%3E", "pergamenum://today"])
func recognisesURLs(_ text: String) {
    #expect(EditorEdits.isURL(text))
}

@Test(arguments: ["", "testo", "vibrofer.it", "https://"])
func rejectsWhatIsNotAURL(_ text: String) {
    #expect(!EditorEdits.isURL(text))
}

@Test func theVocabularyFileKeepsItsCommentThroughARoundTrip() throws {
    // The shipped file carries a `_comment` saying harness-system owns these tables.
    // The importer wrote only the five tables, so the first real import deleted the one
    // sentence telling the reader not to hand-edit the file they were looking at.
    var vocabulary = Vocabulary(
        type: ["note"], status: ["draft"], area: ["training"],
        source: ["web"], deliverableKind: ["report"]
    )
    vocabulary.note = "Replica: re-import rather than editing."

    let data = try JSONEncoder().encode(vocabulary)
    let asText = try #require(String(data: data, encoding: .utf8))
    // Written under the key the file has always used, not under "note".
    #expect(asText.contains("\"_comment\""))
    #expect(try JSONDecoder().decode(Vocabulary.self, from: data) == vocabulary)
}

@Test func aVocabularyFileWithNoCommentStillReads() throws {
    // Every vault written before the comment existed.
    let json = Data("""
    {"type":["note"],"status":[],"area":[],"source":[],"deliverableKind":[]}
    """.utf8)
    let decoded = try JSONDecoder().decode(Vocabulary.self, from: json)
    #expect(decoded.note == nil)
    #expect(decoded.type == ["note"])
}
