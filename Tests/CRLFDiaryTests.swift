import Foundation
import Testing
@testable import Pergamenum

/// PG-321's two review findings on the diary: the break a write uses comes from the whole note,
/// not from the prose half `split` leaves (which drops the closing break), and a second
/// `## Diario` heading is the same section again rather than prose that `write` would later drop.

private func crlf(_ lf: String) -> String { lf.replacingOccurrences(of: "\n", with: "\r\n") }

/// Everything an entry carries except its minted id, which differs between two reads.
private func described(_ entries: [DiaryEntry]) -> [String] {
    entries.map { "\($0.timeText)|\($0.title)|\($0.note)|\($0.colour.rawValue)" }
}

/// The loop the app runs, with the break of the note it read.
private func roundTrip(_ note: String) -> String {
    let split = DiarySection.split(note)
    return DiarySection.write(split.entries, into: split.prose, noteBreak: LineBreak.detected(in: note))
}

// MARK: - The break comes from the note

@Test func aCRLFNoteWhoseProseIsOneLineStaysCRLF() {
    let note = "Prosa.\r\n\r\n## Diario\r\n\r\n- 09:00-10:00 X\r\n"
    // The probe's shape: the prose is a single line directly above the heading.
    let tight = "Prosa.\r\n## Diario\r\n- 09:00-10:00 X\r\n"
    #expect(roundTrip(note) == note)
    #expect(roundTrip(tight) == note)
    // Without the note's break the prose shows none, and the write falls back to LF.
    #expect(DiarySection.write(DiarySection.split(tight).entries, into: DiarySection.split(tight).prose)
        == "Prosa.\n\n## Diario\n\n- 09:00-10:00 X\n")
}

@Test func aCRLFNoteThatIsOnlyTheSectionStaysCRLF() {
    let note = "## Diario\r\n\r\n- 09:00-10:00 X\r\n  nota\r\n- 11:00-12:00 Y\r\n"
    #expect(DiarySection.split(note).prose == "")
    #expect(roundTrip(note) == note)
}

@Test func anLFNoteIsWrittenByteForByteAsBefore() {
    let notes = [
        "Prosa.\n\n## Diario\n\n- 09:00-10:00 X\n",
        "Prosa.\n## Diario\n- 09:00-10:00 X\n",
        "## Diario\n\n- 09:00-10:00 X\n  nota\n",
    ]
    let expected = [notes[0], notes[0], notes[2]]
    for (note, want) in zip(notes, expected) {
        #expect(roundTrip(note) == want)
        // The default, which every existing caller of `write(_:into:)` still gets.
        let split = DiarySection.split(note)
        #expect(DiarySection.write(split.entries, into: split.prose) == want)
    }
}

@MainActor
@Test func writeDiaryKeepsACRLFNoteCRLFWhateverItsProseShows() async throws {
    let day = CalendarDate(iso: "2026-08-11")!
    let entry = DiaryEntry(startMinutes: 11 * 60, durationMinutes: 60, title: "Y")
    for source in [
        "Prosa.\r\n## Diario\r\n- 09:00-10:00 X\r\n",
        "## Diario\r\n\r\n- 09:00-10:00 X\r\n",
    ] {
        let vault = try TemporaryVault()
        try vault.write(source, to: "Diario/20260811.md")
        let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
        await session.rescan()
        let read = try #require(session.readDiary(on: day))
        guard case .written(let result) = await session.writeDiary(
            prose: read.prose, entries: read.entries + [entry], on: day, over: read.disk
        ) else {
            Issue.record("expected .written for \(source.debugDescription)")
            continue
        }
        #expect(result.text.replacingOccurrences(of: "\r\n", with: "").contains("\n") == false)
        #expect(result.text.contains("- 11:00-12:00 Y\r\n"))
        #expect(described(DiarySection.split(result.text).entries).count == 2)
    }
}

// MARK: - A second `## Diario` heading

