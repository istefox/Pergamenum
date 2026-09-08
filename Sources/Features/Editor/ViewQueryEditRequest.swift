import Foundation

/// A view-block fence's own edit affordance (ADR-0034 §D2): the value `.sheet(item:)`
/// presents when "Modifica query" is tapped in `RenderedViewBlock`'s header, in either the
/// live-render or the error-card state.
///
/// `TableGridView.onCommit`'s own shape, not a `Navigation`-routed pending request: a hosted
/// view is rebuilt with the text view on every styling pass, so the closure below can be
/// captured directly where the fence is walked (`refreshViewBlockHosts`) rather than routed
/// up through SwiftUI state and back down, which would only add a second staleness window.
struct ViewQueryEditRequest: Identifiable {
    /// Two clicks on the same fence are two presentations.
    let id: UUID
    /// The fence's body as it is at the moment of the click - the same string
    /// `RenderedViewBlock` is rendering.
    let source: String
    /// Body text in, `true` when the note was rewritten.
    let commit: (String) -> Bool
}
