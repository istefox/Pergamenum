import AppKit
import SwiftUI
import Testing
@testable import Pergamenum

/// ADR-0033 §D3, §D8 (plan `2026-09-06-pg-099-views-board-renderer-orphaned-by`, Task 4):
/// `ViewBlockHostStore` vends the one `NSHostingView` a `pergamenum-view` fence keeps across
/// every styling pass, keyed by the fence's **ordinal**, not its paragraph offset - the
/// deliberate divergence from `TableGridStore` (ADR-0029 §D6) that keeps `RenderedViewBlock`'s
/// query from re-running per keystroke typed above the fence (ADR-0009 §D7). `ViewBlockAttachment`
/// reserves a height at the proposed line fragment's own width, adaptive to the host's measured
/// content and capped at `maximumHeight` (R-06, ADR-0035 amending §D8).
///
/// `ViewBlockHostStore` (`Sources/Features/Editor/ViewBlockHostStore.swift`) and
/// `ViewBlockAttachment` (`Sources/Features/Editor/ViewBlockAttachment.swift`) are **TESTER
/// STUBS** for this task - see each type's own header comment. `ViewBlockHostStore.host(for:in:)`
/// and `.hosts(for:in:)` neither cache nor prune, so every identity/pruning assertion below is
/// red until Task 4's coder fills them in (C6: the one behavior that must never be relaxed).
/// The "two identical fences get two distinct hosts" assertion and every `attachmentBounds`
/// assertion are already true against the stub - the former is a property of the ordinal key
/// space, not of caching; the latter is pure, content-independent geometry written for real in
/// the stub file (see its header) - and both must stay true once Task 4's coder finishes it.

@MainActor
private func makeTextView() -> NSTextView {
    NSTextView(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
}

/// An `NSTextLocation` for a direct call to `attachmentBounds(for:location:textContainer:…)`
/// made outside a real layout pass, matching `EmbedDrawingTests.anyTextLocation()`'s own
/// idiom - ADR §D8's formula never reads `location` at all, so what this answers is never
/// asserted on; it exists only because the SDK's signature requires one.
@MainActor
private func anyTextLocation() -> any NSTextLocation {
    let storage = NSTextContentStorage()
    storage.textStorage?.setAttributedString(NSAttributedString(string: "x"))
    return storage.documentRange.location
}

@MainActor
@Suite struct ViewBlockHostStoreTests {
    /// **Red against the stub.** ADR §D3: the same host instance must come back for the same
    /// ordinal across calls, or a fresh `NSHostingView` per styling pass loses SwiftUI's own
    /// diffing and re-runs `RenderedViewBlock`'s `.task(id:)` from scratch every time.
    /// Asserted by identity (`===`), not equality - two empty `NSHostingView`s are never `==`
    /// but that is not what this behavior is about.
    @Test func sameOrdinalReturnsTheSameHostInstanceAcrossCalls() {
        let store = ViewBlockHostStore()
        let textView = makeTextView()

        let first = store.host(for: 0, in: textView)
        let second = store.host(for: 0, in: textView)

        #expect(first === second, "lo stesso ordinale deve restituire la stessa istanza di host tra due chiamate")
    }

    /// A height written on the first call's returned instance must still be readable through
    /// the second call's returned instance - not just the same object identity, but the same
    /// `ViewBlockHeightBox`, since that box is what makes a measurement survive across styling
    /// passes (ADR-0035).
    @Test func measuredHeightPersistsAcrossRepeatedLookupsOfTheSameOrdinal() {
        let store = ViewBlockHostStore()
        let textView = makeTextView()

        let first = store.host(for: 0, in: textView)
        first.measuredHeight.height = 123

        let second = store.host(for: 0, in: textView)

        #expect(
            second.measuredHeight.height == 123,
            "l'altezza misurata deve sopravvivere a un lookup ripetuto dello stesso ordinale"
        )
    }

    /// **Red against the stub, and the assertion C6 says must never be relaxed.** Asking for
    /// ordinal 0, then asking again after the note gained a line above the fence, must still
    /// return the same instance - the fence is still the note's *first* view block, so its
    /// ordinal has not moved, even though a paragraph-offset key (`TableGridStore`'s own key
    /// space) would have shifted. This is the assertion that distinguishes this store from
    /// `TableGridStore`, which drops and rebuilds a grid on exactly this kind of edit.
    @Test func hostSurvivesAChangedParagraphOffsetAboveTheFence() {
        let store = ViewBlockHostStore()
        let textView = makeTextView()
        textView.textStorage?.setAttributedString(
            NSAttributedString(string: "```pergamenum-view\nrender: table\n```")
        )

        let before = store.host(for: 0, in: textView)

        // The note gains a line above the fence - a real mutation of the text storage that
        // would shift a paragraph-OFFSET key but leaves the fence's ORDINAL (still the note's
        // first view block) unchanged.
        textView.textStorage?.insert(NSAttributedString(string: "una riga nuova\n"), at: 0)

        let after = store.host(for: 0, in: textView)

        #expect(
            before === after,
            "l'host deve sopravvivere a un edit sopra il fence, essendo indicizzato per ordinale e non per offset (C6)"
        )
    }

    /// **Red against the stub.** `hosts(for:in:)` must prune: an ordinal absent from the array
    /// is dropped from what it returns, and a note that loses a fence does not accumulate a
    /// host forever.
    @Test func hostsForOrdinalsPrunesAnOrdinalThatDropsOutOfTheArray() {
        let store = ViewBlockHostStore()
        let textView = makeTextView()

        let firstPass = store.hosts(for: [0, 1], in: textView)
        #expect(Set(firstPass.keys) == Set([0, 1]))

        // The note loses its second view block - only ordinal 0 is asked for now.
        let secondPass = store.hosts(for: [0], in: textView)

        #expect(
            Set(secondPass.keys) == Set([0]),
            "l'ordinale 1, assente dal secondo passaggio, deve essere scartato, non accumulato"
        )
        #expect(secondPass[1] == nil)
    }

    /// **Already true against the stub, and must stay true.** ADR §D3 explicitly rejects a
    /// source-text key: two fences with byte-identical bodies still get two distinct hosts
    /// because they sit at different ordinals - an `NSView` has exactly one superview, so a
    /// host shared between two spots in the note would be a broken layout, not a cosmetic
    /// collision. This is a property of the key space (an `Int` ordinal, never the fence's
    /// text), not of caching, so it holds even against a stub that caches nothing.
    @Test func twoIdenticalFencesAtDifferentOrdinalsGetTwoDistinctHosts() {
        let store = ViewBlockHostStore()
        let textView = makeTextView()

        let first = store.host(for: 0, in: textView)
        let second = store.host(for: 1, in: textView)

        #expect(first !== second, "due fence identici a ordinali diversi devono ricevere due host distinti")
    }
}

