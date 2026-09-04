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
    ///
    /// The face is `font.prose` and not the monospaced 13pt this carried until ADR-0030 §D2:
    /// the page and the interface are different things, and a note read as a code buffer was
    /// the whole of what that chain set out to fix. The paragraph style is set here for the
    /// same reason — `applyStyling` rewrites every attribute on each keystroke, so the line
    /// height has to arrive with the base rather than be applied once and wiped (R-07).
    static func base(theme: Theme) -> [NSAttributedString.Key: Any] {
        [
            .font: ProseTypography.prose(theme),
            .foregroundColor: NSColor(theme.color(.textPrimary)),
            .paragraphStyle: ProseTypography.paragraphStyle(theme),
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
                .font: ProseTypography.heading(level: level, theme),
                .foregroundColor: NSColor(theme.color(.textPrimary)),
            ]
        case .bold:
            [.font: ProseTypography.proseBold(theme)]
        case .italic:
            // The prose family's own italic face where it has one, `[.obliqueness: 0.2]` on
            // the upright face where it does not (ADR-0030 §D6) - the blanket obliqueness this
            // used to return is a slanted roman, which is what the page stops looking like.
            ProseTypography.proseItalicAttributes(theme)
        case .strikethrough:
            // A line through the whole run, markers included - true of strikethrough, which
            // is what SPEC §5's styled source means for this span. It is not universal any
            // more: ADR-0018 narrows it for three cases across its three slices (headings,
            // emphasis, and the image/PDF embed), and strikethrough is not one.
            [.strikethroughStyle: NSUnderlineStyle.single.rawValue]
        case .codeBlock:
            // A background and the mono face. The *colour* is still left to whatever the
            // grammar found inside, and to `textPrimary` where it found nothing - a fence in
            // a language nobody wrote a grammar for still reads as code because of this.
            //
            // The face has to be named here since ADR-0030 §D2: with the base now `font.prose`
            // there is no longer an incidental monospaced background for code to inherit, so
            // every code-carrying span asks for `font.mono` explicitly (R-02).
            [
                .font: ProseTypography.mono(theme),
                .backgroundColor: NSColor(theme.color(.surfaceSunken)),
            ]
        case .code, .frontmatter, .codeToken:
            // `.codeBlock`'s reasoning, for the spans that used to fall through to `default`
            // and take a colour alone. The colour each of them already had is unchanged - it
            // still comes from the one exhaustive table below.
            [
                .font: ProseTypography.mono(theme),
                .foregroundColor: NSColor(theme.color(colorToken(for: span))),
            ]
        case .linkTarget(let target):
            clickable(theme.color(.accentPrimary), url: links ? noteURL(for: target) : nil)
        case .embedTarget(let target):
            // Where the click goes depends on what the target is, by the same rule the
            // reading view uses (ADR-0010 §D2): a note opens, a file is previewed. Sending
            // every `![[…]]` to the file preview is the editor's half of PG-020 - it
            // answered "file non trovato nel vault" for a note that exists.
            clickable(
                theme.color(.accentPrimary),
                url: links
                    ? (Transclusion.isNoteReference(target) ? noteURL(for: target) : embedURL(for: target))
                    : nil
            )
        case .embedRun:
            // No attributes yet, on purpose: `.embedRun` spans the whole `![[foto.png]]`
            // or `![alt](foto.png)`, wider than the marker-sized spans `default` below is
            // safe for, and the collapse into a preview is Step 3's, not this one's. An
            // explicit `[:]` here keeps this step from painting a colour over a range
            // `default` was never asked to cover.
            [:]
        case .tableRun:
            // `.embedRun`'s arm above, verbatim and for the same reason: a `.tableRun` spans
            // a whole table - several lines of it - and `default`'s single colour would grey
            // out every cell's text. The grid that replaces those characters is Task 4's
            // (ADR-0029 §D4); until then the pipes look exactly as they do today.
            [:]
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
        // Struck-through text is text the author kept and marked as gone. Dimmer than the
        // rest, because the line already says what it is and a second signal would shout.
        case .strikethrough: .textSecondary
        case .frontmatter, .code, .annotation: .textSecondary
        // Neither `.headingMarker` nor `.emphasisMarker` needs an arm of its own in
        // `attributes(for:)`: that switch's `default` already returns
        // `[.foregroundColor: …colorToken(for: span)…]`, and `addAttributes` merges
        // rather than replaces, so a marker keeps its run's font - bold, or oblique, or
        // the heading's, applied first - and only gets this colour on top, for free.
        case .linkSyntax, .headingMarker, .emphasisMarker, .listMarker: .textTertiary
        // `.embedRun` has its own explicit arm in `attributes(for:)` that returns `[:]`
        // (Step 3 is what collapses it into a preview), so this entry exists only to
        // keep this table exhaustive - the same shelf as `.heading`/`.linkTarget` above,
        // which never arrive here either.
        case .embedRun: .textTertiary
        // Struck-through text: dimmer than the rest, for the same reason `.strikethrough`
        // itself is below - the line already says what it is.
        case .strikethroughMarker: .textTertiary
        case .blockquoteMarker: .textTertiary
        // A whole rule line, drawn as a syntax marker's colour even though `attributes(for:)`
        // never routes it here in practice once Task 2 wires the collapsing branch.
        case .horizontalRule: .textTertiary
        // `.tableRun` has its own explicit arm in `attributes(for:)` returning `[:]` (Task 4
        // is what turns it into a real grid attachment) - this entry exists only to keep
        // this table exhaustive, the same shelf as `.embedRun` above.
        case .tableRun: .textTertiary
        case .tag, .linkTarget, .embedTarget: .accentPrimary
        case .codeToken(let token): token.colorToken
        case .taskMarker(let state): state == .done ? .taskDone : .taskOpen
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
