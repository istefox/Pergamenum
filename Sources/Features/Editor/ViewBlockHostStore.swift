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
/// The key space is an `Int` ordinal and nothing else, which is also what makes two
/// byte-identical fences in one note two distinct hosts: an `NSView` has exactly one superview,
/// so a host shared between two spots in the note would be a broken layout rather than a
/// cosmetic collision (ADR §D3's rejection of a source-text key).
@MainActor
final class ViewBlockHostStore {
    /// The host already built for each ordinal. Never pruned by this property's own accessors:
    /// `hosts(for:in:)` below is the one call that knows the whole set of ordinals the note
    /// spells, so a host is dropped exactly once per styling pass rather than whenever a
    /// lookup happens to miss - `TableGridStore`'s own division of labour (ADR-0029 §D6).
    private var hosts: [Int: NSHostingView<AnyView>] = [:]

    /// The host for `ordinal`, built on first ask and handed back unchanged after that.
    ///
    /// Handing back the same instance is the whole point (ADR §D3, C6: "the one that must
    /// never be relaxed"): a fresh `NSHostingView` per styling pass loses SwiftUI's own
    /// diffing and re-runs `RenderedViewBlock`'s `.task(id:)` - a query evaluation walking the
    /// index - from scratch, and a styling pass is every keystroke. The ordinal is stable
    /// under an edit that shifts every paragraph offset above the fence, which is exactly the
    /// edit an offset key would rebuild on.
    ///
    /// The root view it is built with is a placeholder: this store knows an ordinal, not a
    /// fence's source, its theme or the vault behind it. The Coordinator pushes the real one
    /// in through `update(_:forOrdinal:)` per pass, built by `rootView(...)` below.
    ///
    /// `textView` is deliberately unread, unlike `TableGridStore.view(for:in:)`, which uses it
    /// to build a grid's resign-first-responder closure: a hosted SwiftUI view runs its own
    /// focus. The parameter is kept for symmetry with that store and with `hosts(for:in:)`.
    func host(for ordinal: Int, in textView: NSTextView) -> NSHostingView<AnyView> {
        if let existing = hosts[ordinal] { return existing }
        let host = NSHostingView(rootView: AnyView(EmptyView()))
        hosts[ordinal] = host
        return host
    }

    /// The hosts for every ordinal the note spells right now, and **only** those - an ordinal
    /// absent from `ordinals` is dropped here.
    ///
    /// Pruning belongs on this call rather than on `host(for:in:)` for `TableGridStore`'s own
    /// reason: a styling pass is the one moment that knows the whole set, so a note whose
    /// fences are edited for an afternoon would otherwise accumulate a host per ordinal any
    /// fence ever reached, each holding a live SwiftUI view hierarchy over the index.
    func hosts(for ordinals: [Int], in textView: NSTextView) -> [Int: NSHostingView<AnyView>] {
        var kept: [Int: NSHostingView<AnyView>] = [:]
        for ordinal in ordinals {
            kept[ordinal] = host(for: ordinal, in: textView)
        }
        hosts = kept
        return kept
    }

    /// Pushes a new root view into the existing host rather than building one (ADR §D3): the
    /// point of keeping the same `NSHostingView` across passes is exactly that SwiftUI diffs
    /// the new `rootView` against the old one instead of the query restarting from scratch.
    func update(_ root: AnyView, forOrdinal ordinal: Int) {
        hosts[ordinal]?.rootView = root
    }

    /// The root view a drawn fence's host carries, composed in one place so that every caller
    /// gets the same wrapper: the block the vault already knows how to render, inside the
    /// `ScrollView` that turns ADR §D8's fixed height into a window onto a result set of any
    /// size, with the theme handed in by value because an `NSHostingView` built from AppKit
    /// inherits no SwiftUI environment from anywhere.
    ///
    /// **The `ScrollView` lives here and never inside `RenderedViewBlock`** (ADR §D8): the same
    /// block is drawn at its natural height by `MarkdownBlocksView` for a transclusion and by
    /// `NoteExporter` for an export (R-10, R-11), and a scroll view inside the block would
    /// bound those two surfaces too - this host is the only site that knows it is
    /// height-bounded.
    ///
    /// Every input but `theme` is forwarded verbatim to the block, `onEditSource` and
    /// `onOpenNote` included (ADR §D9's two optional inputs, §D10's door back to the source):
    /// this function composes the wrapper and decides nothing about the block itself, so the
    /// editor's caller is the one place that says what a drawn fence can reach.
    ///
    /// **All of them default**, which is what keeps R-10/R-11 true by construction rather than
    /// by care: a caller that opts into nothing gets exactly `MarkdownBlocksView`'s own
    /// rendering - no vault ("Nessun vault dietro questa vista"), no click target on a row, no
    /// edit-source control in the header.
    static func rootView(
        source: String,
        notePath: String = "",
        vaultRoot: URL? = nil,
        thumbnails: ThumbnailStore? = nil,
        queries: ViewQuerySource? = nil,
        onEditSource: (() -> Void)? = nil,
        onOpenNote: ((String) -> Void)? = nil,
        theme: Theme
    ) -> AnyView {
        AnyView(
            ScrollView {
                RenderedViewBlock(
                    source: source,
                    notePath: notePath,
                    vaultRoot: vaultRoot,
                    thumbnails: thumbnails,
                    queries: queries,
                    onEditSource: onEditSource,
                    onOpenNote: onOpenNote
                )
            }
            .environment(\.theme, theme)
        )
    }
}
