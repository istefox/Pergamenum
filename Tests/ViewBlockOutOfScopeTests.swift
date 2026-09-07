import Foundation
import SwiftUI
import Testing
@testable import Pergamenum

/// ADR-0033 (plan `2026-09-06-pg-099-views-board-renderer-orphaned-by`, Task 9): the regression
/// fence around the four surfaces this chain must never touch - `MarkdownBlocksView`'s reading
/// path, `TranscludedNoteView`, `NoteExporter`/`NoteExport` and the Viste pane
/// (`ViewsPane`/`ViewCatalogue`) - R-10, R-11, R-12.
///
/// **The grep evidence is the coder's own half of this task** (there is nothing to implement if
/// the design held): `git diff --stat 51066f5..HEAD` for `MarkdownBlocksView.swift`,
/// `TranscludedNoteView.swift`, `NoteExporter.swift`, `ViewsPane.swift` and `ViewCatalogue.swift`
/// is empty for the whole chain so far - reported alongside this file, not asserted by a test,
/// since a test cannot fail a build that never happened.
///
/// **Why reflection, twice, and why it is not "rendered pixels":** `MarkdownBlocksView.view(for:)`
/// constructs its `RenderedViewBlock` inline inside a `switch` with no pure accessor to call
/// instead (unlike Task 7's `openAction(for:)`, which exists precisely so `ViewRowRendererClickTargets`
/// never has to do this) - the only way to see what it built is to look at the opaque `some View`
/// it returns. `find(_:in:)` walks that value's own stored properties via `Mirror` until it finds a
/// concrete `RenderedViewBlock`, then every assertion is a plain property read on that struct - no
/// window, no renderer, no screenshot. `collectStrings(in:into:)` does the same walk one level
/// further, for the one assertion that needs to see *content* rather than *inputs* (the error card):
/// it turns up not only `Text`'s own string storage but every `.accessibilityIdentifier(_:)` string
/// too, which is what lets that one assertion be positive - "the error card is present, and says
/// this" - rather than "the call did not crash".
private func find<T>(_ type: T.Type, in value: Any, depth: Int = 0) -> T? {
    guard depth < 50 else { return nil }
    if let match = value as? T { return match }
    for child in Mirror(reflecting: value).children {
        if let found = find(type, in: child.value, depth: depth + 1) { return found }
    }
    return nil
}

private func collectStrings(in value: Any, into found: inout [String], depth: Int = 0) {
    guard depth < 50 else { return }
    if let string = value as? String { found.append(string) }
    for child in Mirror(reflecting: value).children {
        collectStrings(in: child.value, into: &found, depth: depth + 1)
    }
}

/// `ViewBlock.parse`'s failure, described - the same computation `RenderedViewBlock`'s own
/// (private) `block` property makes, extracted here because that property cannot be reached
/// through `@testable import` (it is `private`, not merely `internal`).
private func parseErrorDescription(_ source: String) -> String {
    do {
        _ = try ViewBlock.parse(source)
        return ""
    } catch let error as ViewBlockError {
        return error.description
    } catch {
        return "\(error)"
    }
}

// MARK: - R-10: `MarkdownBlocksView.view(for:)` still routes to `RenderedViewBlock`, unchanged

