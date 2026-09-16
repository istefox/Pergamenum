import Foundation
import Testing
@testable import Pergamenum

// ADR-0039: a task's board relation is named once, so the row's context menu, the
// Attività toolbar, the Task menu and the "Task collegati" panel's row read the same
// catalogue instead of four hand-kept lists that had already drifted apart.

private func task(_ line: String, sourcePath: String = "x.md") -> TaskItem {
    TaskParser.parse(line: line, sourcePath: sourcePath, lineIndex: 0)!
}

// MARK: - Catalogue shape

@Test func theCatalogueHasExactlyTheFiveCommandsATaskOffers() {
    #expect(TaskCommand.allCases.count == 5)
}

// MARK: - `available(for:)`

@Test func aTaskWithNoBoardAndNoCategoryOffersLinkBoardGoToNoteAndAssignCategory() {
    let commands = TaskCommand.available(for: task("- [ ] Capofila"))
    #expect(commands == [.linkBoard, .goToNote, .assignCategory])
}

@Test func aTaskWithABoardAssignedAlsoOffersGoToBoard() {
    let commands = TaskCommand.available(for: task("- [ ] Verifica ^[[vibrofer-emea.canvas]]"))
    #expect(commands == [.linkBoard, .goToNote, .assignCategory, .goToBoard])
}

// R-03: `.removeCategory` only when the task actually carries a `#project-*` tag,
// the same shape `.goToBoard` already takes above.
@Test func aTaskWithACategoryAssignedAlsoOffersRemoveCategory() {
    let commands = TaskCommand.available(for: task("- [ ] Verifica #project-vibrofer"))
    #expect(commands == [.linkBoard, .goToNote, .assignCategory, .removeCategory])
}

@Test func aTaskWithBothABoardAndACategoryOffersAllFiveCommands() {
    let commands = TaskCommand.available(
        for: task("- [ ] Verifica ^[[vibrofer-emea.canvas]] #project-vibrofer")
    )
    #expect(commands == [.linkBoard, .goToNote, .assignCategory, .goToBoard, .removeCategory])
}

// MARK: - Titles

@Test func everyCommandHasItsExactItalianTitle() {
    let expected: [TaskCommand: String] = [
        .linkBoard: "Collega una board…",
        .goToNote: "Vai alla nota di origine",
        .goToBoard: "Vai alla board collegata",
        .assignCategory: "Assegna categoria…",
        .removeCategory: "Togli la categoria",
    ]
    for command in TaskCommand.allCases {
        #expect(!command.title.isEmpty)
        #expect(command.title == expected[command])
    }
}

// MARK: - Symbols

@Test func everySymbolMatchesTheTableThisFeatureDeclares() {
    let expected: [TaskCommand: String] = [
        .linkBoard: "rectangle.3.group",
        .goToNote: "doc.text.magnifyingglass",
        .goToBoard: "arrow.up.forward.square",
        .assignCategory: "tag",
        .removeCategory: "tag.slash",
    ]
    for command in TaskCommand.allCases {
        #expect(!command.symbol.isEmpty)
        #expect(command.symbol == expected[command])
    }
}

// MARK: - Identifiers

@Test func everyCommandHasAStableIdentifierDerivedFromItsRawValue() {
    let expected: [TaskCommand: String] = [
        .linkBoard: "task-command-linkBoard",
        .goToNote: "task-command-goToNote",
        .goToBoard: "task-command-goToBoard",
        .assignCategory: "task-command-assignCategory",
        .removeCategory: "task-command-removeCategory",
    ]
    for command in TaskCommand.allCases {
        #expect(!command.identifier.isEmpty)
        #expect(command.identifier == expected[command])
    }
}

@Test func everyTaskCommandsIdentifierIsUnique() {
    let identifiers = TaskCommand.allCases.map(\.identifier)
    #expect(Set(identifiers).count == TaskCommand.allCases.count)
}
