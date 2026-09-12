import Foundation

// ADR-0042 (Pratiche inline image placeholders) §D2, §D4, §D6.

/// Everything about how a `cid:` reference to an inline image is found, replaced and
/// reordered in a message's body text. Foundation only - this file compiles into
/// `perg` and `pergamenum-mcp` as well as into the app (ADR-0001 §D1).
enum MessageInlineImage {
    /// `*[immagine non ancora caricata]*` - what stands where an inline image will go
    /// until Mail has its bytes (ADR-0042 §D2). No emoji, no glyph: italic markdown
    /// only, the same style as `PraticaSyncEngine.pendingPlaceholder`. Square brackets
    /// around plain words are not a wikilink and not a markdown link, so nothing
    /// indexes it and nothing backlinks it.
    static let placeholder = "*[immagine non ancora caricata]*"

    /// Every reference to `contentID` in `body` replaced by `replacement`: the whole
    /// `![alt](cid:…)` construct where `HTMLTextReducer` wrote one, then the bare
    /// `cid:…` token elsewhere (a plain-text body mentions it with no markdown around
    /// it at all). Constructs are replaced first, or the bare pass would eat the
    /// construct's insides and leave `![alt]()` behind.
    static func replacingReferences(to contentID: String, in body: String, with replacement: String) -> String {
        var body = body
        let escapedContentID = NSRegularExpression.escapedPattern(for: contentID)
        while let range = body.range(
            of: #"!\[[^\]]*\]\(cid:\#(escapedContentID)\)"#,
            options: .regularExpression
        ) {
            body.replaceSubrange(range, with: replacement)
        }
        body = body.replacingOccurrences(of: "cid:\(contentID)", with: replacement)
        return body
    }

    /// Whether `body` refers to `contentID` at all, in either form (ADR-0042 §D3's
    /// whole question - a part the body never mentions is not waiting for anything).
    static func referencesContentID(_ contentID: String, in body: String) -> Bool {
        body.contains("cid:\(contentID)")
    }

    /// U+2063 INVISIBLE SEPARATOR either side of the marker: not prose, not markdown,
    /// cannot be produced by an email and cannot collide with one.
    private static let deferralMarker = "\u{2063}pergamenum-inline-deferred-"
    private static let deferralTerminator = "\u{2063}"

    /// A token that stands in for a deferred inline image's reference until the note's
    /// three texts have been through `QuoteSplitter.split` and are in their final,
    /// rendered order (ADR-0042 §D6). Never reaches disk.
    static func deferralToken(forPart ordinal: Int) -> String {
        "\(deferralMarker)\(ordinal)\(deferralTerminator)"
    }

    /// `texts` in the order the rendered file will carry them - `[newText,
    /// quotedHistory, signature]`, per ADR-0042 §D6. Every deferral token in every text
    /// becomes `placeholder`; the content ids are returned in the order their tokens
    /// were encountered while walking `texts` in the order given, which is exactly what
    /// `pergamenum-mail-inline-pending` must record (ADR-0042 §D3).
    static func resolvingDeferralTokens(
        in texts: [String], contentIDByOrdinal: [Int: String]
    ) -> (texts: [String], pending: [String]) {
        guard !contentIDByOrdinal.isEmpty else { return (texts, []) }
        var pending: [String] = []
        // A single regex over every token shape, scanned left to right, so the order
        // recorded is the order tokens actually appear in the text - never dictionary
        // iteration order, and never ordinal order (ADR-0042 §D6's own reversed-ordinal
        // test exists precisely to catch that mistake). Built from the real marker
        // characters (never a `\u{...}` escape typed inside a raw regex string, which
        // ICU - NSRegularExpression's engine - does not accept in that form) plus a
        // captured run of digits for the ordinal.
        let tokenPattern = NSRegularExpression.escapedPattern(for: deferralMarker)
            + "(\\d+)"
            + NSRegularExpression.escapedPattern(for: deferralTerminator)
        let resolved = texts.map { text -> String in
            var text = text
            while let match = text.range(of: tokenPattern, options: .regularExpression) {
                let digits = text[match].filter(\.isNumber)
                if let ordinal = Int(digits), let contentID = contentIDByOrdinal[ordinal] {
                    pending.append(contentID)
                }
                text.replaceSubrange(match, with: placeholder)
            }
            return text
        }
        return (resolved, pending)
    }
}
