import AppKit
import SwiftUI
import Testing
@testable import Pergamenum

/// ADR-0033 §D16, probes 1-3 (plan `2026-09-06-pg-099-views-board-renderer-orphaned-by`,
/// Task 3). **This is a gate, not a checkpoint** - Tasks 4 and 8 are not planned in detail
/// until it has an answer, and a negative on probe 2 changes Task 8's shape rather than
/// being worked around inside it.
///
/// The smallest real thing: an `NSTextAttachment` whose provider's `loadView` assigns a real
/// `NSHostingView` over a throwaway SwiftUI view holding a `@State` counter, a `Button`, and
/// a two-column `.draggable`/`.dropDestination` pair - inside a real `CompletingTextView`
/// inside a real `NSWindow`. No fence grammar behind it: the attachment is inserted directly
/// into the text storage, the same "fixed trigger word with no grammar behind it" shape
/// ADR-0029's own Step 4.5 probe used (`git show c2f24e7` -
/// `EditorDecorationDelegate+TableRendering.swift`'s own header comment) - what is under test
/// here is the attachment/hosting mechanism itself, not fence detection (Task 1, already
/// merged) or the substitution pass (Task 5).
///
/// **The window is genuinely ordered front here**, unlike every other offscreen fixture in
/// this suite. `Tests/TableRenderingTests.swift`'s own `TableGridAccessibility` measured that
/// TextKit 2 never mounts an attachment's view at all - `loadView()` is never called, the
/// view's `superview` stays `nil` - unless the window has a non-empty visible rect, which an
/// unordered window never has. Every probe below depends on the view actually mounting, so
/// there is no offscreen substitute.
///
/// **What each probe could and could not determine here**, written down per ADR-0010's
/// standard (the plan asks for this in `PROJECT_BRIEF.md`; this file's own header is the
/// source the report is drawn from):
/// - **Probe 1 (size, click, state survival): only the non-click half is automated below** -
///   size and mount, and that the same hosting-view instance survives a keystroke typed
///   elsewhere. See the amendment right below this list for why the click itself, and
///   therefore the counter's survival *across* a click, could not be dispatched.
/// - **Probe 2 (drag lift/highlight/drop, no text-selection interception): only the
///   *static* precondition is automated** - that a hit-test at a point inside the hosted
///   view's drag-source region resolves to a descendant of the hosting view, never to the
///   enclosing `CompletingTextView` itself, which is what "the text view does not treat the
///   gesture as a text-selection drag" requires as a precondition. The *dynamic* half - an
///   actual lift/highlight/drop - is **not** attempted here: `NSView.beginDraggingSession`
///   is documented to block synchronously until the drag ends, and with no real pointer
///   driving a `mouseUp` into the queue, calling it from a unit test risks hanging the test
///   process rather than answering the question. This is the same class of blind spot
///   CLAUDE.md already documents for TextKit 2 attachment interaction, and ADR-0029 §D16's
///   own probe 2 was itself resolved by a hand check, not an automated test - Task 10's hand
///   check (R-14) is where the dynamic half is actually confirmed, same as it already was for
///   the board's drag-to-write.
/// - **Probe 3 (first responder handoff): only the pre-click state is automated below** - see
///   the amendment right below this list for why the click itself could not be dispatched.
///
/// **Amendment, found while actually running this file, not while writing it**: a synthetic
/// `NSEvent.leftMouseDown`/`leftMouseUp` dispatched *directly* to a mounted `NSHostingView`
/// (`hosting.mouseDown(with:)`) hangs the test process indefinitely in this sandboxed agent
/// environment - it never returns, unlike every other step in `Fixture.present()`. Bisected by
/// hand with a throwaway step-by-step diagnostic (`Tests/DiagProbeStepsTests.swift`, deleted
/// after use): building the hosting view, the attachment, the text storage, the text view and
/// the window, ordering the window front, `makeFirstResponder`, `ensureLayout`, mounting the
/// view via `loadView()`, and a 0.1s `RunLoop` pump all completed in 0.12s total, twice,
/// confirmed via `ps` leaving no stray process either time. Only the line calling
/// `hosting.mouseDown(with:)` never printed its own "returned" marker even after a 180s bound,
/// confirmed twice. This generalizes the risk already named above for probe 2's dynamic half
/// (`NSView.beginDraggingSession` blocking synchronously) to plain clicks too: SwiftUI's own
/// gesture/event-tracking machinery inside `NSHostingView.mouseDown(with:)` appears to block
/// synchronously waiting for a subsequent event to arrive through a real event queue, which a
/// directly-dispatched synthetic event never satisfies. Per the task's own constraint ("if a
/// probe fails, report clearly, do not attempt a workaround, do not continue past it"), the two
/// affected tests below are marked `.disabled(...)` with this exact finding as the reason,
/// rather than deleted (the evidence) or left to hang every future `.claude/test-cmd` run (the
/// Stop hook that runs the whole suite at the end of every turn, CLAUDE.md's own working
/// agreement) - neither silently green nor silently absent, visibly skipped with why.
///
/// **Second amendment, found running the full `PergamenumTests` target (not this file alone)**:
/// the non-click half of probe 1 (real window ordering, `makeFirstResponder`, `ensureLayout`,
/// mounting via `loadView()` - no synthetic event involved) was mid-flight when the test-host
/// process died and `xcodebuild` printed "Restarting after unexpected exit, crash, or test
/// timeout" partway through the ~826-test full run. Read in isolation this looks like evidence
/// against this file; read against the rest of that same log it is not; the same restart
/// message appears twice more in the identical run, once during `EntryComposerTests`'
/// `cancellingTheComposerWritesNothing()` and once during a note-tabs test
/// (`theRecentListFollowsARenameAndDropsATrashedNote()`) - two suites with nothing to do with
/// this chain, neither ordering a window, both pre-existing. All three restarts share one
/// shape: a test reported `started` and never reported `passed`/`failed` before the identical
/// four-line app-launch banner reappeared under a new PID. This reads as a pre-existing,
/// environment-wide test-host instability in this sandboxed agent (a handful of restarts over
/// a long run, unrelated to what is actually executing), not a defect this file introduces -
/// `xcodebuild`'s own retry-and-resume recovered from all three automatically and the run
/// still finished with the exact, correct final count this chain's own math predicts (826
/// tests, 5 issues, all traced to `Tests/ViewBlockRenderingTests.swift`'s three intentionally
/// red assertions). Left enabled rather than disabled for exactly that reason: unlike the
/// mouseDown hang above, this class of interruption self-recovers under the harness's own
/// retry, the same way it already does for two unrelated suites nobody has flagged.
///
/// Left in place, not deleted: not redundant with `Tests/ViewBlockRenderingTests.swift` (that
/// file is about the delegate's hidden-line bookkeeping, this one is about the SwiftUI
/// hosting mechanism itself), and Task 4 is the plan's own named point for cleaning it up
/// once `ViewBlockAttachment`/`ViewBlockHostStore` replace it.
@MainActor
private struct ProbeContentView: View {
    @State private var count = 0
    let onCountChange: (Int) -> Void
    let onDrop: (String) -> Void

    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            Button("Count: \(count)") { count += 1 }
                .buttonStyle(.plain)
                .frame(width: 300, height: 60)
                .contentShape(Rectangle())
                .background(Color.blue.opacity(0.2))
            HStack(spacing: 0) {
                Text("Drag me")
                    .frame(width: 150, height: 60)
                    .contentShape(Rectangle())
                    .background(Color.orange.opacity(0.3))
                    .draggable("probe-card")
                Text(isTargeted ? "Drop here" : "Drop zone")
                    .frame(width: 150, height: 60)
                    .contentShape(Rectangle())
                    .background(isTargeted ? Color.green.opacity(0.5) : Color.gray.opacity(0.2))
                    .dropDestination(for: String.self) { items, _ in
                        guard let first = items.first else { return false }
                        onDrop(first)
                        return true
                    } isTargeted: { targeted in
                        isTargeted = targeted
                    }
            }
        }
        .frame(width: 300, height: 120)
        .onChange(of: count) { _, new in onCountChange(new) }
    }
}

