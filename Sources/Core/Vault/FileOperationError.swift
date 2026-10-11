import Foundation

enum FileOperationError: Error, CustomStringConvertible {
    case invalidTitle([NoteName.Violation])
    case alreadyExists(String)
    case missing(String)
    case failed(String)
    /// ADR-0026 §D1/§D5 - the destination is the folder itself or one of its own
    /// descendants. Never constructed by `NoteFileOperations`/`BoardFileOperations`.
    case wouldNest(String)

    var description: String {
        switch self {
        // Worded as `ConformanceText` words a note title, never the array interpolated: that
        // reads as a debugger dump of `NoteName.Violation`, and this sentence reaches a person
        // through every caller that prints the error.
        case .invalidTitle(let violations):
            ConformanceText.lines(NoteViolations(name: violations)).joined(separator: "; ")
        case .alreadyExists(let path): "esiste già: \(path)"
        case .missing(let path): "non esiste: \(path)"
        case .failed(let reason): reason
        case .wouldNest(let path): "\(path) non può essere spostata dentro sé stessa"
        }
    }
}
