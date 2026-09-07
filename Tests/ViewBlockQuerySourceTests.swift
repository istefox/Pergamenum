import AppKit
import SwiftUI
import Testing
@testable import Pergamenum

/// ADR-0033 §D9/§D10 (plan `2026-09-06-pg-099-views-board-renderer-orphaned-by`, Task 7):
/// wiring `viewQuerySource` into the editor, the live-refresh id `.task(id:)` is keyed on, and
/// click-to-open on the four renderers (R-07, R-09, R-13).
///
/// **Tester stubs declared for this task, all defaulted `nil` (ADR-0049):**
/// - `NoteTextView.queries: ViewQuerySource?` - declared, not read by `EditorColumn+Text.swift`'s
///   `editing(_:)` or by `NoteTextView+ViewBlocks.swift`'s `refreshViewBlockHosts` (still calls
///   `ViewBlockHostStore.rootView(source:theme:)` alone). That threading, and rewriting the now-
///   stale "unreferenced" comment at `EditorColumn+Text.swift:194-198`, are the coder's own work.
/// - `RenderedViewBlock.onEditSource: (() -> Void)?` and `.onOpenNote: ((String) -> Void)?` -
///   declared, not wired into `body`/`header(...)`/`rows(_:_:)`.
/// - `onOpenNote: ((String) -> Void)?` on `ViewTableRenderer`, `ViewListRenderer`,
///   `ViewGalleryRenderer`, `ViewCalendarRenderer`, each paired with an `openAction(for:)` pure
///   stub that always returns `nil` regardless of `onOpenNote` - the seam
///   `ViewRowRendererClickTargets` below asserts on without a live SwiftUI render (this task's
///   own ask). The coder both fills each stub in and calls it from the row's own title inside
///   `body`.
///
/// **Already real and not stubbed**, extended here rather than declared for the first time:
/// `RenderedViewBlock.taskID(source:generation:reloads:)` is a value-preserving extraction of the
/// id string `.task(id:)` already composed before this task (§D7) - pulled into a pure, static
/// function so `RenderedViewBlockTaskIDComposition` can assert on it without a live SwiftUI
/// render, per this task's own "test at the id-composition/store-call level" instruction. It does
/// not change what `.task(id:)` receives.
///
/// **Already true, not red** (Task 4/5's own work, ADR §D3/§D1): `ViewBlockPassSideIDStability`
/// drives the real Coordinator pass and is a regression guard from the pass's own side,
/// complementing `Tests/ViewBlockHostStoreTests.swift`'s store-side coverage of the same
/// property - a keystroke that does not touch the fence, or an edit above it, must not disturb
/// the id's source component or the host's identity.

// MARK: - Fixtures shared by this file (each test file keeps its own copy, this repo's own
// convention - `Tests/ViewBlockCaretTests.swift`'s own header names it)