/// The probe's own attachment, the `TableAttachment`/`TableAttachmentViewProvider` shape
/// (`Sources/Features/Editor/TableAttachment.swift`) with a fixed size rather than one read
/// off a grid's own cells (R-06: "reserves a fixed height").
/// Not `@MainActor` - `TableAttachment.swift`'s own precedent (its `gridView: TableGridView?`
/// crosses the same way): `NSTextAttachmentViewProvider`'s own methods are nonisolated, so an
/// actor-isolated attachment cannot be read from `loadView()`/`attachmentBounds(...)` below.
private final class ProbeAttachment: NSTextAttachment {
    static let fixedSize = CGSize(width: 300, height: 120)
    var hostingView: NSHostingView<ProbeContentView>?

    override func viewProvider(
        for parentView: NSView?, location: any NSTextLocation, textContainer: NSTextContainer?
    ) -> NSTextAttachmentViewProvider? {
        let provider = ProbeAttachmentViewProvider(
            textAttachment: self, parentView: parentView,
            textLayoutManager: textContainer?.textLayoutManager, location: location
        )
        provider.hostingView = hostingView
        provider.tracksTextAttachmentViewBounds = true
        return provider
    }
}

private final class ProbeAttachmentViewProvider: NSTextAttachmentViewProvider {
    var hostingView: NSHostingView<ProbeContentView>?

