import Foundation

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 7 - R-29.
//
// Pure text for the daily-note mirror line «Nota»/«Telefonata» write beside the
// heading itself (`PraticaEntry.insert`). §D5 fixes this as one atomic
// `VaultSession.write`, same as the heading - reading the day's note
// (`VaultSession.dailyNote(for:)`), composing this line onto it, and skipping the
// write entirely when it returns `nil`, are the coder's.
enum DailyNoteMirror {
    struct Entry: Equatable, Sendable {
        var praticaTitle: String
        var kind: PraticaEntry.Kind
        var counterpart: String
    }

    /// `- [[<pratica>]] — <Kind> · <Controparte>` (R-29). An em dash between the link
    /// and the kind, a middle dot between the kind and the counterpart - the same two
    /// separators the entry's own heading uses.
    static func line(for entry: Entry) -> String {
        "- [[\(entry.praticaTitle)]] — \(entry.kind.label) · \(entry.counterpart)"
    }

    /// Appends `line(for:)` to `existingText`, or `nil` when «Scrivi nel diario» is off
    /// (R-29, `PraticheSettings.mirrorsToDailyNote`) - `nil` is what tells the caller's
    /// write path to skip `VaultSession.write` entirely rather than writing an
    /// unchanged file.
    ///
    /// Exactly one line, at the end: the daily note belongs to the day, not to this
    /// feature, so nothing here looks for a section to file the line under or reorders
    /// what somebody else wrote.
    static func appending(_ entry: Entry, to existingText: String, isEnabled: Bool) -> String? {
        guard isEnabled else { return nil }
        var text = existingText
        if !text.isEmpty, !text.hasSuffix("\n") { text += "\n" }
        return text + line(for: entry) + "\n"
    }
}