@MainActor
@Suite struct MarkdownBlocksViewRoutingUnchanged {
    /// The direct-render path (`MarkdownReadingView`, dead code per ADR-0029 §D14 but still the
    /// shape a live vault reaches `MarkdownBlocksView` with `queries` non-nil): `queries` is still
    /// threaded through - it was never part of what Task 7 added - and neither
    /// `onEditSource` nor `onOpenNote` is, because `view(for:)` itself is not edited by this
    /// chain (confirmed by the grep evidence above).
    @Test func aViewLanguageCodeBlockStillRoutesToRenderedViewBlockWithNeitherNewInput() throws {
        let queries = ViewQuerySource(evaluate: { _ in ViewResult(groups: [], total: 0) }, generation: 3)
        let root = URL(fileURLWithPath: "/tmp/pergamenum-test-vault")
        let thumbnails = ThumbnailStore(
            root: root, directory: root.appending(path: "cache", directoryHint: .isDirectory)
        )
        let view = MarkdownBlocksView(
            blocks: [], notePath: "Note/Prova.md", vaultRoot: root, thumbnails: thumbnails,
            queries: queries
        )
        let block = MarkdownBlock.code(language: ViewBlock.language, lines: ["render: table"])

        let found = try #require(
            find(RenderedViewBlock.self, in: view.view(for: block)),
            "view(for:) non instrada più un blocco pergamenum-view a RenderedViewBlock (R-10)"
        )
        #expect(found.source == "render: table")
        #expect(found.notePath == "Note/Prova.md")
        #expect(found.vaultRoot == root)
        #expect(found.thumbnails === thumbnails)
        #expect(found.queries?.generation == 3, "queries deve restare instradato su questo percorso (non è ciò che Task 7 ha aggiunto)")
        #expect(found.onEditSource == nil, "onEditSource non deve essere passato da view(for:) (R-10/R-11)")
        #expect(found.onOpenNote == nil, "onOpenNote non deve essere passato da view(for:) (R-10/R-11)")
    }

    /// A code block in any other language never reaches `RenderedViewBlock` at all - the routing
    /// stayed exactly as specific as it was.
    @Test func aNonViewLanguageCodeBlockNeverRoutesToRenderedViewBlock() {
        let view = MarkdownBlocksView(blocks: [])
        let block = MarkdownBlock.code(language: "swift", lines: ["let x = 1"])
        #expect(find(RenderedViewBlock.self, in: view.view(for: block)) == nil)
    }

    /// The exact call shape `TranscludedNoteView.rendition(of:excerpt:)` uses
    /// (`TranscludedNoteView.swift:104-111`, grepped, unedited by this chain): no `queries:`
    /// argument at all. A transcluded note's `RenderedViewBlock` must still end up with `queries`
    /// nil - "no vault behind this vista" is today's rendering there and R-10/R-11 depend on it.
    @Test func theTranscludedNoteViewCallShapeStillProducesARenderedViewBlockWithNoQueries() throws {
        let view = MarkdownBlocksView(
            blocks: [], notePath: "Altra/Nota.md", vaultRoot: nil, thumbnails: nil,
            transclusions: nil, expandsTransclusions: false
        )
        let block = MarkdownBlock.code(language: ViewBlock.language, lines: ["render: list"])

        let found = try #require(find(RenderedViewBlock.self, in: view.view(for: block)))
        #expect(found.queries == nil, "una nota transclusa ha ora un vault dietro la vista: mai vero prima di questa catena (R-10/R-11)")
        #expect(found.onOpenNote == nil)
        #expect(found.onEditSource == nil)
    }
}

// MARK: - R-11: `NoteExport.html` is byte-identical for a note containing a fence

@Suite struct NoteExporterHTMLUnchangedForANoteContainingAFence {
    private static let note = """
        ---
        date: 2026-08-20
        tags:
          - type-note
        ---

        # Nota con vista

        Testo introduttivo.

        ```pergamenum-view
        render: table
        where: tag("topic-produzione")
        ```

        Testo dopo.
        """

