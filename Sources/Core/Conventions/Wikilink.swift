import Foundation

/// A `[[…]]` reference found in a note body.
///
/// wikilink.md W-01 fixes the first segment as the exact note title: an alias may find
/// a note in search but must never be the link target, or renaming the note silently
/// breaks the link.
struct Wikilink: Equatable, Hashable, Sendable {
    /// The exact target title, or the file name for an embed.
    var target: String
    /// The `#Sezione` fragment, without the hash.
    var section: String?
    /// The `|display text` alternative label.
    var displayText: String?
    /// True for `![[…]]`, the media embed form.
    var isEmbed: Bool
    /// Character range in the source text, for the editor to style and click.
    var range: Range<String.Index>

    /// An embed points at a file, so it carries an extension; a note link does not.
    var looksLikeFileReference: Bool {
        isEmbed || target.contains(".")
    }

    var rendered: String {
        var text = target
        if let section { text += "#\(section)" }
        if let displayText { text += "|\(displayText)" }
        return (isEmbed ? "![[" : "[[") + text + "]]"
    }
}

enum WikilinkParser {
    /// Finds every wikilink in a body, in source order.
    ///
    /// Scans rather than uses a regular expression so that nesting and unbalanced
    /// brackets are handled explicitly: `[[a [[b]]` should yield `b`, not a match that
    /// swallows the rest of the note.
    ///
    /// Code is skipped. `[[ ]]` is bash's test syntax and TOML's array-of-tables
    /// syntax, so a vault holding shell snippets or a pyproject fragment would
    /// otherwise fill its backlink index and its unresolved-links panel with things
    /// like `${esiti[*]}" != *0*` and `tool.mypy.overrides` - observed on a real vault,
    /// not hypothetical.
    static func links(in text: String) -> [Wikilink] {
        var results: [Wikilink] = []
        var index = text.startIndex
        let code = codeRanges(in: text)

        while index < text.endIndex {
            guard let open = text.range(of: "[[", range: index..<text.endIndex) else { break }
            guard let close = text.range(of: "]]", range: open.upperBound..<text.endIndex) else { break }

            if code.contains(where: { $0.contains(open.lowerBound) }) {
                index = open.upperBound
                continue
            }

            let inner = String(text[open.upperBound..<close.lowerBound])
            // A nested opener means the outer one was never a link; restart just after
            // it so the inner link is still found.
            if inner.contains("[[") {
                index = open.upperBound
                continue
            }

            let isEmbed = open.lowerBound > text.startIndex
                && text[text.index(before: open.lowerBound)] == "!"
            let start = isEmbed ? text.index(before: open.lowerBound) : open.lowerBound

            if let link = parse(inner, isEmbed: isEmbed, range: start..<close.upperBound) {
                results.append(link)
            }
            index = close.upperBound
        }
        return results
    }

    /// Ranges covered by fenced code blocks and inline code spans.
    ///
    /// An unterminated fence runs to the end of the note, which is what a reader sees
    /// too: everything after it is rendered as code, so treating it as prose would
    /// disagree with the note's own appearance.
    static func codeRanges(in text: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []

        var fenceStart: String.Index?
        var lineStart = text.startIndex
        while lineStart < text.endIndex {
            let lineEnd = text[lineStart...].firstIndex(of: "\n") ?? text.endIndex
            let line = text[lineStart..<lineEnd].trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                if fenceStart != nil {
                    // Only the opening fence may carry an info string (```bash);
                    // a closing fence is the delimiter alone, so a line like
                    // "``` e poi altro" does not end the block.
                    let isBareDelimiter = line.allSatisfy { $0 == "`" || $0 == "~" }
                    if isBareDelimiter {
                        ranges.append(fenceStart!..<lineEnd)
                        fenceStart = nil
                    }
                } else {
                    fenceStart = lineStart
                }
            }
            guard lineEnd < text.endIndex else { break }
            lineStart = text.index(after: lineEnd)
        }
        if let start = fenceStart { ranges.append(start..<text.endIndex) }

        // Inline spans, paired within a single line and only outside the fences found
        // above. Pairing across the whole text would desynchronise on the three
        // backticks of every fence and then mis-pair everything after it, which is
        // how `[[tool.mypy.overrides]]` inside an inline span survived the first
        // version of this.
        var line = text.startIndex
        while line < text.endIndex {
            let lineEnd = text[line...].firstIndex(of: "\n") ?? text.endIndex
            defer { line = lineEnd < text.endIndex ? text.index(after: lineEnd) : text.endIndex }

            if ranges.contains(where: { $0.contains(line) }) { continue }

            var cursor = line
            while let open = text[cursor..<lineEnd].firstIndex(of: "`") {
                let afterOpen = text.index(after: open)
                guard afterOpen < lineEnd,
                      let close = text[afterOpen..<lineEnd].firstIndex(of: "`")
                else { break }
                let span = open..<text.index(after: close)
                ranges.append(span)
                cursor = span.upperBound
            }
        }
        return ranges
    }

    private static func parse(
        _ inner: String,
        isEmbed: Bool,
        range: Range<String.Index>
    ) -> Wikilink? {
        guard !inner.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }

        // Order matters: `|` binds last, so `[[Note#Sezione|testo]]` splits on the
        // pipe first and the fragment is taken from what remains.
        var remainder = inner
        var displayText: String?
        if let pipe = remainder.firstIndex(of: "|") {
            displayText = String(remainder[remainder.index(after: pipe)...])
                .trimmingCharacters(in: .whitespaces)
            remainder = String(remainder[remainder.startIndex..<pipe])
        }

        var section: String?
        if let hash = remainder.firstIndex(of: "#") {
            section = String(remainder[remainder.index(after: hash)...])
                .trimmingCharacters(in: .whitespaces)
            remainder = String(remainder[remainder.startIndex..<hash])
        }

        let target = remainder.trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty else { return nil }

        return Wikilink(
            target: target,
            section: section?.isEmpty == true ? nil : section,
            displayText: displayText?.isEmpty == true ? nil : displayText,
            isEmbed: isEmbed,
            range: range
        )
    }
}