/// The old writer left a CRLF section read as prose and appended an LF one after it.
@Test func aNoteDamagedByTheOldWriterReadsAsOneSectionWithBothEntries() {
    let damaged = "Prosa.\r\n\r\n## Diario\r\n\r\n- 09:00-10:00 X\r\n\r\n## Diario\n\n- 10:00-11:00 Y\n"
    let split = DiarySection.split(damaged)
    #expect(described(split.entries) == ["09:00-10:00|X||blu", "10:00-11:00|Y||blu"])
    #expect(split.prose == "Prosa.\r\n")
    // The next write heals it into one section, in the note's own break.
    let healed = roundTrip(damaged)
    #expect(healed == "Prosa.\r\n\r\n## Diario\r\n\r\n- 09:00-10:00 X\r\n- 10:00-11:00 Y\r\n")
    #expect(healed.components(separatedBy: "## Diario").count == 2)
}

@Test func aSecondDiarioHeadingJoinsTheSectionInAnLFNoteToo() {
    let note = "Prosa.\n\n## Diario\n\n- 09:00-10:00 X\n  nota\n\n## Diario\n\n- 10:00-11:00 Y\n\n## Altro\n\ntesto\n"
    let split = DiarySection.split(note)
    #expect(described(split.entries) == ["09:00-10:00|X|nota|blu", "10:00-11:00|Y||blu"])
    #expect(split.prose == "Prosa.\n\n## Altro\n\ntesto\n")
    let healed = roundTrip(note)
    #expect(healed.components(separatedBy: "## Diario").count == 2)
    // Idempotent once healed: no entry is lost on the next trip.
    #expect(described(DiarySection.split(healed).entries) == described(split.entries))
    #expect(roundTrip(healed) == healed)
}

@Test func anotherHeadingStillClosesTheSection() {
    let split = DiarySection.split("## Diario\n\n- 09:00-10:00 X\n\n## Diarioo\n\n- 10:00-11:00 Y\n")
    #expect(described(split.entries) == ["09:00-10:00|X||blu"])
    #expect(split.prose.contains("- 10:00-11:00 Y"))
}

// MARK: - CRLF against its LF twin, and exact bytes (PG-320)

@Test func aCRLFDiaryReadsAndWritesAsItsLFTwin() {
    let notes = [
        "---\ndate: 2026-09-29\n---\n\nProsa.\n\n## Diario\n\n- 06:00-07:00 Palestra [colore:verde]\n"
            + "  Panca.\n\n  Corsa.\n- 09:00-11:30 Sopralluogo\n",
        // A heading closes the section; a line the section cannot read goes back to the prose.
        "Prosa.\n\n## Diario\n\n- 09:00-10:00 Riunione\nriga sciolta\n\n## Altro\n\ntesto\n",
        // No section yet.
        "Prosa.\n",
    ]
    for lf in notes {
        let lfSplit = DiarySection.split(lf)
        let crlfSplit = DiarySection.split(crlf(lf))
        #expect(crlfSplit.prose == crlf(lfSplit.prose))
        #expect(described(crlfSplit.entries) == described(lfSplit.entries))
        let extra = DiaryEntry(startMinutes: 720, durationMinutes: 30, title: "Pranzo", note: "uno\ndue")
        for entries in [lfSplit.entries, lfSplit.entries + [extra], []] {
            let lfWritten = DiarySection.write(entries, into: lfSplit.prose)
            #expect(DiarySection.write(entries, into: crlfSplit.prose) == crlf(lfWritten))
        }
    }
}

