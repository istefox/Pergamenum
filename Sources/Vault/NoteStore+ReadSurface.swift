import Foundation

// ADR-0041 (vault layer consistency and security), plan
// docs/superpowers/plans/2026-09-12-vault-layer-consistency-and-security-cha.md, Task 6 -
// R-05: "A read parses once, stats once, and a caller that wants the text asks for the
// text" (ADR §D7).
extension NoteStore {
    /// The boundary-checked, no-parse read a caller that only wants the body asks for -
    /// `perf-NoteStore.swift-ce3`'s finding was that the rename/search callers in
    /// `NoteFileOperations.swift` paid a full record derivation (parse, wikilink scan,
    /// transclusion scan, task parse, SHA-256) to get a `String` they then rewrite. No
    /// parse, no hash: the guard, the read, the UTF-8 decode, and nothing else.
    func text(_ relativePath: String) throws -> String {
        let fileURL = try url(for: relativePath)
        let data = try Data(contentsOf: fileURL)
        guard let text = NoteStore.decodedText(data) else {
            throw StoreError.notUTF8(relativePath)
        }
        return text
    }

    /// The real link-target scan, over a document already parsed once by the caller -
    /// `linkTargets(in text:)` (`NoteStore.swift`) is now the thin wrapper over this, not
    /// the other way round, which is what stops `read` from parsing `NoteDocument` twice
    /// (ADR-0041 §D7). Moved here unchanged from what `linkTargets(in text:)` used to
    /// compute inline.
    ///
    /// A board is not a note: a `.canvas` target - a task's `^[[Q4.canvas]]` marker, or a plain
    /// `[[Q4.canvas]]` - is never a link target, so it is no backlink, unresolved link, graph
    /// neighbour or `links` value (ADR-0064 §D9.5, R-20).
    static func linkTargets(in document: NoteDocument) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for link in WikilinkParser.links(in: document.body)
        where (!link.isEmbed || Transclusion.isNoteReference(link.target))
            && (link.target as NSString).pathExtension.lowercased() != "canvas" {
            if seen.insert(link.target).inserted { ordered.append(link.target) }
        }
        return ordered
    }

    /// Everything `read` derives, given the bytes and attributes a caller already has -
    /// `VaultSession.moveFile` (`VaultSession+Journal.swift`) and Task 8's write actor both
    /// need this shape, one hashing bytes it just moved on disk, the other bytes it hashed
    /// before hopping off the main actor. Decodes and parses once, then shares the same
    /// field-building code `read` uses via `NoteStore.makeRecord` (`NoteStore.swift`) - the
    /// two never build a `NoteRecord` two different ways.
    func record(from data: Data, attributes: [FileAttributeKey: Any], at relativePath: String) throws -> NoteRecord {
        guard let text = NoteStore.decodedText(data) else {
            throw StoreError.notUTF8(relativePath)
        }
        let document = NoteDocument.parse(text)
        return NoteStore.makeRecord(
            from: data, text: text, document: document, attributes: attributes, at: relativePath
        )
    }
}
