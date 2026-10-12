import AppKit
import Foundation
import Testing
@testable import Pergamenum

// ADR-0093 §D2 to §D6, plan docs/plans/scoped-layout-followup.md, Task 3 (R-02, R-05, R-06, R-07, R-09).
//
// The layout record on a hosted editor, driven the way `EditorGrowToFitScopeTests` drives one: typing,
// `insertText`, `setSelectedRange`, `moveToEndOfDocument(_:)` and the passes an update runs. The record
// is read off `coordinator.layoutDebt.log`: which path each settle took, why a whole one was whole, and
// that no owed range went unconverted. The no-estimate witness (the usage height and the last fragment's
// `y` do not move when the document range is then laid out) checks that laying out only what is owed
// leaves no height an estimate.
//
// A click is driven as the part of it that matters here. `NSTextView.mouseDown` runs a nested tracking
// loop until a mouse-up arrives, which a unit test cannot deliver (`WikilinkClickNavigationTests`
// says so), so the click is its two effects: the character under the point becomes the caret, and the
// passes the click's update runs follow while the mouse is still down. What went wrong at G-grow was
// the point resolving to other text once those passes had run.

/// About 2,000 lines: a heading, a blank line and three prose lines, four hundred times, ending in a
/// line that names itself.
private let longNote: String = {
    var lines: [String] = []
    for section in 1...400 {
        lines.append("# Sezione \(section)")
        lines.append("")
        lines.append("Prima riga della sezione \(section), con **grassetto** e un [[Nota \(section)]].")
        lines.append("Seconda riga della sezione \(section), con #project-av\(section % 20) e >2026-10-04.")
        lines.append("Terza riga della sezione \(section), senza nulla di particolare.")
    }
    lines.append("Ultima riga della nota lunga.")
    return lines.joined(separator: "\n")
}()

private let otherNote = (1...40).map { "# Altra nota \($0)\n\nTesto diverso della riga \($0).\n" }.joined(separator: "\n")

private let foldNote = "# Uno\n\nTesto uno.\n\n## Due\n\nTesto due.\n\n## Tre\n\nTesto tre.\n"

/// A sentence long enough to wrap the line it lands in.
private let wrapping = String(repeating: "parola ", count: 40)

/// The end of the first line after `marker`: a place where one `x` changes no construct.
private func endOfLine(after marker: String, in text: String) -> Int {
    let nsText = text as NSString
    let found = nsText.range(of: marker)
    return nsText.lineRange(for: found).upperBound - 1
}

private func paragraph(at location: Int, in text: String) -> NSRange {
    let nsText = text as NSString
    return nsText.paragraphRange(for: NSRange(location: min(location, nsText.length), length: 0))
}

/// Every range lies inside one of the regions widened by a character on each side: the paragraphs that
/// changed, never the note.
private func expectInside(
    _ ranges: [NSRange], regions: [NSRange], in text: String, _ label: String,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    let length = (text as NSString).length
    let allowed = regions.map { region -> NSRange in
        let start = max(0, region.location - 1)
        return NSRange(location: start, length: min(length, NSMaxRange(region) + 1) - start)
    }
    #expect(!ranges.isEmpty, "\(label): no range was laid out", sourceLocation: sourceLocation)
    for range in ranges {
        let inside = allowed.contains { $0.location <= range.location && NSMaxRange(range) <= NSMaxRange($0) }
        #expect(inside, "\(label): laid out \(range), outside \(allowed)", sourceLocation: sourceLocation)
    }
}

/// A storage delegate that is not the coordinator.
private final class ForeignDelegate: NSObject, NSTextStorageDelegate {}

/// The notes the keystroke tests run on: a long plain one, and the rich one (a table, a view block, an
/// embed, a transclusion and a fold below the prose).
private enum Subject: String, CaseIterable, Sendable, CustomTestStringConvertible {
    case long
    case rich

    var testDescription: String { rawValue }

    @MainActor func twin() async throws -> RestyleTwin {
        switch self {
        case .long: RestyleTwin.plain(longNote)
        case .rich: try await RestyleTwin.rich()
        }
    }

    /// A place in the prose near the top where one character changes no construct.
    func top(in text: String) -> Int {
        switch self {
        case .long: endOfLine(after: "Prima riga della sezione 1,", in: text)
        case .rich: (text as NSString).range(of: "prosa").location
        }
    }
}