    override func loadView() {
        view = hostingView
    }

    override func attachmentBounds(
        for attributes: [NSAttributedString.Key: Any], location: any NSTextLocation,
        textContainer: NSTextContainer?, proposedLineFragment: CGRect, position: CGPoint
    ) -> CGRect {
        CGRect(origin: .zero, size: ProbeAttachment.fixedSize)
    }
}

@MainActor
private final class Fixture {
    let textView: CompletingTextView
    let window: NSWindow
    let hosting: NSHostingView<ProbeContentView>
    let attachmentOffset = 6

    init(onCountChange: @escaping (Int) -> Void, onDrop: @escaping (String) -> Void) {
        let hosting = NSHostingView(rootView: ProbeContentView(onCountChange: onCountChange, onDrop: onDrop))
        hosting.frame = CGRect(origin: .zero, size: ProbeAttachment.fixedSize)
        self.hosting = hosting

        let attachment = ProbeAttachment()
        attachment.hostingView = hosting

        let text = NSMutableAttributedString(
            string: "prima \u{FFFC} dopo", attributes: [.font: NSFont.systemFont(ofSize: 13)]
        )
        text.addAttribute(.attachment, value: attachment, range: NSRange(location: attachmentOffset, length: 1))

        let textView = CompletingTextView(usingTextLayoutManager: true)
        textView.frame = CGRect(x: 0, y: 0, width: 600, height: 400)
        textView.textContainer?.size = CGSize(width: 552, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 24, height: 20)
        textView.textStorage?.setAttributedString(text)
        self.textView = textView

        let window = NSWindow(
            contentRect: textView.frame, styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentView = textView
        self.window = window
    }

    /// Orders the window on screen (required, see the file header) and pumps the run loop
    /// briefly so TextKit 2's viewport layout controller and SwiftUI's own layout both settle
    /// before anything is asserted.
    func present() {
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(textView)
        textView.textLayoutManager?.ensureLayout(for: textView.textLayoutManager!.documentRange)
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }

    func teardown() {
        window.orderOut(nil)
    }
}

@MainActor
@Suite struct ViewBlockAttachmentProbe {
    /// **Probe 1, automatable half**: the host draws at the size `attachmentBounds` returned,
    /// and the same hosting-view *instance* survives a keystroke typed elsewhere in the note
    /// (never torn down and rebuilt) - neither assertion dispatches a click, so neither risks
    /// the hang documented in the file header.
    @Test func probe1HostDrawsAtAttachmentBoundsSizeAndSurvivesAKeystrokeElsewhere() throws {
        let fixture = Fixture(onCountChange: { _ in }, onDrop: { _ in })
        defer { fixture.teardown() }
        fixture.present()

        // Mounted at all, and at the size `attachmentBounds` returned - the precondition
        // every other assertion in this probe depends on.
        _ = try #require(fixture.hosting.superview, "l'hosting view non è mai stata montata da TextKit 2")
        #expect(
            fixture.hosting.isDescendant(of: fixture.textView),
            "l'hosting view non è un discendente della text view"
        )
        #expect(
            fixture.hosting.frame.size == ProbeAttachment.fixedSize,
            "la dimensione disegnata (\(fixture.hosting.frame.size)) non è quella restituita da attachmentBounds"
        )

