import Foundation

// ADR-0087 §D2 and §D10, plan docs/plans/note-workflow-n5.md, Task 1 (R-40, R-43).
//
// The caption a transclusion's source line is drawn as, read by the editor and by the export.
// Foundation only (ADR-0001 §D1).

enum TransclusionCaption {
    /// The note's name as the editor draws it, for a reference written as typed: `Cartella/Altra nota`
    /// names the note `Altra nota`, which is the title the editor resolves it to. A `.md` suffix is the
    /// file's, not the name's. The export has no index to resolve a title through, so it reads the name
    /// off the reference.
    static func name(ofReference reference: String) -> String {
        var name = reference.split(separator: "/", omittingEmptySubsequences: true).last.map(String.init) ?? reference
        if name.lowercased().hasSuffix(".md"), name.count > 3 { name.removeLast(3) }
        return name
    }

    /// `da «Nota» › Sezione`, or `da «Nota»` with no section.
    static func text(note: String, section: String?) -> String {
        guard let section, !section.isEmpty else { return "da «\(note)»" }
        return "da «\(note)» › \(section)"
    }
}
