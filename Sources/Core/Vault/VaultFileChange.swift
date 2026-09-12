import Foundation

/// One file's text before and after a change that has not been written yet.
///
/// The shared replacement for `NoteFileOperations.FileChange` (ADR-0041 §D4): a plan and the
/// performer that later applies it agree on exactly what changed, the same triple `renamePlan`
/// already computes and `rename`/`renameFolder`/`renameBoard`/`moveBoard` each write from their
/// own hand-copied loop today. Carries the same three fields, with the same names, as the type it
/// replaces - so the call sites repointed onto it changed spelling only, not meaning. No
/// typealias was left behind for the old name (§D4): a type with two names is a type a future
/// reader has to check twice.
struct VaultFileChange: Equatable, Sendable {
    let path: String
    let before: String
    let after: String
}
