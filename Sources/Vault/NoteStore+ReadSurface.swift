import Foundation

// ADR-0041 (vault layer consistency and security), plan
// docs/superpowers/plans/2026-09-12-vault-layer-consistency-and-security-cha.md, Task 6 -
// R-05: "A read parses once, stats once, and a caller that wants the text asks for the
// text" (ADR §D7).
//
// **Tester-only signature declaration (ADR-0155).** These three members are the surface
// `Tests/NoteStoreReadTests.swift` and Task 8's actor need to compile against. None of
// them do the single-parse work the ADR describes - each returns a value that cannot
// match what `read` derives for a real note, deliberately, so the tests exercising them
// stay red until the coder replaces the body. `read` itself is untouched here: it still
// parses `NoteDocument` twice (once directly, once inside `Self.linkTargets(in:)`), which
// is exactly the double-parse this task removes.
extension NoteStore {
    /// Not yet the boundary-checked, no-parse, no-hash read the ADR asks for - a
    /// placeholder so callers and the test file compile.
    func text(_ relativePath: String) throws -> String {
        ""
    }

    /// Not yet real: the coder inverts this so `linkTargets(in text:)` below becomes the
    /// two-line wrapper and this parses the document that was handed to it, once. Returns
    /// no targets so `linkTargets(in text:)`/`linkTargets(in document:)` disagree on any
    /// note that has a link, until it does.
    static func linkTargets(in document: NoteDocument) -> [String] {
        []
    }

    /// Not yet real: the coder derives every field `read` computes today from the bytes
    /// and attributes a caller already has, and re-expresses `read` in terms of this.
    /// Returns a record that cannot equal `read`'s own for any real note.
    func record(from data: Data, attributes: [FileAttributeKey: Any], at relativePath: String) throws -> NoteRecord {
        NoteRecord(
            relativePath: relativePath,
            title: "",
            frontmatter: .empty,
            linkTargets: [],
            embedTargets: [],
            tasks: [],
            modifiedAt: .distantPast,
            byteSize: 0,
            contentHash: ""
        )
    }
}
