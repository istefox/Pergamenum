import Foundation
import Testing
@testable import Pergamenum

/// The slash menu's catalogue (M8).
///
/// Two things here are load-bearing and neither is obvious. AppKit's completion list
/// hands back the **string it showed**, so the map from title to command has to be total
/// and unambiguous or a chosen entry runs the wrong thing. And every insertion is markdown
/// that some parser in this app will read straight afterwards, so a template that drifts
/// from its parser produces a note that looks right and behaves wrong.

@MainActor
private var catalogue: [EditorCommand] { EditorCommand.all(canRun: { _ in true }) }

// MARK: - The map back from a title

@MainActor
@Test func everyTitleInTheMenuIsUnique() {
    // The whole menu at once, editor entries and app commands together: a collision
    // between the two halves is the one nobody would think to look for.
    var seen: Set<String> = []
    for command in catalogue {
        #expect(seen.insert(command.title).inserted, "«\(command.title)» compare due volte")
    }
}

@MainActor
@Test func anEmptyQueryOffersTheWholeMenuRatherThanNothing() {
    // Typing `/` alone must show the menu. An empty result would read as "there are no
    // commands", which is the same confusion an empty view result causes in ADR-0009.
    #expect(EditorCommand.matching("", in: catalogue).count == catalogue.count)
}

@MainActor
@Test func theKeywordsAreWhatMakeTheMenuUsableWithoutKnowingItsWording() {
    // `/h2` is what a person types; "Titolo 2" is what the menu says. Without the
    // keywords the menu is only searchable by someone who already read it.
    #expect(EditorCommand.matching("h2", in: catalogue).first?.id == "heading2")
    #expect(EditorCommand.matching("todo", in: catalogue).first?.id == "task")
    #expect(EditorCommand.matching("tabella", in: catalogue).first?.id == "table")
}

@MainActor
@Test func theQueryHasToStartAWordAndNotMerelyBeScatteredThroughOne() {
    // Found on screen, typing `/es`: the subsequence matcher accepted "Giorno succ-es-sivo"
    // and "Ins-e-ri-s-ci wikilink", so the list showed four unrelated commands and rebuilt
    // itself on every keystroke - it read as scrolling on its own. A menu of fixed entries
    // is searched by typing the start of a word, and nothing else is a match.
    // The only survivor is the one entry that genuinely *starts* with those letters.
    #expect(EditorCommand.matching("es", in: catalogue).map(\.title) == ["Espandi tutto"])
    // The same letters where they do start a word: still found.
    #expect(EditorCommand.matching("es", in: [
        EditorCommand(id: "x", title: "Esporta", keywords: [], symbol: "square", action: .insert("", cursorBack: 0)),
    ]).count == 1)
}

@MainActor
@Test func aWordInsideTheTitleIsEnoughAndTheTitleItselfComesFirst() {
    // `/cod` has to reach "Blocco di codice", or the menu is only usable by someone who
    // knows each entry's first word.
    #expect(EditorCommand.matching("cod", in: catalogue).first?.id == "codeBlock")
    // Between a title that starts with the query and a title that merely contains the
    // word, the first one wins.
    let titleFirst = EditorCommand.matching("tit", in: catalogue)
    #expect(titleFirst.first?.id == "heading1")
}

@MainActor
@Test func narrowingAQueryNeverReordersWhatSurvives() {
    // The other half of the same defect. The rows that match both `t` and `ta` must keep
    // their relative order, or the row under the selection changes while a person is
    // still typing towards it.
    let wide = EditorCommand.matching("t", in: catalogue).map(\.id)
    let narrow = EditorCommand.matching("ta", in: catalogue).map(\.id)
    #expect(!narrow.isEmpty)
    #expect(narrow == wide.filter(narrow.contains))
}

@MainActor
@Test func aQueryThatMatchesNothingReturnsNothing() {
    // Not "everything", which is what a filter that gives up looks like from the outside.
    #expect(EditorCommand.matching("zzzqwx", in: catalogue).isEmpty)
}

// MARK: - What the insertions actually write

@MainActor
@Test func theTaskTemplateIsReadBackByTheTaskParser() throws {
    // The template and `TaskParser` have to agree, or the slash menu writes a line the
    // Attività pane never shows - which reads as the capture having been lost.
    let template = try #require(insertion(of: "task"))
    let parsed = TaskParser.parse(line: template.text + "Controllare la mescola", sourcePath: "N.md", lineIndex: 0)
    #expect(parsed != nil)
    #expect(parsed?.state == .open)
    #expect(parsed?.text == "Controllare la mescola")
}

@MainActor
@Test func theTableTemplateIsSeenAsATableAndNotAsProse() throws {
    let template = try #require(insertion(of: "table"))
    let blocks = MarkdownBlockParser.blocks(in: template.text)
    let isTable = blocks.contains { block in
        if case .table = block { return true }
        return false
    }
    #expect(isTable, "la tabella del menu non viene letta come tabella")
}

@MainActor
@Test func theCodeFenceLeavesTheCaretInsideIt() throws {
    // The whole point of `cursorBack`: a fence that opens with the caret after the
    // closing backticks means typing the code outside the block.
    let template = try #require(insertion(of: "codeBlock"))
    let caret = template.text.index(template.text.startIndex, offsetBy: template.text.count - template.back)
    let before = String(template.text[template.text.startIndex..<caret])
    #expect(before == "```\n")
}

@MainActor
@Test func theEmbedLeavesTheCaretBetweenTheBrackets() throws {
    let template = try #require(insertion(of: "embed"))
    #expect(template.text == "![[]]")
    #expect(template.back == 2)
}

@MainActor
@Test func everyInsertionPutsTheCaretInsideWhatItWrote() {
    // A `cursorBack` past the start of the template would put the caret before the text
    // the command just inserted, in whatever was there already.
    for command in EditorCommand.editorEntries {
        guard case .insert(let text, let back) = command.action else { continue }
        #expect(back >= 0, "«\(command.title)» ha un cursorBack negativo")
        #expect(back <= text.count, "«\(command.title)» riporta il cursore prima di ciò che scrive")
    }
}

// MARK: - The app half

@MainActor
@Test func theTwoCommandsThatMakeNoSenseFromTheCaretAreNotOffered() {
    // Stated in the catalogue and asserted here so removing the filter is a red test
    // rather than a surprise: capturing from another app while typing in this one, and
    // a plain paste whose pasteboard the menu has just disturbed.
    let appCommands = catalogue.compactMap { command -> ShortcutCommand? in
        guard case .app(let shortcut) = command.action else { return nil }
        return shortcut
    }
    #expect(!appCommands.contains(.globalCapture))
    #expect(!appCommands.contains(.pastePlain))
    // Everything else in the catalogue is there.
    #expect(appCommands.count == ShortcutCommand.allCases.count - 2)
}

@MainActor
@Test func aCommandThatCannotRunIsNotOffered() {
    // The filter is the reason `canRun` exists as a value rather than as a view
    // modifier: a menu that lists what it cannot do teaches people to stop trusting it.
    let none = EditorCommand.all(canRun: { _ in false })
    #expect(none.count == EditorCommand.editorEntries.count)
    // The editor half never depends on the app's state: writing `## ` works with no
    // vault open, and hiding it would be wrong.
    #expect(none.map(\.id) == EditorCommand.editorEntries.map(\.id))
}

// MARK: -

@MainActor
private func insertion(of id: String) -> (text: String, back: Int)? {
    guard let command = EditorCommand.editorEntries.first(where: { $0.id == id }),
          case .insert(let text, let back) = command.action
    else { return nil }
    return (text, back)
}
