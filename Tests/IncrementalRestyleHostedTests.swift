import AppKit
import Foundation
import Testing
@testable import Pergamenum

// ADR-0091 §D2, §D6, §D7, §D8, plan docs/plans/per-paragraph-restyle.md, Task 3 (R-02, R-06, R-07).
//
// A hosted editor restyled by the dirty range is compared with its twin restyled in full, after
// every edit: the storages run by run and every offset-keyed holder through `derivedStateSnapshot()`.
// Nothing here says what the attributes of a note should be; the full restyle is the oracle.
//
// Equal results alone would also hold for an editor that restyles in full, so each test also pins
// that the incremental path ran: `restyleLog.incremental` grows, the storage delegate records the
// edit, and the snapshot carries a map equal to the text's own.

private let seeds: [UInt64] = [3, 11, 19, 27, 35, 43, 51, 59, 67, 75]

/// One edit drawn from a generator: a keystroke, a paste over a range, a deletion, an undo or a redo.
private enum Step {
    case type(String, at: Int)
    case replace(NSRange, with: String)
    case undo
    case redo

    var label: String {
        switch self {
        case .type(let string, let at): "type \(string.debugDescription) at \(at)"
        case .replace(let range, let string): "replace \(range) with \(string.debugDescription)"
        case .undo: "undo"
        case .redo: "redo"
        }
    }
}

/// Tokens that keep to the prose zone: no backtick, pipe, bracket or tilde, so a token cannot open a
/// fence, a table or a link, and every block below the zone is still there after the edit. A newline,
/// a list marker, a quote marker and a heading marker are in, because they change a line's kind.
private let tokens = [
    "a", "b", "x", " ", "  ", "1", "7", "*", "_", "ò", "word ", "\n", "\n\n", "- ", "1. ", "3. ", "> ", "# ",
]

@MainActor
private func step(_ generator: inout SplitMix64, twin: RestyleTwin) -> Step {
    let text = twin.incremental.textView.string as NSString
    let zoneEnd = min(RichNote.zoneEnd(in: text as String), text.length)
    let roll = Int(generator.next() % 100)
    if roll >= 88, twin.canRedo { return .redo }
    if roll >= 76, twin.canUndo { return .undo }
    let location = Int(generator.next() % UInt64(zoneEnd + 1))
    let token = tokens[Int(generator.next() % UInt64(tokens.count))]
    if roll < 50 { return .type(token, at: location) }
    // A paste or a deletion over up to three characters of the zone.
    let length = min(Int(generator.next() % 4), zoneEnd - location)
    return .replace(NSRange(location: location, length: length), with: roll < 70 ? token : "")
}

/// A keystroke inside one of the blocks whose state the incremental path keeps across a restyle
/// (`applyTables(within:)`, `applyViewBlocks(within:firstOrdinal:)`, the embed and fold passes, the
/// frontmatter), and the path ADR-0091 §D3 sends it down. The random edits above keep to the prose
/// zone; these land inside the blocks.
private struct BlockKeystroke: Sendable, CustomTestStringConvertible {
    let name: String
    /// Put before `RichNote.text`, for a block the rich note does not hold.
    var prefix = ""
    /// The text the keystroke lands in, and how far into it.
    let anchor: String
    let offset: Int
    let typed: String
    /// True when §D3 restyles the touched lines, false when it restyles the note.
    let isIncremental: Bool
    /// True when the caret has to stand inside the view block's fence to type there. A revealed fence
    /// registers no host, and `ViewBlockHostStore.hosts(for:in:)` prunes what a pass did not ask for,
    /// so any styling with the caret there drops the host, on the full path as on the incremental one
    /// (ADR-0033 §D3/§D4): the host is not the incremental path's to keep, and the test checks that
    /// the twin restyled in full lost it too.
    var revealsTheViewBlock = false

    var testDescription: String { name }
}

private let blockKeystrokes = [
    BlockKeystroke(name: "a letter in a table cell", anchor: "| 1 | 2 |", offset: 3, typed: "x", isIncremental: true),
    BlockKeystroke(
        name: "a letter in the view-block body", anchor: "render: list", offset: 12, typed: "x",
        isIncremental: true, revealsTheViewBlock: true
    ),
    BlockKeystroke(
        name: "a letter in an embed's target", anchor: "![[foto.png]]", offset: 7, typed: "x", isIncremental: true
    ),
    BlockKeystroke(
        name: "a letter in the folded section", anchor: "Testo nascosto", offset: 5, typed: "x", isIncremental: true
    ),
    // The blank line closing the fold is its last hidden line: a letter at its start moves no hidden
    // offset and no folded heading, so the full path finds the layout unchanged and rescues nothing.
    BlockKeystroke(
        name: "a letter in the fold's last hidden line", anchor: "dalla piega.\n\n", offset: 13, typed: "x",
        isIncremental: true
    ),
    BlockKeystroke(
        name: "a letter in the frontmatter", prefix: "---\ndate: 2026-10-11\n---\n\n",
        anchor: "2026-10-11", offset: 10, typed: "x", isIncremental: false
    ),
    BlockKeystroke(
        name: "a backtick on the view-block fence", anchor: "```pergamenum-view", offset: 3, typed: "`",
        isIncremental: false, revealsTheViewBlock: true
    ),
]

