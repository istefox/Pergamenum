import Foundation

// ADR-0032 (Plaud recording import into Pergamenum), plan
// docs/superpowers/plans/2026-09-05-plaud-recording-import-into-pergamenum.md, Task 1 -
// R-03, R-07, R-13; ADR §D8.
//
// A tolerant timestamp parser for the wire's two documented shapes plus the one it actually
// sends (measured live, 2026-09-05): `generated_at` carries fractional seconds and a `Z`;
// `recorded_at` carries neither, and is UTC anyway - measured, not assumed, from the one
// recording whose `name` still gave the old timestamp form (`name` "2026-09-04 13:44:51" is
// exactly `recorded_at` "2026-09-04T11:44:51" plus Europe/Rome's own +2 DST offset).
enum PlaudTimestamp {
    /// Tries, in order: fractional-second `Z` (`generated_at`), plain `Z` (the shape the
    /// contract document still describes for `recorded_at`), then a zone-less
    /// `yyyy-MM-dd'T'HH:mm:ss` read as **UTC** (what every measured `recorded_at` actually
    /// is). `nil` for anything matching none of the three.
    static func parse(_ raw: String) -> Date? {
        if let date = isoFormatter(withFractionalSeconds: true).date(from: raw) { return date }
        if let date = isoFormatter(withFractionalSeconds: false).date(from: raw) { return date }
        return zonelessFormatter.date(from: raw)
    }

    /// Built per call rather than held in a `static let`, unlike `zonelessFormatter` below:
    /// `ISO8601DateFormatter` carries no `Sendable` conformance, so a shared static of it does
    /// not compile under Swift 6 strict concurrency, and `nonisolated(unsafe)` would be a
    /// promise about a Foundation class rather than a fact. A handful of parses per import
    /// pays for two allocations easily.
    private static func isoFormatter(withFractionalSeconds: Bool) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = withFractionalSeconds
            ? [.withInternetDateTime, .withFractionalSeconds]
            : [.withInternetDateTime]
        return formatter
    }

    /// `en_US_POSIX` and a fixed format, the only combination that parses a machine
    /// timestamp regardless of the machine's own region settings; `UTC` is the measured
    /// reading of the zone-less form, not a default that happened to be convenient.
    private static let zonelessFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()
}
