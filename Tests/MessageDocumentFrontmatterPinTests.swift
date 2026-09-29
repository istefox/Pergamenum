import Foundation
import Testing
@testable import Pergamenum

// ADR-0072 §D9, plan docs/plans/pg-138-pg-141-pg-142-performance-debt.md, Task 1 - R-13.
//
// What `MessageDocument.parse` reads today, pinned before Task 5 reads the frontmatter in one
// pass and builds one date formatter per call: the first occurrence of a duplicated key wins, an
// indented line is skipped even when it carries a known key, whitespace before the colon and a
// value holding colons, the date with an offset and with `Z`, and a fractional `received` parsed
// right before one without fractions (a reused formatter must not carry the fractional option
// over). Each case also renders, parses and renders again byte-identically.

private let sentAt = Date(timeIntervalSince1970: 1_781_093_170)
private let receivedAt = Date(timeIntervalSince1970: 1_781_093_191)

private func pinDocument(subject: String = "Richiesta offerta", dateOffset: Int? = 7200) -> MessageDocument {
    MessageDocument(
        frontmatter: .init(
            schemaVersion: 1, messageID: "<pin@rossi-spa.it>", conversationID: 112_409, direction: .received,
            date: sentAt, dateOffset: dateOffset, received: receivedAt, from: "Mario Rossi <m.rossi@rossi-spa.it>",
            to: ["stefano@stefer.it"], cc: [], subject: subject, attachments: [], body: .complete, original: nil
        ),
        newText: "Corpo.", quotedHistory: nil, signature: nil
    )
}

private typealias NoteTag = Pergamenum.Tag

private func pinTags() throws -> [NoteTag] { [try #require(NoteTag("type-note"))] }

/// The rendered file with its frontmatter lines edited in place.
private func edited(_ text: String, _ transform: (inout [String]) -> Void) -> String {
    var lines = text.components(separatedBy: "\n")
    transform(&lines)
    return lines.joined(separator: "\n")
}

private func line(_ key: String, in lines: [String]) -> Int {
    lines.firstIndex { $0.hasPrefix("\(key):") } ?? lines.count
}

/// Render → parse → render is byte-identical for whatever `parse` made of `text`.
private func expectStableRender(of text: String) throws {
    let tags = try pinTags()
    let parsed = try #require(MessageDocument.parse(text))
    let first = MessageDocument.render(parsed, tags: tags)
    let reparsed = try #require(MessageDocument.parse(first))
    #expect(MessageDocument.render(reparsed, tags: tags) == first)
}

@Test func aDuplicatedKeyReadsItsFirstOccurrence() throws {
    let base = MessageDocument.render(pinDocument(), tags: try pinTags())
    let text = edited(base) { lines in
        lines.insert(#"pergamenum-mail-subject: "Secondo""#, at: line("pergamenum-mail-subject", in: lines) + 1)
        lines.insert(#"pergamenum-mail-from: "altro@x.it""#, at: line("pergamenum-mail-from", in: lines) + 1)
    }
    let parsed = try #require(MessageDocument.parse(text))
    #expect(parsed.frontmatter.subject == "Richiesta offerta")
    #expect(parsed.frontmatter.from == "Mario Rossi <m.rossi@rossi-spa.it>")
    try expectStableRender(of: text)
}

@Test func anIndentedLineIsSkippedEvenWhenItCarriesAKnownKey() throws {
    let base = MessageDocument.render(pinDocument(), tags: try pinTags())
    let text = edited(base) { lines in
        let from = line("pergamenum-mail-from", in: lines)
        lines.insert(#"  pergamenum-mail-subject: "Indentato""#, at: from + 1)
        lines.insert("\tpergamenum-mail-direction: sent", at: from + 1)
    }
    let parsed = try #require(MessageDocument.parse(text))
    #expect(parsed.frontmatter.subject == "Richiesta offerta")
    #expect(parsed.frontmatter.direction == MessageDocument.Direction.received)
    try expectStableRender(of: text)
}

@Test func whitespaceBeforeTheColonStillNamesTheKey() throws {
    let base = MessageDocument.render(pinDocument(), tags: try pinTags())
    let text = edited(base) { lines in
        let subject = line("pergamenum-mail-subject", in: lines)
        lines[subject] = #"pergamenum-mail-subject  : "Spaziato""#
    }
    let parsed = try #require(MessageDocument.parse(text))
    #expect(parsed.frontmatter.subject == "Spaziato")
    try expectStableRender(of: text)
}

@Test func aValueHoldingColonsIsReadWhole() throws {
    let base = MessageDocument.render(pinDocument(subject: "Re: Offerta: ore 10:30"), tags: try pinTags())
    let text = edited(base) { lines in
        lines.insert("pergamenum-mail-original: allegati/a:b:c.eml", at: line("pergamenum-mail-subject", in: lines) + 1)
    }
    let parsed = try #require(MessageDocument.parse(text))
    #expect(parsed.frontmatter.subject == "Re: Offerta: ore 10:30")
    #expect(parsed.frontmatter.original == "allegati/a:b:c.eml")
    try expectStableRender(of: text)
}

@Test(arguments: [7200, -18000, 19800, nil] as [Int?])
func theDateReadsBackWithItsOffset(_ offset: Int?) throws {
    let text = MessageDocument.render(pinDocument(dateOffset: offset), tags: try pinTags())
    let dateLine = try #require(text.components(separatedBy: "\n").first { $0.hasPrefix("pergamenum-mail-date:") })
    #expect(dateLine.hasSuffix("Z") == (offset == nil))
    let parsed = try #require(MessageDocument.parse(text))
    #expect(parsed.frontmatter.date == sentAt)
    #expect(parsed.frontmatter.dateOffset == offset)
    #expect(parsed.frontmatter.received == receivedAt)
    #expect(parsed == pinDocument(dateOffset: offset))
    try expectStableRender(of: text)
}

@Test func aFractionalReceivedParsedFirstDoesNotChangeTheNextOne() throws {
    let base = MessageDocument.render(pinDocument(), tags: try pinTags())
    let fractional = edited(base) { lines in
        lines[line("pergamenum-mail-received", in: lines)] = "pergamenum-mail-received: 2026-06-10T12:06:31.250Z"
    }
    let whole = edited(base) { lines in
        lines[line("pergamenum-mail-received", in: lines)] = "pergamenum-mail-received: 2026-06-10T12:06:31Z"
    }

    let first = try #require(MessageDocument.parse(fractional))
    let second = try #require(MessageDocument.parse(whole))
    let firstReceived = try #require(first.frontmatter.received)
    #expect(abs(firstReceived.timeIntervalSince1970 - (receivedAt.timeIntervalSince1970 + 0.25)) < 0.000_5)
    #expect(second.frontmatter.received == receivedAt)
    #expect(first.frontmatter.date == sentAt)
    #expect(second.frontmatter.date == sentAt)
    try expectStableRender(of: fractional)
    try expectStableRender(of: whole)
}
