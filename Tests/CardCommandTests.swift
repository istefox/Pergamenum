import CoreGraphics
import Foundation
import Testing
@testable import Pergamenum

// ADR-0023: A command is named once and rendered twice.
// Plan: docs/superpowers/plans/2026-08-25-universal-command-surface-parity.md, Task 1.
//
// `CardCommand` is the single catalogue `BoardContentLayer`'s context menu and the new
// `BoardCardControls` toolbar (Task 3) both read, so a card's commands cannot list
// differently on the two surfaces (ADR-0023 §D1).
//
// RED (Task 1): `CardCommand.available(for:isCroppable:hasCrop:)` is a placeholder that
// always returns `[]`, and `title`/`symbol` are placeholders returning a fixed string for
// every case - so every assertion below fails on its assertion, not on a build error.

// MARK: - Fixtures

private func fileNode(_ path: String = "foto.png") -> CanvasNode {
    CanvasNode(id: "a", kind: .file(path: path, subpath: nil), x: 0, y: 0, width: 260, height: 180)
}

private func textNode() -> CanvasNode {
    CanvasNode(id: "b", kind: .text("ciao"), x: 0, y: 0, width: 220, height: 120)
}

private func linkNode() -> CanvasNode {
    CanvasNode(id: "c", kind: .link(url: "https://example.com"), x: 0, y: 0, width: 260, height: 90)
}

private func markdownFileNode() -> CanvasNode {
    CanvasNode(id: "d", kind: .file(path: "01 Progetti/Nota.md", subpath: nil), x: 0, y: 0, width: 260, height: 180)
}

// MARK: - Catalogue shape (R-06)

@Test func theCatalogueHasExactlyTheNineCommandsTheCardOffers() {
    #expect(CardCommand.allCases.count == 9)
}

// MARK: - `available(for:isCroppable:hasCrop:)` (R-06)

@Test func availableOnACroppableFileWithNoCropReturnsTheBaseSetInMenuOrder() {
    let commands = CardCommand.available(for: fileNode(), isCroppable: true, hasCrop: false)
    #expect(commands == [.open, .copyLink, .color, .resize, .crop, .duplicate, .delete])
}

// `BoardContentLayer.swift:66-87`: "Adatta al ritaglio" is drawn inside the "Ridimensiona"
// submenu, right after "Ridimensiona" itself, and "Rimuovi ritaglio" is drawn right after
// "Ritaglia" - both only when the node already carries a crop.
@Test func availableOnACroppableFileWithAnExistingCropAddsFitToCropAndRemoveCropInPlace() {
    let commands = CardCommand.available(for: fileNode(), isCroppable: true, hasCrop: true)
    #expect(commands == [.open, .copyLink, .color, .resize, .fitToCrop, .crop, .removeCrop, .duplicate, .delete])
}

@Test func availableOnANonCroppableNodeOmitsEveryCropCommandButKeepsTheRest() {
    for node in [textNode(), linkNode(), markdownFileNode()] {
        let commands = CardCommand.available(for: node, isCroppable: false, hasCrop: false)
        #expect(commands == [.open, .copyLink, .color, .resize, .duplicate, .delete])
    }
}

// `isCroppable` is the caller's own placeholder/extension check
// (`BoardContentLayer.isCroppable(node)`), which `available` never re-derives from
// `hasCrop`. A non-image node carrying a leftover `pergamenum-crop` key (or any other
// reason `hasCrop` might read true) must not resurrect the crop commands.
@Test func aTrueHasCropIsIgnoredWhenTheNodeIsNotCroppable() {
    let commands = CardCommand.available(for: textNode(), isCroppable: false, hasCrop: true)
    #expect(!commands.contains(.crop))
    #expect(!commands.contains(.fitToCrop))
    #expect(!commands.contains(.removeCrop))
}

// MARK: - Titles (pinned to `BoardContentLayer.swift`'s existing menu strings)

@Test func everyCommandHasItsExactExistingItalianTitle() {
    let expected: [CardCommand: String] = [
        .open: "Apri",
        .copyLink: "Copia link Pergamenum",
        .color: "Colore",
        .resize: "Ridimensiona",
        .fitToCrop: "Adatta al ritaglio",
        .crop: "Ritaglia",
        .removeCrop: "Rimuovi ritaglio",
        .duplicate: "Duplica",
        .delete: "Elimina",
    ]
    for command in CardCommand.allCases {
        #expect(!command.title.isEmpty)
        #expect(command.title == expected[command])
    }
}