// MARK: - Structural links

/// One entry of the `## Note correlate` section: a wikilink plus the reason W-04
/// requires.
struct StructuralLink: Equatable, Sendable {
    var target: String
    var reason: String
}

enum RelatedSection {
    /// The heading the section lives under, fixed by wikilink.md.
    static let heading = "## Note correlate"
    /// W-09: at most five structural links, except on an index note.
    static let maximumLinks = 5

    /// Reads the bullets under `## Note correlate`.
    ///
    /// The expected line shape is `- [[Titolo]] — motivo`. Both the em dash and a
    /// plain hyphen are accepted as the separator, because a note typed by hand will
    /// have whichever the keyboard produced, and rejecting one would report a
    /// conformant note as broken.
    static func parse(from body: String) -> [StructuralLink] {
        guard let sectionRange = body.range(of: heading) else { return [] }
        let afterHeading = body[sectionRange.upperBound...]

        var links: [StructuralLink] = []
        for line in afterHeading.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") { break }  // next heading ends the section
            guard trimmed.hasPrefix("-") else { continue }

            let content = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
            guard let link = WikilinkParser.links(in: content).first, !link.isEmbed else { continue }

            let afterLink = String(content[link.range.upperBound...])
            let reason = afterLink
                .trimmingCharacters(in: .whitespaces)
                .trimmingPrefix(anyOf: ["—", "–", "-", ":"])
                .trimmingCharacters(in: .whitespaces)
            links.append(StructuralLink(target: link.target, reason: reason))
        }
        return links
    }

    /// Compares `related:` against the section (W-06). The two must name the same
    /// titles; the app keeps them aligned, so a difference is a real non-conformity
    /// rather than a formatting preference.
    static func discrepancies(
        frontmatterRelated: [String],
        sectionLinks: [StructuralLink]
    ) -> (missingInSection: [String], missingInFrontmatter: [String]) {
        let inFrontmatter = Set(frontmatterRelated.map(normalized))
        let inSection = Set(sectionLinks.map { normalized($0.target) })
        return (
            missingInSection: inFrontmatter.subtracting(inSection).sorted(),
            missingInFrontmatter: inSection.subtracting(inFrontmatter).sorted()
        )
    }

    /// `related` entries are written as `"[[Titolo]]"`, the section as `[[Titolo]]`;
    /// both reduce to the bare title for comparison.
    private static func normalized(_ value: String) -> String {
        var text = value.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("\""), text.hasSuffix("\""), text.count >= 2 {
            text = String(text.dropFirst().dropLast())
        }
        if let link = WikilinkParser.links(in: text).first { return link.target }
        return text
    }
}

private extension String {
    func trimmingPrefix(anyOf prefixes: [String]) -> String {
        for prefix in prefixes where hasPrefix(prefix) {
            return String(dropFirst(prefix.count))
        }
        return self
    }
}


/// Editor text transformations of SPEC §5.
enum EditorEdits {
    /// Wraps a selection in a markdown link when a URL is pasted over it.
    ///
    /// Returns nil when the pasted text is not a URL or nothing is selected, so an
    /// ordinary paste stays an ordinary paste.
    static func markdownLink(pasting pasted: String, over selection: String) -> String? {
        let trimmedURL = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSelection = selection.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSelection.isEmpty, isURL(trimmedURL) else { return nil }
        return "[\(selection)](\(trimmedURL))"
    }

    /// An embed for a file dropped into the editor: `![[nome.est]]` (SPEC §5).
    ///
    /// The name alone, not the path: a wikilink resolves by name inside the vault, and
    /// writing the path would break the moment the file is moved in the app.
    static func embed(forFileNamed fileName: String) -> String {
        "![[\(fileName)]]"
    }

    /// Whether a string is a URL this app should linkify.
    ///
    /// Requires a scheme: a bare "vibrofer.it" pasted over a word is more likely to be
    /// text than a link, and guessing wrong rewrites what the user typed.
    static func isURL(_ text: String) -> Bool {
        guard let components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(),
              !scheme.isEmpty
        else { return false }
        // A scheme with nothing after it is not a link.
        return !(components.host ?? "").isEmpty || !(components.path).isEmpty
    }
}