@MainActor
private func makeTextView() -> NSTextView {
    NSTextView(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
}

/// `Tests/ViewEvaluatorTests.swift`'s own `record(...)` fixture, trimmed to what R-09's click-
/// target tests need: a title and nothing else.
private func record(_ title: String, path: String? = nil) -> NoteRecord {
    NoteRecord(
        relativePath: path ?? "\(title).md",
        title: title,
        frontmatter: .empty,
        linkTargets: [],
        embedTargets: [],
        tasks: [],
        modifiedAt: .distantPast,
        byteSize: 0,
        contentHash: "-"
    )
}

private func row(_ title: String) -> ViewResult.Row {
    ViewResult.Row(record: record(title), values: [:])
}

private func result(_ titles: String...) -> ViewResult {
    let rows = titles.map(row)
    return ViewResult(groups: [ViewResult.Group(label: nil, rows: rows)], total: rows.count)
}

@MainActor
private struct Editor {
    let textView: CompletingTextView
    let coordinator: NoteTextView.Coordinator
    /// Never read for its own sake - `Tests/ViewBlockCaretTests.swift`'s own fixture's reason:
    /// it exists so `textView.undoManager` resolves through the responder chain to something.
    let window: NSWindow
}

/// `Tests/ViewBlockCaretTests.swift`'s own `editor(_:caret:)` fixture, copied rather than
/// imported on that file's own precedent, with one addition: `queries`, passed straight to
/// `NoteTextView` so a test can confirm the stub compiles and stays inert (assertion 5 below) -
/// unused by production until the coder threads it (this file's own header).
@MainActor
private func editor(_ text: String, hidesMarkup: Bool = true, queries: ViewQuerySource? = nil) -> Editor {
    let view = NoteTextView(
        text: .constant(text), theme: .emergency, noteTitles: [], tagSuggestions: [],
        hidesMarkup: hidesMarkup, onFollowLink: { _ in }, queries: queries
    )
    let coordinator = view.makeCoordinator()
    let textView = CompletingTextView(usingTextLayoutManager: true)
    textView.delegate = coordinator
    textView.isRichText = false
    textView.allowsUndo = true
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.isAutomaticTextReplacementEnabled = false
    textView.isAutomaticSpellingCorrectionEnabled = false
    textView.textContainerInset = NSSize(width: 24, height: 20)
    textView.frame = CGRect(x: 0, y: 0, width: 600, height: 800)
    textView.textContainer?.size = CGSize(width: 552, height: CGFloat.greatestFiniteMagnitude)
    coordinator.textView = textView
    textView.textContentStorage?.delegate = coordinator.decorations
    textView.textLayoutManager?.delegate = coordinator.decorations
    view.wire(textView, to: coordinator)

    let window = NSWindow(
        contentRect: textView.frame, styleMask: [.titled], backing: .buffered, defer: false
    )
    window.contentView = textView
    textView.string = text
    coordinator.applyStyling(to: textView, theme: .emergency)
    window.makeFirstResponder(textView)
    return Editor(textView: textView, coordinator: coordinator, window: window)
}

/// A closed `pergamenum-view` fence, one body line, then an ordinary paragraph -
/// `Tests/ViewBlockCaretTests.swift`'s own `ViewBlockCaretFixture.note`.
private enum Fixture {
    static let note = "prima\n```pergamenum-view\nrender: table\n```\ndopo\n"
    static let openingFenceOffset = 6
    static let bodySource = "render: table"
}

// MARK: - Live refresh: the id composition and the store call (assertion 1, R-07, R-13's third
// named case)

@MainActor
@Suite struct RenderedViewBlockTaskIDComposition {
    /// R-07: a generation bump must change the id, or `.task(id:)` never re-runs the query on a
    /// vault rescan. Pure - no view, no store, no render.
    @Test func bumpingGenerationChangesTheComposedTaskID() {
        let before = RenderedViewBlock.taskID(source: Fixture.bodySource, generation: 1, reloads: 0)
        let after = RenderedViewBlock.taskID(source: Fixture.bodySource, generation: 2, reloads: 0)
        #expect(
            before != after,
            "un generation diverso deve produrre un id diverso, o .task(id:) non rivaluta la query dopo una scansione del vault (R-07)"
        )
    }

    /// The formula itself, named component by component, so a future edit that reorders or
    /// drops one is caught here rather than only by the difference above.
    @Test func theIDIsSourcePipeGenerationPipeReloads() {
        #expect(RenderedViewBlock.taskID(source: "x", generation: 1, reloads: 3) == "x|1|3")
        #expect(RenderedViewBlock.taskID(source: "x", generation: 2, reloads: 3) == "x|2|3")
        #expect(RenderedViewBlock.taskID(source: "y", generation: 1, reloads: 3) == "y|1|3")
    }

    /// "the store pushes an updated root view carrying it": built through the very
    /// `ViewBlockHostStore.rootView(...)` `NoteTextView+ViewBlocks.swift`'s `refreshViewBlockHosts`
    /// calls, pushed through `update(_:forOrdinal:)` - the store-call half of R-13's third named
    /// case, still without a live SwiftUI render. ADR §D3's "never rebuild" is reasserted here in
    /// the queries-aware case specifically: a live refresh is a second `update` on the *same*
    /// host, never a fresh one.
    @Test func theStoreKeepsWritingTheBumpedGenerationIntoTheSameHost() {
        let store = ViewBlockHostStore()
        let textView = makeTextView()
        let host = store.host(for: 0, in: textView)

        let generationOne = ViewQuerySource(evaluate: { _ in ViewResult(groups: [], total: 0) }, generation: 1)
        store.update(
            ViewBlockHostStore.rootView(source: Fixture.bodySource, queries: generationOne, theme: .emergency),
            forOrdinal: 0
        )
        #expect(
            store.host(for: 0, in: textView) === host,
            "il primo update(_:forOrdinal:) non deve ricostruire l'host"
        )

        let generationTwo = ViewQuerySource(evaluate: { _ in ViewResult(groups: [], total: 0) }, generation: 2)
        store.update(
            ViewBlockHostStore.rootView(source: Fixture.bodySource, queries: generationTwo, theme: .emergency),
            forOrdinal: 0
        )
        #expect(
            store.host(for: 0, in: textView) === host,
            "un secondo update(_:forOrdinal:) con una generation diversa deve scrivere sullo stesso host (§D3), non ricrearlo"
        )
    }
}

