import Foundation
import Testing
@testable import Pergamenum

// ADR-0049 (Pratiche links to notes, tasks and boards), plan
// docs/plans/pratiche-note-task-workspace-links.md, Task 1 - R-07, R-08, §D1-§D5.

@Suite struct PraticaLinkReferenceTests {
    // MARK: - Render/parse, one spelling for both

    @Test func rendersAWikilinkForANoteOrABoard() {
        #expect(PraticaLinkReference.wikilink("Offerta 2026").rendered == "[[Offerta 2026]]")
        #expect(PraticaLinkReference.wikilink("Board.canvas").rendered == "[[Board.canvas]]")
    }

    @Test func rendersATaskAsItsNoteWikilinkPlusTheCaretID() {
        #expect(
            PraticaLinkReference.task(noteTitle: "Nota", localID: 3).rendered == "[[Nota]] ^id(3)"
        )
    }

    @Test func parsesAPlainWikilinkBack() throws {
        let parsed = try #require(PraticaLinkReference(parsing: "[[Offerta 2026]]"))
        #expect(parsed == .wikilink("Offerta 2026"))
    }

    @Test func parsesATaskReferenceBack() throws {
        let parsed = try #require(PraticaLinkReference(parsing: "[[Nota]] ^id(3)"))
        #expect(parsed == .task(noteTitle: "Nota", localID: 3))
    }

    @Test func parseFailsOnAnythingThatIsNotAWikilink() {
        #expect(PraticaLinkReference(parsing: "Titolo semplice") == nil)
        #expect(PraticaLinkReference(parsing: "[[Nota]] ^parent(3)") == nil)
        #expect(PraticaLinkReference(parsing: "") == nil)
    }
}

@Suite struct PraticaLinksTests {
    // MARK: - Recognition and default

    @Test func parsingNoForeignKeysYieldsEmpty() {
        #expect(PraticaLinks.parse([]) == .empty)
    }

    @Test func parsesAllThreeKeys() throws {
        let foreignKeys: [Frontmatter.ForeignKey] = [
            .init(name: "pergamenum-dossier-links-notes", lines: [
                "pergamenum-dossier-links-notes:",
                "  - \"[[Offerta 2026]]\"",
            ]),
            .init(name: "pergamenum-dossier-links-tasks", lines: [
                "pergamenum-dossier-links-tasks:",
                "  - \"[[Follow-up]] ^id(3)\"",
            ]),
            .init(name: "pergamenum-dossier-links-boards", lines: [
                "pergamenum-dossier-links-boards:",
                "  - \"[[Rossi.canvas]]\"",
            ]),
        ]
        let links = PraticaLinks.parse(foreignKeys)
        #expect(links.notes == ["Offerta 2026"])
        #expect(links.tasks == [PraticaLinks.TaskReference(noteTitle: "Follow-up", localID: 3)])
        #expect(links.boards == ["Rossi.canvas"])
    }

    // MARK: - Rendering, in `ownedKeys`' order

