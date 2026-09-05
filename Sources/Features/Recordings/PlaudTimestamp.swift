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
    ///
    /// STUB (RED baseline, not yet implemented): always returns `nil`. The coder implements
    /// the three-formatter cascade ADR §D8 names, in that order.
    static func parse(_ raw: String) -> Date? {
        nil
    }
}
