import AppKit

/// The link half of `EditorDecorationDelegate`'s substitution mechanism (ADR-0029 §D1/§D3;
/// plan `2026-09-02-editor-wysiwyg-unification`, Task 2), split out on its own the way
/// `+ListRendering.swift`, `+CheckboxRendering.swift` and `+QuoteRendering.swift` already
/// are - one self-contained concern, one `extension` file, because the main file's class
/// body crossed SwiftLint's `type_body_length` warning again the moment this landed in it.
///
/// A link is the one ADR-0029 construct that needs *two* things of this object rather than
/// one: its brackets are collapsed by the generic path in the main file, like any other
/// marker, and the run they enclosed then carries `.toolTip` saying where it goes - because
/// unlike a `#` or a `**`, hiding a link's syntax hides information rather than noise (R-04).
extension EditorDecorationDelegate {
    /// Whether `range` still spells one of the bracket runs a link is concealed by: a
    /// wikilink's `[[`/`![[`/`]]`, or a CommonMark link's `[` and its `](url)` tail.
    ///
    /// Deliberately not "any run of brackets": a range that has drifted onto ordinary prose
    /// answers no, which is the whole point of the `stillSpells` family - the table is
    /// filled by a styling pass and read by a later layout pass, and collapsing prose is
    /// this mechanism's failure mode.
    ///
    /// Not `private` for the reason `survivors(among:of:in:)` is not: `stillSpells` in the
    /// main file is what routes a `.link` marker here.
    static func stillSpellsALinkDelimiter(_ text: NSString, at range: NSRange) -> Bool {
        guard range.location >= 0, range.length > 0, NSMaxRange(range) <= text.length else { return false }
        let candidate = text.substring(with: range)
        if candidate == "[" || candidate == "[[" || candidate == "![[" || candidate == "]]" { return true }
        return candidate.hasPrefix("](") && candidate.hasSuffix(")")
    }

    /// Where each concealed link in a paragraph goes, over the whole run its brackets
    /// enclose - what `.toolTip` is applied to so a hover over the visible label says where
    /// it leads (ADR-0029 §D3, R-04).
    ///
    /// Rebuilt with the paragraph it lives in on every layout pass, so it cannot go stale
    /// and needs no invalidation - ADR-0018 §D3's *"it does not outlive the pass that made
    /// it"*, one attribute lower. Chosen over `NSView.addToolTipRect(_:owner:userData:)`,
    /// AppKit's other route, for the reason §D3 gives: that one needs a rect, and a rect
    /// needs geometry recomputed on every layout pass, scroll and window resize.
    ///
    /// The delimiters are paired in source order, two at a time. A mispairing - the only
    /// way an odd number of surviving brackets can end - yields a run `linkTarget(inRun:)`
    /// refuses to read, so the worst case is a missing hint rather than a wrong one.
    /// Ranges out are relative to the paragraph, the same space `HiddenMarker.range` uses.
    static func linkTooltips(
        among survivors: [HiddenMarker], of paragraph: NSRange, in text: NSString
    ) -> [(range: NSRange, target: String)] {
        let brackets = survivors
            .filter { $0.kind == .link }
            .sorted { $0.range.location < $1.range.location }
        var result: [(range: NSRange, target: String)] = []
        var index = 0

        while index + 1 < brackets.count {
            let open = brackets[index].range
            let close = brackets[index + 1].range
            index += 2
            let run = NSRange(location: open.location, length: NSMaxRange(close) - open.location)
            guard run.length > 0, NSMaxRange(run) <= paragraph.length else { continue }
            let absolute = NSRange(location: paragraph.location + run.location, length: run.length)
            guard NSMaxRange(absolute) <= text.length,
                  let target = linkTarget(inRun: text.substring(with: absolute))
            else { continue }
            result.append((run, target))
        }
        return result
    }

    /// Where a whole link run leads: the URL of a CommonMark `[testo](url)`, or the target
    /// of a wikilink, read by `WikilinkParser` rather than by a second bracket grammar.
    ///
    /// The raw target and never a resolved note title, which ADR-0029 §D3 offers where one
    /// is available: this object cannot reach the vault's index - it is not `@MainActor`,
    /// holds no session and calls nothing back (the crossing `embedRenditions` documents) -
    /// so what it can say honestly is what the file itself says.
    private static func linkTarget(inRun run: String) -> String? {
        if run.hasSuffix(")"), let tail = run.range(of: "](", options: .backwards) {
            let url = run[tail.upperBound..<run.index(before: run.endIndex)]
                .trimmingCharacters(in: .whitespaces)
            return url.isEmpty ? nil : url
        }
        return WikilinkParser.links(in: run).first?.target
    }
}
