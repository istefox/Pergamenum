import SwiftUI
import UniformTypeIdentifiers

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 8 -
// R-22, ADR §D21.
//
// **The tracer bullet, not the feature.** The plan's own words: "drag one message from
// Mail onto the timeline and read what `.dropDestination` actually receives … Do not
// spend the task on making the drop work." So this records what arrived and shows it;
// it imports nothing, writes nothing and touches no dossier.
//
// The measurement needs a person with Mail open, which is the review gate's job, not a
// unit test's - a drag cannot be synthesised here (`.draggable`→`.dropDestination` is
// an untested machine in this repo, ADR-0026 §D9's own note).
//
// R-22's escape clause is already honoured on screen: until the drop is proven, the
// documented way in is «Aggiungi a pratica da Mail…» (Cmd+Shift+P), and `caption`
// below says so where the drop is offered.
struct MailDropReport: Equatable, Sendable {
    /// Every UTI the dragged item advertised, in the order the provider listed them -
    /// the whole point of the probe. Empty means the drop carried no readable type at
    /// all, which is itself the answer.
    var typeIdentifiers: [String]
    var at: Date

    /// One line for the ADR follow-up §D17 note, and for the banner the pane shows.
    var summary: String {
        typeIdentifiers.isEmpty
            ? "Il trascinamento da Mail non ha offerto alcun tipo leggibile."
            : "Mail ha offerto: \(typeIdentifiers.joined(separator: ", "))."
    }
}

extension View {
    /// Attaches the probe to a view, so a drag from Mail is caught and described
    /// instead of silently doing nothing.
    ///
    /// `.onDrop(of:isTargeted:perform:)` rather than `.dropDestination(for:)`: the
    /// typed form needs a `Transferable` chosen in advance, which is exactly the thing
    /// this probe exists to find out. The untyped form hands over the raw
    /// `NSItemProvider`s and their advertised UTIs.
    func mailDropReceiver(isEnabled: Bool = true, onReport: @escaping (MailDropReport) -> Void) -> some View {
        modifier(MailDropReceiver(isEnabled: isEnabled, onReport: onReport))
    }
}

private struct MailDropReceiver: ViewModifier {
    let isEnabled: Bool
    let onReport: (MailDropReport) -> Void

    @State private var isTargeted = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.onDrop(of: Self.accepted, isTargeted: $isTargeted) { providers in
                let identifiers = providers.flatMap(\.registeredTypeIdentifiers)
                onReport(MailDropReport(typeIdentifiers: identifiers, at: Date()))
                // `false`: nothing was consumed, because nothing is imported here.
                // Answering `true` would tell AppKit the drop succeeded and leave a
                // person believing a message had been filed.
                return false
            }
        } else {
            content
        }
    }

    /// Deliberately wide: `.item` catches whatever Mail actually promises, which is
    /// the measurement. Narrowing it to a guess would answer the question with the
    /// guess.
    private static let accepted: [UTType] = [.item, .fileURL, .url, .emailMessage]
}
