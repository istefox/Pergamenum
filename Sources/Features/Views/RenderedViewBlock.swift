import SwiftUI

/// A `pergamenum-view` fence, run and drawn (ADR-0009).
///
/// Reading mode only. In Modifica the fence stays a code block, which is what Obsidian shows a
/// reader that cannot run it (§D1) and what keeps a board's drop targets out of an `NSTextView`.
///
/// Three states and they look nothing alike, which is the whole of §D1's insistence:
///
/// - **the block does not parse**: the line, the reason, and the block as it is written. Never
///   an empty list, which would be indistinguishable from a vault that lost its notes.
/// - **nothing matched**: said in the view's own words, in the same grey the rest of it uses.
/// - **rows**: the renderer the block asked for.
///
/// The header above all three carries the row count, because without it a view that found
/// nothing and a view that has not run are the same picture.
struct RenderedViewBlock: View {
    @Environment(\.theme) private var theme

    /// The fence body, without the fence lines: what `MarkdownBlockParser` hands over.
    let source: String
    /// Where the note lives, so a gallery looks for an embedded file beside it first.
    var notePath: String = ""
    var vaultRoot: URL?
    var thumbnails: ThumbnailStore?
    /// Nil where there is no vault behind the view - a note card on the canvas, a preview in a
    /// test. The block then says so instead of drawing an empty result.
    var queries: ViewQuerySource?
    /// One more control in the header row, beside the refresh button: how the caret gets back
    /// into a fence this attachment covers (ADR-0033 §D9/§D10). `nil` means the control is not
    /// drawn - exactly today's rendering, and what a surface with no editor behind it gets.
    var onEditSource: (() -> Void)?
    /// A third optional input, on the same terms as `onEditSource` (ADR-0034 §D1): opens the
    /// visual query builder for this fence. Drawn once in `header(renderer:count:)`, present on
    /// both the parse-failure and the live-render branches because both call that one function
    /// (R-01/R-03). `nil` means the control is not drawn - `MarkdownBlocksView`, `NoteExporter`
    /// and a Workspace `.text` card pass nothing and gain nothing.
    var onEditQuery: (() -> Void)?
    /// Threaded to the four renderers as an optional click target carrying a row's own title
    /// (ADR-0033 §D9, R-09). `nil` means no renderer draws a click target - today's rendering,
    /// and what keeps R-10/R-11 (transclusion, export) true by construction rather than by
    /// care: neither passes it, so neither gains an interaction.
    ///
    /// A title and not a path, because that is the string a `[[wikilink]]` carries and this
    /// opens a note through the same door one does - two lookups of one name, never two rules.
    var onOpenNote: ((String) -> Void)?

    @State private var result: ViewResult?
    /// Bumped by the refresh control. §D7 gives a view an explicit refresh; this is it.
    @State private var reloads = 0

