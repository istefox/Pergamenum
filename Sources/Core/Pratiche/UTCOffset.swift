import Foundation

// The `±hh:mm` offset two file formats carry: the tail of a message's `pergamenum-mail-date`
// (ADR-0065 §D8.2, read by `MessageDocument.parse`) and the third token of a manual entry's
// heading (`PraticaManualEntries.heading(_:)`, written by `PraticaEntry.headingTimestamp`).
// One codec, so the two cannot disagree on what an offset is.
//
// Foundation-only on purpose: it compiles into `perg` and `pergamenum-mcp` through the
// `Sources/Core/**` glob.
enum UTCOffset {
    /// Seconds east of UTC for a token that is exactly `+hh:mm` or `-hh:mm` (two ASCII digits,
    /// a colon, two ASCII digits, minutes below 60) and no further than `limit` from UTC, else
    /// nil. `+00:00` answers 0: whether a zero offset means anything different from none is the
    /// caller's question.
    static func seconds(_ token: some StringProtocol) -> Int? {
        let characters = Array(token)
        guard characters.count == 6,
              characters[0] == "+" || characters[0] == "-",
              characters[3] == ":",
              [1, 2, 4, 5].allSatisfy({ characters[$0].isASCII && characters[$0].isNumber }),
              let hours = Int(String(characters[1...2])),
              let minutes = Int(String(characters[4...5])),
              minutes < 60,
              hours * 3600 + minutes * 60 <= limit
        else { return nil }
        return (characters[0] == "-" ? -1 : 1) * (hours * 3600 + minutes * 60)
    }

    /// ±18:00, the range `TimeZone(secondsFromGMT:)` accepts (measured: 64800 gives a zone,
    /// 64860 nil). Nothing this app writes lies outside it: a heading's offset comes from a real
    /// `TimeZone`, and `MessageDocument.isoString` falls back to `Z` for an offset no zone has.
    /// So `+99:00` in a hand-written heading stays part of the subject.
    static let limit = 18 * 3600

    /// `seconds` spelled as `+hh:mm`/`-hh:mm`, zero as `+00:00`. Seconds below a whole minute
    /// (a historical local mean time) are dropped, as the heading drops them from the time.
    static func text(_ seconds: Int) -> String {
        let magnitude = abs(seconds) / 60
        return (seconds < 0 ? "-" : "+") + String(format: "%02d:%02d", magnitude / 60, magnitude % 60)
    }
}