@MainActor
private func makeHost(measuredHeight height: CGFloat?) -> ViewBlockHostView {
    let host = ViewBlockHostView(rootView: AnyView(EmptyView()))
    host.measuredHeight.height = height
    return host
}

@MainActor
@Suite struct ViewBlockAttachmentBoundsTests {
    /// A host with no measurement yet (`measuredHeight.height == nil`) reserves
    /// `unmeasuredHeight` - the placeholder chosen to avoid a visible collapse once the real,
    /// usually smaller, measurement arrives (ADR-0035).
    @Test func unmeasuredHostReservesThePlaceholderHeight() throws {
        let location = anyTextLocation()
        let attachment = ViewBlockAttachment()
        attachment.hostView = makeHost(measuredHeight: nil)
        let provider = try #require(attachment.viewProvider(for: nil, location: location, textContainer: nil))

        let bounds = provider.attachmentBounds(
            for: [:], location: location, textContainer: nil,
            proposedLineFragment: CGRect(x: 0, y: 0, width: 300, height: 1), position: .zero
        )

        #expect(
            bounds.size.height == ViewBlockAttachment.unmeasuredHeight,
            "un host senza misura deve riservare l'altezza placeholder"
        )
    }

    /// A measurement below the cap is reserved as-is - the whole point of the adaptive height
    /// (ADR-0035): a fence with little content no longer reserves the old fixed 320pt.
    @Test func hostMeasuredBelowTheCapReservesItsOwnHeight() throws {
        let location = anyTextLocation()
        let attachment = ViewBlockAttachment()
        attachment.hostView = makeHost(measuredHeight: 90)
        let provider = try #require(attachment.viewProvider(for: nil, location: location, textContainer: nil))

        let bounds = provider.attachmentBounds(
            for: [:], location: location, textContainer: nil,
            proposedLineFragment: CGRect(x: 0, y: 0, width: 300, height: 1), position: .zero
        )

        #expect(bounds.size.height == 90, "una misura sotto il tetto deve essere riservata così com'è")
    }

    /// A measurement above the cap clamps to `maximumHeight` - R-06's original guarantee, now a
    /// ceiling rather than the only height: a forty-card board still scrolls internally past the
    /// cap instead of pushing the rest of the note down.
    @Test func hostMeasuredAboveTheCapClampsToTheMaximum() throws {
        let location = anyTextLocation()
        let attachment = ViewBlockAttachment()
        attachment.hostView = makeHost(measuredHeight: 5_000)
        let provider = try #require(attachment.viewProvider(for: nil, location: location, textContainer: nil))

        let bounds = provider.attachmentBounds(
            for: [:], location: location, textContainer: nil,
            proposedLineFragment: CGRect(x: 0, y: 0, width: 300, height: 1), position: .zero
        )

        #expect(
            bounds.size.height == ViewBlockAttachment.maximumHeight,
            "una misura enorme deve restare limitata al tetto massimo"
        )
    }

    /// A measurement below the floor does not collapse the block's paragraph to nothing.
    @Test func hostMeasuredBelowTheFloorClampsToTheMinimum() throws {
        let location = anyTextLocation()
        let attachment = ViewBlockAttachment()
        attachment.hostView = makeHost(measuredHeight: 2)
        let provider = try #require(attachment.viewProvider(for: nil, location: location, textContainer: nil))

        let bounds = provider.attachmentBounds(
            for: [:], location: location, textContainer: nil,
            proposedLineFragment: CGRect(x: 0, y: 0, width: 300, height: 1), position: .zero
        )

        #expect(
            bounds.size.height == ViewBlockAttachment.minimumHeight,
            "una misura sotto il pavimento non deve azzerare l'altezza riservata"
        )
    }

    /// The width still comes from `proposedLineFragment.width` regardless of the measured
    /// height - width and height are independent, only the height became adaptive.
    @Test func widthStillComesFromTheProposedLineFragmentIndependentOfHeight() throws {
        let location = anyTextLocation()
        let attachment = ViewBlockAttachment()
        attachment.hostView = makeHost(measuredHeight: 90)
        let provider = try #require(attachment.viewProvider(for: nil, location: location, textContainer: nil))

        let narrowBounds = provider.attachmentBounds(
            for: [:], location: location, textContainer: nil,
            proposedLineFragment: CGRect(x: 0, y: 0, width: 300, height: 1), position: .zero
        )
        #expect(narrowBounds.size == CGSize(width: 300, height: 90))

        let wideBounds = provider.attachmentBounds(
            for: [:], location: location, textContainer: nil,
            proposedLineFragment: CGRect(x: 0, y: 0, width: 700, height: 1), position: .zero
        )
        #expect(wideBounds.size == CGSize(width: 700, height: 90))
        #expect(
            wideBounds.size.height == narrowBounds.size.height,
            "l'altezza riservata non dipende dalla larghezza proposta"
        )
    }

    /// A `nil` `hostView` (the failed-cast fallback in `EditorDecorationDelegate` - the cast
    /// still draws an empty attachment rather than refusing the substitution) reserves the same
    /// placeholder height as an unmeasured host.
    @Test func nilHostViewReservesThePlaceholderHeight() throws {
        let location = anyTextLocation()
        let attachment = ViewBlockAttachment()
        attachment.hostView = nil
        let provider = try #require(attachment.viewProvider(for: nil, location: location, textContainer: nil))

        let bounds = provider.attachmentBounds(
            for: [:], location: location, textContainer: nil,
            proposedLineFragment: CGRect(x: 0, y: 0, width: 300, height: 1), position: .zero
        )

        #expect(
            bounds.size.height == ViewBlockAttachment.unmeasuredHeight,
            "un hostView nil deve riservare l'altezza placeholder, come un host non ancora misurato"
        )
    }
}

