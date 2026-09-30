import AppKit
import SwiftUI
import Testing
@testable import Pergamenum

/// The Today view's drop banner never changes height (ADR-0075 §D3, PG-259).
///
/// It sits above the day's `HSplitView` and can appear, or be replaced, while a drop is still
/// committing. A taller banner then makes AppKit renegotiate the split's constraints inside
/// that transaction, and the app aborted: a refused hour drop's two-sentence summary wrapped
/// under the old `.fixedSize(horizontal: false, vertical: true)`. Measured here in a window
/// that is never shown (`HostedViewSupport.swift`), not by the GUI suite.
///
/// This test caught the first fix, `.lineLimit(2, reservesSpace: true)`, still growing by 6pt:
/// the reservation leaves out the line spacing `themedText` adds, so two lines reserved 26pt and
/// two real lines took 32pt.
///
/// `.serialized`: each test builds its own window and reads `NSApp` state around it
/// (`HostedViewPrototypeTests`' reason).
@MainActor
@Suite(.serialized)
struct TaskDropBannerTests {
    /// About the narrowest the Today view gets beside the sidebar.
    private static let width: CGFloat = 640

    private static let oneLine = "Spostato al 11/08/2026, 23:00"
    private static let refusal = oneLine + ". Blocco non creato: nessuno spazio libero il 11/08/2026"
    private static let longRefusal = "Non spostato: "
        + Array(repeating: "«topic-inesistente» non è nel vocabolario dei tag", count: 6)
            .joined(separator: ", ")

    /// The fitting height of `content` laid out at `width`, in a window never shown.
    private func fittingHeight(of content: some View) async -> CGFloat {
        let host = HostedView(
            content.frame(width: Self.width).environment(\.theme, .emergency),
            size: CGSize(width: Self.width, height: 240)
        )
        defer { host.tearDown() }
        await host.settle()
        #expect(host.neverShown)
        #expect(host.refusals.isEmpty)
        return host.hosting.fittingSize.height
    }

    private func bannerHeight(_ summary: String, journalID: String?, isRefusal: Bool) async -> CGFloat {
        await fittingHeight(of: TaskDropBanner(
            drop: DayController.Drop(summary: summary, journalID: journalID, isRefusal: isRefusal),
            onUndo: {},
            onClose: {}
        ))
    }

    /// The control: at this width the long summary does wrap, in the banner's own text style,
    /// so the equality below is not the trivial one of summaries that all fit on a line.
    @Test func theLongSummaryWrapsAtThisWidth() async {
        let one = await fittingHeight(of: Text(Self.oneLine).themedText(.caption))
        let long = await fittingHeight(of: Text(Self.longRefusal).themedText(.caption))
        #expect(one > 0)
        #expect(long > one)
    }

    /// One height for every banner the day view can raise, including one replaced by the next
    /// while it is up: a success, a composed refusal with «Annulla», a refusal without it, and a
    /// summary longer than the two lines reserved.
    @Test func everyBannerHasTheSameHeight() async {
        let heights = [
            await bannerHeight(Self.oneLine, journalID: "j", isRefusal: false),
            await bannerHeight(Self.refusal, journalID: "j", isRefusal: true),
            await bannerHeight(
                "Blocco tempo non creato: nessuno spazio libero il 11/08/2026", journalID: nil, isRefusal: true
            ),
            await bannerHeight(Self.longRefusal, journalID: nil, isRefusal: true),
        ]
        #expect(heights[0] > 0)
        #expect(Set(heights).count == 1, "banner heights differ: \(heights)")
    }
}
