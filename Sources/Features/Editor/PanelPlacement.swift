import AppKit

/// Where a panel goes beside a line of the note, and how tall it may be.
///
/// Lifted out of `CompletionPanel` when the format bar needed the same rules with one side
/// swapped. **Shared and not copied**: «flip when there is no room» in two places would drift,
/// and the placement defects of PG-023 are ones this codebase has already paid for once - a
/// list that put itself over the caret's own line near the bottom of a window, and a clamp
/// that pulled it back onto the text it was supposed to be helping with.
///
/// Pure, with no window in it, so every rule here is checked without a screen. Screen
/// coordinates throughout, so y grows upwards and «below» means a smaller y.
enum PanelPlacement {
    /// Which side the panel would rather be on. The completion panel prefers below the caret,
    /// because a list hanging above the line reads as belonging to the line above it; the
    /// format bar prefers above the selection, because below it covers the line the person is
    /// about to keep reading.
    enum Side { case above, below }

    /// The gap between the anchor line and the panel, and the margin kept from the screen.
    static let gap: CGFloat = 6
    static let margin: CGFloat = 8

    static func visibleFrame(containing anchor: NSRect) -> NSRect {
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
        return screen?.visibleFrame ?? .zero
    }

    /// How tall a panel may be: the taller of the two sides of the anchor line.
    ///
    /// Asked before the panel is built, because the height decides the placement rather than
    /// following from it. Without this the list grew to its content, found room on neither
    /// side, and had to be put somewhere - and every "somewhere" that fits on the screen is on
    /// top of the line being typed into.
    static func room(besides anchor: NSRect, in visible: NSRect) -> CGFloat {
        let below = anchor.minY - visible.minY - gap - margin
        let above = visible.maxY - anchor.maxY - gap - margin
        return max(below, above)
    }

    /// The placement rule.
    ///
    /// On the preferred side when it fits there, on the other when it does not, and **never a
    /// clamp that crosses the anchor**: pulling a panel back inside the screen is what put it
    /// over the text the person was typing. If it fits on neither side it hangs off the screen
    /// edge instead, which is the honest failure of the two.
    static func origin(
        forPanelOf size: NSSize, besides anchor: NSRect, in visible: NSRect, preferring side: Side
    ) -> NSPoint {
        var y: CGFloat
        switch side {
        case .below:
            y = anchor.minY - size.height - gap
            if y < visible.minY + margin { y = anchor.maxY + gap }
        case .above:
            y = anchor.maxY + gap
            if y + size.height > visible.maxY - margin { y = anchor.minY - size.height - gap }
        }
        let x = min(
            max(anchor.minX, visible.minX + margin),
            max(visible.minX + margin, visible.maxX - size.width - margin)
        )
        return NSPoint(x: x, y: y)
    }
}
