import AppKit
import SwiftUI
import Testing
@testable import Pergamenum

/// ADR-0033 §D3, §D8 (plan `2026-09-06-pg-099-views-board-renderer-orphaned-by`, Task 4):
/// `ViewBlockHostStore` vends the one `NSHostingView` a `pergamenum-view` fence keeps across
/// every styling pass, keyed by the fence's **ordinal**, not its paragraph offset - the
/// deliberate divergence from `TableGridStore` (ADR-0029 §D6) that keeps `RenderedViewBlock`'s
/// query from re-running per keystroke typed above the fence (ADR-0009 §D7). `ViewBlockAttachment`
/// reserves a fixed height at the proposed line fragment's own width, independent of content
/// (R-06, §D8).
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
@Suite struct ViewBlockAttachmentBoundsTests {
    /// **Already true against the stub** (`ViewBlockAttachmentViewProvider.attachmentBounds`
    /// is written for real, not stubbed - see `ViewBlockAttachment.swift`'s header). R-06,
    /// ADR §D8: the attachment reserves `proposedLineFragment.width` × the constant
    /// `ViewBlockAttachment.height`, independent of the hosted content - a forty-card board
    /// and an empty result set occupy the exact same rectangle, so the note's layout below the
    /// block never moves as the result set's size changes. Asserted at two different proposed
    /// widths and with two different stub "result sets" standing in for the hosted content.
    @Test func attachmentBoundsIsTheProposedWidthByAConstantHeightIndependentOfContent() throws {
        let location = anyTextLocation()

        let emptyResultSet = NSHostingView(rootView: AnyView(EmptyView()))
        let largeResultSet = NSHostingView(rootView: AnyView(Color.red.frame(width: 5_000, height: 5_000)))

        let narrowAttachment = ViewBlockAttachment()
        narrowAttachment.hostView = emptyResultSet
        let narrowProvider = try #require(
            narrowAttachment.viewProvider(for: nil, location: location, textContainer: nil)
        )

        let wideAttachment = ViewBlockAttachment()
        wideAttachment.hostView = largeResultSet
        let wideProvider = try #require(
            wideAttachment.viewProvider(for: nil, location: location, textContainer: nil)
        )

        let narrowLineFragment = CGRect(x: 0, y: 0, width: 300, height: 1)
        let wideLineFragment = CGRect(x: 0, y: 0, width: 700, height: 1)

        let narrowEmptyBounds = narrowProvider.attachmentBounds(
            for: [:], location: location, textContainer: nil,
            proposedLineFragment: narrowLineFragment, position: .zero
        )
        #expect(narrowEmptyBounds.size == CGSize(width: 300, height: ViewBlockAttachment.height))

        let narrowLargeBounds = wideProvider.attachmentBounds(
            for: [:], location: location, textContainer: nil,
            proposedLineFragment: narrowLineFragment, position: .zero
        )
        #expect(
            narrowLargeBounds.size == narrowEmptyBounds.size,
            "un result set enorme non deve cambiare le dimensioni riservate rispetto a uno vuoto, a parità di larghezza proposta"
        )

        let wideEmptyBounds = narrowProvider.attachmentBounds(
            for: [:], location: location, textContainer: nil,
            proposedLineFragment: wideLineFragment, position: .zero
        )
        #expect(wideEmptyBounds.size == CGSize(width: 700, height: ViewBlockAttachment.height))
        #expect(
            wideEmptyBounds.size.height == narrowEmptyBounds.size.height,
            "l'altezza resta la costante di ViewBlockAttachment qualunque sia la larghezza proposta"
        )
    }
}
