import SwiftUI

// The five renderers `ViewMockup` puts up for approval, drawn one per type.
//
// In a file of their own for the reason `TagBrowserMockupPieces` gives: the scenes say what is
// being asked, the pieces say what it looks like, and neither reads better inside the other.
//
// **Every width here is arithmetic, never a guess.** `MockupGalleryView.contentWidth` is 720,
// the mockup takes 24 off each side and the frame around a rendered view another 16, so a
// renderer paints in **640 points**. The doc comment on `contentWidth` records what going over
// costs: a vertical `ScrollView` does not scroll sideways, so the overflow is clipped at both
// edges at once and reads as broken formatting rather than as something too wide.

// MARK: - Tabella

/// Columns are the block's `columns`, in the order it wrote them. Three things are being
/// decided here and nowhere else:
///
/// - **A missing value is an em dash, not a blank.** A blank cell and a cell holding an empty
///   string look the same, and the view would be lying about which one the file says.
/// - **Tags are chips, everywhere they appear.** The same shape the tag browser uses, because a
///   tag in a table and a tag in the sidebar are the same thing.
/// - **The sorted column says so, in its header.** `sort:` lives in a block the reader may not
///   have open; a table that did not show it would look arbitrarily ordered.
struct ViewTableMockup: View {
    @Environment(\.theme) private var theme

    /// 604 of column plus four 8-point gaps: 636 of the 640 there are.
    private static let columns: [(String, CGFloat)] = [
        ("titolo", 210), ("tag", 170), ("modificata", 90), ("task", 44), ("scadenza", 90),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            row("Vibrofer", tags: ["client-vibrofer", "status-aperto"],
                modified: "18/08", tasks: "2", deadline: "10/09")
            row("Ceramiche Emiliane", tags: ["client-ceramiche"],
                modified: "02/08", tasks: "0", deadline: nil)
            row("Presse idrauliche", tags: ["project-presse", "status-aperto"],
                modified: "19/08", tasks: "1", deadline: "30/08")
        }
    }

    private var header: some View {
        HStack(spacing: theme.spacing(.s)) {
            ForEach(Self.columns, id: \.0) { name, width in
                HStack(spacing: 2) {
                    Text(name).themedText(.caption, color: .textTertiary)
                    if name == "modificata" {
                        Image(systemName: "chevron.down").themedText(.caption, color: .textTertiary)
                    }
                }
                .frame(width: width, alignment: .leading)
            }
        }
        .padding(.bottom, theme.spacing(.xs))
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.color(.borderSubtle)).frame(height: 1)
        }
    }

    private func row(
        _ title: String, tags: [String], modified: String, tasks: String, deadline: String?
    ) -> some View {
        HStack(spacing: theme.spacing(.s)) {
            Text(title).themedText(.body, color: .accentPrimary)
                .lineLimit(1).frame(width: Self.columns[0].1, alignment: .leading)
            HStack(spacing: 4) {
                ForEach(tags, id: \.self) { ViewMockupChip(text: $0) }
            }
            .frame(width: Self.columns[1].1, alignment: .leading)
            Text(modified).themedText(.caption, color: .textSecondary)
                .frame(width: Self.columns[2].1, alignment: .leading)
            Text(tasks).themedText(.caption, color: tasks == "0" ? .textTertiary : .textSecondary)
                .frame(width: Self.columns[3].1, alignment: .leading)
            ViewMockupValue(text: deadline).frame(width: Self.columns[4].1, alignment: .leading)
        }
        .padding(.vertical, theme.spacing(.xs))
    }
}

// MARK: - Board

/// The only renderer that writes (ADR-0009 §D5), and the three cases §D5 decides are all drawn:
/// the *Senza stato* column first, a note carrying two `status-*` tags shown in both, and the
/// card being dragged.
///
/// *Senza stato* is not a decoration: it is the only way to take a status off a note with a
/// gesture. It is drawn dimmer than a real column and never with a tag name, because it stands
/// for the absence of the tag rather than for one.
struct ViewBoardMockup: View {
    @Environment(\.theme) private var theme
    /// Three columns and two 8-point gaps: 3 × 204 + 16 = 628 of the 640 there are.
    private static let columnWidth: CGFloat = 204

    var body: some View {
        HStack(alignment: .top, spacing: theme.spacing(.s)) {
            column(nil, count: 1) {
                card("Letture 2026", tags: [], tasks: nil)
            }
            column("status-aperto", count: 2, isDropTarget: true) {
                card("Vibrofer", tags: ["client-vibrofer"], tasks: "2 aperti")
                card("Presse idrauliche", tags: ["project-presse"], tasks: "1 aperto", isLifted: true)
            }
            column("status-chiuso", count: 1) {
                card("Presse idrauliche", tags: ["project-presse"], tasks: "1 aperto")
            }
        }
    }

    private func column(
        _ tag: String?, count: Int, isDropTarget: Bool = false, @ViewBuilder _ cards: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            HStack(spacing: theme.spacing(.xs)) {
                if let tag {
                    ViewMockupChip(text: tag)
                } else {
                    Text("Senza stato").themedText(.caption, color: .textTertiary)
                }
                Spacer()
                Text("\(count)").themedText(.caption, color: .textTertiary)
            }
            cards()
            Spacer(minLength: 0)
        }
        .padding(theme.spacing(.s))
        .frame(width: Self.columnWidth, alignment: .leading)
        .background(theme.color(.backgroundSecondary))
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous)
                .stroke(isDropTarget ? theme.color(.accentPrimary) : .clear, lineWidth: 1)
        )
    }

    private func card(_ title: String, tags: [String], tasks: String?, isLifted: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).themedText(.body).lineLimit(2)
            HStack(spacing: 4) {
                ForEach(tags, id: \.self) { ViewMockupChip(text: $0) }
            }
            if let tasks {
                Text(tasks).themedText(.caption, color: .textTertiary)
            }
        }
        .padding(theme.spacing(.s))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.color(.surfaceCard))
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
        .shadow(radius: isLifted ? 6 : 0, y: isLifted ? 3 : 0)
        .rotationEffect(.degrees(isLifted ? -1.5 : 0))
    }
}

