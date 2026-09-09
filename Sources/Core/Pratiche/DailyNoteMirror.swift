import Foundation

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 7 - R-29.
//
// Pure text for the daily-note mirror line «Nota»/«Telefonata» write beside the
// heading itself (`PraticaEntry.insert`). §D5 fixes this as one atomic
// `VaultSession.write`, same as the heading - reading the day's note
// (`VaultSession.dailyNote(for:)`), composing this line onto it, and skipping the
// write entirely when it returns `nil`, are the coder's.
//
// Every declaration below is a tester-declared boundary (ADR-0155 §D1): stubbed to a
// wrong-but-safe constant, never `fatalError`.
enum DailyNoteMirror {
    struct Entry: Equatable, Sendable {
        var praticaTitle: String
        var kind: PraticaEntry.Kind
        var counterpart: String
    }

    /// `- [[<pratica>]] — <Kind> · <Controparte>` (R-29).
    ///
    /// RED stub: always the empty string.
    static func line(for entry: Entry) -> String {
        ""
    }

    /// Appends `line(for:)` to `existingText`, or `nil` when «Scrivi nel diario» is off
    /// (R-29, `PraticheSettings.mirrorsToDailyNote`) - `nil` is what tells the coder's
    /// write path to skip `VaultSession.write` entirely rather than writing an
    /// unchanged file.
    ///
    /// RED stub: always returns `existingText` unchanged, regardless of `isEnabled` -
    /// both the append and the gating assertions fail until the coder implements it.
    static func appending(_ entry: Entry, to existingText: String, isEnabled: Bool) -> String? {
        existingText
    }
}