        // A keystroke typed elsewhere in the note - a real mutation of the text storage
        // at an offset before the attachment, leaving the attachment's own character (and
        // therefore the same `ProbeAttachment`/`NSHostingView` instance) untouched.
        fixture.textView.textStorage?.replaceCharacters(in: NSRange(location: 0, length: 0), with: "X")
        fixture.textView.textLayoutManager?.ensureLayout(for: fixture.textView.textLayoutManager!.documentRange)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        #expect(fixture.hosting.superview != nil, "l'hosting view è stata smontata da una modifica altrove nel testo")
    }

    /// **Probe 1, click-dependent half - disabled, not deleted.** The button's actual click
    /// response and whether `@State` survives across that click cannot be checked: dispatching
    /// a synthetic `mouseDown`/`mouseUp` directly to the mounted `NSHostingView` hangs the test
    /// process indefinitely in this environment (see the file header's amendment). Left in the
    /// suite, disabled with the finding as its reason, rather than deleted, so the gap is
    /// visible in every test report rather than silently absent.
    @Test(.disabled("""
    hosting.mouseDown(with:) dispatched directly to a mounted NSHostingView hangs the test \
    process indefinitely in this sandboxed environment (confirmed twice via a step-by-step \
    bisection, 180s bound, no stray process left behind either time) - see this file's header \
    comment. Recommend a manual hand check per ADR-0029 §D16's own precedent for this class of \
    SwiftUI-in-attachment interaction.
    """))
    func probe1ButtonClickResponseAndStateSurvivalAcrossAClick() {}

    /// **Probe 2, static half only** - see the file header for why the dynamic half (an
    /// actual lift/highlight/drop) is not attempted here. What this asserts: a hit-test at a
    /// point inside the hosted view's drag-source region resolves to a descendant of the
    /// hosting view, never to the enclosing `CompletingTextView` itself - the precondition
    /// "the text view does not treat the gesture as a text-selection drag" requires before
    /// any drag session could even begin.
    @Test func probe2StaticHitTestRoutesToTheHostedViewNotToTheTextViewsOwnSelection() throws {
        let fixture = Fixture(onCountChange: { _ in }, onDrop: { _ in })
        defer { fixture.teardown() }
        fixture.present()
        _ = try #require(fixture.hosting.superview, "l'hosting view non è mai stata montata da TextKit 2")

        // The drag-source card sits in the HStack below the button - left half, bottom half.
        let dragSourcePoint = CGPoint(x: 75, y: fixture.hosting.isFlipped ? 90 : 30)
        let windowPoint = fixture.hosting.convert(dragSourcePoint, to: nil)
        let contentPoint = fixture.window.contentView?.convert(windowPoint, from: nil) ?? windowPoint

        let hit = fixture.window.contentView?.hitTest(contentPoint)
        let hitView = try #require(hit, "l'hit-test non ha trovato alcuna view al punto della sorgente del drag")
        #expect(hitView !== fixture.textView, "il click sulla sorgente del drag ha colpito la text view stessa, non la view ospitata")
        #expect(
            hitView.isDescendant(of: fixture.hosting),
            "la view colpita non è un discendente dell'hosting view - il testo intercetterebbe il gesto come selezione"
        )
    }

    /// **Probe 3, pre-click half**: the text view genuinely holds first responder once the
    /// host is mounted, before any click - the state the click-dependent half below would have
    /// started from.
    @Test func probe3TextViewIsFirstResponderBeforeAnyClickOnTheHost() throws {
        let fixture = Fixture(onCountChange: { _ in }, onDrop: { _ in })
        defer { fixture.teardown() }
        fixture.present()
        _ = try #require(fixture.hosting.superview, "l'hosting view non è mai stata montata da TextKit 2")

        #expect(fixture.window.firstResponder === fixture.textView, "la text view non è il first responder iniziale")
    }

    /// **Probe 3, click-dependent half - disabled, not deleted.** Whether first responder
    /// stays sane through an actual click on the host cannot be checked for the same reason as
    /// probe 1's click-dependent half: dispatching a synthetic `mouseDown`/`mouseUp` directly
    /// to the mounted `NSHostingView` hangs the test process indefinitely here (see the file
    /// header's amendment).
    @Test(.disabled("""
    hosting.mouseDown(with:) dispatched directly to a mounted NSHostingView hangs the test \
    process indefinitely in this sandboxed environment - see this file's header comment and \
    probe1ButtonClickResponseAndStateSurvivalAcrossAClick()'s own disabled reason. Recommend a \
    manual hand check per ADR-0029 §D16's own precedent.
    """))
    func probe3FirstResponderNeverEndsUpNowhereAfterAClickOnTheHostAndBackInTheNote() {}
}
