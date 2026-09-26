import Foundation
import Testing
@testable import Pergamenum

// ADR-0041 (vault layer consistency and security), plan
// docs/superpowers/plans/2026-09-12-vault-layer-consistency-and-security-cha.md, Task 6 -
// R-05: "A read parses once, stats once, and a caller that wants the text asks for the
// text" (ADR §D7). `TODO.md:324` names the finding this closes:
// `perf-NoteStore.swift-ce3` (a caller that only wants the body pays a full record
// derivation), `perf-NoteStore.swift-bf6` (frontmatter parsed twice per read),
// `perf-VaultSession+Journal.swift-462` (a moved file read twice).
//
// The tests that characterise `read`'s output exist to catch a regression.
//
// `Tests/TransclusionTests.swift:182` (`aTranscludedNoteIsALinkAndAnEmbeddedFileIsNot`) and
// `:221` (`aTranscludedSectionCountsAsALinkToItsNoteOnce`) exercise the unchanged
// `NoteStore.linkTargets(in text:)` wrapper directly and are not edited here; they stay
// green throughout this task, unedited, because that wrapper's own behaviour is not what
// changes. `Tests/VaultSessionJournalTests.swift`'s move tests
// (`aMoveIsRecordedWithWhereItCameFrom`, `theIndexFollowsAMove`) are the same kind of net
// for `VaultSession.moveFile` and are likewise not edited.

// MARK: - Shared fixture

/// Three wikilinks, one transclusion, one image embed and two tasks - the shape Task 6's
/// brief asks the "exact record" test to cover.
private let fixtureNote = """
---
date: 2026-08-20
tags:
  - type-note
  - topic-prove
---

Vedi [[Uno]], [[Due]] e [[Tre]].

![[Nota trasclusa]]

![[foto.png]]

- [ ] Prima attività >2026-08-21
- [x] Seconda attività @done(2026-08-20)
"""

private let fixturePath = "01 Progetti/Nota di prova.md"

/// The attributes and hash `read` derives from disk, fetched independently so the
/// "expected" record below is not built from the very code path under test.
private func diskFacts(for url: URL) throws -> (attributes: [FileAttributeKey: Any], data: Data) {
    let data = try Data(contentsOf: url)
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
    return (attributes, data)
}

// MARK: - `read` produces the record it produces today (characterisation, ADR §D7)

@Test func readProducesExactlyTheRecordFieldByField() throws {
    let vault = try TemporaryVault()
    let url = try vault.write(fixtureNote, to: fixturePath)
    let facts = try diskFacts(for: url)

    let expected = NoteRecord(
        relativePath: fixturePath,
        title: "Nota di prova",
        frontmatter: NoteDocument.parse(fixtureNote).frontmatter,
        // The transclusion counts as a link (ADR-0010 §D7); the image embed does not.
        linkTargets: ["Uno", "Due", "Tre", "Nota trasclusa"],
        embedTargets: ["foto.png"],
        tasks: TaskParser.tasks(in: fixtureNote, sourcePath: fixturePath),
        modifiedAt: facts.attributes[.modificationDate] as? Date ?? .distantPast,
        byteSize: facts.data.count,
        contentHash: NoteStore.hash(facts.data)
    )

    let (record, text) = try NoteStore(root: vault.root).read(fixturePath)
    #expect(record == expected)
    #expect(text == fixtureNote)
    #expect(record.tasks.count == 2, "la nota di prova ha due attività, non \(record.tasks.count)")
}

// MARK: - `linkTargets(in document:)` agrees with `linkTargets(in text:)` (§D7)

/// The two overloads must agree on every input, including the transclusion rule
/// `Tests/TransclusionTests.swift:180-186` and `:218-223` already pin down for the text
/// overload: `![[nota]]` counts as a link, `![[foto.png]]` does not.
@Test func documentOverloadAgreesWithTextOverloadOnAnOrdinaryNote() {
    let text = "vedi [[Altra]]\n\n![[Curva di trasmissibilità]]\n\n![[foto.png]]\n"
    let fromText = NoteStore.linkTargets(in: text)
    let fromDocument = NoteStore.linkTargets(in: NoteDocument.parse(text))
    #expect(fromDocument == fromText)
    #expect(fromDocument.contains("Altra"))
    #expect(fromDocument.contains("Curva di trasmissibilità"))
    #expect(!fromDocument.contains("foto.png"))
}

@Test func documentOverloadCountsATranscludedSectionOnceLikeTheTextOverload() {
    let text = "![[Prove#Campioni]]\n\n[[Prove]]\n"
    let fromText = NoteStore.linkTargets(in: text)
    let fromDocument = NoteStore.linkTargets(in: NoteDocument.parse(text))
    #expect(fromDocument == fromText)
    #expect(fromDocument == ["Prove"])
}