// MARK: - Symbols (R-13)

// `.delete` reuses `WorkspaceBrowserToolbar`'s own "trash" (`WorkspaceBrowserToolbar.swift:35`).
// `.duplicate` has no prior use anywhere in this app (grepped `Sources/` for "doc.on.doc" -
// no hit) - a genuinely new command may choose one (plan Task 1 RED).
//
// Every other case has no existing icon for this exact command either: the card's own
// context menu draws plain, icon-less `Button`s today (`BoardContentLayer.swift:52-90`),
// and so does the menu bar (`MenuCommands.swift`, `PergamenumApp.swift:398`) and
// `NoteRowMenu` (grepped `systemImage:` across `Sources/`, no hit tied to Apri/Copia
// link/Colore/Ridimensiona/Ritaglia anywhere) - so R-13 has nothing to reuse for them and
// each below is a first choice, recorded here rather than left to a review.
// `"eye"` is deliberately excluded from `.open`: that symbol already means "Anteprima
// rapida" in this same board toolbar (`WorkspaceView.swift:261`), and reusing it for
// `.open` would make the two indistinguishable.
@Test func everySymbolMatchesTheTableThisTaskDeclares() {
    let expected: [CardCommand: String] = [
        .open: "arrow.up.forward.square",
        .copyLink: "link",
        .color: "paintpalette",
        .resize: "arrow.up.left.and.arrow.down.right",
        .fitToCrop: "aspectratio",
        .crop: "crop",
        .removeCrop: "xmark.rectangle",
        .duplicate: "doc.on.doc",
        .delete: "trash",
    ]
    for command in CardCommand.allCases {
        #expect(!command.symbol.isEmpty)
        #expect(command.symbol == expected[command])
    }
}

// MARK: - Task 3: `BoardCardControls.isShown(selection:)` (R-07)
//
// ADR-0023: A command is named once and rendered twice.
// Plan: docs/superpowers/plans/2026-08-25-universal-command-surface-parity.md, Task 3.
//
// RED (Task 3): `BoardCardControls.isShown(selection:)` is a placeholder that always
// returns `false`, so the "exactly one id" assertion below fails on its assertion, not on
// a build error. R-07's rule ("hidden, not disabled") is a pure function of the selection
// count, testable with no window.

@Test func boardCardControlsIsShownForExactlyOneSelectedID() {
    #expect(BoardCardControls.isShown(selection: ["a"]) == true)
}

@Test func boardCardControlsIsHiddenForAnEmptySelection() {
    #expect(BoardCardControls.isShown(selection: []) == false)
}

@Test func boardCardControlsIsHiddenForTwoSelectedIDs() {
    #expect(BoardCardControls.isShown(selection: ["a", "b"]) == false)
}

// MARK: - Task 3: `CardCommand.identifier` (R-06)
//
// RED (Task 3): `identifier` is a placeholder returning `""` for every case, so every
// assertion below fails on its assertion, not on a build error. One stable AX identifier
// per command, derived from `rawValue`, so a new command cannot ship without one.

@Test func everyCommandHasAStableBoardCardIdentifierDerivedFromItsRawValue() {
    let expected: [CardCommand: String] = [
        .open: "board-card-open",
        .copyLink: "board-card-copyLink",
        .color: "board-card-color",
        .resize: "board-card-resize",
        .fitToCrop: "board-card-fitToCrop",
        .crop: "board-card-crop",
        .removeCrop: "board-card-removeCrop",
        .duplicate: "board-card-duplicate",
        .delete: "board-card-delete",
    ]
    for command in CardCommand.allCases {
        #expect(!command.identifier.isEmpty)
        #expect(command.identifier == expected[command])
    }
}

// Two different commands must never collide on the same identifier - the whole point of
// deriving it from `rawValue` rather than hand-typing each one.
@Test func everyCommandsIdentifierIsUnique() {
    let identifiers = CardCommand.allCases.map(\.identifier)
    #expect(Set(identifiers).count == CardCommand.allCases.count)
}
