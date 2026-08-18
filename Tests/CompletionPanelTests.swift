import AppKit
import SwiftUI
import Testing
@testable import Pergamenum

/// The one panel every completion is drawn in (PG-023).
///
/// `EditorCompletionTests` covers the rule - which trigger a piece of text is - and this
/// covers what the panel is then filled with, which key acts on it, and what reaches the
/// note. Driven on a real `CompletingTextView`, as `TranscludedLineTests` and
/// `FoldBadgeClickTests` are, because three defects shipped in one day were green in the
/// unit suite and only visible on screen: anything that can be exercised against real
/// AppKit here is one fewer thing resting on a hand check.

@MainActor
private func panelled(
    _ text: String,
    cursor: Int,
    titles: [String] = [],
    tags: [String] = [],
    commands: [EditorCommand] = []
) -> CompletingTextView {
    let view = CompletingTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
    view.string = text
    view.setSelectedRange(NSRange(location: cursor, length: 0))
    view.noteTitles = titles
    view.tagSuggestions = tags
    view.editorCommands = commands
    view.refreshCompletion(theme: .emergency)
    return view
}

// MARK: - What each trigger fills the panel with

@MainActor
@Test func aWikilinkOffersNoteTitlesAsCandidates() {
    let view = panelled("Vedi [[Cur", cursor: 10, titles: ["Curva di trasmissibilità", "Altro"])
    #expect(view.completionPanel.isVisible)
    #expect(view.completionPanel.items == [.text("Curva di trasmissibilità", symbol: "doc.text")])
}

@MainActor
@Test func aTagOffersTagsAndSaysSoWithItsOwnIcon() {
    // The suggestions carry their own `#`, as `VaultSession.tagSuggestions` builds them,
    // and the replaced range carries it too - so the candidate is written over the `#cli`
    // whole rather than beside it.
    let view = panelled("Nota su #cli", cursor: 12, tags: ["#client-vibrofer", "#topic-gomma"])
    #expect(view.completionPanel.items == [.text("#client-vibrofer", symbol: "tag")])

    view.doCommand(by: #selector(NSTextView.insertNewline(_:)))
    #expect(view.string == "Nota su #client-vibrofer")
}

@MainActor
@Test func aSectionOffersTheHeadingsOfTheNoteNamedBeforeTheHash() {
    let view = CompletingTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
    view.string = "[[Prove#"
    view.setSelectedRange(NSRange(location: 8, length: 0))
    view.noteSections = { _ in ["Campioni", "Strumenti"] }
    view.refreshCompletion(theme: .emergency)

    #expect(view.completionPanel.items == [
        .text("Campioni", symbol: "number"),
        .text("Strumenti", symbol: "number"),
    ])
}

@MainActor
@Test func aSlashOffersCommandsRatherThanStrings() {
    let view = panelled("/tit", cursor: 4, commands: EditorCommand.editorEntries)
    #expect(view.completionPanel.isVisible)
    #expect(!view.completionPanel.items.isEmpty)
    // Outside the macro: `allSatisfy` rethrows, and `#expect` will not swallow that.
    let everyRowIsACommand = view.completionPanel.items.allSatisfy(\.isCommand)
    #expect(everyRowIsACommand)
}

// MARK: - When there is nothing to show

@MainActor
@Test func nothingMatchedMeansNoPanelForACandidateList() {
    // What AppKit's list did, and the right answer here: the candidates are the vault's
    // own notes, so typing the name of one that does not exist yet is the ordinary case
    // and not a dead end worth a box. A command list says so instead, because there the
    // catalogue is closed and an empty result means the query was wrong.
    let view = panelled("Vedi [[zzz", cursor: 10, titles: ["Curva di trasmissibilità"])
    #expect(!view.completionPanel.isVisible)
}

@MainActor
@Test func leavingTheContextClosesThePanel() {
    let view = panelled("Vedi [[Cur", cursor: 10, titles: ["Curva di trasmissibilità"])
    #expect(view.completionPanel.isVisible)

    view.string = "Vedi [[Curva]] e poi altro"
    view.setSelectedRange(NSRange(location: 26, length: 0))
    view.refreshCompletion(theme: .emergency)
    #expect(!view.completionPanel.isVisible)
}

// MARK: - Escape

@MainActor
@Test func escapeKeepsThePanelShutForTheSameWord() {
    // AppKit remembered this for the three completions it served. Nothing else will now,
    // so it is carried here: without it the panel reopened on the very next keystroke,
    // because the context was still the same context.
    let view = panelled("Vedi [[Cur", cursor: 10, titles: ["Curva di trasmissibilità"])
    view.dismissCompletion()
    #expect(!view.completionPanel.isVisible)

    view.string = "Vedi [[Curv"
    view.setSelectedRange(NSRange(location: 11, length: 0))
    view.refreshCompletion(theme: .emergency)
    #expect(!view.completionPanel.isVisible)
    // And the text is untouched, which is the other half of ADR-0008 §D3.
    #expect(view.string == "Vedi [[Curv")
}

