import XCTest

/// The one way a UI test drags something (PG-162).
///
/// `press(forDuration:thenDragTo:)` delivers no translation on this machine (macOS 27.0,
/// Xcode 27.0): a `DragGesture` sees no movement at all, an AppKit splitter or an
/// `NSDraggingSession` never starts, and the assertion that follows reads the untouched
/// starting value (`240.0` where a resize was expected to reach `340.0`). For a while that
/// looked like the OS having stopped honouring synthesized drags, and twelve tests stayed red
/// on that theory. Measured on 2026-09-19 against `WorkspaceBoardUITests`' corner grip, the
/// same gesture four ways:
///
///   - `press(forDuration:thenDragTo:)`                          fails, 240.0 of 340.0
///   - `press(forDuration:thenDragTo:withVelocity:thenHoldForDuration:)`, `.slow` and a hold
///                                                                fails, 240.0 of 340.0
///   - the same drag from window-relative coordinates              fails, 240.0 of 340.0
///   - `click(forDuration:thenDragTo:)`                            passes
///
/// So synthesis works; that one API does not. Velocity, hold time and how the start point is
/// expressed are not what matters, which is worth knowing before trying them again.
///
/// A test drags through `dragTo(_:pressing:)` and never calls `press(forDuration:thenDragTo:)`
/// directly, so the next drag written cannot bring the failure back.
extension XCUICoordinate {
    func dragTo(_ destination: XCUICoordinate, pressing duration: TimeInterval = 0.4) {
        click(forDuration: duration, thenDragTo: destination)
    }
}

extension XCUIElement {
    func dragTo(_ destination: XCUIElement, pressing duration: TimeInterval = 0.4) {
        click(forDuration: duration, thenDragTo: destination)
    }
}
