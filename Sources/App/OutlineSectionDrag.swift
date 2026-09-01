import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// The uniform type a dragged Outline row's payload is exported under, declared the same
/// way `VaultItemDrag` declares `it.stefer.pergamenum.vault-item`
/// (`Sources/App/VaultItemDrag.swift`) — for real in `Project.swift`'s
/// `UTExportedTypeDeclarations`, or the runtime identifier is a synthesized `dyn.` string.
extension UTType {
    static let pergamenumOutlineSection = UTType(
        exportedAs: "it.stefer.pergamenum.outline-section", conformingTo: .data
    )
}

/// One dragged Outline heading row (PG-019): which note it came from, and which entry in
/// that note's outline it names.
///
/// `notePath` guards against a drag started in one note's Outline landing in another's -
/// `OutlinePane` has no notion of "this row belongs to note X" beyond the note it was built
/// for, so the drop side checks it rather than trusting whatever `OutlinePane` happens to be
/// showing when the drop lands.
///
/// No `ProxyRepresentation`: unlike `VaultItemDrag` (ADR-0026 §D3), an Outline row has no
/// existing plain-string drop contract to stay compatible with.
struct OutlineSectionDrag: Codable, Transferable, Equatable {
    let notePath: String
    let entry: Int

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .pergamenumOutlineSection)
    }
}