@MainActor
@Suite(.serialized) struct LayoutDebtHosted {
    /// One keystroke and what it did to the record.
    private func expectKeystroke(
        _ label: String, in editor: ScrolledEditorFixture, killSwitch: Bool,
        sourceLocation: SourceLocation = #_sourceLocation, _ body: () -> Void
    ) {
        let before = editor.coordinator.layoutDebt.log
        body()
        let after = editor.coordinator.layoutDebt.log
        // An unconverted range is counted as ranged too, and leaves the next settle whole.
        #expect(after.unconverted == before.unconverted, "\(label): a range was not converted: \(before) then \(after)", sourceLocation: sourceLocation)
        if killSwitch {
            #expect(after.ranged == before.ranged, "\(label): laid out by ranges with the switch on", sourceLocation: sourceLocation)
            #expect(after.lastWholeReason == .killSwitch, "\(label): \(String(describing: after.lastWholeReason))", sourceLocation: sourceLocation)
        } else {
            #expect(after.ranged > before.ranged, "\(label): the layout was not by ranges: \(before) then \(after)", sourceLocation: sourceLocation)
        }
        editor.expectNoEstimate(label, sourceLocation: sourceLocation)
    }

    /// Runs `action`, and when the settle it caused is not yet in the record runs the passes an update
    /// would: the ranges a settle laid out are read straight after it, before a later empty one.
    private func settling(_ fixture: ScrolledEditorFixture, _ action: () -> Void) {
        let before = fixture.coordinator.layoutDebt.log.ranged
        action()
        if fixture.coordinator.layoutDebt.log.ranged == before { fixture.runPasses() }
    }

    // MARK: R-05 and R-09, no estimate after a keystroke

    // (R-05, R-09) A character, a new paragraph and an insertion that wraps the line, at the top and
    // after a jump to the end of the note: each is laid out by ranges (whole with the switch on) and
    // none leaves a height that is an estimate.
    @Test(arguments: Subject.allCases, [false, true])
    fileprivate func afterAKeystrokeNoHeightInTheNoteIsAnEstimate(_ subject: Subject, killSwitch: Bool) async throws {
        let twin = try await subject.twin()
        defer { twin.tearDown() }
        let editor = twin.incremental
        editor.coordinator.forcesFullLayout = killSwitch
        let layout = try #require(editor.textView.textLayoutManager)
        editor.openLikeTheApp()
        let top = subject.top(in: editor.textView.string)

        expectKeystroke("a character at the top", in: editor, killSwitch: killSwitch) { twin.type("x", at: top) }
        expectKeystroke("a new paragraph at the top", in: editor, killSwitch: killSwitch) { twin.type("\n", at: top + 1) }
        expectKeystroke("a wrapping insertion at the top", in: editor, killSwitch: killSwitch) { twin.type(wrapping, at: top + 1) }

        editor.textView.moveToEndOfDocument(nil)
        layout.textViewportLayoutController.layoutViewport()
        let end = (editor.textView.string as NSString).length
        expectKeystroke("a character at the end", in: editor, killSwitch: killSwitch) { twin.type("x", at: end) }
        #expect(twin.differences().isEmpty, "\(twin.differences())")
    }

    // (R-05, R-09) The same four keystrokes with the witness only at the end. `expectNoEstimate` lays out
    // the document range itself, so the test above starts every keystroke from a fully laid-out note and
    // cannot see an owed range that one settle missed and the next did not reach; here nothing lays the
    // note out between them but the editor's own settles.
    @Test(arguments: Subject.allCases)
    fileprivate func fourKeystrokesInARowLeaveNoEstimateForTheWitnessAtTheEnd(_ subject: Subject) async throws {
        let twin = try await subject.twin()
        defer { twin.tearDown() }
        let editor = twin.incremental
        editor.coordinator.forcesFullLayout = false
        let layout = try #require(editor.textView.textLayoutManager)
        editor.openLikeTheApp()
        let top = subject.top(in: editor.textView.string)
        let before = editor.coordinator.layoutDebt.log

        twin.type("x", at: top)
        twin.type("\n", at: top + 1)
        twin.type(wrapping, at: top + 1)
        editor.textView.moveToEndOfDocument(nil)
        layout.textViewportLayoutController.layoutViewport()
        twin.type("x", at: (editor.textView.string as NSString).length)

        let after = editor.coordinator.layoutDebt.log
        #expect(after.ranged > before.ranged, "the layout was not by ranges: \(before) then \(after)")
        #expect(after.unconverted == before.unconverted, "a range was not converted: \(before) then \(after)")
        editor.expectNoEstimate("four keystrokes, witnessed once")
        #expect(twin.differences().isEmpty, "\(twin.differences())")
    }

