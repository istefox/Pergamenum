import SwiftUI

/// A time block on the day's timeline, with the three things it answers to: the × that
/// deletes it, the menu that publishes it, and the two gestures that move it and stretch
/// it (SPEC §8.3).
///
/// **Every piece of state a gesture touches is local to this box**, and that is the point
/// of the type existing. Held on `DayTimeline`, the hover and the live drag redrew the
/// whole grid on every frame - and the box changing shape under a still pointer made
/// `onHover` fire again, which redrew it again. On screen that was the block moving
/// before its blue caught up, and the resize handle blinking out mid-pull.
struct TimelineBlockBox: View {
    @Environment(\.theme) private var theme

    let block: TimeBlock
    let controller: DayController
    let calendar: EventKitStore
    let firstHour: Int
    let hourHeight: CGFloat

    @State private var isHovered = false
    /// Where the gesture has got to, before anything is written.
    @State private var draggedMinutes = 0
    @State private var pulledDuration: Int?

    private var start: Int { block.startMinutes + draggedMinutes }
    private var duration: Int { pulledDuration ?? block.durationMinutes }
    private var isMoving: Bool { draggedMinutes != 0 || pulledDuration != nil }

    var body: some View {
        TimelineEntryBox(
            entry: TimelineEntry(
                title: block.title,
                // While it is being moved the box says where it would land, which is the
                // only thing worth reading during the gesture.
                subtitle: isMoving
                    ? "\(TimeBlock.timeText(start))-\(TimeBlock.timeText(start + duration))"
                    : (block.isPublished ? "pubblicato" : "solo nella nota"),
                start: start,
                duration: duration,
                token: .stickyBlue,
                isEvent: false
            ),
            firstHour: firstHour,
            hourHeight: hourHeight,
            accessory: { removeButton },
            footer: { resizeHandle }
        )
        // Four points before it counts as a drag, the threshold the diary settled on for
        // the same reason: the × and the context menu on this very box have to keep
        // working, and a gesture that started at one point would eat their click.
        .gesture(moveGesture)
        .onHover { isHovered = $0 }
        .contextMenu {
            Button(block.isPublished ? "Già pubblicato" : "Pubblica sul Calendario") {
                controller.publish(block, toCalendarTitled: calendar.writeCalendarTitle)
            }
            .disabled(block.isPublished || !calendar.eventAccess.isGranted)
            Button("Elimina il blocco") { controller.remove(block) }
        }
        // `.contain` before the identifier, or the hover delete inside disappears from
        // XCUI along with everything else the box draws.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("timeline-block")
    }

    /// Always in the hierarchy, only its opacity follows the pointer. Built by
    /// `if isHovered` it left on mouse-down - the rebuild took the button away between
    /// press and release - so the click landed on nothing and the block stayed, on the
    /// timeline and in the note.
    private var removeButton: some View {
        Button {
            controller.remove(block)
        } label: {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(theme.color(.textSecondary))
        }
        .buttonStyle(.plain)
        .padding(2)
        .opacity(isHovered ? 1 : 0.35)
        .help("Elimina il blocco")
        .accessibilityIdentifier("timeline-remove-block")
    }

    /// The bottom edge, and the two things that make it findable: a grip that appears as
    /// soon as the pointer is on the block, and the resize cursor.
    ///
    /// It stays visible for as long as its own gesture is running, not only while the
    /// pointer is inside the box: pulling upwards takes the pointer out of a shrinking
    /// block, and a handle that vanished mid-pull took its gesture with it.
    private var resizeHandle: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(theme.color(.borderStrong))
            .opacity(isHovered || pulledDuration != nil ? 0.9 : 0)
            .frame(width: 44, height: 4)
            .padding(.bottom, 1)
            // A four-point bar is not something a mouse can be asked to hit: the target
            // is inflated well past what is drawn, and spans the whole bottom edge.
            .frame(maxWidth: .infinity)
            .frame(height: 10)
            .contentShape(Rectangle())
            .pointerStyle(.frameResize(position: .bottom))
            .gesture(resizeGesture)
            .accessibilityHidden(true)
    }

    /// **Measured in global space, never in the box's own.** A `DragGesture` reports its
    /// translation in the coordinate space of the view it is attached to, and both of
    /// these are attached to a view the gesture *moves*: the box slides under the pointer
    /// as it is dragged, and the handle rides its bottom edge as it grows. Measured
    /// locally, every frame recomputes the translation against a view that has already
    /// moved - a feedback loop that oscillates between two sizes, drifts away from the
    /// hand, and on screen looks like a second copy of the block lagging behind.
    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { value in
                // No transaction may animate a live drag: an interpolated height is a box
                // lagging behind the hand that is pulling it.
                withTransaction(Transaction(animation: nil)) {
                    draggedMinutes = delta(value.translation.height)
                }
            }
            .onEnded { value in
                let moved = delta(value.translation.height)
                draggedMinutes = 0
                guard moved != 0 else { return }
                controller.move(block, toStart: block.startMinutes + moved)
            }
    }

    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in
                withTransaction(Transaction(animation: nil)) {
                    pulledDuration = pulled(value.translation.height)
                }
            }
            .onEnded { value in
                let duration = pulled(value.translation.height)
                pulledDuration = nil
                controller.resize(block, toDuration: duration)
            }
    }

    // MARK: What the pointer is worth in minutes

    /// **To the minute while the gesture runs, and to the quarter only when it ends.**
    /// The snap belongs on the way into the file - `TimeBlock.moved` and `.resized` do it
    /// - and putting it here as well made the box jump in eleven-point steps under a hand
    /// moving smoothly: the block stuttered up and down and the handle kept leaving the
    /// pointer behind. A preview that does not follow the pointer is not a preview.
    ///
    /// The grid is `hourHeight` points to the hour, so the conversion is the same
    /// arithmetic the offsets are drawn with.
    private func delta(_ translation: CGFloat) -> Int {
        max(-block.startMinutes, Int((translation / hourHeight * 60).rounded()))
    }

    /// The pulled length, never under a quarter so the box cannot turn inside out while
    /// it is being dragged.
    private func pulled(_ translation: CGFloat) -> Int {
        max(15, block.durationMinutes + Int((translation / hourHeight * 60).rounded()))
    }
}
