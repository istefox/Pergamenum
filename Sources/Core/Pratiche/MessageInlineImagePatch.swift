import Foundation

// ADR-0042 (Pratiche inline image placeholders) §D8: the retry that puts a resolved
// inline image back at its own placeholder, without a full re-render.

/// Patches a message note's placeholders and its `pergamenum-mail-inline-pending` line
/// when a sync resolves some or all of the inline images it was waiting for. Never
/// touches a placeholder unless the file's placeholder count matches the recorded
/// pending count exactly - a mismatch means somebody edited the prose, and a picture in
/// the wrong paragraph is a content error this repo does not accept on a probability
/// argument (ADR-0042 §D8).
enum MessageInlineImagePatch {
    /// What a fresh decode found for an inline image the note was still waiting for.
    enum Resolution: Equatable, Sendable {
        /// Placed in `allegati/`; its placeholder becomes `![[fileName]]`.
        case embedded(fileName: String)
        /// Usable and decorative (ADR-0040 §D9 item 1 order preserved): the placeholder
        /// goes, nothing replaces it.
        case dropped
    }

    struct Outcome: Equatable, Sendable {
        var text: String
        /// What `pergamenum-mail-inline-pending` becomes: the ids still waiting, in
        /// placeholder order.
        var remaining: [String]
        /// Resolved images whose placeholder could not be matched (a count mismatch),
        /// so they are linked as ordinary attachments instead of losing the picture.
        var unplaceable: [String]
    }

    /// `pending` is the note's own recorded list, in placeholder order; `resolved` maps
    /// a content id to what this sync found for it. `nil` only when `text` carries no
    /// `pergamenum-mail` frontmatter to patch.
    static func applying(
        resolved: [String: Resolution], pending: [String], to text: String
    ) -> Outcome? {
        guard !pending.isEmpty else { return Outcome(text: text, remaining: [], unplaceable: []) }

        let placeholderCount = occurrenceCount(of: MessageInlineImage.placeholder, in: text)
        guard placeholderCount == pending.count else {
            // Count mismatch: touch no placeholder. Every resolved id becomes
            // unplaceable (and drops from `remaining`); every id with no resolution
            // this sync stays pending exactly as it was (ADR-0042 §D7).
            var remaining: [String] = []
            var unplaceable: [String] = []
            for contentID in pending {
                switch resolved[contentID] {
                case .embedded(let fileName):
                    unplaceable.append(fileName)
                case .dropped:
                    continue
                case nil:
                    remaining.append(contentID)
                }
            }
            guard let patched = MessageFrontmatterPatch.applying(
                line: remaining.isEmpty ? nil : MessageDocument.inlinePendingLine(for: remaining),
                forKey: MessageDocument.inlinePendingKey,
                before: [MessageDocument.storeReferencesKey, "pergamenum-mail-body"],
                to: text
            ) else { return nil }
            return Outcome(text: patched, remaining: remaining, unplaceable: unplaceable)
        }

        // Counts match: the k-th placeholder in the file IS the k-th recorded id, by
        // construction - both were written together, in the same order, by
        // `MessageInlineImage.resolvingDeferralTokens` (ADR-0042 §D6).
        var remaining: [String] = []
        var patchedText = text
        var searchRange = patchedText.startIndex..<patchedText.endIndex
        for contentID in pending {
            guard let range = patchedText.range(
                of: MessageInlineImage.placeholder, range: searchRange
            ) else { break }
            switch resolved[contentID] {
            case .embedded(let fileName):
                patchedText.replaceSubrange(range, with: "![[\(fileName)]]")
                searchRange = patchedText.index(
                    range.lowerBound, offsetBy: "![[\(fileName)]]".count
                )..<patchedText.endIndex
            case .dropped:
                patchedText.removeSubrange(range)
                searchRange = range.lowerBound..<patchedText.endIndex
            case nil:
                remaining.append(contentID)
                searchRange = range.upperBound..<patchedText.endIndex
            }
        }

        guard let finalText = MessageFrontmatterPatch.applying(
            line: remaining.isEmpty ? nil : MessageDocument.inlinePendingLine(for: remaining),
            forKey: MessageDocument.inlinePendingKey,
            before: [MessageDocument.storeReferencesKey, "pergamenum-mail-body"],
            to: patchedText
        ) else { return nil }

        return Outcome(text: finalText, remaining: remaining, unplaceable: [])
    }

    private static func occurrenceCount(of substring: String, in text: String) -> Int {
        guard !substring.isEmpty else { return 0 }
        var count = 0
        var searchStart = text.startIndex
        while let range = text.range(of: substring, range: searchStart..<text.endIndex) {
            count += 1
            searchStart = range.upperBound
        }
        return count
    }
}