    /// Captured directly from `NoteExport.html(from:title:)` as it stands today (not a golden
    /// file this chain writes): the fence is exported exactly like any other fenced code block -
    /// `MarkdownHTML.render` never reads a fence's language at all, `pergamenum-view` included -
    /// so the vista's own grammar shows up verbatim, escaped, inside a `<pre><code>`.
    private static let expectedHTML = """
        <!DOCTYPE html>
        <html lang="it">
        <head>
        <meta charset="utf-8">
        <title>Nota con vista</title>
        <style>
        body { font: 16px/1.6 -apple-system, system-ui, sans-serif; max-width: 42em;
               margin: 3em auto; padding: 0 1.5em; color: #1c1c1e; }
        h1, h2, h3 { line-height: 1.25; }
        code { font: 0.9em ui-monospace, SFMono-Regular, monospace;
               background: #f2f2f7; padding: 0.1em 0.3em; border-radius: 3px; }
        pre { background: #f2f2f7; padding: 1em; border-radius: 6px; overflow-x: auto; }
        pre code { background: none; padding: 0; }
        blockquote { margin: 0; padding-left: 1em; border-left: 3px solid #d1d1d6; color: #48484a; }
        table { border-collapse: collapse; }
        th, td { border: 1px solid #d1d1d6; padding: 0.4em 0.7em; text-align: left; }
        </style>
        </head>
        <body>
        <h1>Nota con vista</h1>
        <p>Testo introduttivo.</p>
        <pre><code>render: table
        where: tag("topic-produzione")</code></pre>
        <p>Testo dopo.</p>
        </body>
        </html>
        """

    @MainActor
    @Test func exportedHTMLForANoteWithAFenceIsByteIdenticalToTodays() {
        let html = NoteExport.html(from: Self.note, title: "Nota con vista")
        #expect(html == Self.expectedHTML, "l'HTML esportato per una nota con una vista è cambiato (R-11)")
    }
}

// MARK: - R-12: `ViewCatalogue`'s cataloguing of one valid and one invalid fence, unchanged

/// Complements `Tests/SidebarTests.swift:65-110` rather than duplicating it: that file's two
/// cataloguing tests cover two valid fences, and a fence quoted inside another code block (not
/// counted as a view at all). Neither covers a fence that *is* a `pergamenum-view` fence - so
/// `ViewCatalogue.locations` does count its line and heading - but whose body fails
/// `ViewBlock.parse`, which is `ViewsPane.entry`'s own second branch and what a "one valid, one
/// broken" note actually looks like. `Tests/SidebarTests.swift` is read here, not edited or
/// re-run: it must stay green unmodified.
@Suite struct ViewCatalogueCataloguingUnchangedForOneValidAndOneInvalidFence {
    private struct Corpus: ViewCorpus {
        var records: [NoteRecord]
        func paths(forTitle title: String) -> [String] {
            records.filter { $0.title.lowercased() == title.lowercased() }.map(\.relativePath)
        }
    }

    private static func record(_ title: String, tags: [String]) -> NoteRecord {
        var frontmatter = Frontmatter.empty
        frontmatter.tags = tags.compactMap(Tag.init)
        return NoteRecord(
            relativePath: "Clienti/\(title).md", title: title, frontmatter: frontmatter,
            linkTargets: [], embedTargets: [], tasks: [], modifiedAt: .distantPast, byteSize: 100,
            contentHash: "-"
        )
    }

    private static let corpus = Corpus(records: [
        record("Vibrofer", tags: ["client-vibrofer"]),
        record("Ceramiche", tags: ["client-ceramiche"]),
    ])

    private static let note = """
        ---
        date: 2026-08-20
        tags:
          - type-note
        ---

        # Diagnostica viste

        ## Vista valida

        ```pergamenum-view
        render: table
        where: tag("client-vibrofer")
        ```

        ## Vista rotta

        ```pergamenum-view
        outsider: mistero
        ```
        """

    /// `ViewsPane.entry(_:ordinal:parsed:location:session:)`'s own logic, replicated rather than
    /// called - it is `private` and needs a live `VaultSession`, which this test does not build.
    /// If `ViewsPane.swift`'s source is unchanged (the grep evidence this task also reports),
    /// replicating its unedited logic here is a faithful regression fixture, not a guess.
    private static func entry(
        _ record: NoteRecord, ordinal: Int, parsed: Result<ViewBlock, ViewBlockError>,
        location: ViewCatalogue.Location?
    ) -> ViewEntry {
        switch parsed {
        case .success(let block):
            let result = ViewEvaluator.evaluate(block, over: corpus) { _ in nil }
            return ViewEntry(
                path: record.relativePath, noteTitle: record.title, ordinal: ordinal,
                lineIndex: location?.lineIndex ?? 0, heading: location?.heading,
                block: block, error: nil, matches: result.total
            )
        case .failure(let failure):
            return ViewEntry(
                path: record.relativePath, noteTitle: record.title, ordinal: ordinal,
                lineIndex: location?.lineIndex ?? 0, heading: location?.heading,
                block: nil, error: failure.description, matches: nil
            )
        }
    }

