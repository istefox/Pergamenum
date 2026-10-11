import Foundation

// ADR-0083 §D5 (PG-386, N3 session A).

/// One row of the choice a shared title or a dangling link puts in front of the person.
///
/// The catalogue is rendered on two surfaces, a menu at the click and `LinkChoiceSheet`; both
/// draw these values, so the rows cannot differ between them.
struct LinkChoice: Equatable, Sendable, Identifiable {
    enum Action: Equatable, Sendable {
        case open(path: String)
        case create(title: String)
    }

    let id: String
    let label: String
    let detail: String
    let action: Action

    static let rootLabel = "radice del vault"

    /// One row per path of an ambiguous title, labelled by its folder; one «Crea «X»» row for a
    /// creatable dangling link; nothing for any other destination, which is not a choice.
    static func entries(for destination: LinkDestination) -> [LinkChoice] {
        switch destination {
        case .ambiguous(_, let paths):
            return paths.map { path in
                LinkChoice(id: "open:\(path)", label: folderLabel(of: path), detail: path, action: .open(path: path))
            }
        case .missing(let title, creatable: true):
            return [LinkChoice(
                id: "create:\(title)", label: "Crea «\(title)»", detail: "", action: .create(title: title)
            )]
        case .note, .board, .missing, .missingBoard:
            return []
        }
    }

    /// The vault-relative folder of a note, or `rootLabel` for a note at the root.
    static func folderLabel(of path: String) -> String {
        let folder = (path as NSString).deletingLastPathComponent
        return folder.isEmpty ? rootLabel : folder
    }
}