/// `ViewBlockAttachment.storableHeight(measured:current:)` in isolation (ADR-0035): the pure
/// function that decides whether a fresh measurement is worth storing and re-laying out for, and
/// the one that makes a measure -> relayout -> remeasure cycle terminate rather than oscillate.
@Suite struct ViewBlockHeightConvergenceTests {
    /// A first measurement (`current: nil`) is always stored, clamped.
    @Test func firstMeasurementIsAlwaysStoredClamped() {
        let stored = ViewBlockAttachment.storableHeight(measured: 100, current: nil)
        #expect(stored == 100, "la prima misura deve sempre essere memorizzata")
    }

    /// A new measurement within `heightEpsilon` of the already-stored clamped value changes
    /// nothing worth a re-layout for.
    @Test func aMeasurementWithinEpsilonOfCurrentIsNotStored() {
        let stored = ViewBlockAttachment.storableHeight(measured: 100.3, current: 100)
        #expect(stored == nil, "una misura entro l'epsilon non deve richiedere un nuovo relayout")
    }

    /// A new measurement beyond `heightEpsilon` returns the new clamped value.
    @Test func aMeasurementBeyondEpsilonReturnsTheNewClampedValue() {
        let stored = ViewBlockAttachment.storableHeight(measured: 105, current: 100)
        #expect(stored == 105, "una misura oltre l'epsilon deve restituire il nuovo valore")
    }

    /// Anti-oscillation: two measurements both above the cap clamp to the same `maximumHeight`,
    /// so the second one stores nothing and schedules no further relayout - this is what makes
    /// the measure -> relayout -> remeasure cycle terminate for oversized content.
    @Test func twoMeasurementsBothAboveTheCapConverge() {
        let firstStored = ViewBlockAttachment.storableHeight(measured: 5_000, current: nil)
        #expect(firstStored == ViewBlockAttachment.maximumHeight)

        let secondStored = ViewBlockAttachment.storableHeight(measured: 5_003, current: firstStored)
        #expect(
            secondStored == nil,
            "due misure entrambe oltre il tetto devono convergere senza richiedere un secondo relayout"
        )
    }

    /// A raw measurement above the cap with no prior value returns exactly `maximumHeight`, not
    /// the raw value - clamp happens before the value is ever stored.
    @Test func aRawMeasurementAboveTheCapWithNoCurrentClampsBeforeStoring() {
        let stored = ViewBlockAttachment.storableHeight(measured: 5_000, current: nil)
        #expect(
            stored == ViewBlockAttachment.maximumHeight,
            "il clamp deve avvenire prima della memorizzazione, mai il valore grezzo"
        )
    }
}
