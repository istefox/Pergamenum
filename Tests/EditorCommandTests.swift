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
    let today = CalendarDate(iso: "2026-08-20")!
    let none = EditorCommand.all(canRun: { _ in false }, today: today)

    // The editor half never depends on the app's state: writing `## ` works with no
    // vault open, and hiding it would be wrong. Nothing that *runs* a command survives.
    #expect(none.allSatisfy { entry in
        if case .insert = entry.action { return true }
        return false
    })
    let expected = EditorCommand.editorEntries.map(\.id)
        + EditorCommand.taskSyntaxEntries(today: today).map(\.id)
    #expect(none.map(\.id) == expected)
}

// MARK: -

@MainActor
private func insertion(of id: String) -> (text: String, back: Int)? {
    guard let command = EditorCommand.editorEntries.first(where: { $0.id == id }),
          case .insert(let text, let back) = command.action
    else { return nil }
    return (text, back)
}

// MARK: - Le viste nel menu «/» (M11, aggiunte in M12)

@Test func theSlashMenuOffersOneEntryPerRenderer() {
    let views = EditorCommand.viewEntries
    #expect(views.count == ViewBlock.Renderer.allCases.count)
    #expect(views.map(\.title).contains("Vista tabella"))
    #expect(views.map(\.title).contains("Vista board"))
}

@Test func aViewSkeletonParsesAndTheCaretLandsInTheTag() throws {
    for entry in EditorCommand.viewEntries {
        guard case .insert(let text, let cursorBack) = entry.action else {
            Issue.record("«\(entry.title)» non scrive markdown")
            continue
        }
        // What the menu writes has to be a block the app can then run: a skeleton that
        // needs fixing before it parses is a menu entry that produces an error message.
        let body = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .dropFirst()
            .prefix { $0 != "```" }
            .joined(separator: "\n")
        _ = try ViewBlock.parse(body)

        // The caret sits between the quotes of `tag("")`, ready for the tag.
        let caret = text.index(text.endIndex, offsetBy: -cursorBack)
        #expect(text[..<caret].hasSuffix("tag(\""))
    }
}

@Test func aBoardSkeletonCarriesTheGroupItCannotParseWithout() throws {
    let board = try #require(EditorCommand.viewEntries.first { $0.title == "Vista board" })
    guard case .insert(let text, _) = board.action else { return }
    #expect(text.contains("group: tag(\"status-*\")"))
}

// MARK: - I quattro buchi chiusi in M12

@Test func theTaskSyntaxCanBeWrittenFromTheMenu() throws {
    let day = CalendarDate(iso: "2026-08-20")!
    let entries = EditorCommand.taskSyntaxEntries(today: day)

    #expect(entries.count == 4)
    let texts = entries.compactMap { entry -> String? in
        guard case .insert(let text, _) = entry.action else { return nil }
        return text
    }
    #expect(texts.contains(">2026-08-20"))
    #expect(texts.contains("!2026-08-20"))
    #expect(texts.contains("@remind(2026-08-20 09:00)"))
    #expect(texts.contains("@repeat(0/3)"))

    // And what it writes is what the parser reads back: a menu that produced syntax the
    // task parser ignores would schedule nothing and say nothing.
    let task = try #require(TaskParser.parse(
        line: "- [ ] Chiamare il fornitore >2026-08-20 !2026-08-20 @repeat(0/3)",
        sourcePath: "x.md", lineIndex: 0
    ))
    #expect(task.scheduled == day)
    #expect(task.due == day)
    #expect(task.recurrence != nil)
}

@Test func theDateInTheMenuIsBuiltEachTimeAndNotAtLaunch() {
    // A `static let` catalogue would freeze today's date at launch and start writing
    // yesterday's after midnight, on the machine of anybody who leaves the app open.
    let yesterday = EditorCommand.taskSyntaxEntries(today: CalendarDate(iso: "2026-08-19")!)
    let today = EditorCommand.taskSyntaxEntries(today: CalendarDate(iso: "2026-08-20")!)
    #expect(yesterday.first?.action != today.first?.action)
}

@Test func theThreeCommandsThatHadNoKeyNowHaveOne() {
    // Each was reachable only by a control on screen: the star from a context menu on
    // some *other* note, the inspector from one toolbar button, a template only while
    // creating a note.
    for command in [ShortcutCommand.toggleStar, .toggleInspector, .applyTemplate] {
        #expect(!command.defaultBinding.key.isEmpty, "«\(command.title)» non ha una combinazione")
        // In the catalogue means in the slash menu too: `appEntries` maps all of it.
        #expect(EditorCommand.appEntries.contains { $0.id == "app.\(command.rawValue)" })
    }
}