// MARK: - The pass's own side: a keystroke elsewhere, and an edit above the fence (assertions 2
// and 3)

@MainActor
@Suite struct ViewBlockPassSideIDStability {
    /// A keystroke after the fence re-runs `applyStyling`/`applyViewBlocks` (every keystroke
    /// does) but must not change `DrawnViewBlock.source` - the id's only keystroke-sensitive
    /// component, `queries?.generation` and `reloads` both being independent of any edit.
    /// Already true (Task 5), asserted here as the regression guard this task's own brief asks
    /// for.
    @Test func aKeystrokeThatDoesNotTouchTheFenceDoesNotChangeItsSourceComponentOfTheID() {
        let fixture = editor(Fixture.note)
        defer { fixture.window.orderOut(nil) }

        let before = fixture.coordinator.drawnViewBlocks[Fixture.openingFenceOffset]?.source
        #expect(before == Fixture.bodySource, "premessa: il fence deve essere già disegnato prima della modifica")

        // Appends a character to "dopo", well after the fence - never touches its source.
        let end = (fixture.textView.string as NSString).length
        let insertionPoint = NSRange(location: end, length: 0)
        #expect(fixture.textView.shouldChangeText(in: insertionPoint, replacementString: "!"))
        fixture.textView.textStorage?.replaceCharacters(in: insertionPoint, with: "!")
        fixture.textView.didChangeText()

        let after = fixture.coordinator.drawnViewBlocks[Fixture.openingFenceOffset]?.source
        #expect(
            after == before,
            "una modifica che non tocca il fence ha comunque cambiato la componente 'source' dell'id"
        )
    }

    /// An edit above the fence shifts the opening paragraph's own offset - the dictionary key
    /// `drawnViewBlocks` and `apply(viewBlockHosts:)` both use - but must leave the fence's
    /// *ordinal* (still the note's first view block) and therefore its host untouched (ADR §D3),
    /// and its source-component of the id untouched too, since the fence's own body was never
    /// touched. `Tests/ViewBlockHostStoreTests.swift`'s `hostSurvivesAChangedParagraphOffsetAboveTheFence`
    /// asserts the store's own half of this by calling `host(for:in:)` directly; this asserts it
    /// from the pass's side - through the real `applyViewBlocks`/ordinal-enumeration path
    /// (Task 5), which is the thing that actually has to keep computing ordinal 0 for this fence
    /// as the note grows above it.
    @Test func anEditAboveTheFenceLeavesTheHostIdentityAndTheSourceComponentOfTheIDUnchanged() {
        let fixture = editor(Fixture.note)
        defer { fixture.window.orderOut(nil) }

        let hostBefore = fixture.coordinator.viewBlockHosts.host(for: 0, in: fixture.textView)
        let sourceBefore = fixture.coordinator.drawnViewBlocks[Fixture.openingFenceOffset]?.source
        #expect(sourceBefore == Fixture.bodySource, "premessa: il fence deve essere già disegnato prima della modifica")

        let insertedLine = "una riga nuova\n"
        let insertionPoint = NSRange(location: 0, length: 0)
        #expect(fixture.textView.shouldChangeText(in: insertionPoint, replacementString: insertedLine))
        fixture.textView.textStorage?.replaceCharacters(in: insertionPoint, with: insertedLine)
        fixture.textView.didChangeText()

        let shiftedOpening = Fixture.openingFenceOffset + (insertedLine as NSString).length
        let hostAfter = fixture.coordinator.viewBlockHosts.host(for: 0, in: fixture.textView)
        let sourceAfter = fixture.coordinator.drawnViewBlocks[shiftedOpening]?.source

        #expect(
            hostAfter === hostBefore,
            "un edit sopra il fence ha ricostruito l'host invece di riutilizzare quello indicizzato per ordinale (§D3)"
        )
        #expect(
            sourceAfter == sourceBefore,
            "un edit sopra il fence, che non tocca il suo corpo, ha comunque cambiato la componente 'source' dell'id"
        )
    }
}

// MARK: - R-09: a click target carrying the row's title, only when `onOpenNote` is set
// (assertion 4, 8 total)

