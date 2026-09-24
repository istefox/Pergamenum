import Foundation

/// The types describing where the controller's day stands against its file (ADR-0057).
///
/// Declared here rather than inside the class for SwiftLint headroom; the stored
/// properties of these types, and every writer of them, stay in `DiaryController.swift`
/// under `private(set)`.
extension DiaryController {
    /// The two points of a diary write a test can hold on a gate (ADR-0057 §D9).
    enum DiaryWritePhase: Equatable {
        case willWrite
        case didWrite
    }

    /// Whether the day on screen is safely on disk (ADR-0057 §D6). `.pending` and
    /// `.conflicted` both mean it is not; only `.conflicted` stops the controller writing.
    enum SaveState: Equatable {
        case saved
        case pending
        case conflicted(reason: String)
    }

    /// Which file the controller's in-memory day was last read from, and what it held
    /// (ADR-0057 §D2) - mirrors `WorkspaceController`'s `BoardOrigin`. `file` names the
    /// vault too, not only the relative path, since this controller outlives a vault
    /// switch.
    enum DiaryOrigin: Equatable {
        case none
        case read(file: URL, disk: VaultSession.DiaryDiskState)

        /// What the write door checks the current write against - `.absent` when there
        /// is no recorded origin yet, exactly what a first write should expect.
        var disk: VaultSession.DiaryDiskState {
            switch self {
            case .none: .absent
            case .read(_, let disk): disk
            }
        }

        /// The file the day was read from; nil before any read.
        var file: URL? {
            switch self {
            case .none: nil
            case .read(let file, _): file
            }
        }
    }
}
