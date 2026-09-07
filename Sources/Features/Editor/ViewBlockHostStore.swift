import AppKit
import SwiftUI

/// Vends the one `NSHostingView` a `pergamenum-view` fence keeps across every styling pass,
/// keyed by the fence's **ordinal** within the note rather than by paragraph offset (ADR-0033
/// §D3 - a deliberate divergence from `TableGridStore`, ADR-0029 §D6). Plan
/// `2026-09-06-pg-099-views-board-renderer-orphaned-by`, Task 4.
///
/// An offset key would rebuild the host - and re-run `RenderedViewBlock`'s `.task(id:)`, a
/// query evaluation walking the index - on every keystroke typed *above* the fence. ADR-0009
/// §D7 forbids exactly that ("on open, on an explicit refresh, and on a watcher change …
/// debounced, never per keystroke"), so this store's key has to be stable under an edit that
/// does not add or remove a view block, which the fence's ordinal (the note's first, second,
/// third `pergamenum-view` block) is and a paragraph offset is not.
///
/// **TESTER STUB (ADR-0049).** `host(for:in:)` and `hosts(for:in:)` below neither cache nor
/// prune - every call builds a fresh `NSHostingView` and the backing dictionary only ever
/// grows. This is deliberate: it keeps every identity assertion in `ViewBlockHostStoreTests`
/// red (the whole reason this store exists, C6) until Task 4's coder replaces both bodies with
/// `TableGridStore`'s real caching/pruning shape, keyed by ordinal instead of offset. The
/// "two identical fences get two distinct hosts" assertion is already true against this stub
/// (the dictionary is keyed by ordinal from the start) and must stay true - that is a
/// property of the *key space*, not of caching, and nothing here should make it false.
@MainActor
final class ViewBlockHostStore {
    /// The host already built for each ordinal. TESTER STUB: written to on every
    /// `host(for:in:)` call rather than read from first - see the type's own header.
    private var hosts: [Int: NSHostingView<AnyView>] = [:]

    /// The host for `ordinal`, built on first ask and handed back unchanged after that once
    /// Task 4's coder fills this in for real.
    ///
    /// TODO(coder, Task 4): return `hosts[ordinal]` when present, matching
    /// `TableGridStore.view(for:in:)` - the same instance must survive across calls for the
    /// same ordinal, including an edit that shifts every paragraph offset above it (ADR §D3,
    /// C6: "the one that must never be relaxed").
    func host(for ordinal: Int, in textView: NSTextView) -> NSHostingView<AnyView> {
        let host = NSHostingView(rootView: AnyView(EmptyView()))
        hosts[ordinal] = host
        return host
    }

    /// The hosts for every ordinal the note spells right now, and **only** those - an ordinal
    /// absent from `ordinals` must be dropped, not accumulated.
    ///
    /// TODO(coder, Task 4): rebuild a fresh `kept` dictionary from `ordinals` only (calling
    /// `host(for:in:)` per ordinal) and assign `hosts = kept`, matching
    /// `TableGridStore.views(for:in:)`. The stub below does neither: it never removes an
    /// ordinal that stops appearing, so a note that loses a fence still accumulates its host.
    func hosts(for ordinals: [Int], in textView: NSTextView) -> [Int: NSHostingView<AnyView>] {
        for ordinal in ordinals {
            _ = host(for: ordinal, in: textView)
        }
        return hosts
    }

    /// Pushes a new root view into the existing host rather than building one (ADR §D3): the
    /// point of keeping the same `NSHostingView` across passes is exactly that SwiftUI diffs
    /// the new `rootView` against the old one instead of the query restarting from scratch.
    func update(_ root: AnyView, forOrdinal ordinal: Int) {
        hosts[ordinal]?.rootView = root
    }
}
