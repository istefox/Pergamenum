import Foundation

// ADR-0083 §D1, §D2 (PG-386, N3 session B).

/// Where a followed link lands (ADR-0083 §D1): over the focused tab, in a tab of its own, or in
/// the other column.
enum LinkOpening: Equatable, Sendable {
    case replace, newTab, otherColumn

    /// The click variants, read from the live modifier flags (ADR-0083 §D2). Option wins over
    /// Shift: "the other column" is the stronger move, and a person holding both meant more.
    static func forClick(shift: Bool, option: Bool) -> LinkOpening {
        if option { return .otherColumn }
        return shift ? .newTab : .replace
    }
}