    @Test func rendersTheThreeKeysInOrder() {
        var links = PraticaLinks()
        links.notes = ["Offerta 2026"]
        links.tasks = [PraticaLinks.TaskReference(noteTitle: "Follow-up", localID: 3)]
        links.boards = ["Rossi.canvas"]
        let lines = PraticaLinks.render(links).flatMap(\.lines)
        #expect(lines == [
            "pergamenum-dossier-links-notes:",
            "  - \"[[Offerta 2026]]\"",
            "pergamenum-dossier-links-tasks:",
            "  - \"[[Follow-up]] ^id(3)\"",
            "pergamenum-dossier-links-boards:",
            "  - \"[[Rossi.canvas]]\"",
        ])
    }

    @Test func omitsAnEmptyKeyRatherThanWritingItEmpty() {
        #expect(PraticaLinks.render(.empty).isEmpty)
    }

    // MARK: - §D1: foreign to `Dossier`, both merges byte-preserving in either order

    @Test func aPraticaMdCarryingDossierAndLinksKeysRoundTripsThroughBothMergesInEitherOrder() throws {
        let original: [Frontmatter.ForeignKey] = [
            .init(name: "pergamenum-dossier", lines: ["pergamenum-dossier: 1"]),
            .init(name: "pergamenum-dossier-counterparts", lines: [
                "pergamenum-dossier-counterparts:",
                "  - m.rossi@rossi-spa.it",
            ]),
            .init(name: "pergamenum-dossier-links-notes", lines: [
                "pergamenum-dossier-links-notes:",
                "  - \"[[Offerta 2026]]\"",
            ]),
        ]

        let dossier = try #require(Dossier.parse(original))
        let links = PraticaLinks.parse(original)

        let dossierThenLinks = PraticaLinks.merging(links, into: Dossier.merging(dossier, into: original))
        let linksThenDossier = Dossier.merging(dossier, into: PraticaLinks.merging(links, into: original))
        #expect(dossierThenLinks == original)
        #expect(linksThenDossier == original)
    }

    @Test func mergingReplacesOwnedKeysInPlaceAndAppendsNewOnesAtTheEnd() {
        let original: [Frontmatter.ForeignKey] = [
            .init(name: "pergamenum-dossier", lines: ["pergamenum-dossier: 1"]),
            .init(name: "pergamenum-dossier-links-notes", lines: [
                "pergamenum-dossier-links-notes:",
                "  - \"[[Vecchia]]\"",
            ]),
            .init(name: "obsidian-icon", lines: ["obsidian-icon: 📁"]),
        ]
        var links = PraticaLinks.parse(original)
        links.notes = ["Nuova"]
        links.boards = ["Rossi.canvas"]

        let merged = PraticaLinks.merging(links, into: original)
        #expect(merged.map(\.name) == [
            "pergamenum-dossier", "pergamenum-dossier-links-notes", "obsidian-icon", "pergamenum-dossier-links-boards",
        ])
        #expect(merged.first { $0.name == "pergamenum-dossier-links-notes" }?.lines == [
            "pergamenum-dossier-links-notes:", "  - \"[[Nuova]]\"",
        ])
    }

    // MARK: - §D4: reads the file, never the index

    @Test func parsingAPraticaFileWithNoLinksYieldsEmptyRatherThanCrashing() {
        let missing = URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID().uuidString)/pratica.md")
        #expect(PraticaLinks.parse(praticaFileAt: missing) == .empty)
    }

    @Test func parsesLinksFromARealFileOnDisk() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("pratica.md")
        let text = """
        ---
        date: 2026-06-10
        tags:
          - type-note
        pergamenum-dossier: 1
        pergamenum-dossier-links-notes:
          - "[[Offerta 2026]]"
        ---

        """
        try text.write(to: url, atomically: true, encoding: .utf8)

        let links = PraticaLinks.parse(praticaFileAt: url)
        #expect(links.notes == ["Offerta 2026"])
    }
}

// MARK: - R-07: rename passes already rewrite these bytes (§D2, §D3)

@Suite struct PraticaLinkRenameTests {
    @Test func aNoteRenameFollowsTheLinkInARenderedPraticaMd() throws {
        var links = PraticaLinks()
        links.notes = ["Vecchia"]
        let rendered = PraticaLinks.render(links).flatMap(\.lines).joined(separator: "\n")

        let rewritten = try #require(NoteRename.rewritingLinks(in: rendered, from: "Vecchia", to: "Nuova"))
        let parsedBack = PraticaLinks.parse([.init(name: "x", lines: rewritten.components(separatedBy: "\n"))])
        #expect(parsedBack.notes == ["Nuova"])
    }