@MainActor
@Test func aFreshTriggerOpensThePanelAgainAfterAnEscape() {
    let view = panelled("Vedi [[Cur", cursor: 10, titles: ["Curva di trasmissibilità"])
    view.dismissCompletion()

    view.string = "Vedi [[Curva]] e [[Cur"
    view.setSelectedRange(NSRange(location: 22, length: 0))
    view.refreshCompletion(theme: .emergency)
    #expect(view.completionPanel.isVisible)
}

// MARK: - Choosing

@MainActor
@Test func returnWritesTheCandidateOverExactlyWhatWasTyped() {
    let view = panelled("Vedi [[Cur", cursor: 10, titles: ["Curva di trasmissibilità"])
    view.doCommand(by: #selector(NSTextView.insertNewline(_:)))

    // The bare title, as AppKit's list inserted it: the `]]` is left for the person to
    // close, so nothing about what reaches the file changes.
    #expect(view.string == "Vedi [[Curva di trasmissibilità")
    #expect(!view.completionPanel.isVisible)
}

@MainActor
@Test func aSectionReplacesOnlyWhatFollowsTheHash() {
    let view = CompletingTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
    view.string = "[[Prove#Cam"
    view.setSelectedRange(NSRange(location: 11, length: 0))
    view.noteSections = { _ in ["Campioni", "Strumenti"] }
    view.refreshCompletion(theme: .emergency)
    view.doCommand(by: #selector(NSTextView.insertNewline(_:)))

    #expect(view.string == "[[Prove#Campioni")
}

@MainActor
@Test func theArrowKeysWalkTheListAndStopAtItsEnds() {
    let view = panelled(
        "Vedi [[C", cursor: 8,
        titles: ["Curva di trasmissibilità", "Campioni", "Cataloghi"]
    )
    #expect(view.completionPanel.selectedIndex == 0)

    view.doCommand(by: #selector(NSTextView.moveDown(_:)))
    #expect(view.completionPanel.selectedIndex == 1)
    // Up at the top stays at the top rather than wrapping to the bottom: in a long list
    // "I have gone too far" would otherwise become "where am I".
    view.doCommand(by: #selector(NSTextView.moveUp(_:)))
    view.doCommand(by: #selector(NSTextView.moveUp(_:)))
    #expect(view.completionPanel.selectedIndex == 0)
}

@MainActor
@Test func clickingARowLandsWhereReturnLands() {
    // The panel never acts on a choice itself; it hands it back. That is what makes a
    // click and a Return the same edit rather than two implementations of one.
    let view = panelled("Vedi [[Cur", cursor: 10, titles: ["Curva di trasmissibilità"])
    view.completionPanel.onChoose?(.text("Curva di trasmissibilità", symbol: "doc.text"))

    #expect(view.string == "Vedi [[Curva di trasmissibilità")
    #expect(!view.completionPanel.isVisible)
}

// MARK: - Where the panel hangs itself

/// A text view built the way `NoteTextView` builds it: TextKit 2, inside a scroll view,
/// inside a real window. The placement defect only exists in that arrangement, so a
/// helper that skips any part of it would prove nothing.
@MainActor
private func windowed(_ text: String) -> (window: NSWindow, view: CompletingTextView) {
    let view = CompletingTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
    scroll.documentView = view
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
        styleMask: [.titled], backing: .buffered, defer: false
    )
    window.contentView = scroll
    view.string = text
    return (window, view)
}

@MainActor
@Test func theCaretHasARectangleAtTheVeryEndOfTheNote() {
    // The place the panel opened in the wrong corner of the screen: the last line of a
    // long note, empty, with the caret after everything. TextKit 2 lays out lazily, so
    // this is exactly the range it has not measured yet - and a caret rect of zero puts
    // the panel at the screen's bottom-left corner, which is where it went.
    let long = (1...60).map { "Riga numero \($0), lunga abbastanza da riempire." }.joined(separator: "\n")
    let (window, view) = windowed(long + "\n\n/")
    defer { window.orderOut(nil) }

    view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
    let rect = view.caretRectOnScreen()
    #expect(rect.height > 0)
    #expect(rect.origin != .zero)
}

// MARK: - The placement rule

/// A screen 1440 points tall, as the rule sees it: y grows upwards, so `minY` is the
/// bottom edge and `maxY` the top.
private let visible = NSRect(x: 0, y: 0, width: 2560, height: 1440)
private let panelSize = NSSize(width: 340, height: 400)

@Test func thePanelSitsUnderTheCaretWhenThereIsRoom() {
    let caret = NSRect(x: 900, y: 800, width: 1, height: 20)
    let origin = CompletionPanel.origin(forPanelOf: panelSize, under: caret, in: visible)
    #expect(origin.x == 900)
    // Six points of air under the line, and the panel below it: its top edge is the
    // caret's bottom less the gap.
    #expect(origin.y + panelSize.height == caret.minY - 6)
}

@Test func thePanelFlipsAboveTheLineWhenTheBottomOfTheScreenIsClose() {
    // The defect Stefano saw: the caret on the last visible line, near the bottom edge.
    let caret = NSRect(x: 900, y: 40, width: 1, height: 20)
    let origin = CompletionPanel.origin(forPanelOf: panelSize, under: caret, in: visible)
    #expect(origin.y == caret.maxY + 6)
    #expect(origin.y > caret.maxY)
}

@Test func thePanelNeverLeavesTheScreenSideways() {
    let right = CompletionPanel.origin(
        forPanelOf: panelSize, under: NSRect(x: 2550, y: 800, width: 1, height: 20), in: visible
    )
    #expect(right.x + panelSize.width <= visible.maxX)

    let left = CompletionPanel.origin(
        forPanelOf: panelSize, under: NSRect(x: -40, y: 800, width: 1, height: 20), in: visible
    )
    #expect(left.x >= visible.minX)
}

@Test func thePanelNeverCoversTheLineBeingTypedInto() {
    // The second thing Stefano saw. A clamp that held the panel inside the screen pulled
    // it back down over the caret, which is the one place it must never be: a completion
    // list hiding what you are completing is worse than one hanging off the display.
    // Every caret height on the screen, and a panel too tall for either side of most of
    // them.
    let tall = NSSize(width: 340, height: 900)
    for y in stride(from: 0.0, through: 1420.0, by: 20.0) {
        let caret = NSRect(x: 900, y: y, width: 1, height: 20)
        let origin = CompletionPanel.origin(forPanelOf: tall, under: caret, in: visible)
        let panel = NSRect(origin: origin, size: tall)
        #expect(!panel.intersects(caret))
    }
}

@Test func theRoomBesideTheCaretIsTheTallerSide() {
    // Near the bottom of the screen the room is above, near the top it is below, and the
    // number is what the panel is then built to fit - the height decides the placement,
    // not the other way round.
    let low = CompletionPanel.roomForPanel(
        besides: NSRect(x: 900, y: 40, width: 1, height: 20), in: visible
    )
    #expect(low == visible.maxY - 60 - 6 - 8)

    let high = CompletionPanel.roomForPanel(
        besides: NSRect(x: 900, y: 1400, width: 1, height: 20), in: visible
    )
    // Bound rather than written inline: an integer literal on the right of the comparison
    // does not survive the macro as the CGFloat it looks like.
    let expectedHigh: CGFloat = 1400 - 6 - 8
    #expect(high == expectedHigh)
}

@MainActor
@Test func thePanelIsBuiltNoTallerThanTheRoomItWasGiven() {
    // The cap has to reach the drawing, or the placement rule is given a size it cannot
    // honour and the caret gets covered again.
    let many = EditorCommand.editorEntries.map(CompletionItem.command)
    let hosting = NSHostingView(
        rootView: CompletionPanelView(
            items: many, query: "", selectedIndex: 0, maxHeight: 200, onChoose: { _ in }
        )
        .environment(\.theme, .emergency)
    )
    #expect(hosting.fittingSize.height <= 200)
}

@MainActor
@Test func theCaretRectGoesDownTheScreenAsTheCaretGoesDownTheNote() {
    // Screen coordinates grow upwards, so a caret further down the note must come back
    // with a *smaller* minY. If it does not, the rectangle handed to the placement rule is
    // upside down and "below the caret" lands on the caret's own line.
    let lines = (1...40).map { "Riga numero \($0), lunga abbastanza da riempire." }
    let (window, view) = windowed(lines.joined(separator: "\n"))
    defer { window.orderOut(nil) }

    let text = view.string as NSString
    let fifth = text.paragraphRange(for: NSRange(location: 0, length: 0))
    var location = fifth.location
    for _ in 0..<5 { location = text.paragraphRange(for: NSRange(location: location, length: 0)).upperBound }
    view.setSelectedRange(NSRange(location: location, length: 0))
    let higher = view.caretRectOnScreen()

    let next = text.paragraphRange(for: NSRange(location: location, length: 0)).upperBound
    view.setSelectedRange(NSRange(location: next, length: 0))
    let lower = view.caretRectOnScreen()

    #expect(higher.height > 0)
    #expect(lower.height > 0)
    #expect(lower.minY < higher.minY)
    // And one line apart, not several: a rect measured in the wrong space is usually also
    // the wrong size.
    #expect(higher.minY - lower.minY == higher.height)
}

@MainActor
@Test func theCaretRectIsTheCaretsOwnLineAndNotTheOneAboveIt() {
    // The test above compares two carets with each other, so a rectangle a whole line out
    // of place passes it: both shift together. This one pins the first line to the top of
    // the text view, which is the only fixed point there is.
    let lines = (1...40).map { "Riga numero \($0), lunga abbastanza da riempire." }
    let (window, view) = windowed(lines.joined(separator: "\n"))
    defer { window.orderOut(nil) }

    view.setSelectedRange(NSRange(location: 0, length: 0))
    let caret = view.caretRectOnScreen()
    #expect(caret.height > 0)

    // The text view's own top edge, on screen. The first line's caret cannot be above it,
    // and cannot be a whole line below it either.
    let viewTop = window.convertToScreen(view.convert(view.bounds, to: nil)).maxY
    #expect(caret.maxY <= viewTop)
    #expect(viewTop - caret.maxY < caret.height)
}
