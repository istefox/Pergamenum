import Foundation
import Testing
@testable import Pergamenum

/// R-20 (ADR-0083 §D7): what the Cmd+hover preview shows, decided without a view. The pure
/// `make(for:section:noteText:)` takes the destination and a way to read a note's text; the
/// controller's `linkPreviewContent(for:section:)` is the same rule over a real vault.
@Suite struct LinkPreviewContentTests {
    private static func body(_ count: Int) -> String {
        (1...count).map { "riga \($0)" }.joined(separator: "\n")
    }

    private static func text(body: String) -> String {
        "---\ndate: 2026-10-01\ntags:\n  - type-note\n---\n\(body)\n"
    }

    private static func lines(of content: LinkPreviewContent?) -> [String]? {
        guard case .note(_, let lines, _)? = content?.kind else { return nil }
        return lines
    }

    // MARK: A note

    @Test func aNoteShowsItsTitleAndNoMoreThanTwelveLinesOfItsBody() {
        let note = Self.text(body: Self.body(30))
        let content = LinkPreviewContent.make(
            for: .note(path: "Progetti/Alfa.md"), section: nil, noteText: { _ in note }
        )
        guard case .note(let title, let lines, let missing)? = content?.kind else {
            Issue.record("expected a .note preview, got \(String(describing: content))")
            return
        }
        #expect(LinkPreviewContent.lineLimit == 12)
        #expect(title == "Alfa")
        #expect(lines.count == 12)
        #expect(lines.contains("riga 1"))
        #expect(!lines.contains("riga 13"))
        #expect(missing == nil)
    }

    @Test func aShortNoteShowsAllOfItsLines() {
        let note = Self.text(body: Self.body(3))
        let lines = Self.lines(of: LinkPreviewContent.make(
            for: .note(path: "Alfa.md"), section: nil, noteText: { _ in note }
        ))
        #expect(lines?.contains("riga 1") == true)
        #expect(lines?.contains("riga 3") == true)
    }

    @Test func theFrontmatterIsNeverShown() {
        let note = Self.text(body: Self.body(3))
        let lines = Self.lines(of: LinkPreviewContent.make(
            for: .note(path: "Alfa.md"), section: nil, noteText: { _ in note }
        )) ?? []
        #expect(!lines.contains { $0.contains("date:") || $0.contains("type-note") || $0 == "---" })
    }

    @Test func aSectionShowsWhatTranscludingItShows() {
        let note = Self.text(body: """
        ## Prima
        solo nella prima
        ## Seconda
        dentro la seconda
        ## Terza
        solo nella terza
        """)
        let content = LinkPreviewContent.make(
            for: .note(path: "Alfa.md"), section: "Seconda", noteText: { _ in note }
        )
        let lines = Self.lines(of: content) ?? []
        #expect(lines.contains("dentro la seconda"))
        #expect(!lines.contains("solo nella prima"))
        #expect(!lines.contains("solo nella terza"))
        if case .note(_, _, let missing)? = content?.kind { #expect(missing == nil) }
    }

    @Test func aSectionNoHeadingAnswersToIsNamedAsMissing() {
        let note = Self.text(body: "## Prima\nsolo nella prima")
        let content = LinkPreviewContent.make(
            for: .note(path: "Alfa.md"), section: "Inesistente", noteText: { _ in note }
        )
        guard case .note(_, _, let missing)? = content?.kind else {
            Issue.record("expected a .note preview, got \(String(describing: content))")
            return
        }
        #expect(missing == "Inesistente")
    }

    @Test func aNoteThatCannotBeReadHasNoPreview() {
        let content = LinkPreviewContent.make(
            for: .note(path: "Alfa.md"), section: nil, noteText: { _ in nil }
        )
        #expect(content == nil)
    }

    // MARK: A board, several notes, none

    @Test func aBoardShowsItsName() {
        let content = LinkPreviewContent.make(
            for: .board(path: "Progetti/Piano.canvas"), section: nil, noteText: { _ in nil }
        )
        guard case .board(let name)? = content?.kind else {
            Issue.record("expected a .board preview, got \(String(describing: content))")
            return
        }
        // SPEC: «a board link shows the board name». Whether the name keeps `.canvas` is not
        // stated, so either spelling is accepted.
        #expect(name == "Piano" || name == "Piano.canvas")
    }

    @Test func severalNotesShowTheirFoldersAndNeverTheirText() {
        let content = LinkPreviewContent.make(
            for: .ambiguous(title: "Riunione", paths: ["Clienti/Riunione.md", "Riunione.md"]),
            section: nil,
            noteText: { _ in "contenuto che non deve comparire" }
        )
        #expect(content == LinkPreviewContent(kind: .ambiguous(
            title: "Riunione", folders: ["Clienti", LinkChoice.rootLabel]
        )))
    }

    @Test func aMissingTitleSaysSoAndWhetherItCanBeCreated() {
        let creatable = LinkPreviewContent.make(
            for: .missing(title: "Bozza", creatable: true), section: nil, noteText: { _ in nil }
        )
        #expect(creatable == LinkPreviewContent(kind: .missing(title: "Bozza", creatable: true)))

        let notCreatable = LinkPreviewContent.make(
            for: .missing(title: "TRUST.md", creatable: false), section: nil, noteText: { _ in nil }
        )
        #expect(notCreatable == LinkPreviewContent(kind: .missing(title: "TRUST.md", creatable: false)))
    }
}

