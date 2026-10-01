import Foundation

// ADR-0076 §D8 (PG-338), plan docs/plans/pratiche-message-anchored-entries.md, Task 6 - R-11.
//
// The message picker's pure half: which of the pratica's rows it lists, under which filter,
// and which one is the entry's current anchor. The view (`PraticaMessagePicker`) only draws
// these rows and hands the chosen Message-ID to `PraticaCommandActions.anchor(_:to:)`.
enum PraticaMessagePickerModel {
    struct Row: Equatable, Identifiable {
        var messageID: String
        var date: Date
        var sender: String
        var subject: String
        /// The entry being linked already names this message.
        var isCurrent: Bool

        var id: String { messageID }
    }

    /// The messages of `timeline` a manual entry can name (R-11), in the timeline's own order,
    /// oldest first. A message whose Message-ID is missing, or that `PraticaEntryAnchor.line(for:)`
    /// refuses (empty, or holding `-->`, a CR or an LF), has nothing an anchor could carry and is
    /// skipped, so every row listed can be chosen successfully. A Message-ID carried by two message
    /// files is listed once, for the first, which is the one that owns it (ADR-0076 §D2).
    /// `filter`, trimmed, matches the sender or the subject, case- and diacritic-insensitively;
    /// empty lists everything.
    static func rows(from timeline: [PraticaTimelineEntry], filter: String, currentAnchor: String?) -> [Row] {
        let query = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        var seen: Set<String> = []
        var rows: [Row] = []
        for entry in timeline where entry.kind == .message {
            guard let messageID = entry.messageID,
                  PraticaEntryAnchor.line(for: messageID) != nil,
                  seen.insert(messageID).inserted
            else { continue }
            guard query.isEmpty
                || entry.senderDisplayName.localizedStandardContains(query)
                || entry.subject.localizedStandardContains(query)
            else { continue }
            rows.append(Row(
                messageID: messageID, date: entry.date, sender: entry.senderDisplayName,
                subject: entry.subject, isCurrent: messageID == currentAnchor
            ))
        }
        return rows
    }
}
