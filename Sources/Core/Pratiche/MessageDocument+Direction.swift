import Foundation

extension MessageDocument {
    /// R-12: `sent` iff `from` is one of `ownAddresses` (case-insensitive) - **never**
    /// derived from the mailbox, so an archived sent message still counts as sent.
    static func direction(from: EmailAddress?, ownAddresses: Set<String>) -> Direction {
        guard let from, isOwn(from, ownAddresses) else { return .received }
        return .sent
    }

    /// Addresses are compared case-insensitively: the domain is case-insensitive by
    /// RFC and no real mail server treats the local part otherwise, so a `Stefano@…`
    /// in a `To:` must not read as somebody else.
    private static func isOwn(_ address: EmailAddress, _ ownAddresses: Set<String>) -> Bool {
        let mine = Set(ownAddresses.map { $0.lowercased() })
        return mine.contains(address.address.lowercased())
    }

    /// R-12: the sender of a received message; for a sent one, the first `to`
    /// recipient not in `ownAddresses`, else the first `cc`.
    static func counterpart(
        direction: Direction,
        from: EmailAddress?,
        to: [EmailAddress],
        cc: [EmailAddress],
        ownAddresses: Set<String>
    ) -> EmailAddress? {
        switch direction {
        case .received:
            return from
        case .sent:
            // The first recipient who is not me. A message addressed only to myself
            // with the other side in copy still has a counterpart, which is why `cc`
            // is a fallback and not an afterthought.
            return to.first { !isOwn($0, ownAddresses) }
                ?? cc.first { !isOwn($0, ownAddresses) }
                ?? cc.first
        }
    }
}
