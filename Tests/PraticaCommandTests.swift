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
    @Test func theCatalogueHasExactlyTenCommands() {
        #expect(PraticaCommand.allCases.count == 10)
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
            for always: PraticaCommand in [
                .open, .rename, .refresh, .revealInFinder, .linkNote, .linkTask, .linkBoard, .delete,
            ] {
                #expect(commands.contains(always), "\(always) should be offered regardless of status")
            }
        }
    }

    // MARK: - R-01: the three link commands join the catalogue before `.delete`

    @Test func theThreeLinkCommandsAreDeclaredBeforeDeleteSoTheDividerStaysCorrect() throws {
        let ordered = PraticaCommand.available(isActive: true)
        let deleteIndex = try #require(ordered.firstIndex(of: .delete))
        for link: PraticaCommand in [.linkNote, .linkTask, .linkBoard] {
            let linkIndex = try #require(ordered.firstIndex(of: link))
            #expect(linkIndex < deleteIndex, "\(link) must be drawn above the `.delete` divider")
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
            .linkNote: "Collega una nota…",
            .linkTask: "Collega un'attività…",
            .linkBoard: "Collega una board…",
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
    @Test func theCatalogueHasExactlyEightCommands() {
        #expect(MessageCommand.allCases.count == 8)
    }

    // MARK: - R-31: applicability

    @Test func previewAttachmentIsOfferedOnlyWhenTheMessageHasOne() {
        #expect(MessageCommand.available(hasAttachments: true, hasLinkedNote: false).contains(.previewAttachment))
        #expect(!MessageCommand.available(hasAttachments: false, hasLinkedNote: false).contains(.previewAttachment))
    }

    // MARK: - R-02: `.unlinkNote` only when there is something to unlink

    @Test func unlinkNoteIsOfferedOnlyWhenTheMessageHasALinkedNote() {
        #expect(MessageCommand.available(hasAttachments: false, hasLinkedNote: true).contains(.unlinkNote))
        #expect(!MessageCommand.available(hasAttachments: false, hasLinkedNote: false).contains(.unlinkNote))
    }

    @Test func linkNoteIsOfferedRegardlessOfAnExistingLink() {
        #expect(MessageCommand.available(hasAttachments: false, hasLinkedNote: true).contains(.linkNote))
        #expect(MessageCommand.available(hasAttachments: false, hasLinkedNote: false).contains(.linkNote))
    }

    @Test func everyOtherCommandIsOfferedRegardlessOfAttachments() {
        for hasAttachments in [true, false] {
            let commands = MessageCommand.available(hasAttachments: hasAttachments, hasLinkedNote: false)
            for always: MessageCommand in [.openInMail, .exclude, .moveTo, .alsoAddTo, .regenerate, .linkNote] {
                #expect(commands.contains(always))
            }
        }
    }

    @Test func moveToAndAlsoAddToCarryAnArgumentNoOtherCommandDoes() {
        #expect(MessageCommand.moveTo.carriesArgument)
        #expect(MessageCommand.alsoAddTo.carriesArgument)
        for command: MessageCommand in [
            .openInMail, .previewAttachment, .exclude, .regenerate, .linkNote, .unlinkNote,
        ] {
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
            .linkNote: "Collega nota…",
            .unlinkNote: "Scollega nota",
        ]
        for command in MessageCommand.allCases {
            #expect(command.title == expected[command])
        }
    }
}
