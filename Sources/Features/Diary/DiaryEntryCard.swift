import SwiftUI

/// The measurements the diary's grid and the blocks drawn on it have to agree about.
///
/// One value passed down rather than two copies of the same three numbers: the card
/// places itself, so it has to convert minutes to points exactly as the grid does.
struct DiaryGeometry: Equatable, Sendable {
    /// The hour the grid starts at, which is what an offset is measured from.
    var firstHour: Int
    var hourHeight: CGFloat
    /// The strip on the left holding the hour labels.
    var gutter: CGFloat
    /// How wide the grid is, gutter included.
    var width: CGFloat

    var minuteHeight: CGFloat { hourHeight / 60 }

    func offset(ofMinute minute: Int) -> CGFloat {
        CGFloat(minute - firstHour * 60) * minuteHeight
    }

    func height(ofMinutes minutes: Int) -> CGFloat {
        CGFloat(minutes) * minuteHeight
    }

    /// The minute of the day at a point in the grid, never past the last mark.
    func minute(atY y: CGFloat) -> Int {
        let raw = Int((y / minuteHeight).rounded(.down)) + firstHour * 60
        return min(max(0, raw), DiaryGrid.dayMinutes - DiaryGrid.step)
    }

    /// How wide one lane is where `columns` blocks share the same hour.
    func columnWidth(_ columns: Int) -> CGFloat {
        max(0, width - gutter - 8) / CGFloat(max(1, columns))
    }
}

/// One block on the diary's day: what it was, when, and the three things that can be
/// done to it - opened, moved, made longer.
///
/// Its own type rather than a method on `DiaryTimeline`: the timeline was past the
/// length SwiftLint allows, and a block that owns its own drag state is a block whose
/// drag cannot be confused with another one's.
struct DiaryEntryCard: View {
    @Environment(\.theme) private var theme

    let placement: DiaryLayout.Placement
    let geometry: DiaryGeometry
    let controller: DiaryController

    /// How far the block has been dragged, before anything is written.
    @State private var draggedMinutes = 0
    /// The length being pulled to, likewise.
    @State private var draggedDuration: Int?
    @State private var isHovered = false

    /// How close to the bottom edge counts as pulling the block rather than moving it.
    private let resizeGrip: CGFloat = 9

    private var entry: DiaryEntry { placement.entry }
    private var start: Int { entry.startMinutes + draggedMinutes }
    private var duration: Int { draggedDuration ?? entry.durationMinutes }
    private var boxHeight: CGFloat {
        max(geometry.height(ofMinutes: DiaryGrid.step), geometry.height(ofMinutes: duration))
    }

    var body: some View {
        let lane = geometry.columnWidth(placement.columns)
        card
            .frame(width: max(40, lane - 2), height: boxHeight)
            .offset(x: geometry.gutter + lane * CGFloat(placement.column), y: geometry.offset(ofMinute: start))
            .onTapGesture { controller.edit(entry) }
            .gesture(moveGesture)
            .onHover { isHovered = $0 }
            .contextMenu {
                Button("Modifica…") { controller.edit(entry) }
                Button("Elimina") { controller.remove(entry) }
            }
            // `.contain` before the identifier, or the delete inside disappears from
            // XCUI along with everything else the block draws.
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("diary-entry")
    }

    /// The block as it is drawn: its hours, its name, and as much of its note as fits.
    private var card: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(DiaryGrid.timeText(start))-\(DiaryGrid.timeText(start + duration))")
                .themedText(.caption, color: .textSecondary)
                .lineLimit(1)
            Text(entry.displayTitle)
                .themedText(.body)
                .lineLimit(boxHeight > 74 ? 2 : 1)
            if boxHeight > 92, !entry.note.isEmpty {
                Text(entry.note)
                    .themedText(.caption, color: .textSecondary)
                    .lineLimit(max(1, Int((boxHeight - 74) / 16)))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, theme.spacing(.xs))
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(theme.color(entry.colour.token))
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
        .overlay(alignment: .leading) {
            Rectangle().fill(theme.color(.accentPrimary).opacity(0.55)).frame(width: 2)
        }
        .overlay(alignment: .topTrailing) { deleteButton }
        .overlay(alignment: .bottom) { resizeHandle }
        .help(entry.note.isEmpty ? entry.displayTitle : "\(entry.displayTitle)\n\(entry.note)")
    }

    /// Always in the hierarchy, only its opacity follows the pointer: built inside an
    /// `if isHovered` it would leave between mouse-down and mouse-up and the click would
    /// land on nothing, which is exactly how the day view's delete once failed.
    private var deleteButton: some View {
        Button { controller.remove(entry) } label: {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(theme.color(.textSecondary))
        }
        .buttonStyle(.plain)
        .padding(2)
        .opacity(isHovered ? 1 : 0.25)
        .help("Elimina il blocco")
        .accessibilityIdentifier("diary-remove-entry")
    }

    /// The bottom edge, pulled to make a block longer or shorter.
    private var resizeHandle: some View {
        Rectangle()
            .fill(theme.color(.borderStrong))
            .opacity(isHovered ? 0.5 : 0)
            .frame(height: 3)
            .padding(.horizontal, theme.spacing(.s))
            .contentShape(Rectangle().inset(by: -resizeGrip / 2))
            .gesture(resizeGesture)
            .accessibilityHidden(true)
    }

    // MARK: Dragging

    private var moveGesture: some Gesture {
        // Four points before it counts as a drag, so an ordinary click still opens the
        // block instead of nudging it by one mark.
        DragGesture(minimumDistance: 4)
            .onChanged { draggedMinutes = snappedDelta($0.translation.height) }
            .onEnded { value in
                let delta = snappedDelta(value.translation.height)
                draggedMinutes = 0
                guard delta != 0 else { return }
                controller.move(entry, toStart: entry.startMinutes + delta)
            }
    }

    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { draggedDuration = pulledDuration($0.translation.height) }
            .onEnded { value in
                let pulled = pulledDuration(value.translation.height)
                draggedDuration = nil
                controller.resize(entry, toDuration: pulled)
            }
    }

    /// How far the block has moved, in whole ten-minute marks, without falling off the
    /// top of the day.
    private func snappedDelta(_ translation: CGFloat) -> Int {
        let raw = Int((translation / geometry.minuteHeight).rounded())
        return max(-entry.startMinutes, (raw / DiaryGrid.step) * DiaryGrid.step)
    }

    /// The pulled length, on the grid and never under one mark.
    private func pulledDuration(_ translation: CGFloat) -> Int {
        let raw = entry.durationMinutes + Int((translation / geometry.minuteHeight).rounded())
        return max(DiaryGrid.step, DiaryGrid.snap(raw))
    }
}