    // MARK: R-06 and R-09, the view stays where it was

    // (R-06, R-09) A keystroke, Cmd+Down, then a click about 60 pt above the bottom edge: the top of the
    // view stays on the same text, and the point that was aimed at still resolves to the text it was
    // aimed at once the click's passes have run.
    @Test(arguments: [false, true])
    func aClickLowInThePaneAfterAKeystrokeAndCmdDownStaysOnTheSameText(killSwitch: Bool) throws {
        let fixture = ScrolledEditorFixture(text: longNote, forcesFullLayout: killSwitch)
        defer { fixture.window.orderOut(nil) }
        let layout = try #require(fixture.textView.textLayoutManager)
        fixture.openLikeTheApp()
        let baseline = fixture.coordinator.layoutDebt.log

        fixture.type("x", at: endOfLine(after: "Prima riga della sezione 1,", in: longNote))
        fixture.runPasses()
        let afterKeystroke = fixture.coordinator.layoutDebt.log
        if killSwitch {
            #expect(afterKeystroke.ranged == baseline.ranged)
            #expect(afterKeystroke.lastWholeReason == .killSwitch)
        } else {
            #expect(afterKeystroke.ranged > baseline.ranged, "the keystroke was not laid out by ranges: \(baseline) then \(afterKeystroke)")
        }

        fixture.textView.moveToEndOfDocument(nil)
        layout.textViewportLayoutController.layoutViewport()
        fixture.textView.scrollRangeToVisible(fixture.textView.selectedRange())
        layout.textViewportLayoutController.layoutViewport()

        func topOfTheView() -> Int {
            let top = CGPoint(x: fixture.textView.bounds.midX, y: fixture.textView.visibleRect.minY + 4)
            return fixture.textView.characterIndexForInsertion(at: top)
        }
        let point = CGPoint(x: fixture.textView.bounds.midX, y: fixture.textView.visibleRect.maxY - 60)
        let aimed = fixture.textView.characterIndexForInsertion(at: point)
        let topBefore = topOfTheView()

        // The click: the caret goes to the character under the point, and the update it causes runs the
        // passes while the mouse is still down.
        fixture.textView.setSelectedRange(NSRange(location: aimed, length: 0))
        fixture.runPasses()

        let topAfter = topOfTheView()
        let landed = fixture.textView.characterIndexForInsertion(at: point)
        let text = fixture.textView.string as NSString
        let lineBefore = text.substring(with: text.lineRange(for: NSRange(location: topBefore, length: 0)))
        let lineAfter = text.substring(with: text.lineRange(for: NSRange(location: topAfter, length: 0)))
        #expect(abs(topAfter - topBefore) < 200, "the view moved from \"\(lineBefore)\" to \"\(lineAfter)\"")
        #expect(
            paragraph(at: landed, in: fixture.textView.string) == paragraph(at: aimed, in: fixture.textView.string),
            "the point aimed at character \(aimed) resolves to \(landed) after the passes"
        )
        #expect(fixture.textView.selectedRange().location == aimed, "the caret is not at the character that was clicked")
        fixture.expectNoEstimate("after the click")
    }

    // MARK: R-07, the whole note is owed

    // (R-07) At the first use of a coordinator.
    @Test func theFirstUseOwesTheWholeNote() {
        let fixture = ScrolledEditorFixture(text: longNote)
        defer { fixture.window.orderOut(nil) }
        let before = fixture.coordinator.layoutDebt.log

        fixture.coordinator.growToFitTheText(fixture.textView)

        let after = fixture.coordinator.layoutDebt.log
        #expect(after.whole == before.whole + 1, "\(before) then \(after)")
        #expect(after.lastWholeReason == .everythingOwed)
    }

    fileprivate enum WholeTextPass: String, CaseIterable, Sendable, CustomTestStringConvertible {
        case noteSwitch = "a note switch"
        case fullRestyle = "a full restyle"
        case externalChange = "an external change"

        var testDescription: String { rawValue }
    }

    // (R-07) At a whole-text pass: a note switch through `textView.string =`, a full restyle (a theme or
    // a setting change), an external change. Each reaches the record as a range covering the note.
    @Test(arguments: WholeTextPass.allCases)
    fileprivate func aWholeTextPassOwesTheWholeNote(_ pass: WholeTextPass) {
        let fixture = ScrolledEditorFixture(text: longNote)
        defer { fixture.window.orderOut(nil) }
        fixture.openLikeTheApp()
        let before = fixture.coordinator.layoutDebt.log

        switch pass {
        case .noteSwitch:
            fixture.textView.string = otherNote
            fixture.runPasses()
        case .fullRestyle:
            fixture.coordinator.applyStyling(to: fixture.textView, theme: .emergency)
            fixture.coordinator.growToFitTheText(fixture.textView)
        case .externalChange:
            fixture.replace(NSRange(location: 0, length: (fixture.textView.string as NSString).length), with: otherNote)
            fixture.runPasses()
        }

        let after = fixture.coordinator.layoutDebt.log
        #expect(after.whole > before.whole, "\(pass.rawValue): the note was not laid out whole: \(before) then \(after)")
        #expect(after.lastWholeReason == .everythingOwed, "\(pass.rawValue): \(String(describing: after.lastWholeReason))")
        fixture.expectNoEstimate(pass.rawValue)
    }

    // (R-07) At a fold change.
    @Test func aFoldChangeOwesTheWholeNote() {
        let fixture = ScrolledEditorFixture(text: foldNote)
        defer { fixture.window.orderOut(nil) }
        fixture.openLikeTheApp()
        let before = fixture.coordinator.layoutDebt.log

        fixture.fold(heading: "## Due")
        fixture.runPasses()

        #expect(fixture.coordinator.decorations.isFolding, "nothing was folded")
        let after = fixture.coordinator.layoutDebt.log
        #expect(after.whole > before.whole, "the note was not laid out whole: \(before) then \(after)")
        #expect(after.lastWholeReason == .everythingOwed)
        fixture.expectNoEstimate("after the fold")
    }

    // (R-07) At a transclusion change: the resolver's generation moved and the renditions are not what
    // they were.
    @Test func aTransclusionChangeOwesTheWholeNote() async throws {
        let twin = try await RestyleTwin.rich()
        defer { twin.tearDown() }
        let editor = twin.incremental
        editor.openLikeTheApp()
        let generationBefore = editor.coordinator.transclusion.renditionGeneration
        let before = editor.coordinator.layoutDebt.log

        var inputs = editor.coordinator.parent
        inputs.vault.transclusions = TransclusionSource(
            resolve: { reference in
                guard reference.hasPrefix("Prove") else { return nil }
                return TransclusionSource.Resolved(
                    title: reference, relativePath: "\(reference).md",
                    text: "# \(reference)\n\nCinque serie di misure completamente diverse, su più righe.\n\nSeconda riga.\n\nTerza riga.\n"
                )
            },
            generation: 2
        )
        editor.coordinator.parent = inputs
        editor.runPasses()

        #expect(
            editor.coordinator.transclusion.renditionGeneration != generationBefore,
            "the renditions were not redrawn, so this proves nothing about the layout"
        )
        let after = editor.coordinator.layoutDebt.log
        #expect(after.whole > before.whole, "the note was not laid out whole: \(before) then \(after)")
        #expect(after.lastWholeReason == .everythingOwed)
        editor.expectNoEstimate("after the transclusion changed")
    }

    // (R-07) At a view-block height change: the measured height changes through the host's own callback,
    // and one main-actor turn later the deferred relayout runs.
    @Test func aViewBlockHeightChangeOwesTheWholeNote() async throws {
        let twin = try await RestyleTwin.rich()
        defer { twin.tearDown() }
        let editor = twin.incremental
        editor.openLikeTheApp()
        try #require(!editor.coordinator.viewBlocks.drawn.isEmpty, "no view block is drawn")
        let host = editor.coordinator.viewBlocks.hosts.host(for: 0, in: editor.textView)
        let callback = try #require(Self.heightCallback(in: host.rootView), "the host has no height callback")
        let current = host.measuredHeight.height ?? 0
        let target: CGFloat = current > 150 ? 100 : 200
        let before = editor.coordinator.layoutDebt.log

        callback(CGSize(width: 400, height: target))
        #expect(host.measuredHeight.height == target, "the callback did not store the height")
        try await Task.sleep(for: .milliseconds(150))

        let after = editor.coordinator.layoutDebt.log
        #expect(after.whole > before.whole, "the note was not laid out whole: \(before) then \(after)")
        #expect(after.lastWholeReason == .everythingOwed)
        editor.expectNoEstimate("after the view block changed height")
    }

    /// The `onGeometryChange` action of a host's root view, which is the closure that reports a measured
    /// height (`ViewBlockHostStore.rootView`); the real code path, reached by walking the view's value.
    private static func heightCallback(in value: Any, depth: Int = 0) -> ((CGSize) -> Void)? {
        guard depth < 60 else { return nil }
        if let closure = value as? (CGSize) -> Void { return closure }
        for child in Mirror(reflecting: value).children {
            if let found = heightCallback(in: child.value, depth: depth + 1) { return found }
        }
        return nil
    }
}