/// Every "non-nil" assertion is red against the stub above (`openAction(for:)` always returns
/// `nil`): the coder both fills it in and calls it from the row's own title in `body`. Every
/// "nil" assertion is already true with the stub, and must stay true - it is what keeps R-10/R-11
/// (transclusion, export - neither passes `onOpenNote`) true by construction.
@MainActor
@Suite struct ViewRowRendererClickTargets {
    @Test func aTableRowExposesAClickTargetCarryingItsTitleWhenOnOpenNoteIsSet() throws {
        let block = try ViewBlock.parse("render: table")
        var opened: String?
        let renderer = ViewTableRenderer(block: block, result: result("Vibrofer"), onOpenNote: { opened = $0 })

        let action = try #require(
            renderer.openAction(for: row("Vibrofer")),
            "con onOpenNote impostato la riga della tabella non espone un target di click (R-09)"
        )
        action()
        #expect(opened == "Vibrofer")
    }

    @Test func aTableRowExposesNoClickTargetWhenOnOpenNoteIsNil() throws {
        let block = try ViewBlock.parse("render: table")
        let renderer = ViewTableRenderer(block: block, result: result("Vibrofer"))

        #expect(
            renderer.openAction(for: row("Vibrofer")) == nil,
            "senza onOpenNote la riga della tabella non deve avere un target di click (R-10/R-11)"
        )
    }

    @Test func aListLineExposesAClickTargetCarryingItsTitleWhenOnOpenNoteIsSet() throws {
        let block = try ViewBlock.parse("render: list")
        var opened: String?
        let renderer = ViewListRenderer(block: block, result: result("Ceramiche"), onOpenNote: { opened = $0 })

        let action = try #require(
            renderer.openAction(for: row("Ceramiche")),
            "con onOpenNote impostato la riga della lista non espone un target di click (R-09)"
        )
        action()
        #expect(opened == "Ceramiche")
    }

    @Test func aListLineExposesNoClickTargetWhenOnOpenNoteIsNil() throws {
        let block = try ViewBlock.parse("render: list")
        let renderer = ViewListRenderer(block: block, result: result("Ceramiche"))

        #expect(
            renderer.openAction(for: row("Ceramiche")) == nil,
            "senza onOpenNote la riga della lista non deve avere un target di click (R-10/R-11)"
        )
    }

    @Test func aGalleryItemExposesAClickTargetCarryingItsTitleWhenOnOpenNoteIsSet() throws {
        var opened: String?
        let renderer = ViewGalleryRenderer(result: result("Presse"), onOpenNote: { opened = $0 })

        let action = try #require(
            renderer.openAction(for: row("Presse")),
            "con onOpenNote impostato la card della gallery non espone un target di click (R-09)"
        )
        action()
        #expect(opened == "Presse")
    }

    @Test func aGalleryItemExposesNoClickTargetWhenOnOpenNoteIsNil() {
        let renderer = ViewGalleryRenderer(result: result("Presse"))

        #expect(
            renderer.openAction(for: row("Presse")) == nil,
            "senza onOpenNote la card della gallery non deve avere un target di click (R-10/R-11)"
        )
    }

    @Test func aCalendarEntryExposesAClickTargetCarryingItsTitleWhenOnOpenNoteIsSet() throws {
        let block = try ViewBlock.parse("render: calendar")
        var opened: String?
        let renderer = ViewCalendarRenderer(block: block, result: result("Letture"), onOpenNote: { opened = $0 })

        let action = try #require(
            renderer.openAction(for: row("Letture")),
            "con onOpenNote impostato la voce del calendario non espone un target di click (R-09)"
        )
        action()
        #expect(opened == "Letture")
    }

    @Test func aCalendarEntryExposesNoClickTargetWhenOnOpenNoteIsNil() throws {
        let block = try ViewBlock.parse("render: calendar")
        let renderer = ViewCalendarRenderer(block: block, result: result("Letture"))

        #expect(
            renderer.openAction(for: row("Letture")) == nil,
            "senza onOpenNote la voce del calendario non deve avere un target di click (R-10/R-11)"
        )
    }
}

// MARK: - The safe default: no `queries` at all (assertion 5)