    @Test func locationsStillFindsBothFencesWithTheirHeadingAndLine() {
        let locations = ViewCatalogue.locations(in: Self.note)
        let lines = Self.note.components(separatedBy: "\n")

        #expect(locations.count == 2)
        #expect(locations[0].heading == "Vista valida")
        #expect(locations[1].heading == "Vista rotta")
        #expect(lines[locations[0].lineIndex] == "```pergamenum-view")
        #expect(lines[locations[1].lineIndex] == "```pergamenum-view")
    }

    @Test func theCataloguedEntriesKeepTheirNamesRendererMatchesAndLocations() {
        let record = Self.record("Diagnostica", tags: [])
        let text = Self.note
        let locations = ViewCatalogue.locations(in: text)
        let parsedBlocks = ViewBlock.blocks(in: NoteDocument.parse(text).body)
        #expect(parsedBlocks.count == 2, "premessa: la nota deve avere due blocchi vista")

        let entries = parsedBlocks.enumerated().map { ordinal, parsed in
            Self.entry(record, ordinal: ordinal, parsed: parsed,
                       location: ordinal < locations.count ? locations[ordinal] : nil)
        }

        let valid = entries[0]
        #expect(valid.name == "Vista valida")
        #expect(valid.heading == "Vista valida")
        #expect(valid.lineIndex == locations[0].lineIndex)
        #expect(valid.block?.render == .table)
        #expect(ViewCatalogue.rendererName(valid.block!.render) == "tabella")
        #expect(valid.matches == 1, "il filtro tag(\"client-vibrofer\") deve trovare esattamente una nota nel corpus")
        #expect(valid.error == nil)

        let broken = entries[1]
        #expect(broken.name == "Vista rotta")
        #expect(broken.heading == "Vista rotta")
        #expect(broken.lineIndex == locations[1].lineIndex)
        #expect(broken.block == nil)
        #expect(broken.matches == nil)
        #expect(broken.error == parseErrorDescription("outsider: mistero"))
    }
}

// MARK: - The error card still renders on the transclusion/reading path, positively

@MainActor
@Suite struct ErrorCardStillRendersOnTheTranscludedReadingPath {
    /// ADR §D7 / ADR-0009 §D1: "a block that does not parse renders as an error naming the line,
    /// never as an empty result" - kept, on this surface, by this chain not touching it. Asserted
    /// by content, not by the absence of a crash: `collectStrings` recovers both `Text`'s own
    /// string storage and every `.accessibilityIdentifier(_:)` string reachable from `.body`, so
    /// the presence of `"rendered-view-error"` together with the actual error text is the
    /// positive claim this task asks for.
    @Test func anUnparseableFenceRoutedThroughMarkdownBlocksViewDrawsTheErrorCardWithItsContent() throws {
        let badSource = "outsider: mistero"
        let view = MarkdownBlocksView(blocks: [], notePath: "Nota.md")
        let block = MarkdownBlock.code(language: ViewBlock.language, lines: [badSource])

        let rendered = try #require(find(RenderedViewBlock.self, in: view.view(for: block)))
        var strings: [String] = []
        collectStrings(in: rendered.body, into: &strings)

        #expect(strings.contains("rendered-view-error"), "la card d'errore non compare più (ADR §D7)")
        #expect(strings.contains(parseErrorDescription(badSource)), "il motivo dell'errore non compare più")
        #expect(strings.contains(badSource), "il blocco così com'è scritto non compare più")
        #expect(
            !strings.contains("rendered-view-edit-source"),
            "senza onEditSource questo percorso non deve offrire il controllo di modifica (ADR §D9)"
        )
    }
}
