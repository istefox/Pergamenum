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
extension NSAttributedString.Key {
    /// A wikilink target's or a CommonMark label's URL (issue #191). Deliberately not the
    /// standard `.link`: that attribute is what makes AppKit recognize a click as "on a
    /// link" and engage its own automatic click-navigation gesture, which this app's custom
    /// TextKit 2 content-storage substitution makes unreliable (`NoteTextView
    /// +Coordinator.swift`'s `textView(_:clickedOnLink:at:)` carries the full history) - it
    /// fires even on a plain click nowhere near a link, and AppKit then aborts its own
    /// text-selection drag-tracking for that method's return value alone, breaking
    /// drag-to-select everywhere, not just on links. Every click this app cares about is
    /// already resolved by hand (`characterIndexForInsertion(at:)` plus a storage lookup at
    /// `CompletingTextView+Pasteboard.swift`'s `followLinkIfPresent(at:)` and its
    /// `FormattingTextView.swift` twin), so nothing depended on AppKit's own gesture - this
    /// key just stops offering it one to misfire on.
    static let editorLink = NSAttributedString.Key("editorLink")
}

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
        var context = StyleContext(theme: theme, links: links)
        let result = NSMutableAttributedString(string: text, attributes: context.base)
        let length = (text as NSString).length
        for styled in MarkdownStyler.spans(in: text) {
            let range = NSRange(styled.range, in: text)
            guard range.location != NSNotFound, NSMaxRange(range) <= length else { continue }
            result.addAttributes(context.attributes(for: styled.span), range: range)
        }
        return result
    }

    /// The spans that need more than a colour: a font, a background, a link.
    ///
    /// A two-line wrapper over one fresh `StyleContext` (Task 2, PG-139/#239) - kept with
    /// this exact static signature because `Tests/TranscludedLineTests.swift:163` and
    /// `Tests/MarkdownAttributedTextTests.swift` call it directly, one span at a time, with
    /// no context of their own to reuse. Everything the switch used to do inline now lives
    /// on `StyleContext.attributes(for:)`, memoised per pass rather than rebuilt per span -
    /// see that type's own header for why the memoisation could not live inside
    /// `ProseTypography` instead.
    static func attributes(
        for span: MarkdownStyler.Span,
        theme: Theme,
        links: Bool = true
    ) -> [NSAttributedString.Key: Any] {
        var context = StyleContext(theme: theme, links: links)
        return context.attributes(for: span)
    }

    /// One styling pass's memoised attribute pieces (Task 2, PG-139/#239).
    ///
    /// `attributes(for:theme:links:)`'s old body rebuilt every one of these per call: a
    /// heading resolved `ProseTypography.heading(level:theme)` **twice** and rebuilt the
    /// whole `base(theme:)` dictionary just to read its `.paragraphStyle` back out, and
    /// `.bold`/`.italic`/`.codeBlock` and the mono-faced arms each re-resolved their own font
    /// on every span that used them - once per span, per keystroke, since
    /// `NoteTextView+Coordinator.applyStyling` (the actual hot caller) calls
    /// `attributes(for:theme:)` directly in its span loop, not through `attributed` above -
    /// a scratch confined to `attributed` alone would have fixed nothing there.
    ///
    /// Per-pass scratch, not a cache inside `ProseTypography`: `Theme` is `Equatable` but not
    /// `Hashable`, its `==` compares five token dictionaries, and it is runtime-customisable
    /// so its `id` is not identity-stable either - any keyed cache would need a key that is
    /// expensive or wrong, plus a `static var` Swift 6 rejects without a `Mutex` (and it
    /// cannot be `@MainActor`: `EditorDecorationDelegate`, `FoldedHeadingFragment` and
    /// `TableGridView` call `ProseTypography` off the main actor, ADR-0030 §D5). A value
    /// scoped to one styling pass has no invalidation question at all - a theme change makes
    /// a new pass, and a new context with it.
    struct StyleContext {
        let theme: Theme
        let links: Bool
        /// Built once per pass rather than once per heading span, which used to rebuild this
        /// whole dictionary just to read `.paragraphStyle` back out of it.
        let base: [NSAttributedString.Key: Any]

        private var headings: [Int: [NSAttributedString.Key: Any]] = [:]
        private lazy var boldAttributes: [NSAttributedString.Key: Any] = [.font: ProseTypography.proseBold(theme)]
        private lazy var italicAttributes: [NSAttributedString.Key: Any] = ProseTypography.proseItalicAttributes(theme)
        /// Shared by both mono-faced arms below, so the face itself is resolved once - the
        /// colour that goes with it still varies per span (`.codeBlock`'s background versus
        /// `.code`/`.frontmatter`/`.codeToken`'s foreground, which itself varies by token).
        private lazy var monoFont: NSFont = ProseTypography.mono(theme)
        private lazy var codeBlockAttributes: [NSAttributedString.Key: Any] = [
            .font: monoFont,
            .backgroundColor: NSColor(theme.color(.surfaceSunken)),
        ]

        init(theme: Theme, links: Bool) {
            self.theme = theme
            self.links = links
            self.base = MarkdownAttributedText.base(theme: theme)
        }

        /// Today's `attributes(for:theme:links:)` switch, with every rebuild memoised.
        mutating func attributes(for span: MarkdownStyler.Span) -> [NSAttributedString.Key: Any] {
            switch span {
            case .heading(let level):
                if let cached = headings[level] { return cached }
                // The paragraph style is named here and not left to `base`: that one carries
                // `font.prose`'s line-height multiple, and a multiple applies to the run's
                // *own* font, so a 24pt H1 under a 16pt-derived multiple reserves
                // body-proportioned slack against a much taller face — surplus AppKit puts
                // above the glyphs, which is what pushed the fold badge
                // `FoldedHeadingFragment` centres in the line box away from the heading it
                // marks. Composed onto the base style rather than replacing it, per
                // ADR-0030 §D5. Resolved once (not twice, as the pre-Task-2 body did) and
                // based on `base[.paragraphStyle]` rather than a freshly rebuilt `base(theme:)`.
                let font = ProseTypography.heading(level: level, theme)
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: NSColor(theme.color(.textPrimary)),
                    .paragraphStyle: ProseTypography.paragraphStyle(
                        theme, font: font, basedOn: base[.paragraphStyle] as? NSParagraphStyle
                    ),
                ]
                headings[level] = attributes
                return attributes
            case .bold:
                return boldAttributes
            case .italic:
                // The prose family's own italic face where it has one, `[.obliqueness: 0.2]`
                // on the upright face where it does not (ADR-0030 §D6) - the blanket
                // obliqueness this used to return is a slanted roman, which is what the page
                // stops looking like.
                return italicAttributes
            case .strikethrough:
                // A line through the whole run, markers included - true of strikethrough,
                // which is what SPEC §5's styled source means for this span. It is not
                // universal any more: ADR-0018 narrows it for three cases across its three
                // slices (headings, emphasis, and the image/PDF embed), and strikethrough is
                // not one.
                return [.strikethroughStyle: NSUnderlineStyle.single.rawValue]
            case .codeBlock:
                // A background and the mono face. The *colour* is still left to whatever the
                // grammar found inside, and to `textPrimary` where it found nothing - a
                // fence in a language nobody wrote a grammar for still reads as code because
                // of this.
                return codeBlockAttributes
            case .code, .frontmatter, .codeToken:
                // `.codeBlock`'s reasoning, for the spans that used to fall through to
                // `default` and take a colour alone. The colour each of them already had is
                // unchanged - it still comes from the one exhaustive table below.
                return [
                    .font: monoFont,
                    .foregroundColor: NSColor(theme.color(MarkdownAttributedText.colorToken(for: span))),
                ]
            case .linkTarget(let target):
                return MarkdownAttributedText.clickable(
                    theme.color(.accentPrimary),
                    url: links ? MarkdownAttributedText.targetURL(for: target) : nil
                )
            case .embedTarget(let target):
                // Where the click goes depends on what the target is, by the same rule the
                // reading view uses (ADR-0010 §D2): a note opens, a file is previewed.
                // Sending every `![[…]]` to the file preview is the editor's half of PG-020
                // - it answered "file non trovato nel vault" for a note that exists.
                return MarkdownAttributedText.clickable(
                    theme.color(.accentPrimary),
                    url: links
                        ? (Transclusion.isNoteReference(target)
                            ? MarkdownAttributedText.noteURL(for: target)
                            : MarkdownAttributedText.embedURL(for: target))
                        : nil
                )
            case .embedRun:
                // No attributes yet, on purpose: `.embedRun` spans the whole `![[foto.png]]`
                // or `![alt](foto.png)`, wider than the marker-sized spans `default` below
                // is safe for, and the collapse into a preview is Step 3's, not this one's.
                // An explicit `[:]` here keeps this step from painting a colour over a range
                // `default` was never asked to cover.
                return [:]
            case .tableRun:
                // `.embedRun`'s arm above, verbatim and for the same reason: a `.tableRun`
                // spans a whole table - several lines of it - and `default`'s single colour
                // would grey out every cell's text. The grid that replaces those characters
                // is Task 4's (ADR-0029 §D4); until then the pipes look exactly as they do
                // today.
                return [:]
            default:
                return [.foregroundColor: NSColor(theme.color(MarkdownAttributedText.colorToken(for: span)))]
            }
        }
    }

    private static func clickable(_ color: Color, url: URL?) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor(color)]
        if let url {
            attributes[.editorLink] = url
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
        // `.viewBlockRun`'s own shelf (ADR-0033 §D1; plan
        // `2026-09-06-pg-099-views-board-renderer-orphaned-by`, Task 1): a colour only, to
        // keep this table exhaustive, the same reason `.tableRun` needs one above - the
        // real attachment that replaces these characters is a later task's.
        case .viewBlockRun: .textTertiary
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

    /// A `.linkTarget` span's own URL, for both a wikilink target and a CommonMark link's raw
    /// href (issue #188 / R-03, R-04) - the one place that decides which of the two a bare
    /// string is. A wikilink target is never a URL and never ends in `.md`, so this is
    /// behavior-preserving for every existing wikilink/`^[[board.canvas]]` marker.
    static func targetURL(for target: String) -> URL? {
        if let scheme = URL(string: target)?.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            return URL(string: target)
        }
        var title = target
        if title.lowercased().hasSuffix(".md") { title.removeLast(3) }
        return noteURL(for: title)
    }

    /// What a clicked `.link` URL means, decoded once so `NoteTextView+Coordinator` and
    /// `CardTextView`'s Coordinator (R-06) don't each parse the scheme by hand.
    enum LinkClickTarget: Equatable {
        /// A note in this vault, by title - also what a `^[[board.canvas]]` marker's own
        /// target decodes to; resolving `.canvas` into a board navigation is
        /// `CommandActions.open(link:)`'s job (ADR-0039 reuse), not this decoder's.
        case note(title: String)
        /// `![[foto.png]]`'s target: a file to preview, not a note to open.
        case embed(name: String)
        /// A CommonMark link whose href is a real `http`/`https` URL.
        case external(URL)
    }

    static func clickTarget(for url: URL) -> LinkClickTarget? {
        if let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            return .external(url)
        }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        if components.host == embedHost,
           let name = components.queryItems?.first(where: { $0.name == "name" })?.value {
            return .embed(name: name)
        }
        guard components.host == "note",
              let title = components.queryItems?.first(where: { $0.name == "title" })?.value
        else { return nil }
        return .note(title: title)
    }

    private static func url(host: String, item: URLQueryItem) -> URL {
        var components = URLComponents()
        components.scheme = AppInfo.urlScheme
        components.host = host
        components.queryItems = [item]
        return components.url ?? URL(string: "\(AppInfo.urlScheme)://\(host)")!
    }
}

/// A text view delegate that can navigate a resolved link URL directly, without going
/// through `NSTextViewDelegate.textView(_:clickedOnLink:at:)` - both
/// `NoteTextView.Coordinator` and `CardTextView`'s Coordinator gate that delegate method on
/// `NSEvent.modifierFlags` actually holding Cmd at the moment it runs, since AppKit can
/// invoke it on its own, unreliably, on a plain click too (issue #188, confirmed on-screen
/// 2026-09-09). "Apri collegamento" (R-07) must navigate without Cmd held, so it calls this
/// method directly instead, bypassing that gate on purpose.
@MainActor
protocol LinkNavigatingDelegate: NSTextViewDelegate {
    @discardableResult
    func performLinkNavigation(_ link: Any) -> Bool
}