    @Test func aBoardRenameFollowsTheLinkInARenderedPraticaMd() throws {
        var links = PraticaLinks()
        links.boards = ["Vecchia.canvas"]
        let rendered = PraticaLinks.render(links).flatMap(\.lines).joined(separator: "\n")

        let rewritten = try #require(
            NoteRename.rewritingLinks(in: rendered, from: "Vecchia.canvas", to: "Nuova.canvas")
        )
        let parsedBack = PraticaLinks.parse([.init(name: "x", lines: rewritten.components(separatedBy: "\n"))])
        #expect(parsedBack.boards == ["Nuova.canvas"])
    }

    @Test func aTaskReferenceKeepsItsCaretIDAcrossItsNoteBeingRenamed() throws {
        var links = PraticaLinks()
        links.tasks = [PraticaLinks.TaskReference(noteTitle: "Vecchia", localID: 3)]
        let rendered = PraticaLinks.render(links).flatMap(\.lines).joined(separator: "\n")

        let rewritten = try #require(NoteRename.rewritingLinks(in: rendered, from: "Vecchia", to: "Nuova"))
        let parsedBack = PraticaLinks.parse([.init(name: "x", lines: rewritten.components(separatedBy: "\n"))])
        #expect(parsedBack.tasks == [PraticaLinks.TaskReference(noteTitle: "Nuova", localID: 3)])
    }

    @Test func aNoteRenameFollowsTheLinkOnARenderedMessageFile() throws {
        let line = MessageDocument.noteLine(for: PraticaLinkReference.wikilink("Vecchia").rendered)
        let rewritten = try #require(NoteRename.rewritingLinks(in: line, from: "Vecchia", to: "Nuova"))
        #expect(rewritten == "pergamenum-mail-note: \"[[Nuova]]\"")
    }
}

// MARK: - R-08: resolution

@Suite struct PraticaLinkResolverTests {
    @Test func noteResolvesUniqueWhenExactlyOneCandidateMatches() {
        #expect(PraticaLinkResolver.note(candidates: ["Note/Offerta.md"]) == .unique("Note/Offerta.md"))
    }

    @Test func noteResolvesMissingWhenTheTargetIsNoLongerAmongTheCandidates() {
        #expect(PraticaLinkResolver.note(candidates: []) == .missing)
    }

    @Test func noteResolvesAmbiguousOnMoreThanOneCandidate() {
        #expect(PraticaLinkResolver.note(candidates: ["A.md", "B.md"]) == .ambiguous)
    }

    @Test func boardDelegatesToWorkspaceBoardResolverCaseForCase() {
        #expect(
            PraticaLinkResolver.board("Rossi.canvas", boards: ["Cartella/Rossi.canvas"])
                == .unique("Cartella/Rossi.canvas")
        )
        #expect(PraticaLinkResolver.board("Rossi.canvas", boards: []) == .missing)
        #expect(
            PraticaLinkResolver.board("Rossi.canvas", boards: ["A/Rossi.canvas", "B/Rossi.canvas"]) == .ambiguous
        )
    }

    @Test func taskResolvesUniqueWhenTheNoteIsUniqueAndCarriesTheID() {
        #expect(
            PraticaLinkResolver.task(localID: 3, noteCandidates: ["Note/Follow-up.md"], localIDsInResolvedNote: [1, 3])
                == .unique("Note/Follow-up.md")
        )
    }

    @Test func taskResolvesMissingWhenTheNoteNoLongerCarriesThatID() {
        #expect(
            PraticaLinkResolver.task(localID: 9, noteCandidates: ["Note/Follow-up.md"], localIDsInResolvedNote: [1, 3])
                == .missing
        )
    }

    @Test func taskFollowsTheNoteHalfsResolution() {
        #expect(
            PraticaLinkResolver.task(localID: 3, noteCandidates: [], localIDsInResolvedNote: []) == .missing
        )
        #expect(
            PraticaLinkResolver.task(localID: 3, noteCandidates: ["A.md", "B.md"], localIDsInResolvedNote: [3])
                == .ambiguous
        )
    }
}
