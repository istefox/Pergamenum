import Foundation
import Testing
@testable import Pergamenum

// ADR-0009 §D4: a view answers a shell and a window with the same rows, because both run the
// same parser and the same evaluator.

private let noteWithTwoViews = """
---
date: 2026-08-20
tags:
  - type-note
---

```pergamenum-view
where: tag("client-*")
sort: title
render: table
columns: [title, tags]
```

```pergamenum-view
sort: created desc
render: table
```
"""

@MainActor
private func session(_ vault: borrowing TemporaryVault) async throws -> VaultSession {
    try vault.write(
        "---\ndate: 2026-08-19\ntags:\n  - client-nexion\n  - type-note\n---\n\nCorpo.\n",
        to: "Clienti/Nexion.md"
    )
    try vault.write(noteWithTwoViews, to: "Viste.md")
    let session = VaultSession(root: vault.root)
    await session.rescan()
    return session
}

@MainActor
@Test func listingFindsEveryBlockAndSaysWhichCannotRun() async throws {
    let vault = try TemporaryVault()
    let session = try await session(vault)

    let views = VaultAPI.views(session)

    #expect(views.count == 2)
    #expect(views[0].path == "Viste.md")
    #expect(views[0].ordinal == 0)
    #expect(views[0].render == "table")
    #expect(views[0].columns == ["title", "tags"])
    // A block that does not parse is listed with its reason. A listing that dropped it would
    // be §D1's forbidden empty result, told through another channel.
    #expect(views[1].render == nil)
    #expect(views[1].error?.contains("riga 1") == true)
}

@MainActor
@Test func runningAViewGivesTheRowsTheWindowDraws() async throws {
    let vault = try TemporaryVault()
    let session = try await session(vault)

    let run = try VaultAPI.runView(session, at: "Viste.md", ordinal: 0)

    #expect(run.total == 1)
    let row = try #require(run.groups.first?.rows.first)
    #expect(row.title == "Nexion")
    #expect(row.values["title"] == "Nexion")
    #expect(row.values["tags"] == "client-nexion, type-note")
}

@MainActor
@Test func aNoteWithMoreThanOneViewIsNotGuessedAt() async throws {
    let vault = try TemporaryVault()
    let session = try await session(vault)

    #expect(throws: ConnectorError.self) { try VaultAPI.runView(session, at: "Viste.md", ordinal: nil) }
    #expect(throws: ConnectorError.self) { try VaultAPI.runView(session, at: "Viste.md", ordinal: 7) }
}

@MainActor
@Test func aBlockThatDoesNotParseRefusesToRunWithItsLine() async throws {
    let vault = try TemporaryVault()
    let session = try await session(vault)

    let error = #expect(throws: ConnectorError.self) {
        try VaultAPI.runView(session, at: "Viste.md", ordinal: 1)
    }
    #expect(error?.description.contains("created") == true)
}

@MainActor
@Test func aNoteWithNoViewInItSaysSoRatherThanAnsweringNothing() async throws {
    let vault = try TemporaryVault()
    let session = try await session(vault)

    let error = #expect(throws: ConnectorError.self) {
        try VaultAPI.runView(session, at: "Clienti/Nexion.md", ordinal: nil)
    }
    #expect(error?.description.contains("pergamenum-view") == true)
}

/// The cell a shell prints and the cell a table draws come from one function, so a date cannot
/// be written two ways.
@MainActor
@Test func theConnectorFillsTheSameCellsTheRenderersDo() async throws {
    let vault = try TemporaryVault()
    let session = try await session(vault)
    let run = try VaultAPI.runView(session, at: "Viste.md", ordinal: 0)
    let record = try #require(session.index.note(at: "Clienti/Nexion.md"))

    #expect(run.groups.first?.rows.first?.values["tags"]
        == ViewValueText.text(ViewField.tags.value(of: record), of: .tags))
}

// MARK: - Le viste che i milestone spediscono

/// A shipped example that does not parse would teach the wrong thing, so every one of them is
/// run through the parser here rather than proof-read.
@Test func everySampleViewParses() throws {
    for sample in SampleViews.all {
        let blocks = ViewBlock.blocks(in: NoteDocument.parse(sample.text).body)
        // One block each, except the weekly review of ADR-0013, which is four questions in one
        // note: four notes to open on a Friday afternoon is a ritual nobody keeps.
        #expect(!blocks.isEmpty)
        for block in blocks { _ = try block.get() }
    }

    // Pinned, so a block dropped from the weekly review by a careless edit is a failure here
    // rather than a heading with nothing under it in somebody's vault.
    let total = SampleViews.all.reduce(0) { running, sample in
        running + ViewBlock.blocks(in: NoteDocument.parse(sample.text).body).count
    }
    #expect(total == 9)
}

/// They are notes, so the linter judges them like any other. One that shipped non-conformant
/// would put a violation in the vault of whoever accepted the offer.
@Test func everySampleViewIsConformant() throws {
    for sample in SampleViews.all {
        let document = NoteDocument.parse(sample.text)
        #expect(FrontmatterRules.validate(document).isEmpty)
        // The real table, not `.empty`: an empty vocabulary reports every closed-family tag
        // as unavailable, which would be a test about the fixture rather than about the file.
        #expect(TagRules.validate(
            document.frontmatter.tags,
            category: .note,
            vocabulary: Vocabulary(
                type: ["note"], status: [], area: [], source: [], deliverableKind: []
            )
        ).isEmpty)
    }
}

@MainActor
@Test func installingTheSamplesWritesThemOnceAndNeverAgain() async throws {
    let vault = try TemporaryVault()
    let session = try await session(vault)

    let first = session.installSampleViews()
    #expect(first.created.count == SampleViews.all.count)
    #expect(first.failures.isEmpty)

    // Edited by hand, and then offered again: the file stays as it was.
    let path = try #require(first.created.first)
    try session.write("---\ndate: 2026-08-20\ntags:\n  - type-note\n---\n\nMio.\n", to: path)

    let second = session.installSampleViews()
    #expect(second.created.isEmpty)
    #expect(second.alreadyThere.count == SampleViews.all.count)
    #expect(try session.read(path).text.contains("Mio."))
}
