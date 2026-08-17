import AppKit
import SwiftUI

/// Markdown source with the editor's style applied, as an `NSAttributedString`.
///
/// Extracted from `NoteTextView.Coordinator`, which held it privately and could therefore
/// style only the note that is open. A transcluded note drawn in the editor (ADR-0010 §D3)
/// is the same markdown styled the same way, and two stylings of the same syntax that did
/// not share this code would drift - the same argument that moved the block rendering into
/// `MarkdownBlocksView`.
///
/// Not in `Core`: it needs `Theme` and AppKit, and `Sources/Core/**` is compiled by the two
/// command-line tools, which have neither (ADR-0001 §D1).
enum MarkdownAttributedText {
    /// The editor's base attributes: everything else is applied on top of these.
    static func base(theme: Theme) -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor(theme.color(.textPrimary)),
        ]
    }

    /// A whole note, styled.
    ///
    /// `links` is false for text that is drawn rather than edited: a transcluded note is a
    /// picture of another file, and a link attribute inside it would offer a click the text
    /// view cannot route, since the characters under it belong to no note it has open.
    static func attributed(_ text: String, theme: Theme, links: Bool = true) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: base(theme: theme))
        let length = (text as NSString).length
        for styled in MarkdownStyler.spans(in: text) {
            let range = NSRange(styled.range, in: text)
            guard range.location != NSNotFound, NSMaxRange(range) <= length else { continue }
            result.addAttributes(attributes(for: styled.span, theme: theme, links: links), range: range)
        }
        return result
    }

    /// The spans that need more than a colour: a font, a background, a link.
    ///
    /// Everything else falls to `colorToken(for:)`, and the `default` here is safe for the
    /// reason that switch has no default of its own: a span added later reaches it and the
    /// compiler asks what colour it is.
    static func attributes(
        for span: MarkdownStyler.Span,
        theme: Theme,
        links: Bool = true
    ) -> [NSAttributedString.Key: Any] {
        switch span {
        case .heading(let level):
            [
                .font: NSFont.systemFont(ofSize: max(15, 24 - CGFloat(level) * 2), weight: .semibold),
                .foregroundColor: NSColor(theme.color(.textPrimary)),
            ]
        case .bold:
            [.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)]
        case .italic:
            [.obliqueness: 0.2]
        case .codeBlock:
            // Only a background. The colour is left to whatever the grammar found inside,
            // and to `textPrimary` where it found nothing - a fence in a language nobody
            // wrote a grammar for still reads as code because of this.
            [.backgroundColor: NSColor(theme.color(.surfaceSunken))]
        case .linkTarget(let target):
            clickable(theme.color(.accentPrimary), url: links ? noteURL(for: target) : nil)
        case .embedTarget(let target):
            clickable(theme.color(.accentPrimary), url: links ? embedURL(for: target) : nil)
        default:
            [.foregroundColor: NSColor(theme.color(colorToken(for: span)))]
        }
    }

    private static func clickable(_ color: Color, url: URL?) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor(color)]
        if let url {
            attributes[.link] = url
            attributes[.cursor] = NSCursor.pointingHand
        }
        return attributes
    }

    /// Every span's colour, the six above included even though they never arrive here.
    /// No `default`, on purpose: this is the one table that must stay exhaustive.
    static func colorToken(for span: MarkdownStyler.Span) -> ColorToken {
        switch span {
        case .heading, .bold, .italic, .codeBlock: .textPrimary
        case .frontmatter, .code, .annotation: .textSecondary
        case .linkSyntax: .textTertiary
        case .tag, .linkTarget, .embedTarget: .accentPrimary
        case .codeToken(let token): token.colorToken
        case .taskMarker(let done): done ? .taskDone : .taskOpen
        case .scheduled: .taskScheduled
        case .due: .taskOverdue
        }
    }

    // MARK: Links

    static let embedHost = "embed"

    /// Encodes the target as a query item so a title containing `/`, `?` or `#` survives
    /// the round-trip through `URL`.
    static func noteURL(for target: String) -> URL {
        url(host: "note", item: URLQueryItem(name: "title", value: target))
    }

    /// The same trick for an embedded file. A different host, because the click leads
    /// somewhere else: a file to preview rather than a note to open.
    static func embedURL(for target: String) -> URL {
        url(host: embedHost, item: URLQueryItem(name: "name", value: target))
    }

    private static func url(host: String, item: URLQueryItem) -> URL {
        var components = URLComponents()
        components.scheme = AppInfo.urlScheme
        components.host = host
        components.queryItems = [item]
        return components.url ?? URL(string: "\(AppInfo.urlScheme)://\(host)")!
    }
}
