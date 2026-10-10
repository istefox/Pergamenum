import Foundation
import Testing
@testable import Pergamenum

/// (coverage) N3 session B (ADR-0083 §D3, §D5, §D6): paths of the follow door and of the inputs a host
/// is handed that the requirement tests of `LinkFollowCommandTests` do not reach. Each asserts only
/// what the code's documented contract and the existing callers already state; none adds a requirement.
@MainActor
@Suite struct LinkFollowCoverageTests {
    private static func setUp(_ vault: borrowing TemporaryVault) async throws -> CommandActions {
        try LinkFixtures.writeSharedTitleVault(in: vault)
        try vault.write(LinkFixtures.note("Alfa."), to: "Alfa.md")
        return await LinkFixtures.actions(root: vault.root)
    }

    // MARK: The keyboard follow decodes the link the way a click does

    @Test func followLinkOnATagUrlOpensTheTagsPaneWhateverTheVariant() async throws {
        let vault = try TemporaryVault()
        let actions = try await Self.setUp(vault)
        actions.vault.openNote(at: "Alfa.md")
        let acme = Pergamenum.Tag("#client-acme")!  // as CommandActionNavigationTests does: `#require` cannot take a module-qualified call
        actions.vault.recordLinkAtCaret(MarkdownAttributedText.tagURL(for: acme), inColumn: 0)
        actions.navigation.pane = .notes

        actions.run(.followLinkInNewTab)

        #expect(actions.navigation.pane == .tags)
        #expect(actions.navigation.takeTagFilter() == acme)
        #expect(actions.vault.tabs.map(\.note.relativePath) == ["Alfa.md"])
        actions.vault.close()
    }

    @Test func followLinkOnADayUrlOpensTheDayInOggi() async throws {
        let vault = try TemporaryVault()
        let actions = try await Self.setUp(vault)
        actions.vault.openNote(at: "Alfa.md")
        let target = try #require(CalendarDate(iso: "2026-10-12"))
        actions.vault.recordLinkAtCaret(MarkdownAttributedText.dayURL(for: target), inColumn: 0)
        actions.navigation.pane = .notes

        actions.run(.followLink)

        #expect(actions.navigation.pane == .today)
        #expect(actions.day.day == target)
        actions.vault.close()
    }

    @Test func followLinkOnAFileEmbedDoesNothing() async throws {
        let vault = try TemporaryVault()
        let actions = try await Self.setUp(vault)
        actions.vault.openNote(at: "Alfa.md")
        actions.vault.recordLinkAtCaret(MarkdownAttributedText.embedURL(for: "immagine.png"), inColumn: 0)
        actions.navigation.pane = .notes

        actions.run(.followLinkInOtherColumn)

        #expect(actions.navigation.pane == .notes)
        #expect(actions.navigation.linkChoice == nil)
        #expect(actions.vault.columns.count == 1)
        #expect(actions.vault.openNote?.relativePath == "Alfa.md")
        actions.vault.close()
    }

    @Test func followLinkOnAMissingNonCreatableTitleNamesItInsteadOfStayingSilent() async throws {
        let vault = try TemporaryVault()
        let actions = try await Self.setUp(vault)
        actions.vault.openNote(at: "Alfa.md")
        actions.vault.recordLinkAtCaret(LinkFixtures.url(for: "TRUST.md"), inColumn: 0)
        actions.navigation.pane = .notes

        actions.run(.followLink)

        #expect(actions.vault.problems.contains("nota non trovata: TRUST.md"))
        #expect(actions.navigation.linkChoice == nil)
        actions.vault.close()
    }

    @Test func aBoardNameNoBoardAnswersToIsAProblemNotAChoice() async throws {
        let vault = try TemporaryVault()
        let actions = try await Self.setUp(vault)

        actions.open(link: "Assente.canvas", how: .newTab, from: "Alfa.md")

        #expect(actions.vault.problems.contains("board non trovata: Assente.canvas"))
        #expect(actions.vault.routeState.pendingCanvas == nil)
        #expect(actions.navigation.linkChoice == nil)
        actions.vault.close()
    }

    // MARK: The creation offer's folder

    @Test func theOfferBesideARootNoteHasNoFolder() async throws {
        let vault = try TemporaryVault()
        let actions = try await Self.setUp(vault)

        actions.vault.offerNoteCreation(title: "Bozza", besideNoteAt: "Alfa.md")

        #expect(actions.vault.noteDraft?.title == "Bozza")
        #expect(actions.vault.noteDraft?.folder == "")
        actions.vault.close()
    }

    @Test func theOfferWithNoSourceNoteHasNoFolder() async throws {
        let vault = try TemporaryVault()
        let actions = try await Self.setUp(vault)

        actions.vault.offerNoteCreation(title: "Bozza", besideNoteAt: nil)

        #expect(actions.vault.noteDraft?.title == "Bozza")
        #expect(actions.vault.noteDraft?.folder == "")
        #expect(actions.vault.isComposingNote)
        actions.vault.close()
    }

