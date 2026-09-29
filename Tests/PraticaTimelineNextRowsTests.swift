import Foundation
import Testing
@testable import Pergamenum

// ADR-0072 §D7, plan docs/plans/pg-138-pg-141-pg-142-performance-debt.md, Task 6 - R-16.
//
// «Inserisci qui» used to find a row's successor with a linear search per row menu
// (`PraticaTimelineView.following(_:)`). `nextRows(in:)` answers all of them in one pass, and
// must answer what that search answered: the entry after the first one carrying the id, none
// for the last row.

@Suite struct PraticaTimelineNextRowsTests {
    private static let start = Date(timeIntervalSince1970: 1_700_000_000)

    private static func entry(_ id: String, _ kind: PraticaTimelineEntry.Kind, minute: Int,
                              attachments: Bool = false) -> PraticaTimelineEntry {
        PraticaTimelineEntry(
            id: id, kind: kind, date: start.addingTimeInterval(TimeInterval(60 * minute)),
            direction: kind == .message ? .received : nil, senderDisplayName: "Mario Rossi",
            subject: "Oggetto \(id)", bodyPreview: "", hasAttachments: attachments,
            messageID: kind == .message ? "<\(id)@x.it>" : nil, isInMail: true
        )
    }

    /// Today's rule, verbatim in spirit: the entry after `firstIndex`, when there is one.
    private static func reference(_ entries: [PraticaTimelineEntry]) -> [String: PraticaTimelineEntry] {
        var map: [String: PraticaTimelineEntry] = [:]
        for entry in entries {
            guard let index = entries.firstIndex(where: { $0.id == entry.id }),
                  entries.indices.contains(index + 1)
            else { continue }
            map[entry.id] = entries[index + 1]
        }
        return map
    }

    private static let many: [PraticaTimelineEntry] = [
        entry("m1", .message, minute: 0, attachments: true),
        entry("n1", .note, minute: 1),
        entry("m2", .message, minute: 2),
        entry("c1", .call, minute: 3),
        entry("m3", .message, minute: 4, attachments: true),
        entry("m4", .message, minute: 5),
    ]

    @Test func noEntriesHaveNoSuccessors() {
        #expect(PraticaTimelineModel.nextRows(in: []).isEmpty)
    }

    @Test func aSingleEntryHasNoSuccessor() {
        let one = [Self.entry("m1", .message, minute: 0)]
        #expect(PraticaTimelineModel.nextRows(in: one).isEmpty)
        #expect(PraticaTimelineModel.nextRows(in: one) == Self.reference(one))
    }

    @Test func manyEntriesMatchTheLinearSearch() {
        let map = PraticaTimelineModel.nextRows(in: Self.many)
        #expect(map == Self.reference(Self.many))
        #expect(map.count == Self.many.count - 1)
        #expect(map["m4"] == nil, "the last row has no successor")
        #expect(map["n1"]?.id == "m2")
    }

    @Test(arguments: [
        PraticaTimelineFilter(attachmentsOnly: true),
        PraticaTimelineFilter(text: "m"),
        PraticaTimelineFilter(text: "Oggetto n1"),
        PraticaTimelineFilter(text: "nessuna riga"),
    ])
    func aFilteredTimelineMatchesTheLinearSearch(_ filter: PraticaTimelineFilter) {
        let filtered = PraticaTimelineModel.filtered(Self.many, by: filter)
        #expect(PraticaTimelineModel.nextRows(in: filtered) == Self.reference(filtered))
    }

    @Test func aFilteredTimelineSkipsTheHiddenRows() {
        let filtered = PraticaTimelineModel.filtered(Self.many, by: PraticaTimelineFilter(attachmentsOnly: true))
        let map = PraticaTimelineModel.nextRows(in: filtered)
        #expect(map["m1"]?.id == "n1", "a manual entry is never hidden by «Solo con allegati»")
        #expect(map["c1"]?.id == "m3")
        #expect(map["m3"] == nil)
    }
}
