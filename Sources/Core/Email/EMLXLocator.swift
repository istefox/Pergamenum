import Foundation

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 2 - §D4.

/// Locates the `.emlx` file for one row, with «not found» distinguished from «the
/// fan-out rule drifted» (ADR §D4) - the two must never be confused, or a locator bug
/// gets shown to the user as R-16's legitimate «non più in Mail».
enum EMLXLocator {
    enum LocateResult: Equatable, Sendable {
        /// The ordinary, complete container.
        case found(URL)
        /// Mail's headers-only form (`<ROWID>.partial.emlx`, ADR §D4 follow-up) - the
        /// caller writes a `pending` message (R-15), never «non più in Mail».
        case foundPartial(URL)
        /// Neither form exists anywhere this locator looked - a message genuinely
        /// gone from Mail (R-16).
        case notInStore
        /// The predicted path (and its `.partial.emlx` sibling) missed, and the
        /// bounded enumeration this case triggers found nothing either - a rule that
        /// has drifted, reported as a diagnostic rather than shown as R-16's caption.
        case ruleFailed(candidatesTried: [String])
        /// The fallback walk could not answer either way (ADR-0067 §D7): the budget
        /// ran out before covering the tree, or a
        /// subdirectory could not be read. Neither `.notInStore` (R-16's «non più in
        /// Mail») nor `.ruleFailed` (a drifted rule) is honest here - the caller
        /// records the lookup as indeterminate instead of concluding either.
        case indeterminate(Reason)

        enum Reason: Equatable, Sendable {
            case budgetExhausted
            case unreadable
        }
    }

    /// `predictedURL` is `MailStoreReader.emlxPath(forRow:)`'s answer (the digit-fan
    /// rule, reused rather than re-derived here) - `nil` when the mailbox url could
    /// not even be turned into a directory.
    ///
    /// On a miss at the predicted path (and its `.partial.emlx` sibling), this
    /// enumerates that mailbox's `Messages/` directories once, bounded, cached per
    /// mailbox for the caller's lifetime (ADR §D4) - the cache itself is the coder's
    /// concern; this signature takes the one predicted candidate a unit test can
    /// build without a live store.
    /// `enumerationBudget` (ADR-0067 §D7): defaulted to `defaultEnumerationBudget`, so
    /// every existing call compiles unchanged and a test can exhaust it with a tiny
    /// tree. A walk that exhausts it, or that met a directory it could not read and
    /// found nothing, is `.indeterminate`; only a complete walk of a readable `Data/`
    /// directory that found nothing is `.notInStore`.
    static func locate(
        predictedURL: URL?,
        fileManager: FileManager = .default,
        enumerationBudget: Int = defaultEnumerationBudget
    ) -> LocateResult {
        // No predicted path at all means the mailbox url never became a directory:
        // nothing was looked at, so this is the drifted-rule diagnostic and never
        // R-16's «non più in Mail».
        guard let predictedURL else { return .ruleFailed(candidatesTried: []) }

        var tried: [String] = []
        let partialURL = partial(of: predictedURL)
        for candidate in [predictedURL, partialURL] {
            let path = candidate.path(percentEncoded: false)
            tried.append(path)
            guard fileManager.fileExists(atPath: path) else { continue }
            return candidate == predictedURL ? .found(candidate) : .foundPartial(candidate)
        }

        // The fan-out rule may have drifted (ADR §D4): enumerate this mailbox's
        // `Data/**/Messages/` directories once, looking for the same file name
        // anywhere under it. Bounded, so a store with a pathological tree cannot turn
        // one miss into a full-disk walk.
        guard let dataDirectory = ancestor(named: "Data", of: predictedURL) else {
            return .ruleFailed(candidatesTried: tried)
        }
        let wanted = Set([predictedURL.lastPathComponent, partialURL.lastPathComponent])
        guard fileManager.fileExists(atPath: dataDirectory.path(percentEncoded: false)) else {
            return .ruleFailed(candidatesTried: tried + [dataDirectory.path(percentEncoded: false)])
        }
        switch enumerate(
            under: dataDirectory, matching: wanted, fileManager: fileManager, budget: enumerationBudget
        ) {
        case .hit(let hit):
            return hit.lastPathComponent == predictedURL.lastPathComponent
                ? .found(hit)
                : .foundPartial(hit)
        case .completeMiss:
            // The enumeration ran to completion over a real, readable directory and
            // neither form is there: the message is genuinely gone, which is the one
            // state R-16's caption is allowed to describe.
            return .notInStore
        case .indeterminate(let reason):
            // ADR-0067 §D7: a walk cut short by its budget, or one that met a directory
            // it could not read, cannot tell "gone" from "somewhere it did not look".
            return .indeterminate(reason)
        }
    }

    /// `<ROWID>.emlx` → `<ROWID>.partial.emlx`, Mail's headers-only form (ADR §D4
    /// follow-up: 723 of them in one mailbox of the probed store).
    static func partial(of emlxURL: URL) -> URL {
        emlxURL
            .deletingLastPathComponent()
            .appending(
                path: "\(emlxURL.deletingPathExtension().lastPathComponent).partial.emlx",
                directoryHint: .notDirectory
            )
    }

    private static func ancestor(named name: String, of url: URL) -> URL? {
        var current = url.deletingLastPathComponent()
        while current.lastPathComponent != "", current.path(percentEncoded: false) != "/" {
            if current.lastPathComponent == name { return current }
            current = current.deletingLastPathComponent()
        }
        return nil
    }

    /// How many directory entries the fallback walk may visit before it gives up.
    /// A mailbox's `Data/` tree is a few thousand entries; a walk that has not found
    /// the file by then is walking something that is not a mail store.
    ///
    /// Not `private` (Task 3 declaration): `locate(predictedURL:fileManager:
    /// enumerationBudget:)`'s own default reads it, and a test drives a small budget
    /// through that parameter instead of touching this constant.
    static let defaultEnumerationBudget = 20_000

    /// What one fallback walk can honestly say (ADR-0067 §D7): it found the file, it
    /// walked everything readable and found nothing, or it could not finish the job.
    private enum Walk {
        case hit(URL)
        case completeMiss
        case indeterminate(LocateResult.Reason)
    }

    /// A directory the enumerator could not open is reported to `errorHandler`, which
    /// records it and keeps walking: a hit anywhere else still counts, but a miss over
    /// a tree with a hole in it is no longer a complete miss.
    private static func enumerate(
        under directory: URL,
        matching names: Set<String>,
        fileManager: FileManager,
        budget: Int
    ) -> Walk {
        var metUnreadable = false
        guard let walk = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in
                metUnreadable = true
                return true
            }
        ) else { return .indeterminate(.unreadable) }

        var visited = 0
        for case let url as URL in walk {
            visited += 1
            if visited > budget { return .indeterminate(.budgetExhausted) }
            if names.contains(url.lastPathComponent) { return .hit(url) }
        }
        return metUnreadable ? .indeterminate(.unreadable) : .completeMiss
    }
}
