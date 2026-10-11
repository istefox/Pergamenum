import Foundation

// ADR-0083 §D7 (PG-386, N3 session B).

/// What the Cmd+hover preview shows for a destination (ADR-0083 §D7), decided without a view.
struct LinkPreviewContent: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case note(title: String, lines: [String], missingSection: String?)
        case board(name: String)
        case ambiguous(title: String, folders: [String])
        case missing(title: String, creatable: Bool)
    }

    let kind: Kind
    /// True when a note's body ran past `lineLimit` and was cut there, so the view fades the last
    /// line only then: a note of exactly twelve lines shows them all and fades nothing.
    let isCut: Bool

    init(kind: Kind, isCut: Bool = false) {
        self.kind = kind
        self.isCut = isCut
    }

    /// The most body lines a note's preview carries.
    static let lineLimit = 12

    /// A note: its title and the opening lines of its body, or of the named section through
    /// `Transclusion.excerpt(of:section:)`, the function that decides what a transclusion shows;
    /// a section no heading answers to is named instead. A board: its name. Several notes: their
    /// folder labels, never their text. No note: the title and whether it can be created. A board
    /// name nothing answers to has no preview, and neither has a note that cannot be read.
    static func make(
        for destination: LinkDestination, section: String?, noteText: (String) -> String?
    ) -> LinkPreviewContent? {
        switch destination {
        case .note(let path):
            guard let text = noteText(path) else { return nil }
            let title = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
            let note = noteKind(title: title, text: text, section: section)
            return LinkPreviewContent(kind: note.kind, isCut: note.isCut)
        case .board(let path):
            let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
            return LinkPreviewContent(kind: .board(name: name))
        case .ambiguous(let title, let paths):
            return LinkPreviewContent(kind: .ambiguous(title: title, folders: paths.map(LinkChoice.folderLabel(of:))))
        case .missing(let title, let creatable):
            return LinkPreviewContent(kind: .missing(title: title, creatable: creatable))
        case .missingBoard:
            return nil
        }
    }

    private static func noteKind(title: String, text: String, section: String?) -> (kind: Kind, isCut: Bool) {
        let section = section.flatMap { $0.isEmpty ? nil : $0 }
        guard let excerpt = Transclusion.excerpt(of: text, section: section) else {
            // `excerpt` answers nil only for a section no heading answers to.
            return (.note(title: title, lines: [], missingSection: section), false)
        }
        var lines = excerpt.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        // A section's excerpt starts with its own heading, which the preview's title names instead:
        // «Nota › Sezione», as the approved mockup draws it.
        if section != nil, !lines.isEmpty { lines.removeFirst() }
        let isBlank: (String) -> Bool = { $0.trimmingCharacters(in: .whitespaces).isEmpty }
        var body = Array(lines.drop(while: isBlank))
        while let last = body.last, isBlank(last) { body.removeLast() }
        var opening = Array(body.prefix(lineLimit))
        while let last = opening.last, isBlank(last) { opening.removeLast() }
        let shown = section.map { "\(title) › \($0)" } ?? title
        return (.note(title: shown, lines: opening, missingSection: nil), body.count > lineLimit)
    }
}
