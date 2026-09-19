import Foundation

/// One `deletingLastPathComponent()` off this file's own directory (`Tests/`) gives the
/// repository root. If the candidate does not contain a `Sources` directory, this throws
/// naming the path tried - it never skips silently.
///
/// A free function rather than a `static` on a suite, so a test file adopts it by deleting its
/// own copy: two of the seven this replaced were already free functions, and the other five
/// were `private static` on their own suite, which is why each file grew its own (ADR-0051 §D2).
func resolvedRepoRoot() throws -> URL {
    let candidateRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // RepoRootSupport.swift -> Tests/
        .deletingLastPathComponent() // Tests/ -> repository root
    guard FileManager.default.fileExists(atPath: candidateRoot.appendingPathComponent("Sources").path) else {
        throw RepoRootResolutionError.notFound(candidate: candidateRoot.path)
    }
    return candidateRoot
}

enum RepoRootResolutionError: Error, CustomStringConvertible {
    case notFound(candidate: String)

    var description: String {
        switch self {
        case let .notFound(candidate):
            return "Could not resolve the repository root from #filePath. Candidate tried: \(candidate)"
        }
    }
}
