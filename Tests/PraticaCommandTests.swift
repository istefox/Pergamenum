import Foundation
import Testing
@testable import Pergamenum

// ADR-0036 (Pratiche), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 7 -
// R-31, R-34.
//
// `PraticaCommand` and `MessageCommand` are the ADR-0023 shape applied to two more
// clusters: a title/symbol/applicability catalogue read by both the toolbar/menu-bar
// surface and the row's own context menu, exactly the assertion shape
// `Tests/CardCommandTests.swift` already uses for the Workspace card.
//
// RED: `PraticaCommand.available(isActive:)` and `MessageCommand.available(hasAttachments:)`
// are placeholders that always return `[]` (`CardCommand`'s own RED-phase precedent).

@Suite struct PraticaCommandTests {
    @Test func theCatalogueHasExactlySevenCommands() {
        #expect(PraticaCommand.allCases.count == 7)
    }

    // MARK: - R-34: Chiudi/Riapri are mutually exclusive

    @Test func anActivePraticaOffersCloseNeverReopen() {
        let commands = PraticaCommand.available(isActive: true)
        #expect(commands.contains(.close))
        #expect(!commands.contains(.reopen))
    }

    @Test func aClosedPraticaOffersReopenNeverClose() {
        let commands = PraticaCommand.available(isActive: false)
        #expect(commands.contains(.reopen))
        #expect(!commands.contains(.close))
    }

    @Test func everyOtherCommandIsOfferedRegardlessOfStatus() {
        for isActive in [true, false] {
            let commands = PraticaCommand.available(isActive: isActive)
            for always: PraticaCommand in [.open, .rename, .refresh, .revealInFinder, .delete] {
                #expect(commands.contains(always), "\(always) should be offered regardless of status")
            }
        }
    }

    // MARK: - Titles/symbols, pinned to UX-BLUEPRINT.md's menu bar map

    @Test func everyCommandHasItsExactItalianTitle() {
        let expected: [PraticaCommand: String] = [
            .open: "Apri",
            .rename: "Rinomina…",
            .close: "Chiudi",
            .reopen: "Riapri",
            .refresh: "Aggiorna ora",
            .revealInFinder: "Mostra nel Finder",
            .delete: "Elimina…",
        ]
        for command in PraticaCommand.allCases {
            #expect(command.title == expected[command])
        }
    }

    @Test func everyCommandHasAStableIdentifierDerivedFromItsRawValue() {
        for command in PraticaCommand.allCases {
            #expect(command.identifier == "pratiche-command-\(command.rawValue)")
        }
    }
}

@Suite struct MessageCommandTests {
    @Test func theCatalogueHasExactlySixCommands() {
        #expect(MessageCommand.allCases.count == 6)
    }

    // MARK: - R-31: applicability

    @Test func previewAttachmentIsOfferedOnlyWhenTheMessageHasOne() {
        #expect(MessageCommand.available(hasAttachments: true).contains(.previewAttachment))
        #expect(!MessageCommand.available(hasAttachments: false).contains(.previewAttachment))
    }

    @Test func everyOtherCommandIsOfferedRegardlessOfAttachments() {
        for hasAttachments in [true, false] {
            let commands = MessageCommand.available(hasAttachments: hasAttachments)
            for always: MessageCommand in [.openInMail, .exclude, .moveTo, .alsoAddTo, .regenerate] {
                #expect(commands.contains(always))
            }
        }
    }

    @Test func moveToAndAlsoAddToCarryAnArgumentNoOtherCommandDoes() {
        #expect(MessageCommand.moveTo.carriesArgument)
        #expect(MessageCommand.alsoAddTo.carriesArgument)
        for command: MessageCommand in [.openInMail, .previewAttachment, .exclude, .regenerate] {
            #expect(!command.carriesArgument)
        }
    }

    @Test func everyCommandHasItsExactItalianTitle() {
        let expected: [MessageCommand: String] = [
            .openInMail: "Apri in Mail",
            .previewAttachment: "Anteprima allegato",
            .exclude: "Escludi dalla pratica",
            .moveTo: "Sposta in…",
            .alsoAddTo: "Aggiungi anche a…",
            .regenerate: "Rigenera…",
        ]
        for command in MessageCommand.allCases {
            #expect(command.title == expected[command])
        }
    }
}