@MainActor
@Suite struct NoteTextViewSafeDefaultWithNoQueries {
    /// `DiaryView`/`TodayView` and every test built before this task never pass `queries` -
    /// the property must default to `nil` and leave every existing caller's behaviour
    /// unchanged. With `hidesMarkup` also left at `NoteTextView`'s own struct default (`false`,
    /// what a caller that has opted into nothing at all gets), D12's escape hatch already
    /// governs: no marker, no hidden lines, no host - the fence stays its own raw source on
    /// screen, `queries` never entering the question.
    @Test func withNoQueriesAndHidesMarkupAtItsOwnDefaultTheFenceStaysSourceAndNoHostIsCreated() {
        let view = NoteTextView(
            text: .constant(Fixture.note), theme: .emergency, noteTitles: [], tagSuggestions: [],
            onFollowLink: { _ in }
        )
        #expect(view.queries == nil, "il default di NoteTextView.queries deve restare nil")
        #expect(view.hidesMarkup == false, "premessa: il default di NoteTextView.hidesMarkup deve restare false")

        let coordinator = view.makeCoordinator()
        let textView = CompletingTextView(usingTextLayoutManager: true)
        textView.string = Fixture.note
        var markers: [Int: [HiddenMarker]] = [:]

        coordinator.applyViewBlocks(
            to: textView, runs: [NSRange(location: 0, length: (Fixture.note as NSString).length)],
            markers: &markers
        )

        #expect(markers.isEmpty, "senza hidesMarkup è stato comunque registrato un marcatore")
        #expect(coordinator.drawnViewBlocks.isEmpty, "senza hidesMarkup è stato comunque creato un host")
    }

    /// The other configuration a real vault can actually hand `DiaryView`/`TodayView`
    /// (`VaultSettings.hidesMarkup` is `true` by default, ADR-0028) with `queries` still nil,
    /// since neither view passes it (this task's own hard constraint - see this file's header
    /// and `Sources/Features/Diary/DiaryView.swift`/`Sources/Features/Today/TodayView.swift`,
    /// both read, neither edited). Here D1/D6's attachment mechanism runs independently of
    /// `queries` (it is not consulted before an attachment forms) - the host still forms, and
    /// what keeps this safe is `RenderedViewBlock.content`'s own pre-existing
    /// `if queries == nil` branch ("Nessun vault dietro questa vista"), not the absence of a
    /// host. Asserted here only as "no crash, a real host resolves" - the drawn text itself is
    /// `RenderedViewBlock`'s own concern and is not new to this task.
    @Test func withHidesMarkupOnAndNoQueriesAHostStillFormsWithoutCrashing() {
        let fixture = editor(Fixture.note, hidesMarkup: true, queries: nil)
        defer { fixture.window.orderOut(nil) }

        #expect(fixture.coordinator.drawnViewBlocks[Fixture.openingFenceOffset]?.source == Fixture.bodySource)
        _ = fixture.coordinator.viewBlockHosts.host(for: 0, in: fixture.textView)
    }
}

// MARK: - Producer and consumer joined end to end (bonus finding, PG-099 follow-up)

/// `Tests/ViewBlockRenderingTests.swift`'s `ViewBlockAttachmentSubstitution` suite always
/// hand-injects `NSView()` as the host and a marker built by hand - it never runs a real
/// `applyStyling` pass and never puts a real `NSHostingView<AnyView>` through the attachment's
/// own `as? NSHostingView<AnyView>` cast (`EditorDecorationDelegate+ViewBlockRendering.swift`).
/// `ViewBlockQuerySourceTests`'s own suites above drive the real pass but only assert on
/// `drawnViewBlocks`, never on the substituted paragraph. Neither half alone would have caught
/// a regression at the seam between "the pass recognises and registers a fence" and "the
/// delegate substitutes an attachment for what got registered" - which is exactly the seam this
/// session's investigation crossed. This suite runs the real pipeline end to end and inspects
/// the actual substituted paragraph the layout would draw.
@MainActor
@Suite struct ViewBlockEndToEndSubstitution {
    @Test func aRealStylingPassOnAValidFenceSubstitutesARealHostedAttachment() {
        let fixture = editor(Fixture.note)
        defer { fixture.window.orderOut(nil) }

        let host = fixture.coordinator.viewBlockHosts.host(for: 0, in: fixture.textView)
        #expect(host.rootView is AnyView, "il pass reale non ha prodotto un host reale")

        let storage = fixture.textView.textContentStorage!
        let range = (Fixture.note as NSString).paragraphRange(
            for: NSRange(location: Fixture.openingFenceOffset, length: 0)
        )
        let paragraph = fixture.coordinator.decorations.textContentStorage(storage, textParagraphWith: range)
        #expect(paragraph != nil, "il pass reale non sostituisce l'attachment")
        guard let attachment = paragraph?.attributedString.attribute(.attachment, at: 0, effectiveRange: nil)
                as? ViewBlockAttachment
        else {
            Issue.record("l'offset 0 non porta un ViewBlockAttachment dopo un pass reale")
            return
        }
        #expect(attachment.hostView != nil, "il cast a NSHostingView<AnyView> fallisce su un host reale")
    }
}
