import Foundation
import Testing
@testable import Pergamenum

/// R-21, R-22, R-23 (ADR-0083 §D1, §D3, §D5, §D6): `CommandActions`' open-link door, the choice it
/// raises for a shared title, the creation offer for a dangling one, the three keyboard commands
/// and the inputs every editor host is handed.
@MainActor
@Suite struct LinkFollowCommandTests {
    private static func setUp(_ vault: borrowing TemporaryVault) async throws -> CommandActions {
        try LinkFixtures.writeSharedTitleVault(in: vault)
        try vault.write(LinkFixtures.note("Alfa."), to: "Alfa.md")
        try vault.write(#"{"nodes":[],"edges":[]}"#, to: "Piano.canvas")
        return await LinkFixtures.actions(root: vault.root)
    }

    private static func twoColumns(_ actions: CommandActions) {
        actions.vault.openNote(at: "Alfa.md")
        actions.vault.splitEditor()
        actions.vault.openNote(at: "Unica.md")
        actions.vault.focusColumn(0)
    }

    // MARK: Several matches are a choice

    @Test func anAmbiguousTitleRaisesTheChoiceAndOpensNothing() async throws {
        let vault = try TemporaryVault()
        let actions = try await Self.setUp(vault)
        actions.navigation.pane = .workspace

        actions.open(link: "Riunione", how: .newTab, from: "Progetti/Sorgente.md")

        let request = try #require(actions.navigation.linkChoice)
        #expect(request.title == "Riunione")
        #expect(request.how == .newTab)
        #expect(request.sourcePath == "Progetti/Sorgente.md")
        #expect(Set(request.choices.map(\.label)) == ["Clienti", "Progetti"])
        #expect(actions.vault.openNote == nil)
        #expect(actions.navigation.pane == .workspace)
        actions.vault.close()
    }

    @Test func aClickOnAnAmbiguousTitleReturnsTheChoiceAndSetsNoSheet() async throws {
        let vault = try TemporaryVault()
        let actions = try await Self.setUp(vault)

        let outcome = actions.follow(LinkRequest(
            target: "Riunione", how: .replace, sourcePath: "Progetti/Sorgente.md", fromClick: true
        ))

        guard case .choose(let choices) = outcome else {
            Issue.record("expected .choose, got \(outcome)")
            return
        }
        #expect(choices.count == 2)
        #expect(choices.contains { $0.action == .open(path: "Clienti/Riunione.md") })
        #expect(choices.contains { $0.action == .open(path: "Progetti/Riunione.md") })
        #expect(actions.navigation.linkChoice == nil)
        #expect(actions.vault.openNote == nil)
        actions.vault.close()
    }

    @Test func aFollowThatIsNotAClickRaisesTheSheetInsteadOfReturningTheChoice() async throws {
        let vault = try TemporaryVault()
        let actions = try await Self.setUp(vault)

        let outcome = actions.follow(LinkRequest(
            target: "Riunione", how: .replace, sourcePath: nil, fromClick: false
        ))

        #expect(outcome == .done)
        #expect(actions.navigation.linkChoice?.choices.count == 2)
        #expect(actions.vault.openNote == nil)
        actions.vault.close()
    }

    @Test func aUniqueTitleOpensInTheRequestedWayAndSwitchesToTheNotePane() async throws {
        let vault = try TemporaryVault()
        let actions = try await Self.setUp(vault)
        actions.vault.openNote(at: "Alfa.md")
        actions.navigation.pane = .today

        let outcome = actions.follow(LinkRequest(target: "Unica", how: .newTab, sourcePath: "Alfa.md", fromClick: true))

        #expect(outcome == .done)
        #expect(actions.vault.tabs.map(\.note.relativePath) == ["Alfa.md", "Unica.md"])
        #expect(actions.navigation.pane == .notes)
        #expect(actions.navigation.linkChoice == nil)
        actions.vault.close()
    }

    @Test func aPickedRowOpensThatPathInTheClicksWay() async throws {
        let vault = try TemporaryVault()
        let actions = try await Self.setUp(vault)
        actions.vault.openNote(at: "Alfa.md")
        let choice = try #require(LinkChoice.entries(for: .ambiguous(
            title: "Riunione", paths: ["Clienti/Riunione.md", "Progetti/Riunione.md"]
        )).last)

        actions.choose(choice, how: .newTab, from: "Alfa.md")

        #expect(actions.vault.openNote?.relativePath == "Progetti/Riunione.md")
        #expect(actions.vault.tabs.map(\.note.relativePath) == ["Alfa.md", "Progetti/Riunione.md"])
        actions.vault.close()
    }

    @Test func aBoardOpensTheBoardWhateverTheHow() async throws {
        let vault = try TemporaryVault()
        let actions = try await Self.setUp(vault)
        actions.vault.openNote(at: "Alfa.md")

        actions.open(link: "Piano.canvas", how: .otherColumn, from: "Alfa.md")

        #expect(actions.vault.routeState.pendingCanvas?.path == "Piano.canvas")
        #expect(actions.vault.columns.count == 1)
        #expect(actions.navigation.linkChoice == nil)
        actions.vault.close()
    }

    // MARK: A dangling link offers its note

    @Test func aCreatableMissingTitleGivesTheOneCreateChoice() async throws {
        let vault = try TemporaryVault()
        let actions = try await Self.setUp(vault)

        actions.open(link: "Bozza", from: "Progetti/Sorgente.md")

        let request = try #require(actions.navigation.linkChoice)
        #expect(request.choices.map(\.action) == [.create(title: "Bozza")])
        #expect(!actions.vault.problems.contains("nota non trovata: Bozza"))
        actions.vault.close()
    }

    @Test func aClickOnACreatableMissingTitleReturnsTheOneCreateChoice() async throws {
        let vault = try TemporaryVault()
        let actions = try await Self.setUp(vault)

        let outcome = actions.follow(LinkRequest(target: "Bozza", how: .replace, sourcePath: nil, fromClick: true))

        #expect(outcome == .choose(LinkChoice.entries(for: .missing(title: "Bozza", creatable: true))))
        actions.vault.close()
    }

    @Test func choosingCreateOffersTheTitleBesideTheSourceAndShowsTheComposer() async throws {
        let vault = try TemporaryVault()
        let actions = try await Self.setUp(vault)
        actions.navigation.pane = .today
        let create = try #require(LinkChoice.entries(for: .missing(title: "Bozza", creatable: true)).first)

        actions.choose(create, how: .replace, from: "Progetti/Sorgente.md")

        #expect(actions.vault.noteDraft?.title == "Bozza")
        #expect(actions.vault.noteDraft?.folder == "Progetti")
        #expect(actions.vault.isComposingNote)
        #expect(actions.navigation.pane == .notes)
        actions.vault.close()
    }

    @Test func theOfferNeverCreatesAFile() async throws {
        let vault = try TemporaryVault()
        let actions = try await Self.setUp(vault)
        let create = try #require(LinkChoice.entries(for: .missing(title: "Bozza", creatable: true)).first)

        actions.choose(create, how: .replace, from: nil)

        #expect(!FileManager.default.fileExists(atPath: vault.root.appending(path: "Bozza.md").path))
        actions.vault.close()
    }

    @Test func aParkedDraftWithATitleIsKeptAndTheSentenceRecorded() async throws {
        let vault = try TemporaryVault()
        let actions = try await Self.setUp(vault)
        actions.vault.beginNewNote()
        actions.vault.parkNewNote(VaultController.NoteDraft(folder: "Clienti", title: "Già qui"))
        actions.vault.leaveComposer()

        actions.vault.offerNoteCreation(title: "Bozza", besideNoteAt: "Progetti/Sorgente.md")

        #expect(actions.vault.noteDraft?.title == "Già qui")
        #expect(actions.vault.noteDraft?.folder == "Clienti")
        #expect(actions.vault.isComposingNote)
        #expect(actions.vault.problems.contains(
            "Una nota è già in preparazione: completala o annullala, poi riprova"
        ))
        actions.vault.close()
    }

    @Test func aNonCreatableTitleKeepsTheNotFoundSentence() async throws {
        let vault = try TemporaryVault()
        let actions = try await Self.setUp(vault)

        actions.open(link: "TRUST.md")

        #expect(actions.vault.problems.contains("nota non trovata: TRUST.md"))
        #expect(actions.navigation.linkChoice == nil)
        actions.vault.close()
    }

    // MARK: The keyboard

    @Test func followLinkCannotRunWithoutALinkAtTheCaret() async throws {
        let vault = try TemporaryVault()
        let actions = try await Self.setUp(vault)
        actions.vault.openNote(at: "Alfa.md")
        actions.navigation.pane = .notes

        #expect(!actions.canRun(.followLink))
        #expect(!actions.canRun(.followLinkInNewTab))
        #expect(!actions.canRun(.followLinkInOtherColumn))
        actions.vault.close()
    }

    @Test func followLinkCanRunOnlyWithALinkAndTheNotePaneInFront() async throws {
        let vault = try TemporaryVault()
        let actions = try await Self.setUp(vault)
        actions.vault.openNote(at: "Alfa.md")
        actions.vault.recordLinkAtCaret(LinkFixtures.url(for: "Unica"), inColumn: 0)

        actions.navigation.pane = .notes
        #expect(actions.canRun(.followLink))
        #expect(actions.canRun(.followLinkInNewTab))
        #expect(actions.canRun(.followLinkInOtherColumn))

        actions.navigation.pane = .tasks
        #expect(!actions.canRun(.followLink))
        actions.vault.close()
    }

    @Test func runFollowLinkFollowsTheFocusedTabsLinkInPlace() async throws {
        let vault = try TemporaryVault()
        let actions = try await Self.setUp(vault)
        actions.vault.openNote(at: "Alfa.md")
        actions.vault.recordLinkAtCaret(LinkFixtures.url(for: "Unica"), inColumn: 0)
        actions.navigation.pane = .notes

        actions.run(.followLink)

        #expect(actions.vault.openNote?.relativePath == "Unica.md")
        #expect(actions.vault.tabs.count == 1)
        actions.vault.close()
    }

    @Test func runFollowLinkInNewTabOpensABesideTab() async throws {
        let vault = try TemporaryVault()
        let actions = try await Self.setUp(vault)
        actions.vault.openNote(at: "Alfa.md")
        actions.vault.recordLinkAtCaret(LinkFixtures.url(for: "Unica"), inColumn: 0)
        actions.navigation.pane = .notes

        actions.run(.followLinkInNewTab)

        #expect(actions.vault.tabs.map(\.note.relativePath) == ["Alfa.md", "Unica.md"])
        actions.vault.close()
    }

    @Test func runFollowLinkInOtherColumnOpensTheSecondColumn() async throws {
        let vault = try TemporaryVault()
        let actions = try await Self.setUp(vault)
        actions.vault.openNote(at: "Alfa.md")
        actions.vault.recordLinkAtCaret(LinkFixtures.url(for: "Unica"), inColumn: 0)
        actions.navigation.pane = .notes

        actions.run(.followLinkInOtherColumn)

        #expect(actions.vault.columns.count == 2)
        #expect(actions.vault.focusedColumnIndex == 1)
        #expect(actions.vault.openNote?.relativePath == "Unica.md")
        actions.vault.close()
    }

    @Test func runFollowLinkOnASharedTitleRaisesTheSheet() async throws {
        let vault = try TemporaryVault()
        let actions = try await Self.setUp(vault)
        actions.vault.openNote(at: "Progetti/Sorgente.md")
        actions.vault.recordLinkAtCaret(LinkFixtures.url(for: "Riunione"), inColumn: 0)
        actions.navigation.pane = .notes

        actions.run(.followLink)

        #expect(actions.navigation.linkChoice?.choices.count == 2)
        #expect(actions.navigation.linkChoice?.sourcePath == "Progetti/Sorgente.md")
        #expect(actions.vault.openNote?.relativePath == "Progetti/Sorgente.md")
        actions.vault.close()
    }

    // MARK: The inputs a host is handed

    @Test func linkInputsAreWiredForAHost() async throws {
        let vault = try TemporaryVault()
        let actions = try await Self.setUp(vault)

        let inputs = actions.linkInputs(from: "Alfa.md", column: 0)

        #expect(inputs.follow != nil)
        #expect(inputs.choose != nil)
        #expect(inputs.preview != nil)
        #expect(inputs.onCaretLinkChanged != nil)
        actions.vault.close()
    }

    @Test func linkInputsFocusTheColumnAndRunBeforeFollowBeforeFollowing() async throws {
        let vault = try TemporaryVault()
        let actions = try await Self.setUp(vault)
        Self.twoColumns(actions)
        var seenBeforeFollow: [String?] = []
        let inputs = actions.linkInputs(from: "Alfa.md", column: 1) {
            seenBeforeFollow.append(actions.vault.openNote?.relativePath)
        }

        let outcome = inputs.follow?(LinkRequest(target: "Beta", how: .replace, sourcePath: "Alfa.md", fromClick: true))

        #expect(outcome != nil)
        #expect(seenBeforeFollow.count == 1)
        #expect(seenBeforeFollow.first != "Beta.md")
        #expect(actions.vault.focusedColumnIndex == 1)
        actions.vault.close()
    }

    @Test func linkInputsReportTheCaretLinkIntoTheirColumn() async throws {
        let vault = try TemporaryVault()
        let actions = try await Self.setUp(vault)
        Self.twoColumns(actions)
        let url = LinkFixtures.url(for: "Unica")

        actions.linkInputs(from: "Unica.md", column: 1).onCaretLinkChanged?(url)

        #expect(actions.vault.columns[1].active?.linkAtCaret == url)
        #expect(actions.vault.columns[0].active?.linkAtCaret == nil)
        actions.vault.close()
    }

    @Test func linkInputsPreviewAnswersLikeTheController() async throws {
        let vault = try TemporaryVault()
        let actions = try await Self.setUp(vault)

        let content = actions.linkInputs(from: nil, column: nil).preview?("Unica", nil)

        guard case .note(let title, _, _)? = content?.kind else {
            Issue.record("expected a .note preview, got \(String(describing: content))")
            return
        }
        #expect(title == "Unica")
        actions.vault.close()
    }
}
