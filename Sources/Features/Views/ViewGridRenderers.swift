import AppKit
import SwiftUI

/// `render: gallery` (ADR-0009): a card per row, with the first file the note embeds as its
/// thumbnail.
///
/// The field is `embedTargets`, which M11 spent its single schema bump on. A note that embeds
/// nothing keeps its card: dropping it would make the gallery show less than the query found,
/// which is the one failure this whole design is arranged against.
struct ViewGalleryRenderer: View {
    @Environment(\.theme) private var theme

    let result: ViewResult
    var notePath: String = ""
    var vaultRoot: URL?
    var thumbnails: ThumbnailStore?

    /// Wide enough for a page to be legible, narrow enough for three across a reading column.
    private static let cellWidth: CGFloat = 145
    private static let columns = [GridItem(.adaptive(minimum: cellWidth), spacing: 16, alignment: .top)]

    var body: some View {
        LazyVGrid(columns: Self.columns, alignment: .leading, spacing: theme.spacing(.m)) {
            ForEach(result.rows, id: \.path) { row in
                cell(row)
            }
        }
        .accessibilityIdentifier("view-gallery")
    }

    private func cell(_ row: ViewResult.Row) -> some View {
        let target = row.record.embedTargets.first
        return VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            ViewThumbnail(
                target: target, notePath: row.path, root: vaultRoot, thumbnails: thumbnails,
                width: Self.cellWidth
            )
            Text(row.title).themedText(.body).lineLimit(1)
            Text(target ?? "nessun allegato")
                .themedText(.caption, color: .textTertiary)
                .lineLimit(1)
        }
        .frame(width: Self.cellWidth, alignment: .leading)
    }
}

/// One thumbnail, rendered by the same `ThumbnailStore` the Workspace cards and the note
/// embeds use: images through Quick Look, PDFs through PDFKit, both cached on disk.
///
/// One render width for the whole surface, as `EmbeddedFileView` keeps one for reading mode:
/// the store quantises by width, so a constant is one cached render per file rather than one
/// per column layout.
struct ViewThumbnail: View {
    @Environment(\.theme) private var theme

    let target: String?
    let notePath: String
    let root: URL?
    let thumbnails: ThumbnailStore?
    let width: CGFloat

    @State private var image: NSImage?
    @State private var hasLooked = false

    private static let renderWidth: CGFloat = 320

    private var relativePath: String? {
        guard let target, let root else { return nil }
        return Attachment.resolve(target, nearNoteAt: notePath, inVaultAt: root)
    }

    var body: some View {
        content
            .frame(width: width, height: 98)
            .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
            // A hairline around every thumbnail, drawn whatever the file is. A PDF page is
            // white and this gallery is often dark, so without it the cell reads as a hole in
            // the grid rather than as a document with an edge.
            .overlay(
                RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous)
                    .stroke(theme.color(.borderSubtle), lineWidth: 1)
            )
            .task(id: relativePath ?? target ?? "") { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .accessibilityLabel(target ?? "")
        } else {
            // The placeholder a file of this kind would have had, and the same shape whether
            // the note embeds nothing or the render has not arrived: the grid must not jump
            // when it does.
            RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous)
                .fill(theme.color(target == nil ? .surfaceSunken : .surfaceRaised))
                .overlay {
                    Image(systemName: symbol)
                        .font(.system(size: 26))
                        .foregroundStyle(theme.color(target == nil ? .textTertiary : .textSecondary))
                }
        }
    }

    private var symbol: String {
        guard let target else { return "doc.text" }
        let ext = (target as NSString).pathExtension.lowercased()
        if ext == "pdf" { return "doc.richtext" }
        return ["png", "jpg", "jpeg", "heic", "gif", "webp", "tiff"].contains(ext) ? "photo" : "doc"
    }

    private func load() async {
        image = nil
        hasLooked = false
        guard let relativePath, let thumbnails else {
            hasLooked = true
            return
        }
        let rendered = await thumbnails.thumbnail(for: relativePath, width: Self.renderWidth).value
        guard !Task.isCancelled else { return }
        image = rendered
        hasLooked = true
    }
}

/// `render: calendar` (ADR-0009): the rows, placed on the day one of their fields names.
///
/// **Which day** is the choice approved with the mockups: the first date-valued field among
/// `columns` - `date`, `modified`, `deadline.next`, `scheduled.next` - falling back to `date`
/// when the block names none. §D3 holds the grammar at seven keys, and an eighth for this
/// would have been the first crack in that.
///
/// A week at a time, and only the weeks that carry something: a month grid with navigation is
/// M12's work, and inventing one here would be a second calendar to keep in step with it.
/// Rows whose field has no value are listed at the end rather than dropped - the same rule the
/// board's *Senza stato* column follows.
struct ViewCalendarRenderer: View {
    @Environment(\.theme) private var theme

    let block: ViewBlock
    let result: ViewResult

    private static let weekdays = ["lu", "ma", "me", "gi", "ve", "sa", "do"]
    private static let columns = Array(repeating: GridItem(.flexible(minimum: 60), spacing: 4), count: 7)

