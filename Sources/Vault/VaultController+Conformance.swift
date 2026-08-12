import Foundation

/// The linter of SPEC §4.7, as the conformance view asks it.
///
/// Reads the file rather than trusting the index: the linter's whole job is to report
/// what is on disk, and a stale index row would call a note clean after someone edited
/// it in Obsidian.
extension VaultController {
    /// Validates any note in the vault by path, for the vault-wide conformance view.
    ///
    /// Reads the file rather than trusting the index: the linter's whole job is to
    /// report what is on disk, and a stale index row would report a note as clean
    /// after someone edited it in Obsidian.
    func violations(forRecordAt relativePath: String) -> NoteViolations? {
        guard let root,
              let (_, text) = try? NoteStore(root: root).read(relativePath)
        else { return nil }
        return violations(
            path: relativePath,
            title: NoteName.title(fromFileName: (relativePath as NSString).lastPathComponent),
            text: text
        )
    }

    /// Validates the open note against every convention rule, for the conformance view.
    func violations(for note: OpenNote) -> NoteViolations {
        violations(path: note.relativePath, title: note.title, text: note.text)
    }

    func violations(path: String, title: String, text: String) -> NoteViolations {
        let document = NoteDocument.parse(text)
        let category = NoteName.category(
            forFileName: (path as NSString).lastPathComponent,
            dailyFolder: settings.dailyFolder,
            path: path
        )
        let discrepancies = RelatedSection.discrepancies(
            frontmatterRelated: document.frontmatter.related,
            sectionLinks: RelatedSection.parse(from: document.body)
        )
        // A daily note is judged by its own naming rule: `20260811` would fail the
        // ordinary title check for looking like a version-less date, and passing it
        // through `validate` would report every daily note as non-conformant.
        let nameViolations = category == .daily
            ? NoteName.validateDaily(title)
            : NoteName.validate(title)

        return NoteViolations(
            name: nameViolations,
            frontmatter: FrontmatterRules.validate(document),
            tags: TagRules.validate(document.frontmatter.tags, category: category, vocabulary: vocabulary),
            relatedMissingInSection: discrepancies.missingInSection,
            relatedMissingInFrontmatter: discrepancies.missingInFrontmatter
        )
    }
}
