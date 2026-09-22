import AppKit
import Testing
@testable import Pergamenum

/// `DesignAndReadingUITests.swift:159`'s own assertion, reproduced in-process: a GFM
/// table's header line is really hosted by TextKit 2 as a `TableGridView` reachable
/// through the editor's own `accessibilityChildren()`, carrying the `editor-table`
/// identifier the retired GUI test looked for.
///
/// `Tests/TableRenderingTests.swift`'s own `TableGridAccessibility` suite measured this
/// as unreachable in-process and said so in its header comment: with the text view set
/// directly as a window's `contentView` (`EmbedEditorFixtures.editor`'s shape) and no
/// `NSScrollView`, `NSTextViewportLayoutController` never places the grid even after
/// `ensureLayout` and an explicit `layoutViewport()`, because a window that is never
/// ordered in has an empty visible rect - so that suite asserts the accessibility
/// *plumbing* against a grid it places by hand with `addSubview`.
///
/// **What is different here.** Wrapping the text view in a real `NSScrollView` and
/// calling `window.layoutIfNeeded()` before asking for layout - the same two calls
/// `Tests/EditorHeightTests.swift:46-55` already makes, and the shape
/// `NoteTextView.makeNSView` itself builds (a bare content view is not what the app
/// ever draws into) - gives the text view a real, non-empty `visibleRect` without the
/// window ever being ordered front, `isKeyWindow`, or shown to anyone (R-15): measured
/// on this tree, `grid.superview` is a real `_NSTextViewportElementView` afterwards, not
/// nil. `textView.layoutSubtreeIfNeeded()` right before `layoutViewport()` turned out to
/// be load-bearing too - without it the grid stayed unplaced even with the scroll view
/// and `ensureLayout` both in place, measured the same way.
@MainActor
@Test func aTablesHeaderIsHostedAsAGridReachableThroughTheEditorsAccessibilityTree() {
    let note = "prima\n| a | b |\n|---|---|\n| 1 | 2 |\n| 3 | 4 |\ndopo\n"
    let view = NoteTextView(
        text: .constant(note), theme: .emergency, noteTitles: [], tagSuggestions: [],
        hidesMarkup: true, onFollowLink: { _ in }
    )
    let coordinator = view.makeCoordinator()
    let textView = CompletingTextView(usingTextLayoutManager: true)
    textView.delegate = coordinator
    textView.isRichText = false
    textView.allowsUndo = true
    textView.textContainerInset = NSSize(width: 24, height: 20)
    textView.isVerticallyResizable = true
    textView.autoresizingMask = [.width]
    textView.frame = CGRect(x: 0, y: 0, width: 600, height: 700)
    textView.textContainer?.size = CGSize(width: 552, height: CGFloat.greatestFiniteMagnitude)
    coordinator.textView = textView
    textView.textContentStorage?.delegate = coordinator.decorations
    textView.textLayoutManager?.delegate = coordinator.decorations
    view.wire(textView, to: coordinator)
    textView.string = note

    let scroll = NSScrollView(frame: CGRect(x: 0, y: 0, width: 600, height: 700))
    scroll.documentView = textView
    scroll.hasVerticalScroller = true
    let window = NSWindow(
        contentRect: CGRect(x: 0, y: 0, width: 600, height: 700),
        styleMask: [.titled], backing: .buffered, defer: false
    )
    window.contentView = scroll
    window.layoutIfNeeded()
    defer { window.orderOut(nil) }

    coordinator.applyStyling(to: textView, theme: .emergency)
    guard let layout = textView.textLayoutManager else {
        Issue.record("il text view non ha un text layout manager")
        return
    }
    layout.ensureLayout(for: layout.documentRange)
    textView.layoutSubtreeIfNeeded()
    layout.textViewportLayoutController.layoutViewport()

    // "prima\n" is six characters; the table's header paragraph starts right after it -
    // `TableFixture.headerOffset` in `TableRenderingTests.swift`, not shared from there on
    // purpose (ADR-0051 §D4: only the pieces genuinely narrower than a fixture stay local).
    guard let grid = coordinator.decorations.tableViews[6] else {
        Issue.record("la griglia della tabella non è stata costruita")
        return
    }

    let offered = (textView.accessibilityChildren() ?? []).compactMap { $0 as? TableGridView }
    #expect(offered == [grid], "la griglia non è tra i figli accessibili dell'editor")
    #expect(
        offered.first?.accessibilityIdentifier() == "editor-table",
        "la griglia esposta non porta l'identificatore che la suite UI cercava"
    )
}