@Test func documentOverloadAgreesOnFrontmatterAndFencedNoise() {
    // The same shape `Tests/TransclusionTests.swift:162` (`occurrencesSkipFencesAndFrontmatter`)
    // exercises for `Transclusion.occurrences` - a wikilink quoted in `related:` and one
    // fenced inside a code block must not be counted by either overload.
    let text = """
    ---
    date: 2026-08-17
    related: ["[[Prove]]"]
    ---
    ```md
    [[Nel fence]]
    ```

    [[Vera]]
    """
    let fromText = NoteStore.linkTargets(in: text)
    let fromDocument = NoteStore.linkTargets(in: NoteDocument.parse(text))
    #expect(fromDocument == fromText)
    #expect(fromDocument == ["Vera"])
}

// MARK: - `text(_:)` (boundary, `Data(contentsOf:)`, UTF-8 decode only)

@Test func textReturnsTheSameStringReadReturns() throws {
    let vault = try TemporaryVault()
    try vault.write(fixtureNote, to: fixturePath)
    let store = NoteStore(root: vault.root)

    let (_, expected) = try store.read(fixturePath)
    #expect(try store.text(fixturePath) == expected)
}

@Test func textRefusesEscapingTheVault() throws {
    let vault = try TemporaryVault()
    let store = NoteStore(root: vault.root)
    #expect(throws: VaultBoundary.Violation.self) {
        try store.text("../../etc/passwd")
    }
}

@Test func textThrowsNotUTF8OnInvalidBytes() throws {
    let vault = try TemporaryVault()
    let url = vault.root.appending(path: "binaria.md")
    try Data([0xFF, 0xFE, 0x00, 0x01]).write(to: url)
    let store = NoteStore(root: vault.root)
    #expect(throws: NoteStore.StoreError.self) {
        try store.text("binaria.md")
    }
}

// MARK: - `record(from:attributes:at:)` equals `read`'s own record (Task 8 depends on this)

@Test func recordFromBytesAndAttributesEqualsReadsOwnRecord() throws {
    let vault = try TemporaryVault()
    let url = try vault.write(fixtureNote, to: fixturePath)
    let facts = try diskFacts(for: url)
    let store = NoteStore(root: vault.root)

    let fromRead = try store.read(fixturePath).record
    let fromBytes = try store.record(from: facts.data, attributes: facts.attributes, at: fixturePath)
    #expect(fromBytes == fromRead)
}

@Test func recordFromBytesThrowsNotUTF8LikeReadDoes() throws {
    let vault = try TemporaryVault()
    let store = NoteStore(root: vault.root)
    let invalid = Data([0xFF, 0xFE, 0x00, 0x01])
    #expect(throws: NoteStore.StoreError.self) {
        try store.record(from: invalid, attributes: [:], at: "binaria.md")
    }
}

// MARK: - Structural: the double parse is gone (asserted the way
// `Tests/SharedSourcesPurityTests.swift` asserts a repository fact - a text scan of the
// source, not a review note)

/// `read`'s own body must parse `NoteDocument` exactly once. Today it parses once
/// directly (for the frontmatter) and once more indirectly, inside the text-taking
/// `linkTargets(in: text:)` wrapper it still calls for its link targets - `perf-NoteStore.swift-bf6`'s
/// "frontmatter parsed twice per read". The second parse is textually inside a different
/// function's body, so it is traced there rather than assumed away: if `read` still calls
/// the text overload, that overload's own parse is added to the count.
@Test func readsCallGraphParsesTheDocumentExactlyOnce() throws {
    let repoRoot = try resolvedRepoRoot()
    let sourceURL = repoRoot.appendingPathComponent("Sources/Vault/NoteStore.swift")
    let source = try String(contentsOf: sourceURL, encoding: .utf8)

    let readBody = try #require(
        functionBody(named: "func read(_ relativePath: String)", in: source),
        "non trovo il corpo di NoteStore.read in \(sourceURL.path)"
    )

    var parseCount = occurrenceCount(of: "NoteDocument.parse(", in: readBody)
    if readBody.contains("linkTargets(in: text)") {
        let wrapperBody = try #require(
            functionBody(named: "static func linkTargets(in text: String)", in: source),
            "non trovo il corpo del wrapper linkTargets(in text:) in \(sourceURL.path)"
        )
        parseCount += occurrenceCount(of: "NoteDocument.parse(", in: wrapperBody)
    }

    #expect(parseCount == 1, "read's own call graph parses NoteDocument \(parseCount) times, not once")
}

private func occurrenceCount(of needle: String, in haystack: String) -> Int {
    haystack.components(separatedBy: needle).count - 1
}

/// Extracts the `{ ... }` block that follows the first occurrence of `signature`, by
/// brace depth - good enough for one file this test controls the shape of, and the same
/// "read the source as text" approach `SharedSourcesPurityTests` already uses.
private func functionBody(named signature: String, in source: String) -> String? {
    guard let signatureRange = source.range(of: signature) else { return nil }
    guard let braceStart = source[signatureRange.upperBound...].firstIndex(of: "{") else { return nil }

    var depth = 0
    var index = braceStart
    while index < source.endIndex {
        switch source[index] {
        case "{": depth += 1
        case "}":
            depth -= 1
            if depth == 0 { return String(source[braceStart...index]) }
        default: break
        }
        index = source.index(after: index)
    }
    return nil
}
