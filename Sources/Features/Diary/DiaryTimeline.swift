import SwiftUI

/// The diary's hourly grid: 06:00 to midnight, cut every ten minutes.
///
/// Everything on it is the user's: blocks are created by dragging over empty time,
/// moved by dragging them, made longer by pulling their bottom edge, and opened by
/// clicking. No calendar is consulted and none is written to.
struct DiaryTimeline: View {
    @Environment(\.theme) private var theme

    @Bindable var controller: DiaryController

    /// Sixty points to the hour, which puts a ten-minute mark exactly ten points from
    /// the last one - the grid the diary promises, drawn at a size a pointer can hit.
    private let hourHeight: CGFloat = 60
    private let gutter: CGFloat = 52
    /// Under this a drag is a click, and a click blocks out an hour.
    private let dragThreshold: CGFloat = 9

    /// The stretch of empty time being dragged over, before it becomes a block.
    @State private var creating: (start: Int, end: Int)?
    /// Moved on every tick, which is what carries the "now" line down the day.
    @State private var now = Date()

    private var firstHour: Int { controller.firstHour }
    private var lastHour: Int { controller.lastHour }
    private var minuteHeight: CGFloat { hourHeight / 60 }
    private var gridHeight: CGFloat { CGFloat(lastHour - firstHour) * hourHeight }

    var body: some View {
        ScrollView {
            GeometryReader { proxy in
                let geometry = DiaryGeometry(
                    firstHour: firstHour, hourHeight: hourHeight,
                    gutter: gutter, width: proxy.size.width
                )
                ZStack(alignment: .topLeading) {
                    hourLines
                    creationPreview(geometry)
                    ForEach(controller.placements) { placement in
                        DiaryEntryCard(placement: placement, geometry: geometry, controller: controller)
                    }
                    nowLine
                }
                .frame(height: gridHeight, alignment: .top)
            }
            .frame(height: gridHeight)
            .padding(.vertical, theme.spacing(.s))
        }
        .background(theme.color(.backgroundSecondary))
        .safeAreaInset(edge: .top) { header }
        // The clock rather than a timer object: one line that moves once a minute does
        // not deserve a Combine subscription, and the task stops with the view.
        .task {
            while !Task.isCancelled {
                now = Date()
                try? await Task.sleep(for: .seconds(30))
            }
        }
        .accessibilityIdentifier("diary-timeline")
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: theme.spacing(.xs)) {
            Text("GIORNATA").themedText(.caption, color: .textTertiary)
            Spacer()
            if !controller.entries.isEmpty {
                Text(occupancy).themedText(.caption, color: .textTertiary)
                    .accessibilityIdentifier("diary-occupancy")
            }
        }
        .padding(.horizontal, theme.spacing(.s))
        .padding(.vertical, theme.spacing(.xs))
        .background(theme.color(.backgroundSecondary))
    }

    /// `3 blocchi · 4h 30m`, which is the whole of what a diary is asked at the end of
    /// a day.
    private var occupancy: String {
        let minutes = controller.totalMinutes
        let hours = minutes / 60
        let rest = minutes % 60
        let length = hours == 0 ? "\(rest)m" : (rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m")
        let count = controller.entries.count
        return "\(count) \(count == 1 ? "blocco" : "blocchi") · \(length)"
    }

    // MARK: The grid

    /// The hour lines, the half-hour marks between them, and the empty space that
    /// listens for a drag.
    private var hourLines: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(firstHour..<lastHour, id: \.self) { hour in
                hourLine(hour, withHalfHour: true)
                    .frame(height: hourHeight, alignment: .top)
            }
            // The line that closes the day. Without it the grid ended under the 23:00
            // row with nothing to say where midnight was, and a block running to the
            // end of the day stopped in mid-air.
            hourLine(lastHour).frame(height: 0, alignment: .top)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        // Behind the blocks, so a click on one of them is never taken by this: the
        // topmost view wins hit testing, and the blocks are drawn after.
        .contentShape(Rectangle())
        .gesture(createGesture)
        .accessibilityIdentifier("diary-grid")
    }

    /// One hour: its label in the gutter, its line, and the fainter half-hour mark
    /// halfway down. The closing hour has no half of its own.
    private func hourLine(_ hour: Int, withHalfHour: Bool = false) -> some View {
        HStack(alignment: .top, spacing: theme.spacing(.s)) {
            Text(String(format: "%02d:00", hour))
                .themedText(.caption, color: .textTertiary)
                .frame(width: gutter - theme.spacing(.s), alignment: .trailing)
                .offset(y: -6)
            VStack(spacing: 0) {
                Rectangle().fill(theme.color(.borderSubtle)).frame(height: 1)
                if withHalfHour {
                    Spacer(minLength: 0)
                    Rectangle().fill(theme.color(.borderSubtle).opacity(0.45)).frame(height: 1)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    /// Drag over empty time to block it out; a click blocks out an hour.
    private var createGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in creating = range(of: value) }
            .onEnded { value in
                let dragged = range(of: value)
                creating = nil
                let duration = abs(value.translation.height) > dragThreshold
                    ? dragged.end - dragged.start
                    : 60
                controller.compose(startMinutes: dragged.start, durationMinutes: duration)
            }
    }

    /// The stretch a drag covers, in whole ten-minute marks, whichever way it went.
    private func range(of value: DragGesture.Value) -> (start: Int, end: Int) {
        let anchor = minutes(at: value.startLocation.y)
        let current = minutes(at: value.location.y)
        let start = DiaryGrid.snapDown(min(anchor, current))
        return (start, max(start + DiaryGrid.step, DiaryGrid.snap(max(anchor, current))))
    }

    @ViewBuilder
    private func creationPreview(_ geometry: DiaryGeometry) -> some View {
        if let creating {
            RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous)
                .fill(theme.color(.accentMuted))
                .overlay(alignment: .topLeading) {
                    Text("\(DiaryGrid.timeText(creating.start))-\(DiaryGrid.timeText(creating.end))")
                        .themedText(.caption, color: .textSecondary)
                        .padding(.horizontal, theme.spacing(.xs))
                        .padding(.top, 2)
                }
                .frame(
                    width: geometry.columnWidth(1),
                    height: geometry.height(ofMinutes: max(DiaryGrid.step, creating.end - creating.start))
                )
                .offset(x: gutter, y: geometry.offset(ofMinute: creating.start))
                .allowsHitTesting(false)
        }
    }

    /// Where the current time is, on the day that is today. A diary written in the
    /// evening about the morning needs to see where "now" falls.
    @ViewBuilder
    private var nowLine: some View {
        let current = minutesOfDay(now)
        if controller.day == .today, current >= firstHour * 60, current <= lastHour * 60 {
            HStack(spacing: 0) {
                Circle()
                    .fill(theme.color(.taskOverdue))
                    .frame(width: 6, height: 6)
                Rectangle()
                    .fill(theme.color(.taskOverdue))
                    .frame(height: 1)
            }
            .offset(x: gutter - 3, y: CGFloat(current - firstHour * 60) * minuteHeight)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    // MARK: Geometry

    /// The minute of the day at a point in the grid.
    private func minutes(at y: CGFloat) -> Int {
        let raw = Int((y / minuteHeight).rounded(.down)) + firstHour * 60
        return min(max(0, raw), DiaryGrid.dayMinutes - DiaryGrid.step)
    }

    private func minutesOfDay(_ date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}
