import Foundation

// ADR-0072 §D8, plan docs/plans/pg-138-pg-141-pg-142-performance-debt.md, Task 5 - R-11.
//
// A counterpart used to cost one statement for its conversation ids plus two per conversation
// (the rows, then their recipients). Here the ids go into `IN` lists of at most `batchSize`, so it
// costs two statements per batch instead, whatever a batch holds. The order is the one
// `messages(inConversation:)` always answered, made explicit: `date_sent`, then `ROWID` for two
// messages sent in the same second (pinned by `Tests/MailStoreReaderOrderPinTests.swift`), and a
// message's recipients in row order. Foundation only, like the rest of `Sources/Core/Email`: both
// connectors compile this file.

extension MailStoreReader {
    /// Every non-deleted message of each conversation in `ids`, keyed by conversation id, in
    /// `date_sent` then `ROWID` order (R-03). A conversation with no message has no key. An empty
    /// `ids` runs no statement.
    func messages(inConversations ids: [Int]) -> [Int: [MailMessageRow]] {
        var seen = Set<Int>()
        let unique = ids.filter { seen.insert($0).inserted }
        var byConversation: [Int: [MailMessageRow]] = [:]
        var start = unique.startIndex
        while start < unique.endIndex {
            let end = min(start + max(batchSize, 1), unique.endIndex)
            for (conversation, rows) in batch(Array(unique[start..<end])) {
                byConversation[conversation] = rows
            }
            start = end
        }
        return byConversation
    }

    /// One chunk: one statement for the rows, one for their recipients.
    private func batch(_ ids: [Int]) -> [Int: [MailMessageRow]] {
        let list = Self.placeholders(count: ids.count)
        let bind: (OpaquePointer) -> Void = { statement in
            for (offset, id) in ids.enumerated() {
                connection.bindInt(statement, Int32(offset + 1), id)
            }
        }
        let sql = """
        \(Self.rowSelect)
        WHERE m.conversation_id IN (\(list)) AND m.deleted = 0
        ORDER BY m.date_sent, m.ROWID
        """
        let found = (try? rows(sql, bind: bind)) ?? []
        let recipientsByMessage = recipients(inList: list, bind: bind)

        var byConversation: [Int: [MailMessageRow]] = [:]
        for var row in found {
            // Never nil here: the row matched `conversation_id IN (…)`.
            guard let conversation = row.conversationID else { continue }
            row.recipients = recipientsByMessage[row.rowID] ?? []
            byConversation[conversation, default: []].append(row)
        }
        return byConversation
    }

    /// ADR-0036 §D24.2's recipients join, for every message of a chunk's conversations, in row
    /// order. Fails closed (§D24.4): a statement that cannot be prepared, e.g. a store without a
    /// `recipients` table, answers "no recipients" for everyone rather than throwing.
    private func recipients(inList list: String, bind: (OpaquePointer) -> Void) -> [Int: [String]] {
        let sql = """
        SELECT r.message, a.address
        FROM recipients AS r
        JOIN addresses AS a ON a.ROWID = r.address
        JOIN messages AS m ON m.ROWID = r.message
        WHERE m.conversation_id IN (\(list))
        ORDER BY r.ROWID
        """
        let rows = (try? collect(sql, bind: bind) { statement -> (Int, String)? in
            guard let message = connection.columnInt(statement, 0),
                  let address = connection.columnText(statement, 1)
            else { return nil }
            return (message, address.lowercased())
        }) ?? []

        var byMessage: [Int: [String]] = [:]
        for (message, address) in rows {
            byMessage[message, default: []].append(address)
        }
        return byMessage
    }

    /// `?1, ?2, …, ?count`.
    private static func placeholders(count: Int) -> String {
        (1...count).map { "?\($0)" }.joined(separator: ", ")
    }
}