// MARK: - Gallery

/// Thumbnails come from `embedTargets`, the field M11 spent its schema bump on.
///
/// A note that embeds nothing still gets a card, with the placeholder its file type would have
/// had. Dropping it would make the gallery disagree with the query that produced it, and a
/// renderer that quietly shows fewer rows than the view found is the one failure this whole
/// design is arranged against.
struct ViewGalleryMockup: View {
    @Environment(\.theme) private var theme
    /// Four cells and three 16-point gaps: 4 × 145 + 48 = 628 of the 640 there are.
    private static let cell: CGFloat = 145

    var body: some View {
        HStack(alignment: .top, spacing: theme.spacing(.m)) {
            cell("Trasmissibilità", file: "curva.pdf", icon: "doc.richtext")
            cell("Sopralluogo pressa 4", file: "pressa.jpg", icon: "photo")
            cell("Capitolato 2026", file: "capitolato.pdf", icon: "doc.richtext")
            cell("Appunti fiera", file: nil, icon: "doc.text")
        }
    }

    private func cell(_ title: String, file: String?, icon: String) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous)
                .fill(theme.color(file == nil ? .surfaceSunken : .surfaceRaised))
                .frame(width: Self.cell, height: 98)
                .overlay {
                    Image(systemName: icon)
                        .font(.system(size: 26))
                        .foregroundStyle(theme.color(file == nil ? .textTertiary : .textSecondary))
                }
            Text(title).themedText(.body).lineLimit(1)
            Text(file ?? "nessun allegato")
                .themedText(.caption, color: .textTertiary).lineLimit(1)
        }
        .frame(width: Self.cell, alignment: .leading)
    }
}

// MARK: - Calendario

/// A month, with the rows placed on a day.
///
/// **Which day is the question this screen asks.** The language has seven keys and no eighth is
/// being added for it, so the calendar reads the first date-valued field in `columns` - `date`,
/// `modified`, `deadline.next` or `scheduled.next` - and falls back to `date` when the block
/// names none. Writing `columns: [title, deadline.next]` therefore makes a deadline calendar,
/// which is the same key doing the same job it does in a table.
struct ViewCalendarMockup: View {
    @Environment(\.theme) private var theme
    /// Seven days and six 4-point gaps: 7 × 86 + 24 = 626 of the 640 there are.
    private static let day: CGFloat = 86

    private static let entries: [Int: [(String, Bool)]] = [
        25: [("Disegno presse", false)],
        27: [("Vibrofer", false), ("Ceramiche", false)],
        30: [("Consegna capitolato", true)],
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            HStack(spacing: theme.spacing(.xs)) {
                ForEach(["lun", "mar", "mer", "gio", "ven", "sab", "dom"], id: \.self) { name in
                    Text(name).themedText(.caption, color: .textTertiary)
                        .frame(width: Self.day, alignment: .leading)
                }
            }
            HStack(spacing: theme.spacing(.xs)) {
                ForEach(24...30, id: \.self) { number in day(number) }
            }
        }
    }

    private func day(_ number: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(number)").themedText(.caption, color: number == 27 ? .accentPrimary : .textSecondary)
            ForEach(Self.entries[number] ?? [], id: \.0) { title, isOverdue in
                Text(title)
                    .themedText(.caption, color: isOverdue ? .taskOverdue : .textPrimary)
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
        .frame(width: Self.day, height: 84, alignment: .topLeading)
        .background(theme.color(.backgroundSecondary))
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
    }
}

// MARK: - Lista

/// The renderer for a view embedded in a note that is about something else: a project page
/// carrying its own documents wants a paragraph's worth of rows, not a table with headers.
///
/// One line each, the columns after the title folded into a single caption in the order the
/// block wrote them.
struct ViewListMockup: View {
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            row("Vibrofer", detail: "client-vibrofer · 18/08 · 2 task aperti")
            row("Ceramiche Emiliane", detail: "client-ceramiche · 02/08")
            row("Presse idrauliche", detail: "project-presse · 19/08 · scadenza 30/08")
        }
    }

    private func row(_ title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: theme.spacing(.xs)) {
            Image(systemName: "doc.text").themedText(.caption, color: .textTertiary)
            Text(title).themedText(.body, color: .accentPrimary).lineLimit(1)
            Text(detail).themedText(.caption, color: .textTertiary).lineLimit(1)
        }
    }
}

// MARK: - I pezzi comuni

/// A tag, drawn the way the tag browser draws one: the same thing in two places looks the same.
struct ViewMockupChip: View {
    @Environment(\.theme) private var theme
    let text: String

    var body: some View {
        Text(text)
            .themedText(.caption, color: .textSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(theme.color(.surfaceSunken))
            .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
    }
}

/// A cell whose field has no value. An em dash rather than nothing: a blank cell and a cell
/// holding an empty string are indistinguishable, and the file says different things.
struct ViewMockupValue: View {
    let text: String?

    var body: some View {
        if let text {
            Text(text).themedText(.caption, color: .textSecondary)
        } else {
            Text("—").themedText(.caption, color: .textTertiary)
        }
    }
}
