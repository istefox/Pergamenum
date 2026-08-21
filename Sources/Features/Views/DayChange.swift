import SwiftUI

/// Runs an action when the system day changes (ADR-0014 §D4).
///
/// A view whose `where` carries a relative bound - `modified >= week-start` - answers a
/// question about *now*, and one left open across midnight answers about yesterday without
/// saying so. That is the same silent staleness ADR-0009 §D1 refuses inside a block, drawn
/// instead of typed, so the view re-evaluates rather than waiting to be asked.
///
/// **An observation, not a timer, and the difference is the whole reason this is affordable:
/// nothing wakes up to check the time, something is told when it changed.** The same shape
/// `EventKitStore` already uses for `EKEventStoreChanged`.
///
/// Two limits, read from the macOS 26.5 SDK header rather than assumed, and both worth
/// knowing before this is trusted with anything heavier:
///
/// - **It is not promised to be punctual.** The header says there is no guarantee the
///   notification arrives in a timely manner, «same as with distributed notifications». So this
///   fires *at the day change*, not at 00:00:00. A view is also evaluated on open and on
///   explicit refresh (§D7), and this only closes the window where neither happens.
/// - **A sleeping Mac gets one on wake**, once, however many days were skipped - which is the
///   correct behaviour here, since re-evaluating once is all a view needs whether one day
///   passed or five.
///
/// The day is `Calendar.current`'s, so a machine whose time zone moves gets one too. That is
/// right: `CalendarDate(_:in:)` already decided that this app's today is the machine's.
extension View {
    func onDayChange(perform action: @escaping () -> Void) -> some View {
        task {
            for await _ in NotificationCenter.default.notifications(named: .NSCalendarDayChanged) {
                action()
            }
        }
    }
}
