import Foundation
import Testing
@testable import Pergamenum

// PG-263 (burn-down 2026-10-03): «Escludi dalla pratica» moves the message's files to the Trash
// and now draws the `trash` glyph, like the other destructive verbs; the attachment chip's
// «Anteprima» entry takes its title from the message row's own command so the verb reads the
// same on both surfaces.

@Suite struct MessageCommandSymbolTests {
    @Test func excludeDrawsTheTrashGlyph() {
        #expect(MessageCommand.exclude.symbol == "trash")
    }

    @Test func everyMessageCommandHasItsExactSymbol() {
        let expected: [MessageCommand: String] = [
            .openInMail: "envelope",
            .previewAttachment: "eye",
            .exclude: "trash",
            .moveTo: "folder",
            .alsoAddTo: "plus.circle",
            .regenerate: "arrow.triangle.2.circlepath",
            .addNote: "square.and.pencil",
            .addCall: "phone",
            .linkNote: "doc.badge.plus",
            .unlinkNote: "doc.badge.minus",
        ]
        #expect(Set(MessageCommand.allCases) == Set(expected.keys), "a new command needs its symbol pinned")
        for command in MessageCommand.allCases {
            #expect(command.symbol == expected[command], "\(command.rawValue)")
        }
    }

    /// The chip's preview entry is the row's preview command by identity, not by a copied word.
    @Test func theChipsPreviewTitleIsTheMessageRowsCommandTitle() {
        #expect(AttachmentChipModel.Command.preview.title == MessageCommand.previewAttachment.title)
        #expect(AttachmentChipModel.Command.preview.title == "Anteprima allegato")
    }
}
