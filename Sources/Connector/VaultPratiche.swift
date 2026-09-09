import Foundation

/// Reading pratiche from outside the app (ADR-0036, SPEC "Connectors").
///
/// The same reasoning `VaultViews.swift` states for the query engine applies here:
/// `Sources/Core/Pratiche/**` is what makes this possible from a shell or a model, and
/// this file is thin on purpose - the shape of the answer, never a second copy of the
/// pratica-recognition or ordering rules.
///
/// **No `MailStore`/`EMLXReader`/`SQLite3` name may ever appear in this file** (R-36,
/// the structural half `Tests/SharedSourcesPurityTests.swift`'s Task 5 case checks):
/// a connector answers from whatever a sync already wrote to disk, never by opening
/// the Mail store or triggering one itself - TCC would attribute that access to the
/// terminal or the MCP client, not to Pergamenum.
extension VaultAPI {
    /// Every pratica of `session`'s vault (SPEC "Connectors": `pratiche` →
    /// `[{ path, title, client, status, counterparts, lastActivity, messageCount,
    /// trayCount }]`).
    ///
    /// RED stub (tester-declared boundary, ADR-0155 §D1): the coder mirrors
    /// `PraticheController.listItems`'s own algorithm here - reading `Dossier.parse`
    /// over every `pratica.md` the index knows about, `MessageDocument.parse` (or
    /// just a file count) over each folder's `email/*.md`, and
    /// `PraticaLedger.load(from:)` for `trayCount` - rather than calling that type
    /// directly, since `Sources/Features/Pratiche/PraticheController.swift` imports
    /// AppKit and is not in `sharedSources` (CLAUDE.md "AI connector"). Always empty
    /// for now, which is wrong-but-compiling: every positive assertion in
    /// `Tests/PraticheConnectorTests.swift` is genuinely red until the coder fills
    /// this in, while the structural "never touches Mail" half is already true of an
    /// empty array.
    @MainActor
    static func pratiche(_ session: VaultSession) -> [PraticaSummary] {
        []
    }

    /// Resolves `reference` - a pratica's folder path, or its title (the folder's own
    /// last path component) - and answers with its timeline as ordered entries (SPEC
    /// "Connectors": `pratica <title|path>` → `{ kind, date, direction, from, subject,
    /// attachments, body }`, plus the CLI's own printed transcript, which `perg`'s
    /// front end builds from this same payload).
    ///
    /// "Resolution of the argument reuses `VaultLookup`'s existing title/path rules"
    /// (SPEC) names the shape `VaultLookup.task(_:matching:)` already has for a task
    /// phrase: an exact `path:` match short-circuits everything else, and otherwise a
    /// title match that resolves to more than one pratica is refused rather than
    /// guessed at (the same ambiguity report `task(_:matching:)` gives, adapted from
    /// tasks to pratica folders).
    ///
    /// RED stub (ADR-0155 §D1): always throws, never touching a real pratica folder -
    /// the coder reads `pratica.md` plus `email/*.md`, ordered ascending the same way
    /// `PraticaTimelineModel.sortDate(of:)` orders the app's own timeline (that type
    /// is not shared either, so the ordering rule is reproduced here rather than
    /// called).
    @MainActor
    static func pratica(_ session: VaultSession, _ reference: String) throws -> PraticaTimelinePayload {
        throw ConnectorError("non implementato")
    }
}