@MainActor
@Suite(.serialized) struct IncrementalRestyleHosted {
    // (R-02) Ten fixed seeds, twenty-five edits each, through the keystroke, the paste and the undo
    // stack: the incremental editor and its twin agree after every one, and the fixture holds every
    // kind of derived state below the edit the whole time.
    @Test(arguments: seeds)
    func editsStyleLikeAFullRestyle(_ seed: UInt64) async throws {
        let twin = try await RestyleTwin.rich()
        defer { twin.tearDown() }
        var generator = SplitMix64(seed: seed)

        // Before any edit the fixture is not vacuous, and the twins already agree.
        #expect(RestyleTwin.emptyFields(of: twin.incremental.coordinator.derivedStateSnapshot()).isEmpty,
                "empty before the first edit: \(RestyleTwin.emptyFields(of: twin.incremental.coordinator.derivedStateSnapshot()))")
        #expect(twin.differences().isEmpty, "\(twin.differences())")

        var mismatches = 0
        var vacant = 0
        var firstMismatch: String?
        var firstVacant: String?
        for index in 0..<25 {
            let next = step(&generator, twin: twin)
            switch next {
            case .type(let string, let at): twin.type(string, at: at)
            case .replace(let range, let string): twin.replace(range, with: string)
            case .undo: twin.undo()
            case .redo: twin.redo()
            }
            let differences = twin.differences()
            if !differences.isEmpty {
                mismatches += 1
                firstMismatch = firstMismatch ?? "edit \(index) (\(next.label)): \(differences.prefix(3))"
            }
            let empty = RestyleTwin.emptyFields(of: twin.incremental.coordinator.derivedStateSnapshot())
            if !empty.isEmpty {
                vacant += 1
                firstVacant = firstVacant ?? "edit \(index) (\(next.label)): \(empty)"
            }
        }
        #expect(mismatches == 0, "seed \(seed): \(mismatches) of 25 edits differ from a full restyle; first: \(firstMismatch ?? "")")
        #expect(vacant == 0, "seed \(seed): \(vacant) edits left a derived field empty; first: \(firstVacant ?? "")")
        // The incremental path ran, or this compared a full restyle with itself.
        #expect(twin.incremental.coordinator.restyleLog.incremental > 0, "seed \(seed): no styling took the incremental path")
        #expect(twin.full.coordinator.restyleLog.incremental == 0)
        // And the map it keeps is the map of the text it now holds.
        let map = twin.incremental.coordinator.derivedStateSnapshot().map
        #expect(map == StructureMap(text: twin.incremental.textView.string), "seed \(seed): the kept map is not the text's own")
    }

    // MARK: Inside the blocks

    // (R-02, R-05) A keystroke inside a table cell, a view-block body, an embed line, a folded
    // section, the frontmatter or a fence: the editor equals its twin restyled in full, the log shows
    // the path §D3 chose, and the table's grid is the same object. So is the view block's host,
    // unless the caret had to reveal the fence, which drops it on both paths.
    @Test(arguments: blockKeystrokes)
    fileprivate func aKeystrokeInsideABlockStylesLikeAFullRestyle(_ keystroke: BlockKeystroke) async throws {
        let twin = try await RestyleTwin.rich(text: keystroke.prefix + RichNote.text)
        defer { twin.tearDown() }
        let anchor = (twin.incremental.textView.string as NSString).range(of: keystroke.anchor)
        try #require(anchor.location != NSNotFound, "\(keystroke.anchor) is not in the note")
        let location = anchor.location + keystroke.offset
        let editor = twin.incremental.coordinator
        // Taken with the caret outside the blocks: a caret on a view block reveals its source, and
        // the delegate holds no host for it until the caret leaves.
        let gridsBefore = editor.tables.grids.identities()
        let hostsBefore = editor.decorations.viewBlockHosts.mapValues { ObjectIdentifier($0) }
        let fullHostsBefore = twin.full.coordinator.decorations.viewBlockHosts.mapValues { ObjectIdentifier($0) }
        #expect(!gridsBefore.isEmpty, "no table grid to keep")
        #expect(!hostsBefore.isEmpty, "no view-block host to keep")

        // The caret goes there first and the count is taken after: moving it into a fence crosses
        // it, which is a full restyle of its own (ADR-0091 §D10), and not what this test is about.
        twin.both { $0.textView.setSelectedRange(NSRange(location: location, length: 0)) }
        twin.both { $0.runPasses() }
        #expect(twin.differences().isEmpty, "before the keystroke: \(twin.differences())")
        let before = editor.restyleLog

        twin.type(keystroke.typed, at: location)

        let after = editor.restyleLog
        if keystroke.isIncremental {
            #expect(after.incremental == before.incremental + 1, "not restyled by the range: \(before) then \(after)")
            #expect(after.full == before.full, "restyled in full: \(before) then \(after)")
        } else {
            #expect(after.full == before.full + 1, "not restyled in full: \(before) then \(after)")
            #expect(after.incremental == before.incremental, "restyled by the dirty range: \(before) then \(after)")
        }
        #expect(twin.differences().isEmpty, "\(twin.differences())")
        #expect(twin.full.coordinator.restyleLog.incremental == 0)

        // The caret leaves the blocks again, so the delegate holds every host it draws.
        twin.both { $0.textView.setSelectedRange(NSRange(location: 0, length: 0)) }
        twin.both { $0.runPasses() }
        #expect(twin.differences().isEmpty, "after the caret left: \(twin.differences())")
        let gridsAfter = editor.tables.grids.identities()
        #expect(Set(gridsAfter.values) == Set(gridsBefore.values), "a table grid was rebuilt")
        let hostsAfter = editor.decorations.viewBlockHosts.mapValues { ObjectIdentifier($0) }
        if keystroke.revealsTheViewBlock {
            // Not the incremental path's doing: the twin restyled in full lost its host as well.
            let fullHostsAfter = twin.full.coordinator.decorations.viewBlockHosts.mapValues { ObjectIdentifier($0) }
            #expect(Set(fullHostsAfter.values) != Set(fullHostsBefore.values), "the full restyle kept the host")
        } else {
            #expect(Set(hostsAfter.values) == Set(hostsBefore.values), "a view-block host was rebuilt")
        }
    }

    // MARK: Undo

    // (R-06) A keystroke is one undo step: one undo restores the text before it, and the selection and
    // the reveal set after it are the full restyle's.
    @Test func aKeystrokeIsOneUndoStep() async throws {
        let twin = try await RestyleTwin.rich()
        defer { twin.tearDown() }
        let at = 5
        let before = twin.incremental.textView.string

        twin.type("x", at: at)
        let typed = twin.incremental.textView.string
        #expect(typed != before)
        #expect(twin.incremental.coordinator.restyleLog.incremental > 0, "the keystroke was not restyled by the dirty range")
        twin.type("y", at: at + 1)

        twin.undo()
        #expect(twin.incremental.textView.string == typed, "one undo took back more than the last keystroke")
        #expect(twin.differences().isEmpty, "\(twin.differences())")
        twin.undo()
        #expect(twin.incremental.textView.string == before)
        #expect(twin.differences().isEmpty, "\(twin.differences())")
        #expect(twin.incremental.textView.selectedRange() == twin.full.textView.selectedRange())
        #expect(twin.incremental.coordinator.reveal.lastRevealed == twin.full.coordinator.reveal.lastRevealed)
        #expect(!twin.incremental.coordinator.reveal.lastRevealed.isEmpty, "no paragraph revealed under the caret")

        twin.redo()
        #expect(twin.incremental.textView.string == typed)
        #expect(twin.differences().isEmpty, "\(twin.differences())")
    }

    // (R-06) A keystroke that renumbers a list is still one undo step: "1." becomes "3." and the run
    // after it is renumbered in the same step, and one undo takes both back.
    @Test func aRenumberingKeystrokeIsOneUndoStep() async throws {
        let twin = try await RestyleTwin.rich()
        defer { twin.tearDown() }
        let before = twin.incremental.textView.string
        let digit = (before as NSString).range(of: "1. uno")
        #expect(digit.location != NSNotFound)

        twin.type("3", over: NSRange(location: digit.location, length: 1))
        let renumbered = twin.incremental.textView.string
        #expect(renumbered.contains("3. uno"))
        #expect(renumbered.contains("4. due"), "the run was not renumbered after the keystroke")
        #expect(twin.differences().isEmpty, "\(twin.differences())")

        twin.undo()
        #expect(twin.incremental.textView.string == before, "one undo did not take back the keystroke and its renumbering")
        #expect(twin.differences().isEmpty, "\(twin.differences())")
        #expect(twin.incremental.textView.selectedRange() == twin.full.textView.selectedRange())
        #expect(twin.incremental.coordinator.restyleLog.incremental > 0, "no styling took the incremental path")
    }

    // MARK: Composition

    // (R-07) A restyle over the marked range does not end composition: the marked range, the
    // selection and `hasMarkedText()` are what the twin has, and the composition is still there.
    @Test func aRestyleDuringCompositionLeavesTheCompositionAlone() async throws {
        let twin = try await RestyleTwin.rich()
        defer { twin.tearDown() }
        let word = (RichNote.text as NSString).range(of: "prosa")
        #expect(word.location != NSNotFound)
        let middle = word.location + 2

        twin.edit { fixture in
            fixture.textView.setSelectedRange(NSRange(location: middle, length: 0))
            fixture.textView.setMarkedText(
                "ñ", selectedRange: NSRange(location: 1, length: 0),
                replacementRange: NSRange(location: middle, length: 0)
            )
        }

        #expect(twin.incremental.textView.hasMarkedText(), "composition ended")
        #expect(twin.incremental.textView.markedRange() == NSRange(location: middle, length: 1))
        #expect(twin.incremental.textView.markedRange() == twin.full.textView.markedRange())
        #expect(twin.incremental.textView.selectedRange() == twin.full.textView.selectedRange())
        #expect(twin.incremental.textView.hasMarkedText() == twin.full.textView.hasMarkedText())
        #expect(twin.differences().isEmpty, "\(twin.differences())")
        #expect(twin.incremental.coordinator.restyleLog.incremental > 0, "composition was restyled in full or not at all")

        // A second composed character moves on, and the composition still stands.
        twin.edit { fixture in
            fixture.textView.setMarkedText(
                "ñé", selectedRange: NSRange(location: 2, length: 0),
                replacementRange: fixture.textView.markedRange()
            )
        }
        #expect(twin.incremental.textView.markedRange() == twin.full.textView.markedRange())
        #expect(twin.incremental.textView.hasMarkedText())
        #expect(twin.differences().isEmpty, "\(twin.differences())")
    }

    // MARK: Platform pins

    // (R-06, platform pin) TextKit 2 reports a typed character as `(range: {10, 1}, delta: 1)`, and a
    // deletion of three as `(range: {10, 0}, delta: -3)`. ADR-0091 C4 rests on this.
    @Test func theStorageReportsAKeystrokeAsItsRangeAndDelta() async throws {
        let fixture = ScrolledEditorFixture(text: "Una riga di prosa abbastanza lunga.\n")
        defer { fixture.window.orderOut(nil) }

        fixture.type("x", at: 10)
        #expect(fixture.coordinator.lastRecordedEdit == StorageEdit(range: NSRange(location: 10, length: 1), delta: 1))

        fixture.replace(NSRange(location: 10, length: 3), with: "")
        #expect(fixture.coordinator.lastRecordedEdit == StorageEdit(range: NSRange(location: 10, length: 0), delta: -3))
    }

    // (R-06, platform pin) The storage's delegate slot is free on a fresh fixture, before the first
    // full restyle, so installing the coordinator displaces nothing.
    @Test func theStorageDelegateIsNilOnAFreshFixture() {
        let text = "Una riga.\n"
        let view = NoteTextView(
            text: .constant(text), theme: .emergency, noteTitles: [], tagSuggestions: [], onFollowLink: { _ in }
        )
        let coordinator = view.makeCoordinator()
        let textView = CompletingTextView(usingTextLayoutManager: true)
        textView.delegate = coordinator
        textView.string = text
        #expect(textView.textStorage?.delegate == nil, "something already owns the storage's delegate")
    }

    // MARK: The log

    // (R-06) A prose keystroke counts as incremental, and a keystroke on a fence line counts as full.
    @Test func theLogCountsAProseKeystrokeAsIncrementalAndAFenceLineAsFull() throws {
        let fixture = ScrolledEditorFixture(text: "Prosa uno.\n\nProsa due.\n\n```swift\nlet a = 1\n```\n\nCoda.\n")
        defer { fixture.window.orderOut(nil) }
        fixture.openLikeTheApp()

        let before = fixture.coordinator.restyleLog
        fixture.type("x", at: 4)
        let afterProse = fixture.coordinator.restyleLog
        #expect(afterProse.incremental == before.incremental + 1, "a prose keystroke was not restyled by the dirty range")
        #expect(afterProse.full == before.full)
        let dirty = try #require(afterProse.lastDirtyRange)
        #expect(NSLocationInRange(4, dirty) || NSMaxRange(dirty) == 4)

        let fence = (fixture.textView.string as NSString).range(of: "```swift")
        fixture.type("`", at: fence.location + 3)
        let afterFence = fixture.coordinator.restyleLog
        #expect(afterFence.full == afterProse.full + 1, "a keystroke on a fence line was not a full restyle")
        #expect(afterFence.incremental == afterProse.incremental)
    }
}
