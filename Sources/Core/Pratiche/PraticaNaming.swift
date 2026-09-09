import Foundation

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 3 - R-01,
// R-08.

/// The file and tag names a pratica's own files and client folder use.
///
/// Reuses `ImportNaming.kebabCase`/`canonicalCounterparty`/`uniqueFileName` and adds
/// nothing to `ImportNaming` itself (this task's own instruction) - naming.md's rules
/// are the same rules, only the shape of the final name differs.
enum PraticaNaming {
    /// `YYYYMMDD_HHMM_<Controparte>_<oggetto-slug>.md` (R-08), extending
    /// `ImportNaming.emailFileName` with the `HHMM` component the SPEC's data model
    /// asks for - one counterpart can send several messages a day, and two files
    /// cannot share a name.
    ///
    /// Drops a leading `Re:`/`R:`/`Fwd:`/`I:`/`AW:` before slugging the subject, and
    /// caps the slug at 40 characters (R-08). No collision handling here - two
    /// messages that would otherwise share this exact name are told apart by
    /// `uniqueMessageFileName(...)`, since a same-`Message-ID` "collision" (a re-sync)
    /// is not a collision at all.
    ///
    /// Protected interface (`.claude/protected-interfaces`): re-import matches an
    /// existing message file by the name this derives, so a silent signature or
    /// behavior change orphans every message already on disk.
    static func messageFileName(
        date: CalendarDate,
        time: TaskTime,
        counterpart: String,
        subject: String
    ) -> String {
        // Coder-owned. Stubbed to the empty string so every shape assertion in
        // `Tests/PraticaNamingTests.swift` is red until it exists.
        ""
    }

    /// R-08's collision rule: a file that already carries the name `messageFileName`
    /// would produce is **not** a collision when its recorded `Message-ID` matches
    /// `messageID` - a re-sync of the same message - only a genuinely different
    /// `Message-ID` gets `-2`, `-3`.
    static func uniqueMessageFileName(
        date: CalendarDate,
        time: TaskTime,
        counterpart: String,
        subject: String,
        messageID: String,
        existing: [(fileName: String, messageID: String)]
    ) -> String {
        // Coder-owned.
        messageFileName(date: date, time: time, counterpart: counterpart, subject: subject)
    }

    /// `YYYYMMDD_<original-name-sanitised>` (SPEC "Attachment file name").
    static func attachmentFileName(date: CalendarDate, name: String) -> String {
        // Coder-owned.
        ""
    }

    /// R-01: the client is the pratica folder's own parent directory, relative to the
    /// configured Pratiche root - `"01 Progetti/Rossi/Offerta 2026"` under root
    /// `"01 Progetti"` has client `"Rossi"`. `nil` when `relativePath` is not under
    /// `root` at all, or has no parent folder below it.
    static func client(forPraticaAt relativePath: String, root: String) -> String? {
        // Coder-owned.
        nil
    }

    /// The `client-<slug>` tag ADR §D11 puts in `pratica.md`'s frontmatter, derived
    /// from `client(forPraticaAt:root:)` through the same `ImportNaming.kebabCase`
    /// every other slug in this app uses.
    static func clientTag(forPraticaAt relativePath: String, root: String) -> Tag? {
        guard let client = client(forPraticaAt: relativePath, root: root) else { return nil }
        return Tag("client-\(ImportNaming.kebabCase(client))")
    }
}