// The rest of the suite, in an extension only to keep the struct's body within SwiftLint's.
extension LayoutDebtHosted {
    // (R-07) At a container width change: the scroll view is resized and the layout meets a new width.
    @Test func aContainerWidthChangeOwesTheWholeNote() throws {
        let fixture = ScrolledEditorFixture(text: longNote)
        defer { fixture.window.orderOut(nil) }
        fixture.openLikeTheApp()
        let container = try #require(fixture.textView.textContainer)
        let widthBefore = container.size.width
        let before = fixture.coordinator.layoutDebt.log

        fixture.scrollView.setFrameSize(NSSize(width: 400, height: 700))
        fixture.window.layoutIfNeeded()
        fixture.coordinator.applyReadableWidth(to: fixture.textView)
        try #require(container.size.width != widthBefore, "the container kept its width \(widthBefore)")
        fixture.coordinator.growToFitTheText(fixture.textView)

        let after = fixture.coordinator.layoutDebt.log
        #expect(after.whole > before.whole, "the note was not laid out whole: \(before) then \(after)")
        #expect(after.lastWholeReason == .widthChanged)
        fixture.expectNoEstimate("after the width changed")
    }

    // (R-07) At a readable-width inset change: past the readable-width cap the container is
    // `cap + 2 * gutter` wide whatever the pane does, so a resize moves only the inset
    // (`applyReadableWidth`), which invalidates the layout of the whole note without a storage edit.
    // The container width is the same before and after, so it cannot be what tells the record.
    @Test(arguments: [(900, 1200), (1200, 900)] as [(CGFloat, CGFloat)])
    func aReadableWidthInsetChangeOwesTheWholeNote(from start: CGFloat, to end: CGFloat) throws {
        let fixture = ScrolledEditorFixture(text: longNote, width: start)
        defer { fixture.window.orderOut(nil) }
        fixture.openLikeTheApp()
        let container = try #require(fixture.textView.textContainer)
        let widthBefore = container.size.width
        let insetBefore = fixture.textView.textContainerInset.width
        let before = fixture.coordinator.layoutDebt.log

        // The viewport stays at the top: from deep in the note, the layout of the viewport that
        // `growToFitTheText` asks for after the document range re-estimates what is above it, whatever
        // the record said (the container-width path does the same).
        fixture.scrollView.setFrameSize(NSSize(width: end, height: 700))
        fixture.window.layoutIfNeeded()
        fixture.coordinator.applyReadableWidth(to: fixture.textView)
        fixture.window.layoutIfNeeded()
        try #require(
            fixture.textView.textContainerInset.width != insetBefore,
            "the inset kept its value \(insetBefore)"
        )
        try #require(
            abs(container.size.width - widthBefore) < 0.5,
            "the container moved from \(widthBefore) to \(container.size.width): this is not the pinned regime"
        )
        fixture.type("x", at: endOfLine(after: "Prima riga della sezione 1,", in: longNote))

        let after = fixture.coordinator.layoutDebt.log
        #expect(after.whole > before.whole, "the note was not laid out whole: \(before) then \(after)")
        #expect(after.lastWholeReason == .widthChanged)
        fixture.expectNoEstimate("after the inset changed from \(start) to \(end)")
    }

    // MARK: R-07, only what changed is owed

    // (R-07) After a keystroke: the paragraph it landed in, widened by a character each side.
    @Test func aKeystrokeOwesOnlyItsParagraph() {
        let fixture = ScrolledEditorFixture(text: longNote)
        defer { fixture.window.orderOut(nil) }
        let location = endOfLine(after: "Terza riga della sezione 3,", in: longNote)
        // The caret first, so the reveal it causes is not part of the keystroke.
        fixture.textView.setSelectedRange(NSRange(location: location, length: 0))
        fixture.runPasses()
        fixture.openLikeTheApp()
        let before = fixture.coordinator.layoutDebt.log

        settling(fixture) { fixture.type("x", at: location) }

        let after = fixture.coordinator.layoutDebt.log
        #expect(after.whole == before.whole, "the note was laid out whole: \(before) then \(after)")
        #expect(after.ranged > before.ranged, "\(before) then \(after)")
        #expect(after.unconverted == before.unconverted, "a range was not converted: \(before) then \(after)")
        expectInside(after.lastRanges, regions: [paragraph(at: location, in: fixture.textView.string)], in: fixture.textView.string, "a keystroke")
    }

    // (R-07) After a reveal: the caret moves into a paragraph with markup, and the paragraph it left and
    // the one it entered are owed.
    @Test func aRevealOwesOnlyTheParagraphsItChanged() {
        let fixture = ScrolledEditorFixture(text: longNote)
        defer { fixture.window.orderOut(nil) }
        fixture.openLikeTheApp()
        let before = fixture.coordinator.layoutDebt.log
        let text = fixture.textView.string
        let target = (text as NSString).range(of: "Prima riga della sezione 5,").location + 5
        let left = paragraph(at: fixture.textView.selectedRange().location, in: text)

        settling(fixture) { fixture.textView.setSelectedRange(NSRange(location: target, length: 0)) }

        #expect(!fixture.coordinator.reveal.lastRevealed.isEmpty, "no paragraph was revealed under the caret")
        let after = fixture.coordinator.layoutDebt.log
        #expect(after.whole == before.whole, "the note was laid out whole: \(before) then \(after)")
        #expect(after.ranged > before.ranged, "\(before) then \(after)")
        #expect(after.unconverted == before.unconverted, "a range was not converted: \(before) then \(after)")
        expectInside(after.lastRanges, regions: [left, paragraph(at: target, in: text)], in: text, "a reveal")
    }

    // (R-07) After an embed: the thumbnail rendition arrives and the paragraph of the embed is owed.
    @Test func anEmbedRenditionOwesOnlyItsParagraph() async throws {
        let root = try EmbedEditorFixtures.makeTempVaultRoot(prefix: "pergamenum-layout-")
        defer { try? FileManager.default.removeItem(at: root) }
        try EmbedEditorFixtures.writeImage(named: "foto.png", in: root)
        let thumbnails = ThumbnailStore(root: root, directory: root.appending(path: "cache", directoryHint: .isDirectory))
        let text = "Riga di prosa prima.\n\n![[foto.png]]\n\nRiga di prosa dopo.\n"
        let fixture = ScrolledEditorFixture(
            text: text, vault: .init(vaultRoot: root, notePath: "Nota.md", thumbnails: thumbnails)
        )
        defer { fixture.window.orderOut(nil) }
        fixture.runPasses()
        fixture.openLikeTheApp()
        let before = fixture.coordinator.layoutDebt.log

        // The thumbnail arrives on its own; the passes an update runs follow it. The ranges are read
        // at the first settle that laid something out.
        var after = before
        for _ in 0..<100 {
            try? await Task.sleep(for: .milliseconds(50))
            fixture.runPasses()
            after = fixture.coordinator.layoutDebt.log
            if !fixture.coordinator.embeds.renditions.isEmpty, after.ranged > before.ranged { break }
        }
        try #require(!fixture.coordinator.embeds.renditions.isEmpty, "the thumbnail never arrived")
        #expect(after.whole == before.whole, "the note was laid out whole: \(before) then \(after)")
        #expect(after.ranged > before.ranged, "\(before) then \(after)")
        #expect(after.unconverted == before.unconverted, "a range was not converted: \(before) then \(after)")
        let embed = (text as NSString).range(of: "![[foto.png]]")
        expectInside(after.lastRanges, regions: [paragraph(at: embed.location, in: text)], in: text, "an embed rendition")
        fixture.expectNoEstimate("after the thumbnail arrived")
    }

    // (R-07) After a view-block per-paragraph edit: a keystroke in a fence body, which the restyle covers
    // as the fence's lines, owes those lines and not the note.
    @Test func aKeystrokeInAViewBlockBodyOwesOnlyTheFencesLines() async throws {
        let twin = try await RestyleTwin.rich()
        defer { twin.tearDown() }
        let editor = twin.incremental
        let anchor = (editor.textView.string as NSString).range(of: "render: list")
        try #require(anchor.location != NSNotFound)
        let location = anchor.location + 12
        // The caret goes into the fence first: moving it there is a full restyle of its own.
        editor.textView.setSelectedRange(NSRange(location: location, length: 0))
        editor.runPasses()
        editor.coordinator.growToFitTheText(editor.textView)
        let before = editor.coordinator.layoutDebt.log

        // A twin's undo managers do not group by event, so the keystroke is grouped by hand.
        settling(editor) {
            editor.undoManager?.beginUndoGrouping()
            editor.type("x", at: location)
            editor.undoManager?.endUndoGrouping()
        }

        let text = editor.textView.string as NSString
        let opening = text.range(of: "```pergamenum-view")
        let closing = text.range(of: "\n```\n", options: [], range: NSRange(location: opening.location, length: text.length - opening.location))
        try #require(opening.location != NSNotFound && closing.location != NSNotFound)
        let fence = NSRange(location: opening.location, length: NSMaxRange(closing) - opening.location)
        let after = editor.coordinator.layoutDebt.log
        #expect(after.whole == before.whole, "the note was laid out whole: \(before) then \(after)")
        #expect(after.ranged > before.ranged, "\(before) then \(after)")
        #expect(after.unconverted == before.unconverted, "a range was not converted: \(before) then \(after)")
        expectInside(after.lastRanges, regions: [fence], in: text as String, "a keystroke in a fence body")
    }

    // MARK: R-02, a foreign delegate

    // (R-02) With the storage's delegate replaced by another object, the next grow-to-fit lays out the
    // whole note, names why, and no height is an estimate.
    @Test func aForeignDelegateMeansWholeNoteLayout() throws {
        let fixture = ScrolledEditorFixture(text: longNote)
        defer { fixture.window.orderOut(nil) }
        fixture.openLikeTheApp()
        let storage = try #require(fixture.textView.textStorage)
        let foreign = ForeignDelegate()
        storage.delegate = foreign
        let before = fixture.coordinator.layoutDebt.log

        fixture.coordinator.growToFitTheText(fixture.textView)

        let after = fixture.coordinator.layoutDebt.log
        #expect(after.whole == before.whole + 1, "\(before) then \(after)")
        #expect(after.lastWholeReason == .foreignDelegate)
        fixture.expectNoEstimate("with a foreign delegate")
    }

    // (R-02, ADR-0093 §D5) The restyle half: with a foreign delegate the coordinator records nothing, and
    // the keystroke used to be skipped. It is restyled in full instead, and the coordinator is the
    // storage's delegate again afterwards.
    @Test func aForeignDelegateStillGetsTheKeystrokeRestyledAndIsReplaced() throws {
        let fixture = ScrolledEditorFixture(text: longNote)
        defer { fixture.window.orderOut(nil) }
        fixture.openLikeTheApp()
        let storage = try #require(fixture.textView.textStorage)
        let foreign = ForeignDelegate()
        storage.delegate = foreign
        let before = fixture.coordinator.restyleLog

        fixture.type("x", at: endOfLine(after: "Prima riga della sezione 1,", in: longNote))

        let after = fixture.coordinator.restyleLog
        #expect(after.full > before.full, "the keystroke was not restyled in full: \(before) then \(after)")
        #expect(after.skipped == before.skipped, "the keystroke was skipped: \(before) then \(after)")
        #expect(storage.delegate === fixture.coordinator, "the coordinator did not take the storage's delegate back")
        fixture.runPasses()
        fixture.expectNoEstimate("after the foreign delegate was replaced")
    }
}