    private var block: Result<ViewBlock, ViewBlockError> {
        Result { try ViewBlock.parse(source) }
            .mapError { $0 as? ViewBlockError ?? ViewBlockError(line: 1, reason: "\($0)") }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.s)) {
            switch block {
            case .failure(let error):
                header(renderer: nil, count: nil)
                failed(error)
            case .success(let parsed):
                header(renderer: parsed.render, count: result?.total)
                content(parsed)
            }
        }
        .padding(theme.spacing(.m))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.color(.backgroundSecondary))
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous)
                .stroke(theme.color(.borderSubtle), lineWidth: 1)
        )
        .accessibilityIdentifier("rendered-view")
        // The id is what §D7 turns into a re-evaluation: the source itself, the scan
        // generation, and the refresh. Not a timer, and not every redraw.
        .task(id: Self.taskID(source: source, generation: queries?.generation ?? -1, reloads: reloads)) {
            evaluate()
        }
        // A block carrying a relative bound means a different set of notes tomorrow, with no
        // file having changed (ADR-0014 §D4). Bumping the same counter the refresh button
        // uses, because it is the same act.
        .onDayChange { reloads += 1 }
    }

    private func evaluate() {
        result = (try? block.get()).flatMap { parsed in queries?.evaluate(parsed) }
    }

    /// The id `.task(id:)` is keyed on (§D7): the fence's own source, the vault's scan
    /// generation, and the explicit-refresh counter. Extracted as a pure, static function -
    /// value-preserving against the inline string it replaces - so a test can assert on the
    /// composition without a live SwiftUI render (Task 7's own tester ask; R-07, R-13's third
    /// named case: a generation bump must change this string, or the query never re-runs on a
    /// vault rescan).
    static func taskID(source: String, generation: Int, reloads: Int) -> String {
        "\(source)|\(generation)|\(reloads)"
    }

    // MARK: L'intestazione

    private func header(renderer: ViewBlock.Renderer?, count: Int?) -> some View {
        HStack(spacing: theme.spacing(.xs)) {
            Text((renderer?.title ?? "vista").uppercased()).themedText(.caption, color: .textTertiary)
            if let count {
                Text("·").themedText(.caption, color: .textTertiary)
                Text(count == 1 ? "1 nota" : "\(count) note").themedText(.caption, color: .textTertiary)
            }
            Spacer()
            // Before the refresh rather than after it, so the control that has been there
            // since PG-012 stays where the eye already looks for it. Drawn only where
            // something is listening: a transclusion and an export have no caret to place
            // (ADR §D9), and a door to nowhere is worse than no door.
            if let onEditSource {
                Button(action: onEditSource) {
                    Image(systemName: "text.cursor").themedText(.caption, color: .textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Modifica la sorgente")
                .accessibilityIdentifier("rendered-view-edit-source")
            }
            // ADR-0034 §D1: the same door on both fence states, since both branches of the
            // block's `switch` call this one function. Drawn only where something is
            // listening - a transclusion and an export have no sheet to raise.
            if let onEditQuery {
                Button(action: onEditQuery) {
                    Image(systemName: "slider.horizontal.3").themedText(.caption, color: .textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Modifica query")
                .accessibilityIdentifier("rendered-view-edit-query")
            }
            Button { reloads += 1 } label: {
                Image(systemName: "arrow.clockwise").themedText(.caption, color: .textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Aggiorna la vista")
            .accessibilityIdentifier("rendered-view-refresh")
        }
    }

    // MARK: I tre stati

    @ViewBuilder
    private func content(_ block: ViewBlock) -> some View {
        if queries == nil {
            Text("Nessun vault dietro questa vista.")
                .themedText(.body, color: .textTertiary)
        } else if let result, result.total > 0 {
            rows(block, result)
        } else {
            Text("Nessuna nota risponde a questa vista.")
                .themedText(.body, color: .textTertiary)
                .accessibilityIdentifier("rendered-view-empty")
        }
    }

    @ViewBuilder
    private func rows(_ block: ViewBlock, _ result: ViewResult) -> some View {
        switch block.render {
        case .table: ViewTableRenderer(block: block, result: result, onOpenNote: onOpenNote)
        case .list: ViewListRenderer(block: block, result: result, onOpenNote: onOpenNote)
        case .gallery:
            ViewGalleryRenderer(
                result: result, notePath: notePath, vaultRoot: vaultRoot, thumbnails: thumbnails,
                onOpenNote: onOpenNote
            )
        case .calendar: ViewCalendarRenderer(block: block, result: result, onOpenNote: onOpenNote)
        // The one renderer that writes (§D5), and only when the grouping is a tag namespace:
        // it decides that for itself.
        case .board:
            ViewBoardRenderer(block: block, result: result, queries: queries) { reloads += 1 }
        }
    }

    /// §D1: the line, the reason, and the block as written. The reader is the person who
    /// wrote it and the block is four lines up in the same file.
    private func failed(_ error: ViewBlockError) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            HStack(alignment: .firstTextBaseline, spacing: theme.spacing(.xs)) {
                Image(systemName: "exclamationmark.triangle").themedText(.caption, color: .taskOverdue)
                Text(error.description)
                    .themedText(.caption, color: .taskOverdue)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(source.components(separatedBy: .newlines).enumerated()), id: \.offset) { offset, line in
                    Text(line)
                        .themedText(.mono, color: offset + 1 == error.line ? .taskOverdue : .textSecondary)
                }
            }
            .padding(theme.spacing(.s))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.color(.surfaceSunken))
            .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
        }
        .accessibilityIdentifier("rendered-view-error")
    }
}

extension ViewBlock.Renderer {
    /// What the header calls this renderer, in the interface's language.
    var title: String {
        switch self {
        case .table: "tabella"
        case .board: "board"
        case .gallery: "gallery"
        case .calendar: "calendario"
        case .list: "lista"
        }
    }
}
