import Foundation
import UniformTypeIdentifiers

/// How an embed reads (ADR-0087 §D9): drawn as a picture, as a chip, or as a transclusion. Decided
/// from the target's name alone, never by opening the file: this is a question about what the
/// editor draws, not one `Attachment` (Core) needs an opinion on.
enum EmbedPresentation: Equatable, Sendable {
    case drawn, chip, transclusion

    /// A note is a transclusion wherever it is written; a picture or a PDF on a line of its own is
    /// drawn; anything else, or any file inside a line of prose, is a chip.
    static func of(target: String, isWholeLine: Bool) -> EmbedPresentation {
        if Transclusion.isNoteReference(target) { return .transclusion }
        return isWholeLine && isDrawable(target) ? .drawn : .chip
    }

    /// Whether `name`'s extension names a picture or a PDF (ADR-0018 D3).
    static func isDrawable(_ name: String) -> Bool {
        guard let type = UTType(filenameExtension: (name as NSString).pathExtension) else { return false }
        return type.conforms(to: .image) || type.conforms(to: .pdf)
    }

    /// The SF Symbol a chip draws before the name: a PDF, a picture, anything else.
    static func symbolName(forTarget target: String) -> String {
        let type = UTType(filenameExtension: (target as NSString).pathExtension)
        if type?.conforms(to: .pdf) == true { return "doc.richtext" }
        if type?.conforms(to: .image) == true { return "photo" }
        return "doc"
    }
}