    /// The field the rows are placed by. The rule is `ViewBlock.calendarField`, in `Core`
    /// beside the grammar it is a consequence of.
    private var field: ViewField { block.calendarField }

    private var placed: [CalendarDate: [ViewResult.Row]] {
        var days: [CalendarDate: [ViewResult.Row]] = [:]
        for row in result.rows {
            guard case .day(let day) = row.values[field] ?? field.value(of: row.record) else { continue }
            days[day, default: []].append(row)
        }
        return days
    }

    private var undated: [ViewResult.Row] {
        result.rows.filter { row in
            if case .day = row.values[field] ?? field.value(of: row.record) { return false }
            return true
        }
    }

    var body: some View {
        let days = placed
        VStack(alignment: .leading, spacing: theme.spacing(.s)) {
            ForEach(Self.weeks(covering: Array(days.keys)), id: \.self) { monday in
                week(from: monday, days: days)
            }
            if !undated.isEmpty {
                Text("Senza \(field.label)").themedText(.caption, color: .textTertiary)
                ForEach(undated, id: \.path) { row in
                    Text(row.title).themedText(.caption, color: .accentPrimary).lineLimit(1)
                }
            }
        }
        .accessibilityIdentifier("view-calendar")
    }

    /// The Monday of every week that carries a row, earliest first.
    private static func weeks(covering days: [CalendarDate]) -> [CalendarDate] {
        var mondays: Set<CalendarDate> = []
        for day in days {
            var candidate = day
            while DateEntry.weekday(of: candidate) != 2 { candidate = candidate.adding(days: -1) }
            mondays.insert(candidate)
        }
        return mondays.sorted { $0 < $1 }
    }

    private func week(from monday: CalendarDate, days: [CalendarDate: [ViewResult.Row]]) -> some View {
        let dates = (0..<7).map { monday.adding(days: $0) }
        return VStack(alignment: .leading, spacing: 2) {
            Text(DateEntry.monthName(month: monday.month, year: monday.year))
                .themedText(.caption, color: .textTertiary)
            LazyVGrid(columns: Self.columns, spacing: 4) {
                ForEach(Array(Self.weekdays.enumerated()), id: \.offset) { _, name in
                    Text(name).themedText(.caption, color: .textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(dates, id: \.self) { date in
                    day(date, rows: days[date] ?? [])
                }
            }
        }
    }

    private func day(_ date: CalendarDate, rows: [ViewResult.Row]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(date.day)").themedText(.caption, color: .textSecondary)
            ForEach(rows, id: \.path) { row in
                Text(row.title)
                    .themedText(.caption)
                    .lineLimit(1)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.color(.surfaceCard))
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            Spacer(minLength: 0)
        }
        .padding(theme.spacing(.xs))
        .frame(minHeight: 76, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.color(.backgroundPrimary))
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
    }
}

/// `render: board`, read-only.
///
/// §D5 already describes a read-only board - grouping by anything other than a tag namespace
/// gives one - so this is a state the design has rather than one invented for a half-finished
/// slice. The drag that rewrites a `status-*` tag is the next slice, and it is a write.
///
/// *Senza stato* comes first and carries no tag name: it stands for the absence of the tag
/// rather than for one. A note with two `status-*` tags appears in both columns, because the
/// file really does say both.
struct ViewBoardRenderer: View {
    @Environment(\.theme) private var theme

    let result: ViewResult

    private static let columns = [GridItem(.adaptive(minimum: 180), spacing: 8, alignment: .top)]

    var body: some View {
        LazyVGrid(columns: Self.columns, alignment: .leading, spacing: theme.spacing(.s)) {
            ForEach(result.groups.indices, id: \.self) { index in
                column(result.groups[index])
            }
        }
        .accessibilityIdentifier("view-board")
    }

    private func column(_ group: ViewResult.Group) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            HStack(spacing: theme.spacing(.xs)) {
                if let label = group.label {
                    ViewTagChip(text: label)
                } else {
                    Text("Senza stato").themedText(.caption, color: .textTertiary)
                }
                Spacer()
                Text("\(group.rows.count)").themedText(.caption, color: .textTertiary)
            }
            ForEach(group.rows, id: \.path) { row in
                card(row)
            }
            Spacer(minLength: 0)
        }
        .padding(theme.spacing(.s))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.color(.backgroundPrimary))
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous))
    }

    private func card(_ row: ViewResult.Row) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(row.title).themedText(.body).lineLimit(2)
            let tags = row.record.frontmatter.tags.map(\.description)
            if !tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(tags.prefix(2), id: \.self) { ViewTagChip(text: $0) }
                }
            }
            let open = row.record.tasks.count { $0.state.isOpen }
            if open > 0 {
                Text(open == 1 ? "1 aperto" : "\(open) aperti")
                    .themedText(.caption, color: .textTertiary)
            }
        }
        .padding(theme.spacing(.s))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.color(.surfaceCard))
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
    }
}