    @Test func aSecondOfferReplacesAnEmptyDraftWithoutASentence() async throws {
        let vault = try TemporaryVault()
        let actions = try await Self.setUp(vault)
        actions.vault.offerNoteCreation(title: "Prima", besideNoteAt: "Progetti/Sorgente.md")
        actions.vault.leaveComposer()
        actions.vault.noteDraft?.title = "   "

        actions.vault.offerNoteCreation(title: "Seconda", besideNoteAt: "Clienti/Riunione.md")

        #expect(actions.vault.noteDraft?.title == "Seconda")
        #expect(actions.vault.noteDraft?.folder == "Clienti")
        #expect(!actions.vault.problems.contains(
            "Una nota è già in preparazione: completala o annullala, poi riprova"
        ))
        actions.vault.close()
    }

    // MARK: The inputs a host is handed

    @Test func theOfferInputOffersTheTitleBesideTheSourceAndShowsTheNotePane() async throws {
        let vault = try TemporaryVault()
        let actions = try await Self.setUp(vault)
        actions.navigation.pane = .today

        actions.linkInputs(from: "Progetti/Sorgente.md", column: nil).offerCreation?("Bozza")

        #expect(actions.vault.noteDraft?.title == "Bozza")
        #expect(actions.vault.noteDraft?.folder == "Progetti")
        #expect(actions.vault.isComposingNote)
        #expect(actions.navigation.pane == .notes)
        actions.vault.close()
    }

    @Test func aHostWithNoColumnReportsNoCaretLink() async throws {
        let vault = try TemporaryVault()
        let actions = try await Self.setUp(vault)

        let inputs = actions.linkInputs(from: "Alfa.md", column: nil)

        #expect(inputs.onCaretLinkChanged == nil)
        #expect(inputs.follow != nil)
        actions.vault.close()
    }

    @Test func theChoiceInputFocusesTheColumnThenOpensInTheClicksWay() async throws {
        let vault = try TemporaryVault()
        let actions = try await Self.setUp(vault)
        actions.vault.openNote(at: "Alfa.md")
        actions.vault.splitEditor()
        actions.vault.openNote(at: "Unica.md")
        actions.vault.focusColumn(0)
        var prepared = 0
        let inputs = actions.linkInputs(from: "Alfa.md", column: 1) { prepared += 1 }
        let choice = try #require(LinkChoice.entries(for: .ambiguous(
            title: "Riunione", paths: ["Clienti/Riunione.md", "Progetti/Riunione.md"]
        )).last)

        inputs.choose?(choice, .replace)

        #expect(prepared == 1)
        #expect(actions.vault.focusedColumnIndex == 1)
        #expect(actions.vault.columns[1].active.map(\.note.relativePath) == "Progetti/Riunione.md")
        #expect(actions.vault.columns[0].active.map(\.note.relativePath) == "Alfa.md")
        actions.vault.close()
    }
}

/// (coverage) The ledger the caret-link report rides on (`NoteTextView+Requests.swift`): the report
/// fires when the answer changes, and a note switch starts the answer over, since the tab it lands
/// on carries no link (the doc comment on `lastCaretLink`).
@MainActor
@Suite struct CaretLinkLedgerCoverageTests {
    private let url = MarkdownAttributedText.noteURL(for: "Destinazione")

    @Test func aRepeatedAnswerIsNotClaimedTwice() {
        let ledger = RequestLedger(parent: { nil })

        #expect(ledger.claimCaretLink(url))
        #expect(!ledger.claimCaretLink(url))
        #expect(ledger.claimCaretLink(nil))
        #expect(!ledger.claimCaretLink(nil))
    }

    @Test func theFirstAnswerIsClaimedEvenWhenItIsNoLink() {
        let ledger = RequestLedger(parent: { nil })

        #expect(ledger.claimCaretLink(nil))
    }

    @Test func aNoteSwitchMakesTheSameLinkClaimableAgain() {
        let ledger = RequestLedger(parent: { nil })
        _ = ledger.claimNotePath("A.md")
        #expect(ledger.claimCaretLink(url))
        #expect(!ledger.claimCaretLink(url))

        #expect(ledger.claimNotePath("B.md"))

        #expect(ledger.claimCaretLink(url))
    }

    @Test func theSameNotePathDoesNotResetTheLedger() {
        let ledger = RequestLedger(parent: { nil })
        _ = ledger.claimNotePath("A.md")
        #expect(ledger.claimCaretLink(url))

        #expect(!ledger.claimNotePath("A.md"))

        #expect(!ledger.claimCaretLink(url))
    }
}
