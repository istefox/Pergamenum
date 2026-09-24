import Foundation

/// The timeline's read-only geometry, derived from `hours` and `entries`.
///
/// Moved out of `DiaryController.swift` for SwiftLint headroom when the serial write door
/// and the origin arrived there (ADR-0057). A pure move of read-only members. `hours`
/// itself stays in the declaring file: it reads the controller's private `vault`, and
/// widening that to reach it from here would hand every caller the vault's write door.
extension DiaryController {
    var firstHour: Int { hours.first }
    var lastHour: Int { hours.last }

    var placements: [DiaryLayout.Placement] { DiaryLayout.place(entries) }

    /// How much of the day is accounted for, which is the one number a diary is asked
    /// for at the end of an evening.
    var totalMinutes: Int { entries.reduce(0) { $0 + $1.durationMinutes } }
}