/// The same rule over a real vault: `VaultController.linkPreviewContent(for:section:)` resolves the
/// target through the one destination rule and reads the note's text itself.
@MainActor
@Suite struct VaultLinkPreviewContent {
    @Test func aUniqueNoteTitleGivesItsPreview() async throws {
        let vault = try TemporaryVault()
        try vault.write(LinkFixtures.note("Una riga di prova."), to: "Progetti/Alfa.md")
        let controller = await LinkFixtures.controller(root: vault.root)

        let content = controller.linkPreviewContent(for: "Alfa", section: nil)

        guard case .note(let title, let lines, _)? = content?.kind else {
            Issue.record("expected a .note preview, got \(String(describing: content))")
            return
        }
        #expect(title == "Alfa")
        #expect(lines.contains("Una riga di prova."))
        controller.close()
    }

    @Test func aSharedTitleGivesTheFolderList() async throws {
        let vault = try TemporaryVault()
        try LinkFixtures.writeSharedTitleVault(in: vault)
        let controller = await LinkFixtures.controller(root: vault.root)

        let content = controller.linkPreviewContent(for: "Riunione", section: nil)

        guard case .ambiguous(let title, let folders)? = content?.kind else {
            Issue.record("expected an .ambiguous preview, got \(String(describing: content))")
            return
        }
        #expect(title == "Riunione")
        #expect(Set(folders) == ["Clienti", "Progetti"])
        controller.close()
    }

    @Test func aDanglingCreatableTitleSaysSo() async throws {
        let vault = try TemporaryVault()
        try vault.write(LinkFixtures.note(), to: "Alfa.md")
        let controller = await LinkFixtures.controller(root: vault.root)

        let content = controller.linkPreviewContent(for: "Bozza", section: nil)

        #expect(content == LinkPreviewContent(kind: .missing(title: "Bozza", creatable: true)))
        controller.close()
    }

    @Test func aBoardShowsItsName() async throws {
        let vault = try TemporaryVault()
        try vault.write(LinkFixtures.note(), to: "Alfa.md")
        try vault.write(#"{"nodes":[],"edges":[]}"#, to: "Piano.canvas")
        let controller = await LinkFixtures.controller(root: vault.root)

        let content = controller.linkPreviewContent(for: "Piano.canvas", section: nil)

        guard case .board(let name)? = content?.kind else {
            Issue.record("expected a .board preview, got \(String(describing: content))")
            return
        }
        #expect(name == "Piano" || name == "Piano.canvas")
        controller.close()
    }

    @Test func anExternalTargetNeverGetsContent() async throws {
        let vault = try TemporaryVault()
        try vault.write(LinkFixtures.note(), to: "Alfa.md")
        let controller = await LinkFixtures.controller(root: vault.root)

        #expect(controller.linkPreviewContent(for: "https://example.com/pagina", section: nil) == nil)
        controller.close()
    }
}
