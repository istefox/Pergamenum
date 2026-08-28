import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// The uniform type a dragged vault item's structured payload is exported under
/// (ADR-0026 §D3). Declared for real in `Project.swift`'s `infoPlist` under
/// `UTExportedTypeDeclarations` — Task 4's code step, not this file — so that
/// `UTType.pergamenumVaultItem.identifier` reads back this string rather than a
/// dynamically synthesized `dyn.` identifier at runtime. The Swift-side declaration
/// below compiles and this file's tests pass with no Info.plist entry at all; only the
/// runtime identifier itself depends on that entry landing.
extension UTType {
    static let pergamenumVaultItem = UTType(
        exportedAs: "it.stefer.pergamenum.vault-item", conformingTo: .data
    )
}

/// `VaultItemRef`/`VaultItemKind` (`Sources/Vault/VaultMoveBatch.swift`, Task 1) declare
/// no `Codable` conformance, and never needed one for their own purpose — `VaultMoveBatch
/// .plan` only ever compares them in memory. `VaultItemDrag` is the first thing that puts
/// one on a pasteboard, so the conformance is written here, by hand: Swift only
/// auto-synthesizes `Codable` when the conformance is declared in the same file as the
/// type's own declaration (verified: an empty `extension Foo: Codable {}` from a second
/// file fails to build with "extension outside of file declaring struct 'Foo' prevents
/// automatic synthesis of 'init(from:)'"), and `VaultMoveBatch.swift` is Task 1's file,
/// not this one's.
extension VaultItemKind: Codable {
    private enum Coded: String, Codable {
        case note, board, folder
    }

    init(from decoder: Decoder) throws {
        switch try decoder.singleValueContainer().decode(Coded.self) {
        case .note: self = .note
        case .board: self = .board
        case .folder: self = .folder
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .note: try container.encode(Coded.note)
        case .board: try container.encode(Coded.board)
        case .folder: try container.encode(Coded.folder)
        }
    }
}

extension VaultItemRef: Codable {
    private enum CodingKeys: String, CodingKey {
        case path, kind
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            path: try container.decode(String.self, forKey: .path),
            kind: try container.decode(VaultItemKind.self, forKey: .kind)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(path, forKey: .path)
        try container.encode(kind, forKey: .kind)
    }
}

/// One dragged row's payload (ADR-0026 §D3): the whole effective drag set, under a
/// structured, exported-UTType representation a folder row's `.dropDestination(for:
/// VaultItemDrag.self)` reads, and — on the very same pasteboard item — the plain name
/// `CompletingTextView.performDragOperation` has always read as a bare `String`
/// (`CompletingTextView+Pasteboard.swift:106-111`, SPEC §7.2 "collegamento assistito").
///
/// `dragName` for a note is `NoteRecord.title`, byte-identical to what `.draggable(note
/// .title)` puts on the pasteboard today (`NoteListPane.swift:197`) — never the relative
/// path, never a wrapped or prefixed string. `ProxyRepresentation(exporting: \.dragName)`
/// exports exactly this field with no further transformation, which is what lets this
/// chain add the structured representation without editing
/// `CompletingTextView+Pasteboard.swift` at all (R-09).
struct VaultItemDrag: Codable, Transferable, Equatable {
    /// The whole effective drag set (ADR-0026 §D4): every item this drag carries, in
    /// order.
    let items: [VaultItemRef]
    /// The note's title / the row's name — the §7.2 payload.
    let dragName: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .pergamenumVaultItem)
        ProxyRepresentation(exporting: \.dragName)
    }
}
