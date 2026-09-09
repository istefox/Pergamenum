import Foundation

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 1 - R-03.

/// Every member of one Mail `conversation_id`, as answered by
/// `MailStoreReader.conversations(counterpart:within:)` (R-03) - Mail's own threading,
/// which the pratica follows rather than reinventing (SPEC "Verified facts").
struct MailConversation: Equatable, Sendable {
    var conversationID: Int
    var messages: [MailMessageRow]
}