@Test func aDiaryIsWrittenInTheNotesOwnBreakWithExactBytes() {
    let entry = DiaryEntry(startMinutes: 540, durationMinutes: 60, title: "Riunione", note: "uno\ndue", colour: .verde)
    let section = "## Diario\n\n- 09:00-10:00 Riunione [colore:verde]\n  uno\n  due\n"
    let cases: [(prose: String, expected: String)] = [
        ("Prosa.\n", "Prosa.\n\n" + section),
        ("Prosa.\r\n", crlf("Prosa.\n\n" + section)),
        // Mixed: a closing LF in a CRLF note, and a closing CRLF in an LF note.
        ("T\r\nProsa.\n", "T\r\nProsa." + crlf("\n\n" + section)),
        ("T\nProsa.\r\n", "T\nProsa.\n\n" + section),
    ]
    for (prose, expected) in cases {
        #expect(DiarySection.write([entry], into: prose) == expected)
    }
    // An existing section is rewritten in the note's own break; the prose keeps its own lines.
    let mixed = "---\r\ndate: 2026-09-29\r\n---\r\n\r\nProsa.\n\n## Diario\n\n- 09:00-10:00 Vecchio\n"
    let split = DiarySection.split(mixed)
    #expect(split.prose == "---\r\ndate: 2026-09-29\r\n---\r\n\r\nProsa.\n")
    #expect(DiarySection.write([entry], into: split.prose)
        == "---\r\ndate: 2026-09-29\r\n---\r\n\r\nProsa." + crlf("\n\n" + section))
    #expect(DiarySection.write([], into: split.prose) == "---\r\ndate: 2026-09-29\r\n---\r\n\r\nProsa.\r\n")
}

/// Read against a `"\n"` split, a CRLF line kept its `\r`: the heading never matched, so the whole
/// section was prose and every write added a second one.
@Test func aCRLFDiarySectionIsFoundAndNothingReadFromItCarriesACarriageReturn() {
    let note = "Prosa.\r\n\r\n## Diario\r\n\r\n- 09:00-10:00 Riunione [colore:rosa]\r\n  nota\r\n"
    let split = DiarySection.split(note)
    #expect(split.prose == "Prosa.\r\n")
    #expect(described(split.entries) == ["09:00-10:00|Riunione|nota|rosa"])
    let rewritten = DiarySection.write(split.entries, into: split.prose)
    #expect(rewritten == note)
    #expect(rewritten.components(separatedBy: "## Diario").count == 2)
}

/// The whole loop the app runs on a diary: read, add an entry, write, read again. A CRLF note must
/// end with one section, the same entries in the same order as its LF twin, and prose untouched.
@Test func aCRLFDiaryRoundTripKeepsOneSectionAndEveryEntryInOrder() {
    let lf = "---\ndate: 2026-09-29\n---\n\nProsa sopra.\n\n## Diario\n\n- 06:00-07:00 Palestra [colore:verde]\n"
        + "  Panca.\n\n  Corsa.\n- 09:00-11:30 Sopralluogo\n\n## Altro\n\ntesto dopo\n"
    let extra = DiaryEntry(startMinutes: 480, durationMinutes: 30, title: "Caffe", note: "uno\ndue")
    var lfNote = lf
    var crlfNote = crlf(lf)
    for _ in 0..<2 {
        let lfSplit = DiarySection.split(lfNote)
        let crlfSplit = DiarySection.split(crlfNote)
        lfNote = DiarySection.write(lfSplit.entries + [extra], into: lfSplit.prose)
        crlfNote = DiarySection.write(crlfSplit.entries + [extra], into: crlfSplit.prose)
        #expect(crlfNote == crlf(lfNote))
        #expect(crlfNote.components(separatedBy: "## Diario").count == 2)
        #expect(!crlfNote.replacingOccurrences(of: "\r\n", with: "").contains("\n"))
    }
    let after = DiarySection.split(crlfNote)
    let twin = DiarySection.split(lfNote)
    #expect(described(after.entries) == described(twin.entries))
    // Sorted by start; the added entry is present once per write, never dropped or reordered.
    #expect(after.entries.map(\.timeText) == after.entries.map(\.timeText).sorted())
    #expect(after.entries.filter { $0.title == "Palestra" }.count == 1)
    // Prose outside the section is byte-identical after the trip.
    #expect(crlfNote.hasPrefix("---\r\ndate: 2026-09-29\r\n---\r\n\r\nProsa sopra.\r\n"))
    #expect(crlfNote.contains("\r\n## Altro\r\n\r\ntesto dopo\r\n"))
}
